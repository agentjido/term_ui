defmodule TermUI.Test.TestRendererTest do
  use ExUnit.Case, async: true

  alias TermUI.Renderer.Cell
  alias TermUI.Test.TestRenderer

  describe "new/2 and destroy/1" do
    test "creates renderer with correct dimensions" do
      {:ok, renderer} = TestRenderer.new(24, 80)
      assert {24, 80} == TestRenderer.dimensions(renderer)
      TestRenderer.destroy(renderer)
    end

    test "initializes with empty cells" do
      {:ok, renderer} = TestRenderer.new(10, 10)
      cell = TestRenderer.get_cell(renderer, 1, 1)
      assert cell.char == " "
      assert cell.fg == :default
      TestRenderer.destroy(renderer)
    end
  end

  describe "set_cell/4 and get_cell/3" do
    test "sets and gets cell correctly" do
      {:ok, renderer} = TestRenderer.new(10, 10)
      cell = Cell.new("X", fg: :red)
      :ok = TestRenderer.set_cell(renderer, 1, 1, cell)

      result = TestRenderer.get_cell(renderer, 1, 1)
      assert result.char == "X"
      assert result.fg == :red
      TestRenderer.destroy(renderer)
    end

    test "returns error for out of bounds" do
      {:ok, renderer} = TestRenderer.new(10, 10)
      cell = Cell.new("X")
      assert {:error, :out_of_bounds} = TestRenderer.set_cell(renderer, 11, 1, cell)
      TestRenderer.destroy(renderer)
    end
  end

  describe "write_string/5" do
    test "writes string at position" do
      {:ok, renderer} = TestRenderer.new(10, 80)
      TestRenderer.write_string(renderer, 1, 1, "Hello")

      assert TestRenderer.get_text_at(renderer, 1, 1, 5) == "Hello"
      TestRenderer.destroy(renderer)
    end

    test "returns number of columns written" do
      {:ok, renderer} = TestRenderer.new(10, 80)
      written = TestRenderer.write_string(renderer, 1, 1, "Hello")
      assert written == 5
      TestRenderer.destroy(renderer)
    end
  end

  describe "get_text_at/4" do
    test "returns text at position with width" do
      {:ok, renderer} = TestRenderer.new(10, 80)
      TestRenderer.write_string(renderer, 1, 1, "Hello, World!")

      assert TestRenderer.get_text_at(renderer, 1, 1, 5) == "Hello"
      assert TestRenderer.get_text_at(renderer, 1, 8, 5) == "World"
      TestRenderer.destroy(renderer)
    end

    test "returns spaces for empty cells" do
      {:ok, renderer} = TestRenderer.new(10, 80)
      assert TestRenderer.get_text_at(renderer, 1, 1, 5) == "     "
      TestRenderer.destroy(renderer)
    end
  end

  describe "get_style_at/3" do
    test "returns style at position" do
      {:ok, renderer} = TestRenderer.new(10, 80)
      cell = Cell.new("X", fg: :red, bg: :blue, attrs: [:bold])
      TestRenderer.set_cell(renderer, 1, 1, cell)

      style = TestRenderer.get_style_at(renderer, 1, 1)
      assert style.fg == :red
      assert style.bg == :blue
      assert MapSet.member?(style.attrs, :bold)
      TestRenderer.destroy(renderer)
    end
  end

  describe "get_row_text/2" do
    test "returns entire row as text" do
      {:ok, renderer} = TestRenderer.new(10, 20)
      TestRenderer.write_string(renderer, 1, 1, "Hello")

      row = TestRenderer.get_row_text(renderer, 1)
      assert String.starts_with?(row, "Hello")
      assert String.length(row) == 20
      TestRenderer.destroy(renderer)
    end
  end

  describe "text_at?/4" do
    test "returns true when text matches" do
      {:ok, renderer} = TestRenderer.new(10, 80)
      TestRenderer.write_string(renderer, 1, 1, "Hello")

      assert TestRenderer.text_at?(renderer, 1, 1, "Hello")
      assert TestRenderer.text_at?(renderer, 1, 1, "He")
      TestRenderer.destroy(renderer)
    end

    test "returns false when text differs" do
      {:ok, renderer} = TestRenderer.new(10, 80)
      TestRenderer.write_string(renderer, 1, 1, "Hello")

      refute TestRenderer.text_at?(renderer, 1, 1, "World")
      TestRenderer.destroy(renderer)
    end
  end

  describe "text_contains?/5" do
    test "returns true when text contains substring" do
      {:ok, renderer} = TestRenderer.new(10, 80)
      TestRenderer.write_string(renderer, 1, 1, "Hello, World!")

      assert TestRenderer.text_contains?(renderer, 1, 1, 13, "World")
      TestRenderer.destroy(renderer)
    end

    test "returns false when text does not contain substring" do
      {:ok, renderer} = TestRenderer.new(10, 80)
      TestRenderer.write_string(renderer, 1, 1, "Hello")

      refute TestRenderer.text_contains?(renderer, 1, 1, 5, "World")
      TestRenderer.destroy(renderer)
    end
  end

  describe "find_text/2" do
    test "finds text positions in buffer" do
      {:ok, renderer} = TestRenderer.new(10, 80)
      TestRenderer.write_string(renderer, 1, 1, "Error here")
      TestRenderer.write_string(renderer, 3, 10, "Another Error")

      positions = TestRenderer.find_text(renderer, "Error")
      assert {1, 1} in positions
      assert {3, 18} in positions
      TestRenderer.destroy(renderer)
    end

    test "returns empty list when not found" do
      {:ok, renderer} = TestRenderer.new(10, 80)
      TestRenderer.write_string(renderer, 1, 1, "Hello")

      assert TestRenderer.find_text(renderer, "Error") == []
      TestRenderer.destroy(renderer)
    end
  end

  describe "snapshot/1 and matches_snapshot?/2" do
    test "creates snapshot of buffer" do
      {:ok, renderer} = TestRenderer.new(5, 10)
      TestRenderer.write_string(renderer, 1, 1, "Test")

      snapshot = TestRenderer.snapshot(renderer)
      assert snapshot.rows == 5
      assert snapshot.cols == 10
      assert snapshot.cells[{1, 1}].char == "T"
      TestRenderer.destroy(renderer)
    end

    test "matches identical buffer" do
      {:ok, renderer} = TestRenderer.new(5, 10)
      TestRenderer.write_string(renderer, 1, 1, "Test")
      snapshot = TestRenderer.snapshot(renderer)

      assert TestRenderer.matches_snapshot?(renderer, snapshot)
      TestRenderer.destroy(renderer)
    end

    test "does not match modified buffer" do
      {:ok, renderer} = TestRenderer.new(5, 10)
      TestRenderer.write_string(renderer, 1, 1, "Test")
      snapshot = TestRenderer.snapshot(renderer)

      TestRenderer.write_string(renderer, 1, 1, "Changed")
      refute TestRenderer.matches_snapshot?(renderer, snapshot)
      TestRenderer.destroy(renderer)
    end
  end

  describe "diff_snapshot/2" do
    test "returns differences between buffer and snapshot" do
      {:ok, renderer} = TestRenderer.new(5, 10)
      TestRenderer.write_string(renderer, 1, 1, "Test")
      snapshot = TestRenderer.snapshot(renderer)

      TestRenderer.write_string(renderer, 1, 1, "Best")
      diffs = TestRenderer.diff_snapshot(renderer, snapshot)

      # First character changed from T to B
      assert diffs != []
      TestRenderer.destroy(renderer)
    end
  end

  describe "clear/1" do
    test "clears all cells to empty" do
      {:ok, renderer} = TestRenderer.new(10, 10)
      TestRenderer.write_string(renderer, 1, 1, "Hello")
      TestRenderer.clear(renderer)

      assert TestRenderer.get_text_at(renderer, 1, 1, 5) == "     "
      TestRenderer.destroy(renderer)
    end
  end

  describe "to_string/1" do
    test "converts buffer to printable string" do
      {:ok, renderer} = TestRenderer.new(3, 10)
      TestRenderer.write_string(renderer, 1, 1, "Line 1")
      TestRenderer.write_string(renderer, 2, 1, "Line 2")

      result = TestRenderer.to_string(renderer)
      assert result =~ "Line 1"
      assert result =~ "Line 2"
      TestRenderer.destroy(renderer)
    end
  end

  describe "in_bounds?/3" do
    test "returns true for valid positions" do
      {:ok, renderer} = TestRenderer.new(10, 20)
      assert TestRenderer.in_bounds?(renderer, 1, 1)
      assert TestRenderer.in_bounds?(renderer, 10, 20)
      TestRenderer.destroy(renderer)
    end

    test "returns false for invalid positions" do
      {:ok, renderer} = TestRenderer.new(10, 20)
      refute TestRenderer.in_bounds?(renderer, 0, 1)
      refute TestRenderer.in_bounds?(renderer, 11, 1)
      refute TestRenderer.in_bounds?(renderer, 1, 21)
      TestRenderer.destroy(renderer)
    end
  end
end
