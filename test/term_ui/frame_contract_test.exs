defmodule TermUI.FrameContractTest do
  use ExUnit.Case, async: true

  alias TermUI.{Cell, Frame, Style}

  test "normalizes existing cells before they reach a backend" do
    unsafe = %Cell{char: "\e]52;c;payload\a", width: 1}
    frame = Frame.new(4, 1, cells: %{{1, 1} => unsafe})

    assert Frame.row_text(frame, 1) == "    "
    refute inspect(Frame.cells(frame)) =~ "52;c"
  end

  test "normalizes text, wide graphemes, combining graphemes, and the cursor" do
    frame = Frame.from_rows(["a界b", "e\u0301"], 4, 2, cursor: {99, 2})

    assert frame.width == 4
    assert frame.height == 2
    assert frame.cursor == {4, 2}
    assert %Cell{char: "界", width: 2} = Frame.cell(frame, 1, 2)
    assert %Cell{wide_placeholder: true} = Frame.cell(frame, 1, 3)
    assert %Cell{char: "e\u0301", width: 1} = Frame.cell(frame, 2, 1)
    assert Frame.row_text(frame, 1) == "a界b"
  end

  test "accepts styled spans as the same cell frame representation" do
    style = Style.new() |> Style.fg(:green) |> Style.bold()
    frame = Frame.from_rows([[{"ok", style}, "!"]], 4, 1)

    assert %Cell{char: "o", fg: :green, attrs: attrs} = Frame.cell(frame, 1, 1)
    assert :bold in attrs
    assert Frame.row_text(frame, 1) == "ok! "
  end

  test "safe tiny frames and frame comparison clear old content" do
    old = Frame.from_rows(["x"], 1, 1)
    new = Frame.from_rows([""], 1, 1, cursor: {9, 9})

    assert new.cursor == {1, 1}
    assert Frame.diff(old, new) == [{{1, 1}, {" ", :default, :default, []}}]
  end

  test "one cell contains one grapheme and updates its display width" do
    assert %Cell{char: "a", width: 1} = Cell.new("abc")
    assert %Cell{char: "界", width: 2} = Cell.put_char(Cell.new("a"), "界more")
  end

  test "overlays one canonical frame and moves its cursor" do
    base = Frame.from_rows(["xxxx", "xxxx"], 4, 2)
    child = Frame.from_rows(["界"], 2, 1, cursor: {1, 1})
    frame = Frame.overlay(base, child, 2, 2)

    assert Frame.row_text(frame, 1) == "xxxx"
    assert Frame.row_text(frame, 2) == "x界x"
    assert frame.cursor == {2, 2}
  end

  test "replaces both columns when one half of a wide cell is overwritten" do
    wide = Frame.from_rows(["界"], 2, 1)

    primary_replaced = Frame.put_cell(wide, 1, 1, Cell.new("a"))
    placeholder_replaced = Frame.put_cell(wide, 1, 2, Cell.new("b"))

    assert Frame.row_text(primary_replaced, 1) == "a "
    assert Frame.cells(primary_replaced) == [{{1, 1}, {"a", :default, :default, []}}]
    assert Frame.diff(wide, primary_replaced) == clear_wide_changes("a")

    assert Frame.row_text(placeholder_replaced, 1) == " b"
    assert Frame.cells(placeholder_replaced) == [{{1, 2}, {"b", :default, :default, []}}]
  end

  test "adds a placeholder for a wide cell and rejects a wide cell at the last column" do
    frame = Frame.new(2, 1)
    wide = Frame.put_cell(frame, 1, 1, Cell.new("界"))
    clipped = Frame.put_cell(frame, 1, 2, Cell.new("界"))

    assert %Cell{char: "界", width: 2} = Frame.cell(wide, 1, 1)
    assert %Cell{wide_placeholder: true} = Frame.cell(wide, 1, 2)
    assert Frame.row_text(wide, 1) == "界"
    assert Frame.cells(clipped) == []
  end

  test "put_row clears old wide-cell data and overlay clears an intersecting wide cell" do
    wide = Frame.from_rows(["界"], 2, 1)

    assert wide |> Frame.put_row(1, "a") |> Frame.row_text(1) == "a "

    overlaid = Frame.overlay(wide, Frame.new(1, 1), 2, 1)
    assert Frame.row_text(overlaid, 1) == "  "
    assert Frame.cells(overlaid) == []
  end

  test "out-of-bounds writes and reads preserve the frame" do
    frame = Frame.from_rows(["abc"], 3, 1)

    assert Frame.put_row(frame, 0, "no") == frame
    assert Frame.put_row(frame, 2, "no") == frame
    assert Frame.put_cell(frame, 0, 1, Cell.new("x")) == frame
    assert Frame.put_cell(frame, 1, 4, Cell.new("x")) == frame
    assert Frame.row_text(frame, 0) == ""
    assert Frame.row_text(frame, 2) == ""
    assert Frame.fit("ignored", 0) == ""
  end

  test "row and cell normalization accepts public input forms" do
    frame =
      Frame.new(4, 2,
        cells: [
          {1, 1, Cell.new("a")},
          {{1, 2}, Cell.new("b")},
          {{9, 9}, Cell.new("z")}
        ],
        cursor: :invalid
      )

    assert Frame.row_text(frame, 1) == "ab  "
    assert frame.cursor == nil

    frame = Frame.put_row(frame, 2, 123)
    assert Frame.row_text(frame, 2) == "123 "

    frame = Frame.put_rows(frame, 1, ["x", "y", "ignored"])
    assert Frame.row_text(frame, 1) == "x   "
    assert Frame.row_text(frame, 2) == "y   "
  end

  test "diff omits unchanged cells and wide placeholders" do
    previous = Frame.from_rows(["界x"], 4, 1)
    current = Frame.from_rows(["界 "], 4, 1)

    assert Frame.diff(previous, previous) == []
    assert Frame.diff(previous, current) == [{{1, 3}, {" ", :default, :default, []}}]
  end

  test "wide placeholders without a primary cell are discarded" do
    placeholder = Cell.new(" ") |> Cell.wide_placeholder()
    frame = Frame.new(3, 1, cells: %{{1, 2} => placeholder})

    assert frame.cells == %{}
  end

  test "wrap starts a new row at display-width boundaries" do
    assert Frame.wrap("ab界c", 3) == ["ab", "界c"]
    assert Frame.wrap("", 3) == [""]
  end

  test "invalid dimensions raise with the public bounds" do
    assert_raise ArgumentError, ~r/frame dimensions must be within/, fn -> Frame.new(0, 1) end
    assert_raise ArgumentError, ~r/frame dimensions must be within/, fn -> Frame.new(1_001, 1) end
  end

  defp clear_wide_changes(replacement) do
    [
      {{1, 1}, {replacement, :default, :default, []}},
      {{1, 2}, {" ", :default, :default, []}}
    ]
  end
end
