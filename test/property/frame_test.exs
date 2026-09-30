defmodule TermUI.Property.FrameTest do
  use ExUnit.Case, async: true

  alias TermUI.{Cell, DisplayWidth, Frame}
  alias TermUI.Test.BoundaryCases, as: Cases

  test "row writes, wide-cell replacements, and overlays preserve a valid bounded frame" do
    Cases.check(&frame_case/0, fn {width, height, rows, edits, child_rows, column, row} ->
      frame = Frame.from_rows(rows, width, height, cursor: {width + 5, height + 5})
      assert_frame(frame)

      frame =
        Enum.reduce(edits, frame, fn {row, column, text}, frame ->
          next = Frame.put_cell(frame, row, column, Cell.new(text, bg: :blue))
          assert_frame(next)
          next
        end)

      child = Frame.from_rows(child_rows, 4, 2, cursor: {4, 2})
      frame |> Frame.overlay(child, column, row) |> assert_frame()
    end)
  end

  test "backend diffs reconstruct changed frames including wide-cell and blank erasure" do
    Cases.check(&diff_case/0, fn {width, height, before_rows, after_rows} ->
      before = Frame.from_rows(before_rows, width, height)
      after_frame = Frame.from_rows(after_rows, width, height)
      assert Frame.diff(after_frame, after_frame) == []

      reconstructed =
        Enum.reduce(Frame.diff(before, after_frame), before, fn
          {{row, column}, {char, fg, bg, attrs}}, frame ->
            Frame.put_cell(frame, row, column, Cell.new(char, fg: fg, bg: bg, attrs: attrs))
        end)

      assert reconstructed.cells == after_frame.cells
    end)
  end

  defp frame_case do
    {width, height, rows, after_rows} = diff_case()

    edits =
      for _index <- 1..12,
          do:
            {Cases.integer(0, height + 2), Cases.integer(0, width + 2),
             Cases.choose(["界", "x", " ", "👩‍💻", "\e[31mX"])}

    {width, height, rows, edits, after_rows, Cases.integer(1, width + 2),
     Cases.integer(1, height + 2)}
  end

  defp diff_case do
    width = Cases.integer(1, 24)
    height = Cases.integer(1, 5)
    rows = for _row <- 1..height, do: Cases.text()
    after_rows = for _row <- 1..height, do: Cases.text()
    {width, height, rows, after_rows}
  end

  defp assert_frame(frame) do
    assert {:ok, _frame} = Zoi.parse(Frame.schema(), frame)
    assert map_size(frame.cells) <= frame.width * frame.height

    for row <- 1..frame.height do
      assert DisplayWidth.width(Frame.row_text(frame, row)) == frame.width
    end

    for {{row, column}, cell} <- frame.cells do
      cond do
        cell.wide_placeholder ->
          assert column > 1
          assert %{width: 2, wide_placeholder: false} = Frame.cell(frame, row, column - 1)

        cell.width == 2 ->
          assert column < frame.width
          assert %{width: 0, wide_placeholder: true} = Frame.cell(frame, row, column + 1)

        true ->
          assert cell.width == 1
      end
    end

    frame
  end
end
