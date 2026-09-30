defmodule TermUI.CharacterSetTest do
  use ExUnit.Case, async: true

  alias TermUI.CharacterSet

  # ===========================================================================
  # Task 3.6.1 Tests - Character Set Module
  # ===========================================================================

  describe "get/1 with :unicode" do
    test "returns a map" do
      assert is_map(CharacterSet.get(:unicode))
    end

    test "includes box corners" do
      chars = CharacterSet.get(:unicode)
      assert chars.tl == "┌"
      assert chars.tr == "┐"
      assert chars.bl == "└"
      assert chars.br == "┘"
    end

    test "includes lines" do
      chars = CharacterSet.get(:unicode)
      assert chars.h_line == "─"
      assert chars.v_line == "│"
    end

    test "includes T-junctions" do
      chars = CharacterSet.get(:unicode)
      assert chars.t_up == "┴"
      assert chars.t_down == "┬"
      assert chars.t_left == "┤"
      assert chars.t_right == "├"
    end

    test "includes cross junction" do
      chars = CharacterSet.get(:unicode)
      assert chars.cross == "┼"
    end

    test "includes progress/gauge characters" do
      chars = CharacterSet.get(:unicode)
      assert chars.bar_full == "█"
      assert chars.bar_empty == "░"
      assert is_list(chars.bar_levels)
      assert length(chars.bar_levels) == 8
    end

    test "includes check marks" do
      chars = CharacterSet.get(:unicode)
      assert chars.check == "✓"
      assert chars.cross_mark == "✗"
    end

    test "includes arrows" do
      chars = CharacterSet.get(:unicode)
      assert chars.arrow_up == "↑"
      assert chars.arrow_down == "↓"
      assert chars.arrow_left == "←"
      assert chars.arrow_right == "→"
    end

    test "all characters are strings" do
      chars = CharacterSet.get(:unicode)
      # These keys are lists, not single strings
      list_keys = [:bar_levels, :sparkline_levels, :spinner_frames]

      for key <- CharacterSet.keys() do
        value = Map.get(chars, key)

        if key in list_keys do
          assert is_list(value), "#{key} should be a list"
          assert Enum.all?(value, &is_binary/1), "#{key} elements should be strings"
        else
          assert is_binary(value), "#{key} should be a string, got: #{inspect(value)}"
        end
      end
    end
  end

  describe "get/1 with :ascii" do
    test "returns a map" do
      assert is_map(CharacterSet.get(:ascii))
    end

    test "includes box corners as +" do
      chars = CharacterSet.get(:ascii)
      assert chars.tl == "+"
      assert chars.tr == "+"
      assert chars.bl == "+"
      assert chars.br == "+"
    end

    test "includes lines" do
      chars = CharacterSet.get(:ascii)
      assert chars.h_line == "-"
      assert chars.v_line == "|"
    end

    test "includes T-junctions as +" do
      chars = CharacterSet.get(:ascii)
      assert chars.t_up == "+"
      assert chars.t_down == "+"
      assert chars.t_left == "+"
      assert chars.t_right == "+"
    end

    test "includes cross junction as +" do
      chars = CharacterSet.get(:ascii)
      assert chars.cross == "+"
    end

    test "includes progress/gauge characters" do
      chars = CharacterSet.get(:ascii)
      assert chars.bar_full == "#"
      assert chars.bar_empty == "."
      assert is_list(chars.bar_levels)
      assert length(chars.bar_levels) == 5
    end

    test "includes check marks" do
      chars = CharacterSet.get(:ascii)
      assert chars.check == "x"
      assert chars.cross_mark == "X"
    end

    test "includes arrows" do
      chars = CharacterSet.get(:ascii)
      assert chars.arrow_up == "^"
      assert chars.arrow_down == "v"
      assert chars.arrow_left == "<"
      assert chars.arrow_right == ">"
    end

    test "all characters are strings" do
      chars = CharacterSet.get(:ascii)
      # These keys are lists, not single strings
      list_keys = [:bar_levels, :sparkline_levels, :spinner_frames]

      for key <- CharacterSet.keys() do
        value = Map.get(chars, key)

        if key in list_keys do
          assert is_list(value), "#{key} should be a list"
          assert Enum.all?(value, &is_binary/1), "#{key} elements should be strings"
        else
          assert is_binary(value), "#{key} should be a string, got: #{inspect(value)}"
        end
      end
    end
  end

  describe "get/1 consistency" do
    test "both character sets have the same keys" do
      unicode_keys = CharacterSet.get(:unicode) |> Map.keys() |> Enum.sort()
      ascii_keys = CharacterSet.get(:ascii) |> Map.keys() |> Enum.sort()

      assert unicode_keys == ascii_keys
    end

    test "all expected keys are present" do
      expected_keys = CharacterSet.keys() |> Enum.sort()
      unicode_keys = CharacterSet.get(:unicode) |> Map.keys() |> Enum.sort()

      assert unicode_keys == expected_keys
    end
  end

  describe "get/1 validation" do
    test "raises ArgumentError for invalid charset" do
      assert_raise ArgumentError, ~r/unknown character set :invalid/, fn ->
        CharacterSet.get(:invalid)
      end
    end

    test "raises ArgumentError for string input" do
      assert_raise ArgumentError, ~r/unknown character set "unicode"/, fn ->
        CharacterSet.get("unicode")
      end
    end

    test "error message suggests valid options" do
      error =
        assert_raise ArgumentError, fn ->
          CharacterSet.get(:foo)
        end

      assert error.message =~ "expected :unicode or :ascii"
    end
  end

  describe "keys/0" do
    test "returns a list of atoms" do
      keys = CharacterSet.keys()
      assert is_list(keys)
      assert Enum.all?(keys, &is_atom/1)
    end

    test "includes all box drawing keys" do
      keys = CharacterSet.keys()
      assert :tl in keys
      assert :tr in keys
      assert :bl in keys
      assert :br in keys
      assert :h_line in keys
      assert :v_line in keys
    end

    test "includes all junction keys" do
      keys = CharacterSet.keys()
      assert :t_up in keys
      assert :t_down in keys
      assert :t_left in keys
      assert :t_right in keys
      assert :cross in keys
    end

    test "includes progress/gauge keys" do
      keys = CharacterSet.keys()
      assert :bar_full in keys
      assert :bar_empty in keys
      assert :bar_levels in keys
    end

    test "includes check mark keys" do
      keys = CharacterSet.keys()
      assert :check in keys
      assert :cross_mark in keys
    end

    test "includes arrow keys" do
      keys = CharacterSet.keys()
      assert :arrow_up in keys
      assert :arrow_down in keys
      assert :arrow_left in keys
      assert :arrow_right in keys
    end
  end

  describe "current/0" do
    setup do
      # Save original config
      original = Application.get_env(:term_ui, :character_set)

      on_exit(fn ->
        # Restore original config
        if original do
          Application.put_env(:term_ui, :character_set, original)
        else
          Application.delete_env(:term_ui, :character_set)
        end
      end)

      :ok
    end

    test "defaults to :unicode when not configured" do
      Application.delete_env(:term_ui, :character_set)
      assert CharacterSet.current() == :unicode
    end

    test "returns :unicode when configured" do
      Application.put_env(:term_ui, :character_set, :unicode)
      assert CharacterSet.current() == :unicode
    end

    test "returns :ascii when configured" do
      Application.put_env(:term_ui, :character_set, :ascii)
      assert CharacterSet.current() == :ascii
    end
  end

  describe "current_charset/0" do
    setup do
      # Save original config
      original = Application.get_env(:term_ui, :character_set)

      on_exit(fn ->
        # Restore original config
        if original do
          Application.put_env(:term_ui, :character_set, original)
        else
          Application.delete_env(:term_ui, :character_set)
        end
      end)

      :ok
    end

    test "returns Unicode charset when configured as unicode" do
      Application.put_env(:term_ui, :character_set, :unicode)
      chars = CharacterSet.current_charset()
      assert chars == CharacterSet.get(:unicode)
    end

    test "returns ASCII charset when configured as ascii" do
      Application.put_env(:term_ui, :character_set, :ascii)
      chars = CharacterSet.current_charset()
      assert chars == CharacterSet.get(:ascii)
    end

    test "returns Unicode charset by default" do
      Application.delete_env(:term_ui, :character_set)
      chars = CharacterSet.current_charset()
      assert chars == CharacterSet.get(:unicode)
    end

    test "returns a valid character map" do
      chars = CharacterSet.current_charset()
      assert is_map(chars)
      assert Map.has_key?(chars, :tl)
      assert Map.has_key?(chars, :bar_levels)
    end
  end

  describe "Unicode character validity" do
    test "Unicode box-drawing characters are single graphemes" do
      chars = CharacterSet.get(:unicode)

      # Box drawing should all be single graphemes
      single_grapheme_keys = [
        :tl,
        :tr,
        :bl,
        :br,
        :h_line,
        :v_line,
        :t_up,
        :t_down,
        :t_left,
        :t_right,
        :cross,
        :bar_full,
        :bar_empty,
        :check,
        :cross_mark,
        :arrow_up,
        :arrow_down,
        :arrow_left,
        :arrow_right
      ]

      for key <- single_grapheme_keys do
        value = Map.get(chars, key)
        graphemes = String.graphemes(value)

        assert length(graphemes) == 1,
               "#{key} should be single grapheme, got #{length(graphemes)}: #{inspect(value)}"
      end
    end

    test "bar_levels are all single graphemes" do
      chars = CharacterSet.get(:unicode)

      for {level, index} <- Enum.with_index(chars.bar_levels) do
        graphemes = String.graphemes(level)

        assert length(graphemes) == 1,
               "bar_levels[#{index}] should be single grapheme, got: #{inspect(level)}"
      end
    end
  end

  describe "ASCII character validity" do
    test "ASCII characters are all printable" do
      chars = CharacterSet.get(:ascii)
      # These keys are lists, not single strings
      list_keys = [:bar_levels, :sparkline_levels, :spinner_frames]

      for key <- CharacterSet.keys() do
        value = Map.get(chars, key)

        if key in list_keys do
          for {level, _} <- Enum.with_index(value) do
            assert String.printable?(level),
                   "#{key} contains non-printable: #{inspect(level)}"
          end
        else
          assert String.printable?(value), "#{key} is not printable: #{inspect(value)}"
        end
      end
    end

    test "ASCII characters are single bytes (except space)" do
      chars = CharacterSet.get(:ascii)

      single_char_keys = [
        :tl,
        :tr,
        :bl,
        :br,
        :h_line,
        :v_line,
        :t_up,
        :t_down,
        :t_left,
        :t_right,
        :cross,
        :bar_full,
        :bar_empty,
        :check,
        :cross_mark,
        :arrow_up,
        :arrow_down,
        :arrow_left,
        :arrow_right
      ]

      for key <- single_char_keys do
        value = Map.get(chars, key)
        assert byte_size(value) == 1, "#{key} should be single byte, got: #{inspect(value)}"
      end
    end
  end

  # ===========================================================================
  # Line Drawing Convenience Functions Tests
  # ===========================================================================

  describe "horizontal_line/1" do
    test "creates line of specified width" do
      Application.put_env(:term_ui, :character_set, :unicode)
      line = CharacterSet.horizontal_line(5)
      assert line == "─────"
    end

    test "returns empty string for width 0" do
      assert CharacterSet.horizontal_line(0) == ""
    end

    test "uses ascii characters when configured" do
      Application.put_env(:term_ui, :character_set, :ascii)
      line = CharacterSet.horizontal_line(5)
      assert line == "-----"
      Application.put_env(:term_ui, :character_set, :unicode)
    end
  end

  describe "vertical_line/1" do
    test "creates list of vertical characters" do
      Application.put_env(:term_ui, :character_set, :unicode)
      lines = CharacterSet.vertical_line(3)
      assert lines == ["│", "│", "│"]
    end

    test "returns empty list for height 0" do
      assert CharacterSet.vertical_line(0) == []
    end

    test "uses ascii characters when configured" do
      Application.put_env(:term_ui, :character_set, :ascii)
      lines = CharacterSet.vertical_line(3)
      assert lines == ["|", "|", "|"]
      Application.put_env(:term_ui, :character_set, :unicode)
    end
  end

  describe "box_top/1" do
    test "creates top border with corners" do
      Application.put_env(:term_ui, :character_set, :unicode)
      top = CharacterSet.box_top(10)
      assert top == "┌────────┐"
    end

    test "handles minimum width of 2" do
      Application.put_env(:term_ui, :character_set, :unicode)
      top = CharacterSet.box_top(2)
      assert top == "┌┐"
    end

    test "handles width of 1" do
      Application.put_env(:term_ui, :character_set, :unicode)
      top = CharacterSet.box_top(1)
      assert top == "─"
    end

    test "uses ascii characters when configured" do
      Application.put_env(:term_ui, :character_set, :ascii)
      top = CharacterSet.box_top(10)
      assert top == "+--------+"
      Application.put_env(:term_ui, :character_set, :unicode)
    end
  end

  describe "box_bottom/1" do
    test "creates bottom border with corners" do
      Application.put_env(:term_ui, :character_set, :unicode)
      bottom = CharacterSet.box_bottom(10)
      assert bottom == "└────────┘"
    end

    test "handles minimum width of 2" do
      Application.put_env(:term_ui, :character_set, :unicode)
      bottom = CharacterSet.box_bottom(2)
      assert bottom == "└┘"
    end

    test "uses ascii characters when configured" do
      Application.put_env(:term_ui, :character_set, :ascii)
      bottom = CharacterSet.box_bottom(10)
      assert bottom == "+--------+"
      Application.put_env(:term_ui, :character_set, :unicode)
    end
  end
end
