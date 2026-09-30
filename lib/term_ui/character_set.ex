defmodule TermUI.CharacterSet do
  @moduledoc """
  Character set definitions for Unicode and ASCII box-drawing characters.

  This module provides character sets for rendering borders, progress bars,
  check marks, and other UI elements. Two character sets are available:

  - `:unicode` - Full Unicode box-drawing characters for modern terminals
  - `:ascii` - ASCII fallback characters for limited terminals

  ## Usage

  Widgets should use `get/1` to retrieve the appropriate character set based
  on terminal capabilities:

      chars = TermUI.CharacterSet.get(:unicode)
      top_border = chars.tl <> String.duplicate(chars.h_line, width - 2) <> chars.tr

  For runtime queries, use `current/0` which reads from persistent_term:

      chars = TermUI.CharacterSet.get(TermUI.CharacterSet.current())

  Or use the convenience function `current_charset/0`:

      chars = TermUI.CharacterSet.current_charset()

  ## Available Characters

  ### Box Drawing
  - `tl`, `tr`, `bl`, `br` - Corners (top-left, top-right, bottom-left, bottom-right)
  - `tl_round`, `tr_round`, `bl_round`, `br_round` - Rounded corners
  - `h_line`, `v_line` - Horizontal and vertical lines (light)
  - `h_line_heavy`, `v_line_heavy` - Heavy horizontal and vertical lines
  - `t_up`, `t_down`, `t_left`, `t_right` - T-junctions
  - `cross` - Cross junction (four-way)

  ### Progress/Gauge
  - `bar_full` - Full block for filled progress
  - `bar_empty` - Empty/light block for unfilled progress
  - `bar_levels` - List of characters for fractional progress (8 levels Unicode, 5 ASCII)
  - `sparkline_levels` - List of vertical bar characters for sparklines
  - `spinner_frames` - List of animation frames for spinners

  ### Indicators
  - `check` - Check mark for success/selected
  - `cross_mark` - X mark for failure/deselected
  - `bullet`, `bullet_empty` - Filled and empty circle bullets
  - `pointer` - Pointer/cursor indicator

  ### Arrows and Triangles
  - `arrow_up`, `arrow_down`, `arrow_left`, `arrow_right` - Directional arrows
  - `arrow_up_down` - Bidirectional vertical arrow
  - `triangle_up`, `triangle_down`, `triangle_left`, `triangle_right` - Solid triangles

  ### Special Icons
  - `info` - Information icon
  - `warning` - Warning icon
  - `loading` - Loading/spinner icon

  ### Misc
  - `ellipsis` - Ellipsis character
  - `dot` - Bullet dot/point

  ## Configuration

  The default character set can be configured in your application:

      config :term_ui, :character_set, :unicode

  Or at runtime:

      Application.put_env(:term_ui, :character_set, :ascii)
  """

  @typedoc """
  Character set type.

  - `:unicode` - Full Unicode box-drawing characters
  - `:ascii` - ASCII fallback characters
  """

  @type charset :: :unicode | :ascii

  @typedoc """
  Character set map containing all box-drawing and special characters.
  """
  @type t :: %{
          # Box corners (light)
          tl: String.t(),
          tr: String.t(),
          bl: String.t(),
          br: String.t(),
          # Rounded box corners
          tl_round: String.t(),
          tr_round: String.t(),
          bl_round: String.t(),
          br_round: String.t(),
          # Lines (light)
          h_line: String.t(),
          v_line: String.t(),
          # Lines (heavy)
          h_line_heavy: String.t(),
          v_line_heavy: String.t(),
          # T-junctions
          t_up: String.t(),
          t_down: String.t(),
          t_left: String.t(),
          t_right: String.t(),
          # Cross junction
          cross: String.t(),
          # Progress/gauge
          bar_full: String.t(),
          bar_empty: String.t(),
          bar_levels: [String.t()],
          # Sparkline levels (vertical bars)
          sparkline_levels: [String.t()],
          # Check marks
          check: String.t(),
          cross_mark: String.t(),
          # Arrows
          arrow_up: String.t(),
          arrow_down: String.t(),
          arrow_left: String.t(),
          arrow_right: String.t(),
          arrow_up_down: String.t(),
          # Triangle indicators
          triangle_up: String.t(),
          triangle_down: String.t(),
          triangle_left: String.t(),
          triangle_right: String.t(),
          # Selection indicators
          bullet: String.t(),
          bullet_empty: String.t(),
          pointer: String.t(),
          # Special icons
          info: String.t(),
          warning: String.t(),
          loading: String.t(),
          spinner_frames: [String.t()],
          # Misc
          ellipsis: String.t(),
          dot: String.t()
        }

  # Define charsets as module attributes for compile-time access
  @unicode_charset %{
    # Box corners (light)
    tl: "┌",
    tr: "┐",
    bl: "└",
    br: "┘",
    # Rounded box corners
    tl_round: "╭",
    tr_round: "╮",
    bl_round: "╰",
    br_round: "╯",
    # Lines (light)
    h_line: "─",
    v_line: "│",
    # Lines (heavy)
    h_line_heavy: "━",
    v_line_heavy: "┃",
    # T-junctions (light)
    t_up: "┴",
    t_down: "┬",
    t_left: "┤",
    t_right: "├",
    # Cross junction (light)
    cross: "┼",
    # Progress/gauge characters
    bar_full: "█",
    bar_empty: "░",
    # 8 levels of progress (1/8 to 8/8)
    bar_levels: ["▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"],
    # 8 sparkline levels (vertical bars)
    sparkline_levels: ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"],
    # Check marks
    check: "✓",
    cross_mark: "✗",
    # Arrows
    arrow_up: "↑",
    arrow_down: "↓",
    arrow_left: "←",
    arrow_right: "→",
    arrow_up_down: "↕",
    # Triangle indicators (for expand/collapse, sort, etc.)
    triangle_up: "▲",
    triangle_down: "▼",
    triangle_left: "◀",
    triangle_right: "▶",
    # Selection indicators
    bullet: "●",
    bullet_empty: "○",
    pointer: "►",
    # Special icons
    info: "ℹ",
    warning: "⚠",
    loading: "⟳",
    spinner_frames: ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"],
    # Misc
    ellipsis: "…",
    dot: "•"
  }

  @ascii_charset %{
    # Box corners (ASCII)
    tl: "+",
    tr: "+",
    bl: "+",
    br: "+",
    # Rounded box corners (same as regular in ASCII)
    tl_round: "+",
    tr_round: "+",
    bl_round: "+",
    br_round: "+",
    # Lines (ASCII)
    h_line: "-",
    v_line: "|",
    # Lines (heavy - same as regular in ASCII)
    h_line_heavy: "=",
    v_line_heavy: "|",
    # T-junctions (ASCII)
    t_up: "+",
    t_down: "+",
    t_left: "+",
    t_right: "+",
    # Cross junction (ASCII)
    cross: "+",
    # Progress/gauge characters (ASCII)
    bar_full: "#",
    bar_empty: ".",
    # 5 levels of progress for ASCII
    bar_levels: [" ", ".", ":", "=", "#"],
    # 5 sparkline levels for ASCII
    sparkline_levels: ["_", ".", ":", "=", "#"],
    # Check marks (ASCII)
    check: "x",
    cross_mark: "X",
    # Arrows (ASCII)
    arrow_up: "^",
    arrow_down: "v",
    arrow_left: "<",
    arrow_right: ">",
    arrow_up_down: "|",
    # Triangle indicators (ASCII approximations)
    triangle_up: "^",
    triangle_down: "v",
    triangle_left: "<",
    triangle_right: ">",
    # Selection indicators (ASCII)
    bullet: "*",
    bullet_empty: "o",
    pointer: ">",
    # Special icons (ASCII)
    info: "i",
    warning: "!",
    loading: "*",
    spinner_frames: ["|", "/", "-", "\\"],
    # Misc (ASCII)
    ellipsis: "...",
    dot: "*"
  }

  # Derive keys from the actual charset map at compile time
  @charset_keys Map.keys(@unicode_charset)

  @doc """
  Returns the character set for the given type.

  ## Parameters

  - `type` - Either `:unicode` or `:ascii`

  ## Returns

  A map containing all box-drawing and special characters.

  ## Examples

      iex> chars = TermUI.CharacterSet.get(:unicode)
      iex> chars.tl
      "┌"

      iex> chars = TermUI.CharacterSet.get(:ascii)
      iex> chars.tl
      "+"
  """
  @spec get(charset()) :: t()
  def get(:unicode), do: @unicode_charset
  def get(:ascii), do: @ascii_charset

  def get(invalid) do
    raise ArgumentError, "unknown character set #{inspect(invalid)}, expected :unicode or :ascii"
  end

  @doc """
  Returns the currently configured character set type.

  Reads application configuration and defaults to `:unicode`.

  ## Returns

  Either `:unicode` or `:ascii`.

  ## Examples

      iex> TermUI.CharacterSet.current()
      :unicode

      iex> Application.put_env(:term_ui, :character_set, :ascii)
      iex> TermUI.CharacterSet.current()
      :ascii
      iex> Application.delete_env(:term_ui, :character_set)
  """
  @spec current() :: charset()
  def current do
    case Application.get_env(:term_ui, :character_set, :unicode) do
      character_set when character_set in [:unicode, :ascii] -> character_set
      _invalid -> :unicode
    end
  end

  @doc """
  Returns the current character set as a map.

  Convenience function that combines `current/0` and `get/1`.

  ## Returns

  A map containing all box-drawing and special characters for the
  currently configured character set.

  ## Examples

      iex> chars = TermUI.CharacterSet.current_charset()
      iex> is_map(chars)
      true

      iex> Application.put_env(:term_ui, :character_set, :ascii)
      iex> TermUI.CharacterSet.current_charset().tl
      "+"
  """
  @spec current_charset() :: t()
  def current_charset do
    get(current())
  end

  @doc """
  Returns the list of all character keys available in a character set.

  Keys are derived from the actual character set map at compile time,
  ensuring they stay in sync with the character set definitions.

  Useful for validation and testing.

  ## Returns

  List of atom keys.

  ## Examples

      iex> :tl in TermUI.CharacterSet.keys()
      true
  """
  @spec keys() :: nonempty_list(atom())
  def keys, do: @charset_keys

  # ----------------------------------------------------------------------------
  # Line Drawing Convenience Functions
  # ----------------------------------------------------------------------------

  @doc """
  Creates a horizontal line of the specified width.

  Uses the current character set's horizontal line character.

  ## Parameters

  - `width` - Width of the line in characters

  ## Examples

      iex> TermUI.CharacterSet.horizontal_line(5)
      "─────"  # Unicode mode

      iex> Application.put_env(:term_ui, :character_set, :ascii)
      iex> TermUI.CharacterSet.horizontal_line(5)
      "-----"
  """
  @spec horizontal_line(non_neg_integer()) :: String.t()
  def horizontal_line(width) when is_integer(width) and width >= 0 do
    chars = current_charset()
    String.duplicate(chars.h_line, width)
  end

  @doc """
  Creates a vertical line as a list of strings.

  Returns a list of vertical line characters, one per line.

  ## Parameters

  - `height` - Height of the line in characters

  ## Examples

      iex> TermUI.CharacterSet.vertical_line(3)
      ["│", "│", "│"]  # Unicode mode
  """
  @spec vertical_line(non_neg_integer()) :: [String.t()]
  def vertical_line(height) when is_integer(height) and height >= 0 do
    chars = current_charset()
    List.duplicate(chars.v_line, height)
  end

  @doc """
  Creates the top border of a box.

  Format: `┌` + horizontal line + `┐`

  ## Parameters

  - `width` - Total width including corners (minimum 2)

  ## Examples

      iex> TermUI.CharacterSet.box_top(10)
      "┌────────┐"  # Unicode mode
  """
  @spec box_top(non_neg_integer()) :: String.t()
  def box_top(width) when is_integer(width) and width >= 2 do
    chars = current_charset()
    inner_width = width - 2
    chars.tl <> String.duplicate(chars.h_line, inner_width) <> chars.tr
  end

  def box_top(width) when is_integer(width) and width >= 0 do
    horizontal_line(width)
  end

  @doc """
  Creates the bottom border of a box.

  Format: `└` + horizontal line + `┘`

  ## Parameters

  - `width` - Total width including corners (minimum 2)

  ## Examples

      iex> TermUI.CharacterSet.box_bottom(10)
      "└────────┘"  # Unicode mode
  """
  @spec box_bottom(non_neg_integer()) :: String.t()
  def box_bottom(width) when is_integer(width) and width >= 2 do
    chars = current_charset()
    inner_width = width - 2
    chars.bl <> String.duplicate(chars.h_line, inner_width) <> chars.br
  end

  def box_bottom(width) when is_integer(width) and width >= 0 do
    horizontal_line(width)
  end
end
