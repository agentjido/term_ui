defmodule TermUI.ANSI do
  @moduledoc false

  @type sequence :: nonempty_list(binary())

  # These constructors return fixed two-part iolists. Dialyzer cannot express a
  # fixed-length list type and reports the correct sequence/0 contract as a
  # supertype when :underspecs is enabled.
  @dialyzer {:nowarn_function,
             cursor_show: 0,
             cursor_hide: 0,
             save_cursor: 0,
             restore_cursor: 0,
             clear_screen: 0,
             clear_screen_from_cursor: 0,
             clear_screen_to_cursor: 0,
             clear_line: 0,
             clear_line_from_cursor: 0,
             clear_line_to_cursor: 0,
             bold: 0,
             dim: 0,
             italic: 0,
             underline: 0,
             blink: 0,
             reverse: 0,
             hidden: 0,
             strikethrough: 0,
             reset: 0,
             reset_style: 0,
             enable_bracketed_paste: 0,
             disable_bracketed_paste: 0,
             enable_focus_events: 0,
             disable_focus_events: 0,
             enable_app_cursor: 0,
             disable_app_cursor: 0,
             enable_mouse_tracking: 1,
             disable_mouse_tracking: 1,
             enable_sgr_mouse: 0,
             disable_sgr_mouse: 0,
             enter_alternate_screen: 0,
             leave_alternate_screen: 0}

  # Escape sequence constants
  @csi "\e["

  # Client API

  # =============================================================================
  # Cursor Control (1.2.1)
  # =============================================================================

  @doc """
  Generates absolute cursor positioning sequence.

  Row and column are 1-indexed.

  ## Examples

      iex> TermUI.ANSI.cursor_position(5, 10) |> IO.iodata_to_binary()
      "\\e[5;10H"

      iex> TermUI.ANSI.cursor_position(1, 1) |> IO.iodata_to_binary()
      "\\e[1;1H"
  """
  @spec cursor_position(pos_integer(), pos_integer()) :: sequence()
  def cursor_position(row, col)
      when is_integer(row) and is_integer(col) and row > 0 and col > 0 do
    [@csi, Integer.to_string(row), ";", Integer.to_string(col), "H"]
  end

  @doc """
  Generates cursor up movement sequence.

  ## Examples

      iex> TermUI.ANSI.cursor_up(3) |> IO.iodata_to_binary()
      "\\e[3A"

      iex> TermUI.ANSI.cursor_up(1) |> IO.iodata_to_binary()
      "\\e[A"
  """
  @spec cursor_up(pos_integer()) :: sequence()
  def cursor_up(n \\ 1)
  def cursor_up(1), do: [@csi, "A"]
  def cursor_up(n) when is_integer(n) and n > 0, do: [@csi, Integer.to_string(n), "A"]

  @doc """
  Generates cursor down movement sequence.

  ## Examples

      iex> TermUI.ANSI.cursor_down(3) |> IO.iodata_to_binary()
      "\\e[3B"

      iex> TermUI.ANSI.cursor_down(1) |> IO.iodata_to_binary()
      "\\e[B"
  """
  @spec cursor_down(pos_integer()) :: sequence()
  def cursor_down(n \\ 1)
  def cursor_down(1), do: [@csi, "B"]
  def cursor_down(n) when is_integer(n) and n > 0, do: [@csi, Integer.to_string(n), "B"]

  @doc """
  Generates cursor forward (right) movement sequence.

  ## Examples

      iex> TermUI.ANSI.cursor_forward(3) |> IO.iodata_to_binary()
      "\\e[3C"

      iex> TermUI.ANSI.cursor_forward(1) |> IO.iodata_to_binary()
      "\\e[C"
  """
  @spec cursor_forward(pos_integer()) :: sequence()
  def cursor_forward(n \\ 1)
  def cursor_forward(1), do: [@csi, "C"]
  def cursor_forward(n) when is_integer(n) and n > 0, do: [@csi, Integer.to_string(n), "C"]

  @doc """
  Generates cursor back (left) movement sequence.

  ## Examples

      iex> TermUI.ANSI.cursor_back(3) |> IO.iodata_to_binary()
      "\\e[3D"

      iex> TermUI.ANSI.cursor_back(1) |> IO.iodata_to_binary()
      "\\e[D"
  """
  @spec cursor_back(pos_integer()) :: sequence()
  def cursor_back(n \\ 1)
  def cursor_back(1), do: [@csi, "D"]
  def cursor_back(n) when is_integer(n) and n > 0, do: [@csi, Integer.to_string(n), "D"]

  @doc """
  Generates cursor show sequence.

  ## Examples

      iex> TermUI.ANSI.cursor_show() |> IO.iodata_to_binary()
      "\\e[?25h"
  """
  @spec cursor_show() :: sequence()
  def cursor_show, do: [@csi, "?25h"]

  @doc """
  Generates cursor hide sequence.

  ## Examples

      iex> TermUI.ANSI.cursor_hide() |> IO.iodata_to_binary()
      "\\e[?25l"
  """
  @spec cursor_hide() :: sequence()
  def cursor_hide, do: [@csi, "?25l"]

  @doc """
  Generates save cursor position sequence.

  ## Examples

      iex> TermUI.ANSI.save_cursor() |> IO.iodata_to_binary()
      "\\e[s"
  """
  @spec save_cursor() :: sequence()
  def save_cursor, do: [@csi, "s"]

  @doc """
  Generates restore cursor position sequence.

  ## Examples

      iex> TermUI.ANSI.restore_cursor() |> IO.iodata_to_binary()
      "\\e[u"
  """
  @spec restore_cursor() :: sequence()
  def restore_cursor, do: [@csi, "u"]

  # =============================================================================
  # Screen Manipulation (1.2.2)
  # =============================================================================

  @doc """
  Generates clear entire screen sequence.

  ## Examples

      iex> TermUI.ANSI.clear_screen() |> IO.iodata_to_binary()
      "\\e[2J"
  """
  @spec clear_screen() :: sequence()
  def clear_screen, do: [@csi, "2J"]

  @doc """
  Generates clear screen from cursor to end sequence.

  ## Examples

      iex> TermUI.ANSI.clear_screen_from_cursor() |> IO.iodata_to_binary()
      "\\e[0J"
  """
  @spec clear_screen_from_cursor() :: sequence()
  def clear_screen_from_cursor, do: [@csi, "0J"]

  @doc """
  Generates clear screen from beginning to cursor sequence.

  ## Examples

      iex> TermUI.ANSI.clear_screen_to_cursor() |> IO.iodata_to_binary()
      "\\e[1J"
  """
  @spec clear_screen_to_cursor() :: sequence()
  def clear_screen_to_cursor, do: [@csi, "1J"]

  @doc """
  Generates clear entire line sequence.

  ## Examples

      iex> TermUI.ANSI.clear_line() |> IO.iodata_to_binary()
      "\\e[2K"
  """
  @spec clear_line() :: sequence()
  def clear_line, do: [@csi, "2K"]

  @doc """
  Generates clear line from cursor to end sequence.

  ## Examples

      iex> TermUI.ANSI.clear_line_from_cursor() |> IO.iodata_to_binary()
      "\\e[K"
  """
  @spec clear_line_from_cursor() :: sequence()
  def clear_line_from_cursor, do: [@csi, "K"]

  @doc """
  Generates clear line from beginning to cursor sequence.

  ## Examples

      iex> TermUI.ANSI.clear_line_to_cursor() |> IO.iodata_to_binary()
      "\\e[1K"
  """
  @spec clear_line_to_cursor() :: sequence()
  def clear_line_to_cursor, do: [@csi, "1K"]

  @doc """
  Generates set scroll region sequence.

  ## Examples

      iex> TermUI.ANSI.set_scroll_region(5, 20) |> IO.iodata_to_binary()
      "\\e[5;20r"
  """
  @spec set_scroll_region(pos_integer(), pos_integer()) :: sequence()
  def set_scroll_region(top, bottom)
      when is_integer(top) and is_integer(bottom) and top > 0 and bottom > 0 do
    [@csi, Integer.to_string(top), ";", Integer.to_string(bottom), "r"]
  end

  @doc """
  Generates scroll up sequence.

  ## Examples

      iex> TermUI.ANSI.scroll_up(3) |> IO.iodata_to_binary()
      "\\e[3S"

      iex> TermUI.ANSI.scroll_up(1) |> IO.iodata_to_binary()
      "\\e[S"
  """
  @spec scroll_up(pos_integer()) :: sequence()
  def scroll_up(n \\ 1)
  def scroll_up(1), do: [@csi, "S"]
  def scroll_up(n) when is_integer(n) and n > 0, do: [@csi, Integer.to_string(n), "S"]

  @doc """
  Generates scroll down sequence.

  ## Examples

      iex> TermUI.ANSI.scroll_down(3) |> IO.iodata_to_binary()
      "\\e[3T"

      iex> TermUI.ANSI.scroll_down(1) |> IO.iodata_to_binary()
      "\\e[T"
  """
  @spec scroll_down(pos_integer()) :: sequence()
  def scroll_down(n \\ 1)
  def scroll_down(1), do: [@csi, "T"]
  def scroll_down(n) when is_integer(n) and n > 0, do: [@csi, Integer.to_string(n), "T"]

  # =============================================================================
  # Colors and Styles (1.2.3)
  # =============================================================================

  @doc """
  Generates foreground color sequence for basic 16-color mode.

  ## Examples

      iex> TermUI.ANSI.foreground(:red) |> IO.iodata_to_binary()
      "\\e[31m"

      iex> TermUI.ANSI.foreground(:bright_blue) |> IO.iodata_to_binary()
      "\\e[94m"
  """
  @spec foreground(atom()) :: sequence()
  def foreground(color) when is_atom(color) do
    code = color_to_foreground_code(color)
    [@csi, Integer.to_string(code), "m"]
  end

  @doc """
  Generates background color sequence for basic 16-color mode.

  ## Examples

      iex> TermUI.ANSI.background(:blue) |> IO.iodata_to_binary()
      "\\e[44m"

      iex> TermUI.ANSI.background(:bright_red) |> IO.iodata_to_binary()
      "\\e[101m"
  """
  @spec background(atom()) :: sequence()
  def background(color) when is_atom(color) do
    code = color_to_background_code(color)
    [@csi, Integer.to_string(code), "m"]
  end

  @doc """
  Generates foreground color sequence for 256-color palette.

  ## Examples

      iex> TermUI.ANSI.foreground_256(196) |> IO.iodata_to_binary()
      "\\e[38;5;196m"
  """
  @spec foreground_256(0..255) :: sequence()
  def foreground_256(index) when is_integer(index) and index >= 0 and index <= 255 do
    [@csi, "38;5;", Integer.to_string(index), "m"]
  end

  @doc """
  Generates background color sequence for 256-color palette.

  ## Examples

      iex> TermUI.ANSI.background_256(196) |> IO.iodata_to_binary()
      "\\e[48;5;196m"
  """
  @spec background_256(0..255) :: sequence()
  def background_256(index) when is_integer(index) and index >= 0 and index <= 255 do
    [@csi, "48;5;", Integer.to_string(index), "m"]
  end

  @doc """
  Generates foreground color sequence for true-color RGB.

  ## Examples

      iex> TermUI.ANSI.foreground_rgb(255, 128, 0) |> IO.iodata_to_binary()
      "\\e[38;2;255;128;0m"
  """
  @spec foreground_rgb(0..255, 0..255, 0..255) :: sequence()
  def foreground_rgb(r, g, b)
      when is_integer(r) and r >= 0 and r <= 255 and
             is_integer(g) and g >= 0 and g <= 255 and
             is_integer(b) and b >= 0 and b <= 255 do
    [
      @csi,
      "38;2;",
      Integer.to_string(r),
      ";",
      Integer.to_string(g),
      ";",
      Integer.to_string(b),
      "m"
    ]
  end

  @doc """
  Generates background color sequence for true-color RGB.

  ## Examples

      iex> TermUI.ANSI.background_rgb(255, 128, 0) |> IO.iodata_to_binary()
      "\\e[48;2;255;128;0m"
  """
  @spec background_rgb(0..255, 0..255, 0..255) :: sequence()
  def background_rgb(r, g, b)
      when is_integer(r) and r >= 0 and r <= 255 and
             is_integer(g) and g >= 0 and g <= 255 and
             is_integer(b) and b >= 0 and b <= 255 do
    [
      @csi,
      "48;2;",
      Integer.to_string(r),
      ";",
      Integer.to_string(g),
      ";",
      Integer.to_string(b),
      "m"
    ]
  end

  @doc "Generates bold text attribute sequence."
  @spec bold() :: sequence()
  def bold, do: [@csi, "1m"]

  @doc "Generates dim text attribute sequence."
  @spec dim() :: sequence()
  def dim, do: [@csi, "2m"]

  @doc "Generates italic text attribute sequence."
  @spec italic() :: sequence()
  def italic, do: [@csi, "3m"]

  @doc "Generates underline text attribute sequence."
  @spec underline() :: sequence()
  def underline, do: [@csi, "4m"]

  @doc "Generates blink text attribute sequence."
  @spec blink() :: sequence()
  def blink, do: [@csi, "5m"]

  @doc "Generates reverse video text attribute sequence."
  @spec reverse() :: sequence()
  def reverse, do: [@csi, "7m"]

  @doc "Generates hidden text attribute sequence."
  @spec hidden() :: sequence()
  def hidden, do: [@csi, "8m"]

  @doc "Generates strikethrough text attribute sequence."
  @spec strikethrough() :: sequence()
  def strikethrough, do: [@csi, "9m"]

  @doc """
  Generates reset all styles sequence.

  ## Examples

      iex> TermUI.ANSI.reset() |> IO.iodata_to_binary()
      "\\e[0m"
  """
  @spec reset() :: sequence()
  def reset, do: [@csi, "0m"]

  @doc "Alias for reset/0."
  @spec reset_style() :: sequence()
  def reset_style, do: reset()

  @doc """
  Generates combined style sequence from a list of attributes.

  Merges multiple attributes into a single SGR sequence for efficiency.

  ## Examples

      iex> TermUI.ANSI.format([:bold, :red]) |> IO.iodata_to_binary()
      "\\e[1;31m"

      iex> TermUI.ANSI.format([:underline, :bright_blue, :bg_yellow]) |> IO.iodata_to_binary()
      "\\e[4;94;43m"
  """
  @spec format([atom()]) :: iolist()
  def format([]), do: []

  def format(attrs) when is_list(attrs) do
    codes =
      attrs
      |> Enum.map(&attribute_to_code/1)
      |> Enum.intersperse(";")

    [@csi, codes, "m"]
  end

  # =============================================================================
  # Special Modes (1.2.4)
  # =============================================================================

  @doc """
  Generates enable bracketed paste mode sequence.

  ## Examples

      iex> TermUI.ANSI.enable_bracketed_paste() |> IO.iodata_to_binary()
      "\\e[?2004h"
  """
  @spec enable_bracketed_paste() :: sequence()
  def enable_bracketed_paste, do: [@csi, "?2004h"]

  @doc """
  Generates disable bracketed paste mode sequence.

  ## Examples

      iex> TermUI.ANSI.disable_bracketed_paste() |> IO.iodata_to_binary()
      "\\e[?2004l"
  """
  @spec disable_bracketed_paste() :: sequence()
  def disable_bracketed_paste, do: [@csi, "?2004l"]

  @doc """
  Generates enable focus event reporting sequence.

  ## Examples

      iex> TermUI.ANSI.enable_focus_events() |> IO.iodata_to_binary()
      "\\e[?1004h"
  """
  @spec enable_focus_events() :: sequence()
  def enable_focus_events, do: [@csi, "?1004h"]

  @doc """
  Generates disable focus event reporting sequence.

  ## Examples

      iex> TermUI.ANSI.disable_focus_events() |> IO.iodata_to_binary()
      "\\e[?1004l"
  """
  @spec disable_focus_events() :: sequence()
  def disable_focus_events, do: [@csi, "?1004l"]

  @doc """
  Generates enable application cursor keys mode sequence.

  ## Examples

      iex> TermUI.ANSI.enable_app_cursor() |> IO.iodata_to_binary()
      "\\e[?1h"
  """
  @spec enable_app_cursor() :: sequence()
  def enable_app_cursor, do: [@csi, "?1h"]

  @doc """
  Generates disable application cursor keys mode sequence.

  ## Examples

      iex> TermUI.ANSI.disable_app_cursor() |> IO.iodata_to_binary()
      "\\e[?1l"
  """
  @spec disable_app_cursor() :: sequence()
  def disable_app_cursor, do: [@csi, "?1l"]

  @doc """
  Generates enable mouse tracking sequence for the specified mode.

  Modes:
  - `:x10` - X10 mouse reporting (press only)
  - `:normal` - Normal tracking (press and release)
  - `:button` - Button-event tracking (press, release, motion with button)
  - `:all` - All motion tracking (all motion events)

  ## Examples

      iex> TermUI.ANSI.enable_mouse_tracking(:x10) |> IO.iodata_to_binary()
      "\\e[?9h"

      iex> TermUI.ANSI.enable_mouse_tracking(:all) |> IO.iodata_to_binary()
      "\\e[?1003h"
  """
  @spec enable_mouse_tracking(:x10 | :normal | :button | :all) :: sequence()
  def enable_mouse_tracking(:x10), do: [@csi, "?9h"]
  def enable_mouse_tracking(:normal), do: [@csi, "?1000h"]
  def enable_mouse_tracking(:button), do: [@csi, "?1002h"]
  def enable_mouse_tracking(:all), do: [@csi, "?1003h"]

  @doc """
  Generates disable mouse tracking sequence for the specified mode.

  ## Examples

      iex> TermUI.ANSI.disable_mouse_tracking(:x10) |> IO.iodata_to_binary()
      "\\e[?9l"

      iex> TermUI.ANSI.disable_mouse_tracking(:all) |> IO.iodata_to_binary()
      "\\e[?1003l"
  """
  @spec disable_mouse_tracking(:x10 | :normal | :button | :all) :: sequence()
  def disable_mouse_tracking(:x10), do: [@csi, "?9l"]
  def disable_mouse_tracking(:normal), do: [@csi, "?1000l"]
  def disable_mouse_tracking(:button), do: [@csi, "?1002l"]
  def disable_mouse_tracking(:all), do: [@csi, "?1003l"]

  @doc """
  Generates enable SGR mouse mode sequence for extended coordinate encoding.

  ## Examples

      iex> TermUI.ANSI.enable_sgr_mouse() |> IO.iodata_to_binary()
      "\\e[?1006h"
  """
  @spec enable_sgr_mouse() :: sequence()
  def enable_sgr_mouse, do: [@csi, "?1006h"]

  @doc """
  Generates disable SGR mouse mode sequence.

  ## Examples

      iex> TermUI.ANSI.disable_sgr_mouse() |> IO.iodata_to_binary()
      "\\e[?1006l"
  """
  @spec disable_sgr_mouse() :: sequence()
  def disable_sgr_mouse, do: [@csi, "?1006l"]

  @doc """
  Generates enter alternate screen buffer sequence.

  ## Examples

      iex> TermUI.ANSI.enter_alternate_screen() |> IO.iodata_to_binary()
      "\\e[?1049h"
  """
  @spec enter_alternate_screen() :: sequence()
  def enter_alternate_screen, do: [@csi, "?1049h"]

  @doc """
  Generates leave alternate screen buffer sequence.

  ## Examples

      iex> TermUI.ANSI.leave_alternate_screen() |> IO.iodata_to_binary()
      "\\e[?1049l"
  """
  @spec leave_alternate_screen() :: sequence()
  def leave_alternate_screen, do: [@csi, "?1049l"]

  # =============================================================================
  # Private helpers
  # =============================================================================

  @foreground_colors %{
    black: 30,
    red: 31,
    green: 32,
    yellow: 33,
    blue: 34,
    magenta: 35,
    cyan: 36,
    white: 37,
    default: 39,
    bright_black: 90,
    bright_red: 91,
    bright_green: 92,
    bright_yellow: 93,
    bright_blue: 94,
    bright_magenta: 95,
    bright_cyan: 96,
    bright_white: 97
  }

  @background_colors %{
    black: 40,
    red: 41,
    green: 42,
    yellow: 43,
    blue: 44,
    magenta: 45,
    cyan: 46,
    white: 47,
    default: 49,
    bright_black: 100,
    bright_red: 101,
    bright_green: 102,
    bright_yellow: 103,
    bright_blue: 104,
    bright_magenta: 105,
    bright_cyan: 106,
    bright_white: 107
  }

  @attribute_codes %{
    reset: "0",
    bold: "1",
    dim: "2",
    italic: "3",
    underline: "4",
    blink: "5",
    reverse: "7",
    hidden: "8",
    strikethrough: "9",
    black: "30",
    red: "31",
    green: "32",
    yellow: "33",
    blue: "34",
    magenta: "35",
    cyan: "36",
    white: "37",
    default: "39",
    bright_black: "90",
    bright_red: "91",
    bright_green: "92",
    bright_yellow: "93",
    bright_blue: "94",
    bright_magenta: "95",
    bright_cyan: "96",
    bright_white: "97",
    bg_black: "40",
    bg_red: "41",
    bg_green: "42",
    bg_yellow: "43",
    bg_blue: "44",
    bg_magenta: "45",
    bg_cyan: "46",
    bg_white: "47",
    bg_default: "49",
    bg_bright_black: "100",
    bg_bright_red: "101",
    bg_bright_green: "102",
    bg_bright_yellow: "103",
    bg_bright_blue: "104",
    bg_bright_magenta: "105",
    bg_bright_cyan: "106",
    bg_bright_white: "107"
  }

  defp color_to_foreground_code(color), do: Map.fetch!(@foreground_colors, color)

  defp color_to_background_code(color), do: Map.fetch!(@background_colors, color)

  defp attribute_to_code(attr), do: Map.fetch!(@attribute_codes, attr)
end
