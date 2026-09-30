defmodule TermUI.DisplayWidth do
  @moduledoc """
  Calculates display width of Unicode characters and strings.

  Display width determines how many terminal columns a character occupies:
  - Most characters are single-width (1 column)
  - East Asian characters (CJK) are double-width (2 columns)
  - Combining characters are zero-width (0 columns)

  This module uses Unicode properties to determine width, essential for
  correct cursor positioning and layout calculations.
  """

  @doc """
  Returns the display width of a grapheme cluster.

  ## Examples

      iex> DisplayWidth.width("A")
      1

      iex> DisplayWidth.width("日")
      2

      iex> DisplayWidth.width("é")  # e + combining acute
      1
  """
  @spec width(String.t()) :: non_neg_integer()
  def width(grapheme) when is_binary(grapheme) do
    grapheme
    |> String.to_charlist()
    |> Enum.reduce(0, fn codepoint, acc ->
      acc + char_width(codepoint)
    end)
    |> max(0)
  end

  @doc """
  Returns the total display width of a string.

  ## Examples

      iex> DisplayWidth.string_width("Hello")
      5

      iex> DisplayWidth.string_width("日本語")
      6

      iex> DisplayWidth.string_width("Café")
      4
  """
  @spec string_width(String.t()) :: non_neg_integer()
  def string_width(string) when is_binary(string) do
    string
    |> String.graphemes()
    |> Enum.reduce(0, fn grapheme, acc ->
      acc + width(grapheme)
    end)
  end

  @doc """
  Checks if a character is double-width (East Asian Wide/Fullwidth).

  ## Examples

      iex> DisplayWidth.double_width?("日")
      true

      iex> DisplayWidth.double_width?("A")
      false
  """
  @spec double_width?(String.t()) :: boolean()
  def double_width?(grapheme) when is_binary(grapheme) do
    width(grapheme) == 2
  end

  @doc """
  Checks if a character is zero-width (combining character).

  ## Examples

      iex> DisplayWidth.zero_width?("\\u0301")  # combining acute
      true

      iex> DisplayWidth.zero_width?("A")
      false
  """
  @spec zero_width?(String.t()) :: boolean()
  def zero_width?(grapheme) when is_binary(grapheme) do
    width(grapheme) == 0
  end

  @doc """
  Truncates a string to fit within the given display width.

  Returns the truncated string and its actual display width.

  ## Examples

      iex> DisplayWidth.truncate("Hello World", 5)
      {"Hello", 5}

      iex> DisplayWidth.truncate("日本語", 4)
      {"日本", 4}
  """
  @spec truncate(String.t(), non_neg_integer()) :: {String.t(), non_neg_integer()}
  def truncate(string, max_width) when is_binary(string) and is_integer(max_width) do
    string
    |> String.graphemes()
    |> Enum.reduce_while({[], 0}, fn grapheme, {chars, current_width} ->
      grapheme_width = width(grapheme)
      new_width = current_width + grapheme_width

      if new_width <= max_width do
        {:cont, {[grapheme | chars], new_width}}
      else
        {:halt, {chars, current_width}}
      end
    end)
    |> then(fn {chars, final_width} ->
      {chars |> Enum.reverse() |> Enum.join(), final_width}
    end)
  end

  @doc """
  Pads a string to the given display width.

  ## Options

  - `:direction` - `:left`, `:right`, or `:center` (default: `:right`)
  - `:char` - Padding character (default: " ")

  ## Examples

      iex> DisplayWidth.pad("Hi", 5)
      "Hi   "

      iex> DisplayWidth.pad("Hi", 5, direction: :left)
      "   Hi"

      iex> DisplayWidth.pad("日", 4)
      "日  "
  """
  @spec pad(String.t(), non_neg_integer(), keyword()) :: String.t()
  def pad(string, target_width, opts \\ []) when is_binary(string) and is_integer(target_width) do
    direction = Keyword.get(opts, :direction, :right)
    pad_char = Keyword.get(opts, :char, " ")

    current_width = string_width(string)
    padding_needed = max(0, target_width - current_width)

    case direction do
      :right ->
        string <> String.duplicate(pad_char, padding_needed)

      :left ->
        String.duplicate(pad_char, padding_needed) <> string

      :center ->
        left_pad = div(padding_needed, 2)
        right_pad = padding_needed - left_pad
        String.duplicate(pad_char, left_pad) <> string <> String.duplicate(pad_char, right_pad)
    end
  end

  # Private character width calculation

  # Control characters and NULL
  defp char_width(c) when c < 32, do: 0
  defp char_width(127), do: 0

  # DEL through 0x9F (C1 control characters)
  defp char_width(c) when c >= 0x7F and c <= 0x9F, do: 0

  # Combining characters (common ranges)
  # Combining Diacritical Marks
  defp char_width(c) when c >= 0x0300 and c <= 0x036F, do: 0
  # Combining Diacritical Marks Extended
  defp char_width(c) when c >= 0x1AB0 and c <= 0x1AFF, do: 0
  # Combining Diacritical Marks Supplement
  defp char_width(c) when c >= 0x1DC0 and c <= 0x1DFF, do: 0
  # Combining Diacritical Marks for Symbols
  defp char_width(c) when c >= 0x20D0 and c <= 0x20FF, do: 0
  # Combining Half Marks
  defp char_width(c) when c >= 0xFE20 and c <= 0xFE2F, do: 0

  # Zero-width characters
  # Zero Width Space, Non-Joiner, Joiner
  defp char_width(c) when c in [0x200B, 0x200C, 0x200D], do: 0
  # Word Joiner
  defp char_width(0x2060), do: 0
  # Zero Width No-Break Space (BOM)
  defp char_width(0xFEFF), do: 0

  # East Asian Wide characters (W and F categories)
  # CJK Radicals Supplement through Ideographic Description
  defp char_width(c) when c >= 0x2E80 and c <= 0x2FFF, do: 2
  # CJK Symbols and Punctuation, Hiragana, Katakana
  defp char_width(c) when c >= 0x3000 and c <= 0x303F, do: 2
  defp char_width(c) when c >= 0x3040 and c <= 0x309F, do: 2
  defp char_width(c) when c >= 0x30A0 and c <= 0x30FF, do: 2
  # Bopomofo through CJK Unified Ideographs Extension A
  defp char_width(c) when c >= 0x3100 and c <= 0x4DBF, do: 2
  # CJK Unified Ideographs
  defp char_width(c) when c >= 0x4E00 and c <= 0x9FFF, do: 2
  # Hangul Jamo
  defp char_width(c) when c >= 0x1100 and c <= 0x11FF, do: 2
  # Hangul Compatibility Jamo
  defp char_width(c) when c >= 0x3130 and c <= 0x318F, do: 2
  # Hangul Syllables
  defp char_width(c) when c >= 0xAC00 and c <= 0xD7AF, do: 2
  # CJK Compatibility Ideographs
  defp char_width(c) when c >= 0xF900 and c <= 0xFAFF, do: 2
  # Fullwidth Forms
  defp char_width(c) when c >= 0xFF01 and c <= 0xFF60, do: 2
  defp char_width(c) when c >= 0xFFE0 and c <= 0xFFE6, do: 2
  # CJK Unified Ideographs Extension B-F and beyond
  defp char_width(c) when c >= 0x20000 and c <= 0x2FFFF, do: 2
  defp char_width(c) when c >= 0x30000 and c <= 0x3FFFF, do: 2

  # Emoji (most are wide)
  # Miscellaneous Symbols and Pictographs
  defp char_width(c) when c >= 0x1F300 and c <= 0x1F64F, do: 2
  # Emoticons
  defp char_width(c) when c >= 0x1F680 and c <= 0x1F6FF, do: 2
  # Transport and Map Symbols, Supplemental Symbols
  defp char_width(c) when c >= 0x1F900 and c <= 0x1F9FF, do: 2

  # Default: single width
  defp char_width(_), do: 1
end
