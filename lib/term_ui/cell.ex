defmodule TermUI.Cell do
  @moduledoc """
  Represents a single cell in the terminal screen buffer.

  A cell contains a character (grapheme cluster), foreground and background
  colors, and style attributes. Cells are immutable - updates create new
  cells, enabling efficient diffing by reference comparison.

  ## Color Types

  Colors can be specified as:
  - `:default` - Terminal default color
  - Atom - Named color (`:red`, `:green`, `:blue`, etc.)
  - Integer 0-255 - 256-color palette index
  - `{r, g, b}` tuple - True color RGB values (0-255 each)

  ## Attributes

  Supported style attributes:
  - `:bold` - Bold/bright text
  - `:dim` - Dimmed text
  - `:italic` - Italic text
  - `:underline` - Underlined text
  - `:blink` - Blinking text
  - `:reverse` - Reversed colors
  - `:hidden` - Hidden text
  - `:strikethrough` - Strikethrough text
  """

  # Dialyzer does not preserve MapSet's opaque type through the generated
  # defstruct defaults.
  @dialyzer {:nowarn_function, empty: 0}

  @type color :: TermUI.Style.named_color() | 0..255 | {0..255, 0..255, 0..255}

  @type attribute ::
          :bold | :dim | :italic | :underline | :blink | :reverse | :hidden | :strikethrough

  @type t :: %__MODULE__{
          char: String.t(),
          fg: color(),
          bg: color(),
          attrs: MapSet.t(attribute()),
          width: 0 | 1 | 2,
          wide_placeholder: boolean()
        }

  @valid_attributes [:bold, :dim, :italic, :underline, :blink, :reverse, :hidden, :strikethrough]

  @named_colors [
    :black,
    :red,
    :green,
    :yellow,
    :blue,
    :magenta,
    :cyan,
    :white,
    :bright_black,
    :bright_red,
    :bright_green,
    :bright_yellow,
    :bright_blue,
    :bright_magenta,
    :bright_cyan,
    :bright_white
  ]

  @color_channel Zoi.integer() |> Zoi.gte(0) |> Zoi.lte(255)
  @color_schema Zoi.union([
                  Zoi.enum([:default | @named_colors]),
                  @color_channel,
                  Zoi.tuple({@color_channel, @color_channel, @color_channel})
                ])

  @schema Zoi.struct(__MODULE__, %{
            char: Zoi.string() |> Zoi.default(" "),
            fg: @color_schema |> Zoi.default(:default),
            bg: @color_schema |> Zoi.default(:default),
            attrs:
              Zoi.map_set(Zoi.enum(@valid_attributes))
              |> Zoi.default(MapSet.new()),
            width: Zoi.enum([0, 1, 2]) |> Zoi.default(1),
            wide_placeholder: Zoi.boolean() |> Zoi.default(false)
          })
          |> Zoi.refine({__MODULE__, :validate_schema, []})

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for terminal cells."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc false
  @spec validate_schema(t(), keyword()) :: :ok | {:error, String.t()}
  def validate_schema(%__MODULE__{char: "", width: 0, wide_placeholder: true}, _opts), do: :ok

  def validate_schema(%__MODULE__{char: char, width: width, wide_placeholder: false}, _opts) do
    case String.graphemes(char) do
      [_grapheme] ->
        if width in [1, 2] and width == calculate_width(char),
          do: :ok,
          else: {:error, "cell character, width, and placeholder fields are inconsistent"}

      _other ->
        {:error, "cell character, width, and placeholder fields are inconsistent"}
    end
  end

  def validate_schema(%__MODULE__{}, _opts),
    do: {:error, "cell character, width, and placeholder fields are inconsistent"}

  @doc """
  Creates a new cell with the given character and optional styling.

  ## Examples

      iex> Cell.new("A")
      %Cell{char: "A", fg: :default, bg: :default, attrs: MapSet.new()}

      iex> Cell.new("X", fg: :red, attrs: [:bold])
      %Cell{char: "X", fg: :red, bg: :default, attrs: MapSet.new([:bold])}
  """
  @spec new(String.t(), keyword()) :: t()
  def new(char, opts \\ []) when is_binary(char) do
    fg = Keyword.get(opts, :fg, :default)
    bg = Keyword.get(opts, :bg, :default)
    attrs = Keyword.get(opts, :attrs, [])
    sanitized = sanitize_char(char)

    %__MODULE__{
      char: sanitized,
      fg: validate_color!(fg),
      bg: validate_color!(bg),
      attrs: attrs |> Enum.map(&validate_attribute!/1) |> MapSet.new(),
      width: calculate_width(sanitized),
      wide_placeholder: false
    }
  end

  @doc """
  Creates a placeholder cell for the second column of a wide character.

  This cell inherits the styling from the primary cell but renders as empty.
  """
  @spec wide_placeholder(t()) :: t()
  def wide_placeholder(%__MODULE__{} = primary) do
    %__MODULE__{
      char: "",
      fg: primary.fg,
      bg: primary.bg,
      attrs: primary.attrs,
      width: 0,
      wide_placeholder: true
    }
  end

  @doc """
  Returns the display width of a cell (1 or 2).
  """
  @spec width(t()) :: non_neg_integer()
  def width(%__MODULE__{width: w}), do: w

  @doc """
  Returns true if this cell is a wide character placeholder.
  """
  @spec wide_placeholder?(t()) :: boolean()
  def wide_placeholder?(%__MODULE__{wide_placeholder: wp}), do: wp

  @doc """
  Returns true if this cell is a wide (double-width) character.
  """
  @spec wide?(t()) :: boolean()
  def wide?(%__MODULE__{width: 2}), do: true
  def wide?(%__MODULE__{}), do: false

  # Calculate display width using DisplayWidth module
  defp calculate_width(char) do
    alias TermUI.DisplayWidth
    width = DisplayWidth.width(char)
    # Clamp to 1 or 2 for cell width
    cond do
      width >= 2 -> 2
      width <= 0 -> 1
      true -> 1
    end
  end

  @doc """
  Returns an empty cell with default styling.

  An empty cell contains a space character with default colors and no attributes.

  ## Examples

      iex> Cell.empty()
      %Cell{char: " ", fg: :default, bg: :default, attrs: MapSet.new()}
  """
  @spec empty() :: t()
  def empty do
    %__MODULE__{attrs: MapSet.new()}
  end

  @doc """
  Compares two cells for equality.

  Returns `true` if both cells have the same character, colors, and attributes.
  Used by the diff algorithm to identify changed cells.

  ## Examples

      iex> Cell.equal?(Cell.empty(), Cell.empty())
      true

      iex> Cell.equal?(Cell.new("A"), Cell.new("B"))
      false
  """
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{} = a, %__MODULE__{} = b) do
    a.char == b.char and
      a.fg == b.fg and
      a.bg == b.bg and
      MapSet.equal?(a.attrs, b.attrs) and
      a.width == b.width and
      a.wide_placeholder == b.wide_placeholder
  end

  @doc """
  Checks if a cell is empty (space with default styling).

  ## Examples

      iex> Cell.empty?(Cell.empty())
      true

      iex> Cell.empty?(Cell.new("A"))
      false
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = cell) do
    cell.char == " " and
      cell.fg == :default and
      cell.bg == :default and
      MapSet.size(cell.attrs) == 0
  end

  @doc """
  Returns a cell with updated character.

  ## Examples

      iex> cell = Cell.new("A", fg: :red)
      iex> Cell.put_char(cell, "B")
      %Cell{char: "B", fg: :red, bg: :default, attrs: MapSet.new()}
  """
  @spec put_char(t(), String.t()) :: t()
  def put_char(%__MODULE__{} = cell, char) when is_binary(char) do
    char = sanitize_char(char)
    %{cell | char: char, width: calculate_width(char), wide_placeholder: false}
  end

  @doc """
  Returns a cell with updated foreground color.
  """
  @spec put_fg(t(), color()) :: t()
  def put_fg(%__MODULE__{} = cell, color) do
    %{cell | fg: validate_color!(color)}
  end

  @doc """
  Returns a cell with updated background color.
  """
  @spec put_bg(t(), color()) :: t()
  def put_bg(%__MODULE__{} = cell, color) do
    %{cell | bg: validate_color!(color)}
  end

  @doc """
  Adds an attribute to the cell.
  """
  @spec add_attr(t(), attribute()) :: t()
  def add_attr(%__MODULE__{} = cell, attr) do
    %{cell | attrs: MapSet.put(cell.attrs, validate_attribute!(attr))}
  end

  @doc """
  Removes an attribute from the cell.
  """
  @spec remove_attr(t(), attribute()) :: t()
  def remove_attr(%__MODULE__{} = cell, attr) do
    %{cell | attrs: MapSet.delete(cell.attrs, attr)}
  end

  @doc """
  Checks if the cell has a specific attribute.
  """
  @spec has_attr?(t(), attribute()) :: boolean()
  def has_attr?(%__MODULE__{} = cell, attr) do
    MapSet.member?(cell.attrs, attr)
  end

  @doc """
  Returns list of valid color names.
  """
  @spec named_colors() :: nonempty_list(atom())
  def named_colors, do: @named_colors

  @doc """
  Returns list of valid attributes.
  """
  @spec valid_attributes() :: nonempty_list(attribute())
  def valid_attributes, do: @valid_attributes

  # Private helpers

  defp validate_color!(:default), do: :default

  defp validate_color!(color) when color in @named_colors, do: color

  defp validate_color!(color) when is_integer(color) and color >= 0 and color <= 255, do: color

  defp validate_color!({r, g, b} = color)
       when is_integer(r) and r >= 0 and r <= 255 and
              is_integer(g) and g >= 0 and g <= 255 and
              is_integer(b) and b >= 0 and b <= 255 do
    color
  end

  defp validate_color!(invalid) do
    raise ArgumentError, "Invalid color: #{inspect(invalid)}"
  end

  defp validate_attribute!(attr) when attr in @valid_attributes, do: attr

  defp validate_attribute!(invalid) do
    raise ArgumentError,
          "Invalid attribute: #{inspect(invalid)}. Valid attributes: #{inspect(@valid_attributes)}"
  end

  # Sanitize character to prevent escape sequence injection
  # Removes control characters (0x00-0x1F except space, 0x7F) and escape sequences
  defp sanitize_char(char) when is_binary(char) do
    sanitized =
      char
      # Strip ANSI escape sequences first
      |> strip_escape_sequences()
      # Remove control characters while preserving valid Unicode
      |> filter_control_chars()

    case String.graphemes(sanitized) do
      [grapheme | _rest] -> grapheme
      [] -> " "
    end
  end

  # Strip CSI sequences: ESC [ ... final_char (0x40-0x7E)
  # Strip OSC sequences: ESC ] ... ST (0x07 or ESC \)
  defp strip_escape_sequences(str) do
    str
    # CSI sequences: \e[ followed by any params and intermediate bytes, ending with final byte
    |> String.replace(~r/\e\[[0-9;]*[A-Za-z]/, "")
    # OSC sequences: \e] followed by anything until BEL or ST
    |> String.replace(~r/\e\][^\x07\e]*(?:\x07|\e\\)?/, "")
    # Any other escape sequences (ESC followed by single char)
    |> String.replace(~r/\e./, "")
  end

  defp filter_control_chars(str) do
    if String.valid?(str) do
      str
      |> String.graphemes()
      |> Enum.map_join(&sanitize_grapheme/1)
    else
      # Handle invalid UTF-8 by filtering bytes
      str
      |> :binary.bin_to_list()
      |> Enum.filter(&safe_byte?/1)
      |> List.to_string()
    end
  end

  defp sanitize_grapheme(grapheme) do
    grapheme
    |> String.to_charlist()
    |> Enum.filter(&safe_codepoint?/1)
    |> List.to_string()
  end

  # For byte-level filtering (invalid UTF-8)
  defp safe_byte?(byte) when byte >= 0x20 and byte <= 0x7E, do: true
  defp safe_byte?(_), do: false

  # Allow printable ASCII (space through tilde), and Unicode above 0x9F
  # Block: control chars (0x00-0x1F), DEL (0x7F), and C1 controls (0x80-0x9F)
  defp safe_codepoint?(cp) when cp >= 0x20 and cp <= 0x7E, do: true

  # Block bidirectional formatting characters (can cause visual text direction confusion)
  # LRE, RLE, PDF, LRO, RLO (U+202A-U+202E)
  defp safe_codepoint?(cp) when cp >= 0x202A and cp <= 0x202E, do: false
  # LRI, RLI, FSI, PDI (U+2066-U+2069)
  defp safe_codepoint?(cp) when cp >= 0x2066 and cp <= 0x2069, do: false

  # Block Unicode non-characters (should never appear in interchange per Unicode spec)
  defp safe_codepoint?(0xFFFE), do: false
  defp safe_codepoint?(0xFFFF), do: false
  defp safe_codepoint?(cp) when cp >= 0xFDD0 and cp <= 0xFDEF, do: false

  defp safe_codepoint?(cp) when cp >= 0xA0, do: true
  defp safe_codepoint?(_), do: false
end
