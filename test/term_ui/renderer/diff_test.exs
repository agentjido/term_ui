defmodule TermUI.Renderer.DiffTest do
  use ExUnit.Case, async: true

  alias TermUI.Renderer.Buffer
  alias TermUI.Renderer.Cell
  alias TermUI.Renderer.Diff
  alias TermUI.Renderer.Style

  describe "diff/2" do
    test "returns empty list for identical buffers" do
      {:ok, current} = Buffer.new(5, 10)
      {:ok, previous} = Buffer.new(5, 10)

      operations = Diff.diff(current, previous)
      assert operations == []

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "detects single cell change" do
      {:ok, current} = Buffer.new(5, 10)
      {:ok, previous} = Buffer.new(5, 10)

      Buffer.set_cell(current, 1, 1, Cell.new("X"))

      operations = Diff.diff(current, previous)

      assert {:move, 1, 1} in operations

      assert Enum.any?(operations, fn
               {:text, "X"} -> true
               _ -> false
             end)

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "detects multiple changes on same row" do
      {:ok, current} = Buffer.new(5, 10)
      {:ok, previous} = Buffer.new(5, 10)

      Buffer.set_cell(current, 1, 1, Cell.new("A"))
      Buffer.set_cell(current, 1, 5, Cell.new("B"))

      operations = Diff.diff(current, previous)

      # Should have moves for both changes
      move_ops =
        Enum.filter(operations, fn
          {:move, _, _} -> true
          _ -> false
        end)

      assert move_ops != []

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "detects changes across multiple rows" do
      {:ok, current} = Buffer.new(5, 10)
      {:ok, previous} = Buffer.new(5, 10)

      Buffer.set_cell(current, 1, 1, Cell.new("A"))
      Buffer.set_cell(current, 3, 5, Cell.new("B"))

      operations = Diff.diff(current, previous)

      move_ops =
        Enum.filter(operations, fn
          {:move, _, _} -> true
          _ -> false
        end)

      # Should have at least 2 moves for different rows
      assert length(move_ops) >= 2

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "handles contiguous changes as single span" do
      {:ok, current} = Buffer.new(5, 20)
      {:ok, previous} = Buffer.new(5, 20)

      Buffer.write_string(current, 1, 1, "Hello")

      operations = Diff.diff(current, previous)

      # Should have single move for contiguous text
      move_ops =
        Enum.filter(operations, fn
          {:move, _, _} -> true
          _ -> false
        end)

      assert length(move_ops) == 1
      assert {:move, 1, 1} in move_ops

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end
  end

  describe "diff_row/4" do
    test "returns empty for unchanged row" do
      {:ok, current} = Buffer.new(5, 10)
      {:ok, previous} = Buffer.new(5, 10)

      operations = Diff.diff_row(current, previous, 1, 10)
      assert operations == []

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "detects single change in row" do
      {:ok, current} = Buffer.new(5, 10)
      {:ok, previous} = Buffer.new(5, 10)

      Buffer.set_cell(current, 2, 5, Cell.new("X", fg: :red))

      operations = Diff.diff_row(current, previous, 2, 10)

      assert {:move, 2, 5} in operations

      assert Enum.any?(operations, fn
               {:text, "X"} -> true
               _ -> false
             end)

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "handles style changes" do
      {:ok, current} = Buffer.new(5, 10)
      {:ok, previous} = Buffer.new(5, 10)

      # Same character, different color
      Buffer.set_cell(current, 1, 1, Cell.new("A", fg: :red))
      Buffer.set_cell(previous, 1, 1, Cell.new("A", fg: :blue))

      operations = Diff.diff_row(current, previous, 1, 10)

      style_ops =
        Enum.filter(operations, fn
          {:style, _} -> true
          _ -> false
        end)

      assert style_ops != []

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end
  end

  describe "find_changed_spans/3" do
    test "finds single span" do
      current_cells = [
        {1, Cell.new("A")},
        {2, Cell.new(" ")},
        {3, Cell.new(" ")}
      ]

      previous_cells = [
        {1, Cell.empty()},
        {2, Cell.empty()},
        {3, Cell.empty()}
      ]

      spans = Diff.find_changed_spans(current_cells, previous_cells, 1)

      assert length(spans) == 1
      [span] = spans
      assert span.row == 1
      assert span.start_col == 1
      assert span.end_col == 1
    end

    test "finds multiple disjoint spans" do
      current_cells = [
        {1, Cell.new("A")},
        {2, Cell.empty()},
        {3, Cell.empty()},
        {4, Cell.empty()},
        {5, Cell.new("B")}
      ]

      previous_cells = for i <- 1..5, do: {i, Cell.empty()}

      spans = Diff.find_changed_spans(current_cells, previous_cells, 1)

      assert length(spans) == 2
    end

    test "finds contiguous span" do
      current_cells = [
        {1, Cell.new("H")},
        {2, Cell.new("i")},
        {3, Cell.empty()}
      ]

      previous_cells = for i <- 1..3, do: {i, Cell.empty()}

      spans = Diff.find_changed_spans(current_cells, previous_cells, 1)

      assert length(spans) == 1
      [span] = spans
      assert span.start_col == 1
      assert span.end_col == 2
    end
  end

  describe "merge_spans/2" do
    test "returns empty for empty input" do
      assert Diff.merge_spans([], %{}) == []
    end

    test "returns single span unchanged" do
      span = %{
        row: 1,
        start_col: 1,
        end_col: 3,
        cells: [Cell.new("A"), Cell.new("B"), Cell.new("C")]
      }

      assert Diff.merge_spans([span], %{}) == [span]
    end

    test "merges spans with small gap using actual cells" do
      span1 = %{row: 1, start_col: 1, end_col: 2, cells: [Cell.new("A"), Cell.new("B")]}
      span2 = %{row: 1, start_col: 4, end_col: 5, cells: [Cell.new("D"), Cell.new("E")]}

      # Provide the actual cell for column 3 (the gap)
      current_cells_map = %{
        1 => Cell.new("A"),
        2 => Cell.new("B"),
        3 => Cell.new("C"),
        4 => Cell.new("D"),
        5 => Cell.new("E")
      }

      merged = Diff.merge_spans([span1, span2], current_cells_map)

      # Gap of 1 should be merged (< threshold of 3)
      assert length(merged) == 1
      [result] = merged
      assert result.start_col == 1
      assert result.end_col == 5
      # Check that the gap cell is the actual cell from current buffer
      assert length(result.cells) == 5
      assert Enum.at(result.cells, 2).char == "C"
    end

    test "keeps spans with large gap separate" do
      span1 = %{row: 1, start_col: 1, end_col: 2, cells: [Cell.new("A"), Cell.new("B")]}
      span2 = %{row: 1, start_col: 10, end_col: 11, cells: [Cell.new("C"), Cell.new("D")]}

      merged = Diff.merge_spans([span1, span2], %{})

      # Gap of 7 should not be merged
      assert length(merged) == 2
    end
  end

  describe "span_to_operations/1" do
    test "generates move and text operations" do
      span = %{
        row: 5,
        start_col: 10,
        cells: [Cell.new("H"), Cell.new("i")]
      }

      operations = Diff.span_to_operations(span)

      assert {:move, 5, 10} in operations

      assert Enum.any?(operations, fn
               {:text, text} -> String.contains?(text, "H") and String.contains?(text, "i")
               _ -> false
             end)
    end

    test "generates style operations" do
      span = %{
        row: 1,
        start_col: 1,
        cells: [Cell.new("X", fg: :red)]
      }

      operations = Diff.span_to_operations(span)

      style_ops =
        Enum.filter(operations, fn
          {:style, _} -> true
          _ -> false
        end)

      assert style_ops != []
    end

    test "splits on style changes" do
      span = %{
        row: 1,
        start_col: 1,
        cells: [
          Cell.new("A", fg: :red),
          Cell.new("B", fg: :blue)
        ]
      }

      operations = Diff.span_to_operations(span)

      style_ops =
        Enum.filter(operations, fn
          {:style, _} -> true
          _ -> false
        end)

      # Should have 2 style operations for different colors
      assert length(style_ops) == 2
    end
  end

  describe "wide_char?/1" do
    test "returns false for ASCII character" do
      cell = Cell.new("A")
      refute Diff.wide_char?(cell)
    end

    test "returns true for CJK character" do
      cell = Cell.new("日")
      assert Diff.wide_char?(cell)
    end

    test "returns false for space" do
      cell = Cell.empty()
      refute Diff.wide_char?(cell)
    end
  end

  describe "Style.equal?/2" do
    test "returns true for identical styles" do
      s1 = Style.new(fg: :red, bg: :black, attrs: [:bold])
      s2 = Style.new(fg: :red, bg: :black, attrs: [:bold])
      assert Style.equal?(s1, s2)
    end

    test "returns false for different fg" do
      s1 = Style.new(fg: :red)
      s2 = Style.new(fg: :blue)
      refute Style.equal?(s1, s2)
    end

    test "returns false for different bg" do
      s1 = Style.new(bg: :white)
      s2 = Style.new(bg: :black)
      refute Style.equal?(s1, s2)
    end

    test "returns false for different attrs" do
      s1 = Style.new(attrs: [:bold])
      s2 = Style.new(attrs: [:italic])
      refute Style.equal?(s1, s2)
    end

    test "handles empty styles" do
      s1 = Style.new()
      s2 = Style.new()
      assert Style.equal?(s1, s2)
    end
  end

  describe "integration scenarios" do
    test "simple text rendering" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      Buffer.write_string(current, 1, 1, "Hello World")

      operations = Diff.diff(current, previous)

      # Should have move to start
      assert {:move, 1, 1} in operations

      # Should have text
      text_ops =
        Enum.filter(operations, fn
          {:text, _} -> true
          _ -> false
        end)

      assert text_ops != []
      text = Enum.map_join(text_ops, "", fn {:text, t} -> t end)
      assert text == "Hello World"

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "styled text rendering" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      style = Style.new() |> Style.fg(:green) |> Style.bold()
      Buffer.write_string(current, 1, 1, "Test", style: style)

      operations = Diff.diff(current, previous)

      style_ops =
        Enum.filter(operations, fn
          {:style, s} -> s.fg == :green
          _ -> false
        end)

      assert style_ops != []

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "partial update" do
      {:ok, current} = Buffer.new(24, 80)
      {:ok, previous} = Buffer.new(24, 80)

      # Set up identical content
      Buffer.write_string(current, 1, 1, "Hello World")
      Buffer.write_string(previous, 1, 1, "Hello World")

      # Change just one word
      Buffer.write_string(current, 1, 7, "Elixir")

      operations = Diff.diff(current, previous)

      # Should only update changed portion
      move_ops =
        Enum.filter(operations, fn
          {:move, _, _} -> true
          _ -> false
        end)

      assert length(move_ops) == 1
      [{:move, row, col}] = move_ops
      assert row == 1
      assert col == 7

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "multiple rows with changes" do
      {:ok, current} = Buffer.new(10, 40)
      {:ok, previous} = Buffer.new(10, 40)

      Buffer.write_string(current, 1, 1, "Line 1")
      Buffer.write_string(current, 5, 1, "Line 5")
      Buffer.write_string(current, 10, 1, "Line 10")

      operations = Diff.diff(current, previous)

      move_ops =
        Enum.filter(operations, fn
          {:move, _, _} -> true
          _ -> false
        end)

      # Should have moves for each changed row
      assert length(move_ops) == 3

      rows = move_ops |> Enum.map(fn {:move, r, _} -> r end) |> Enum.sort()
      assert rows == [1, 5, 10]

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "deterministic output" do
      {:ok, current} = Buffer.new(5, 20)
      {:ok, previous} = Buffer.new(5, 20)

      Buffer.write_string(current, 1, 1, "Test")
      Buffer.write_string(current, 2, 5, "Data")

      ops1 = Diff.diff(current, previous)
      ops2 = Diff.diff(current, previous)

      assert ops1 == ops2

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end
  end

  describe "edge cases" do
    test "handles empty buffers" do
      {:ok, current} = Buffer.new(1, 1)
      {:ok, previous} = Buffer.new(1, 1)

      operations = Diff.diff(current, previous)
      assert operations == []

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "handles full screen change" do
      {:ok, current} = Buffer.new(3, 5)
      {:ok, previous} = Buffer.new(3, 5)

      # Fill entire screen
      for row <- 1..3, col <- 1..5 do
        Buffer.set_cell(current, row, col, Cell.new("X"))
      end

      operations = Diff.diff(current, previous)

      # Should have operations for all rows
      move_ops =
        Enum.filter(operations, fn
          {:move, _, _} -> true
          _ -> false
        end)

      assert length(move_ops) == 3

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "re-emits style on each row when adjacent rows share a style" do
      # Regression test: filter_redundant_style must invalidate its
      # tracked last_style when a :reset op flows through, otherwise
      # the second row span's :style gets deduped after the :reset
      # has already cleared the terminal SGR state -- leaving every
      # row but the first rendered without styling.
      {:ok, current} = Buffer.new(2, 5)
      {:ok, previous} = Buffer.new(2, 5)

      cell = Cell.new("X", bg: 236)

      for col <- 1..5 do
        Buffer.set_cell(current, 1, col, cell)
        Buffer.set_cell(current, 2, col, cell)
      end

      operations = Diff.diff(current, previous)

      style_ops =
        Enum.filter(operations, fn
          {:style, %Style{bg: 236}} -> true
          _ -> false
        end)

      assert length(style_ops) == 2,
             "expected one :style op per row, got #{length(style_ops)}: #{inspect(operations)}"

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end

    test "handles changes at buffer boundaries" do
      {:ok, current} = Buffer.new(5, 10)
      {:ok, previous} = Buffer.new(5, 10)

      # First and last positions
      Buffer.set_cell(current, 1, 1, Cell.new("A"))
      Buffer.set_cell(current, 5, 10, Cell.new("Z"))

      operations = Diff.diff(current, previous)

      move_ops =
        Enum.filter(operations, fn
          {:move, _, _} -> true
          _ -> false
        end)

      assert length(move_ops) == 2

      Buffer.destroy(current)
      Buffer.destroy(previous)
    end
  end
end
