defmodule TermUI.Test.Assertions do
  @moduledoc """
  TUI-specific assertion helpers for testing.

  Provides assertions for checking rendered content, styles, component state,
  and focus. Assertions produce clear failure messages showing expected vs actual.

  ## Usage

      use TermUI.Test.Assertions

      # Content assertions
      assert_text(renderer, 1, 1, "Hello")
      assert_text_contains(renderer, 1, 1, 80, "Error")
      refute_text(renderer, 1, 1, "Goodbye")

      # Style assertions
      assert_style(renderer, 1, 1, fg: :red)
      assert_attr(renderer, 1, 1, :bold)

      # State assertions
      assert_state(state, [:counter, :value], 42)
  """

  @doc """
  Imports all assertion macros.

  ## Example

      defmodule MyTest do
        use ExUnit.Case
        use TermUI.Test.Assertions

        test "renders correctly" do
          {:ok, renderer} = TestRenderer.new(24, 80)
          assert_text(renderer, 1, 1, "Hello")
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      import TermUI.Test.Assertions
    end
  end

  alias TermUI.Test.TestRenderer

  @doc """
  Asserts that text appears at the given position.

  ## Examples

      assert_text(renderer, 1, 1, "Hello")
  """
  defmacro assert_text(renderer, row, col, expected) do
    quote do
      renderer = unquote(renderer)
      row = unquote(row)
      col = unquote(col)
      expected = unquote(expected)
      width = String.length(expected)

      actual = TestRenderer.get_text_at(renderer, row, col, width)

      if actual == expected do
        true
      else
        raise ExUnit.AssertionError,
          message: """
          Text assertion failed at (#{row}, #{col})

          Expected: #{inspect(expected)}
          Actual:   #{inspect(actual)}

          Context (row #{row}): #{inspect(TestRenderer.get_row_text(renderer, row) |> String.trim_trailing())}
          """
      end
    end
  end

  @doc """
  Asserts that text does not appear at the given position.
  """
  defmacro refute_text(renderer, row, col, text) do
    quote do
      renderer = unquote(renderer)
      row = unquote(row)
      col = unquote(col)
      text = unquote(text)
      width = String.length(text)

      actual = TestRenderer.get_text_at(renderer, row, col, width)

      if actual != text do
        true
      else
        raise ExUnit.AssertionError,
          message: """
          Text refutation failed at (#{row}, #{col})

          Did not expect: #{inspect(text)}
          But found:      #{inspect(actual)}
          """
      end
    end
  end

  @doc """
  Asserts that a region contains the expected text.

  ## Examples

      assert_text_contains(renderer, 1, 1, 80, "Error")
  """
  defmacro assert_text_contains(renderer, row, col, width, expected) do
    quote do
      renderer = unquote(renderer)
      row = unquote(row)
      col = unquote(col)
      width = unquote(width)
      expected = unquote(expected)

      actual = TestRenderer.get_text_at(renderer, row, col, width)

      if String.contains?(actual, expected) do
        true
      else
        raise ExUnit.AssertionError,
          message: """
          Text contains assertion failed at (#{row}, #{col}) with width #{width}

          Expected to contain: #{inspect(expected)}
          Actual content:      #{inspect(actual)}
          """
      end
    end
  end

  @doc """
  Asserts that a region does not contain the text.
  """
  defmacro refute_text_contains(renderer, row, col, width, text) do
    quote do
      renderer = unquote(renderer)
      row = unquote(row)
      col = unquote(col)
      width = unquote(width)
      text = unquote(text)

      actual = TestRenderer.get_text_at(renderer, row, col, width)

      if String.contains?(actual, text) do
        raise ExUnit.AssertionError,
          message: """
          Text contains refutation failed at (#{row}, #{col}) with width #{width}

          Did not expect to contain: #{inspect(text)}
          Actual content:            #{inspect(actual)}
          """
      else
        true
      end
    end
  end

  @doc """
  Asserts that text exists somewhere in the buffer.

  ## Examples

      assert_text_exists(renderer, "Error")
  """
  defmacro assert_text_exists(renderer, text) do
    quote do
      renderer = unquote(renderer)
      text = unquote(text)

      positions = TestRenderer.find_text(renderer, text)

      if positions != [] do
        true
      else
        raise ExUnit.AssertionError,
          message: """
          Text existence assertion failed

          Expected to find: #{inspect(text)}
          But text was not found in buffer.

          Buffer content:
          #{TestRenderer.to_string(renderer)}
          """
      end
    end
  end

  @doc """
  Asserts that text does not exist anywhere in the buffer.
  """
  defmacro refute_text_exists(renderer, text) do
    quote do
      renderer = unquote(renderer)
      text = unquote(text)

      positions = TestRenderer.find_text(renderer, text)

      if positions == [] do
        true
      else
        raise ExUnit.AssertionError,
          message: """
          Text existence refutation failed

          Expected not to find: #{inspect(text)}
          But found at positions: #{inspect(positions)}
          """
      end
    end
  end

  @doc """
  Asserts that a cell has the expected style.

  ## Options

  - `:fg` - Expected foreground color
  - `:bg` - Expected background color
  - `:attrs` - Expected attributes (list or MapSet)

  ## Examples

      assert_style(renderer, 1, 1, fg: :red)
      assert_style(renderer, 1, 1, fg: :red, bg: :white)
      assert_style(renderer, 1, 1, attrs: [:bold, :underline])
  """
  defmacro assert_style(renderer, row, col, expected) do
    quote do
      renderer = unquote(renderer)
      row = unquote(row)
      col = unquote(col)
      expected = unquote(expected)

      actual_style = TestRenderer.get_style_at(renderer, row, col)

      errors =
        Enum.reduce(expected, [], fn
          {:fg, expected_fg}, acc ->
            if actual_style.fg == expected_fg do
              acc
            else
              ["fg: expected #{inspect(expected_fg)}, got #{inspect(actual_style.fg)}" | acc]
            end

          {:bg, expected_bg}, acc ->
            if actual_style.bg == expected_bg do
              acc
            else
              ["bg: expected #{inspect(expected_bg)}, got #{inspect(actual_style.bg)}" | acc]
            end

          {:attrs, expected_attrs}, acc ->
            expected_set = MapSet.new(List.wrap(expected_attrs))
            actual_set = actual_style.attrs

            if MapSet.equal?(expected_set, actual_set) do
              acc
            else
              [
                "attrs: expected #{inspect(MapSet.to_list(expected_set))}, got #{inspect(MapSet.to_list(actual_set))}"
                | acc
              ]
            end
        end)

      if errors == [] do
        true
      else
        raise ExUnit.AssertionError,
          message: """
          Style assertion failed at (#{row}, #{col})

          #{Enum.join(Enum.reverse(errors), "\n")}
          """
      end
    end
  end

  @doc """
  Asserts that a cell has a specific attribute.

  ## Examples

      assert_attr(renderer, 1, 1, :bold)
  """
  defmacro assert_attr(renderer, row, col, attr) do
    quote do
      renderer = unquote(renderer)
      row = unquote(row)
      col = unquote(col)
      attr = unquote(attr)

      style = TestRenderer.get_style_at(renderer, row, col)

      if MapSet.member?(style.attrs, attr) do
        true
      else
        raise ExUnit.AssertionError,
          message: """
          Attribute assertion failed at (#{row}, #{col})

          Expected attribute: #{inspect(attr)}
          Actual attributes:  #{inspect(MapSet.to_list(style.attrs))}
          """
      end
    end
  end

  @doc """
  Asserts that a cell does not have a specific attribute.
  """
  defmacro refute_attr(renderer, row, col, attr) do
    quote do
      renderer = unquote(renderer)
      row = unquote(row)
      col = unquote(col)
      attr = unquote(attr)

      style = TestRenderer.get_style_at(renderer, row, col)

      if MapSet.member?(style.attrs, attr) do
        raise ExUnit.AssertionError,
          message: """
          Attribute refutation failed at (#{row}, #{col})

          Did not expect attribute: #{inspect(attr)}
          But found in attributes:  #{inspect(MapSet.to_list(style.attrs))}
          """
      else
        true
      end
    end
  end

  @doc """
  Asserts state at a path matches expected value.

  ## Examples

      assert_state(%{counter: %{value: 42}}, [:counter, :value], 42)
      assert_state(state, [:items], [1, 2, 3])
  """
  defmacro assert_state(state, path, expected) do
    quote do
      state = unquote(state)
      path = unquote(path)
      expected = unquote(expected)

      actual = get_in(state, path)

      if actual == expected do
        true
      else
        raise ExUnit.AssertionError,
          message: """
          State assertion failed at path #{inspect(path)}

          Expected: #{inspect(expected)}
          Actual:   #{inspect(actual)}
          """
      end
    end
  end

  @doc """
  Asserts state at a path does not match value.
  """
  defmacro refute_state(state, path, value) do
    quote do
      state = unquote(state)
      path = unquote(path)
      value = unquote(value)

      actual = get_in(state, path)

      if actual != value do
        true
      else
        raise ExUnit.AssertionError,
          message: """
          State refutation failed at path #{inspect(path)}

          Did not expect: #{inspect(value)}
          But found:      #{inspect(actual)}
          """
      end
    end
  end

  @doc """
  Asserts state at a path exists (is not nil).
  """
  defmacro assert_state_exists(state, path) do
    quote do
      state = unquote(state)
      path = unquote(path)

      actual = get_in(state, path)

      if actual != nil do
        true
      else
        raise ExUnit.AssertionError,
          message: """
          State existence assertion failed at path #{inspect(path)}

          Expected value to exist but got nil
          """
      end
    end
  end

  @doc """
  Asserts that a snapshot matches the current buffer.

  ## Examples

      snapshot = TestRenderer.snapshot(renderer)
      # ... operations ...
      assert_snapshot(renderer, snapshot)
  """
  defmacro assert_snapshot(renderer, snapshot) do
    quote do
      renderer = unquote(renderer)
      snapshot = unquote(snapshot)

      if TestRenderer.matches_snapshot?(renderer, snapshot) do
        true
      else
        diffs = TestRenderer.diff_snapshot(renderer, snapshot)
        diff_count = length(diffs)

        sample_list = Enum.take(diffs, 5)
        formatted = Enum.map(sample_list, &unquote(__MODULE__).format_diff/1)
        sample_diffs = Enum.join(formatted, "\n")

        raise ExUnit.AssertionError,
          message: """
          Snapshot assertion failed

          #{diff_count} cells differ#{if diff_count > 5, do: " (showing first 5)", else: ""}:
          #{sample_diffs}

          Expected:
          #{TestRenderer.snapshot_to_string(snapshot)}

          Actual:
          #{TestRenderer.to_string(renderer)}
          """
      end
    end
  end

  @doc """
  Asserts that buffer is empty (all spaces with default style).
  """
  defmacro assert_empty(renderer) do
    quote do
      renderer = unquote(renderer)
      {rows, cols} = TestRenderer.dimensions(renderer)

      non_empty =
        for row <- 1..rows,
            col <- 1..cols,
            !cell_empty?(TestRenderer.get_cell(renderer, row, col)) do
          {row, col}
        end

      if non_empty == [] do
        true
      else
        raise ExUnit.AssertionError,
          message: """
          Empty buffer assertion failed

          Buffer has #{length(non_empty)} non-empty cells
          First few: #{inspect(Enum.take(non_empty, 5))}
          """
      end
    end
  end

  @doc false
  def cell_empty?(cell) do
    cell.char == " " and
      cell.fg == :default and
      cell.bg == :default and
      MapSet.size(cell.attrs) == 0
  end

  @doc false
  def format_diff({row, col, expected, actual}) do
    "  (#{row}, #{col}): expected #{inspect(expected.char)}, got #{inspect(actual.char)}"
  end

  @doc """
  Asserts row matches expected text (trimming trailing spaces).
  """
  defmacro assert_row(renderer, row, expected) do
    quote do
      renderer = unquote(renderer)
      row = unquote(row)
      expected = unquote(expected)

      actual = TestRenderer.get_row_text(renderer, row) |> String.trim_trailing()

      if actual == expected do
        true
      else
        raise ExUnit.AssertionError,
          message: """
          Row assertion failed for row #{row}

          Expected: #{inspect(expected)}
          Actual:   #{inspect(actual)}
          """
      end
    end
  end
end
