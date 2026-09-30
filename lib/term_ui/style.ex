defmodule TermUI.Style do
  @moduledoc """
  Style system for consistent visual presentation.

  Styles define colors, text attributes, and visual properties for components.
  Styles are immutable—modifications return new styles.

  ## Color Types

  - Named colors: `:black`, `:red`, `:green`, `:yellow`, `:blue`, `:magenta`, `:cyan`, `:white`
  - Bright variants: `:bright_black`, `:bright_red`, etc.
  - Indexed (256): `{:indexed, 0..255}`
  - RGB (true color): `{:rgb, r, g, b}`

  ## Examples

      # Build a style
      style = Style.new()
        |> Style.fg(:blue)
        |> Style.bg(:white)
        |> Style.bold()
        |> Style.underline()

      # Merge styles
      merged = Style.merge(base, override)

      # Inherit from parent
      effective = Style.inherit(child, parent)

      # Variants
      variants = %{
        normal: Style.new() |> Style.fg(:white),
        focused: Style.new() |> Style.fg(:blue) |> Style.bold()
      }
      style = Style.get_variant(variants, :focused)
  """

  # Dialyzer does not preserve MapSet's opaque type through generated struct
  # defaults or empty MapSet replacements.
  @dialyzer {:nowarn_function, new: 0, clear_attrs: 1, reset: 1}

  @type named_color ::
          :black
          | :red
          | :green
          | :yellow
          | :blue
          | :magenta
          | :cyan
          | :white
          | :bright_black
          | :bright_red
          | :bright_green
          | :bright_yellow
          | :bright_blue
          | :bright_magenta
          | :bright_cyan
          | :bright_white
          | :default

  @type indexed_color :: {:indexed, 0..255}
  @type rgb_color :: {:rgb, 0..255, 0..255, 0..255}

  @type color :: named_color() | indexed_color() | rgb_color()

  @type attr ::
          :bold
          | :dim
          | :italic
          | :underline
          | :blink
          | :reverse
          | :hidden
          | :strikethrough

  @type t :: %__MODULE__{
          fg: color() | nil,
          bg: color() | nil,
          attrs: MapSet.t(attr())
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
                  Zoi.tuple({Zoi.literal(:indexed), @color_channel}),
                  Zoi.tuple({Zoi.literal(:rgb), @color_channel, @color_channel, @color_channel}),
                  Zoi.literal(nil)
                ])

  @schema Zoi.struct(__MODULE__, %{
            fg: @color_schema |> Zoi.default(nil),
            bg: @color_schema |> Zoi.default(nil),
            attrs: Zoi.map_set(Zoi.enum(@valid_attributes)) |> Zoi.default(MapSet.new())
          })

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for terminal styles."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  # RGB values for 16 named colors (standard terminal colors)
  @color_rgb %{
    black: {0, 0, 0},
    red: {128, 0, 0},
    green: {0, 128, 0},
    yellow: {128, 128, 0},
    blue: {0, 0, 128},
    magenta: {128, 0, 128},
    cyan: {0, 128, 128},
    white: {192, 192, 192},
    bright_black: {128, 128, 128},
    bright_red: {255, 0, 0},
    bright_green: {0, 255, 0},
    bright_yellow: {255, 255, 0},
    bright_blue: {0, 0, 255},
    bright_magenta: {255, 0, 255},
    bright_cyan: {0, 255, 255},
    bright_white: {255, 255, 255}
  }

  # Public API - Construction

  @doc """
  Creates a new style with default values.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{attrs: MapSet.new()}
  end

  @doc "Creates a style from options."
  @spec new(keyword() | map()) :: t()
  def new(opts), do: from(opts)

  @doc """
  Creates a style from a keyword list or map.

  ## Examples

      Style.from(fg: :blue, bg: :white, bold: true)
  """
  @spec from(keyword() | map()) :: t()
  def from(opts) when is_list(opts) or is_map(opts) do
    opts = if is_map(opts), do: Map.to_list(opts), else: opts

    Enum.reduce(opts, new(), fn
      {:fg, color}, style ->
        fg(style, color)

      {:bg, color}, style ->
        bg(style, color)

      {:bold, true}, style ->
        bold(style)

      {:dim, true}, style ->
        dim(style)

      {:italic, true}, style ->
        italic(style)

      {:underline, true}, style ->
        underline(style)

      {:blink, true}, style ->
        blink(style)

      {:reverse, true}, style ->
        reverse(style)

      {:hidden, true}, style ->
        hidden(style)

      {:strikethrough, true}, style ->
        strikethrough(style)

      {:attrs, attrs}, style ->
        %{style | attrs: attrs |> Enum.map(&validate_attr!/1) |> MapSet.new()}

      _, style ->
        style
    end)
  end

  # Public API - Color setters

  @doc """
  Sets the foreground color.
  """
  @spec fg(t(), color() | nil) :: t()
  def fg(style, color) do
    %{style | fg: validate_color!(color)}
  end

  @doc """
  Sets the background color.
  """
  @spec bg(t(), color() | nil) :: t()
  def bg(style, color) do
    %{style | bg: validate_color!(color)}
  end

  # Public API - Attribute setters

  @doc "Adds bold attribute."
  @spec bold(t()) :: t()
  def bold(style), do: add_attr(style, :bold)

  @doc "Adds dim attribute."
  @spec dim(t()) :: t()
  def dim(style), do: add_attr(style, :dim)

  @doc "Adds italic attribute."
  @spec italic(t()) :: t()
  def italic(style), do: add_attr(style, :italic)

  @doc "Adds underline attribute."
  @spec underline(t()) :: t()
  def underline(style), do: add_attr(style, :underline)

  @doc "Adds blink attribute."
  @spec blink(t()) :: t()
  def blink(style), do: add_attr(style, :blink)

  @doc "Adds reverse attribute."
  @spec reverse(t()) :: t()
  def reverse(style), do: add_attr(style, :reverse)

  @doc "Adds hidden attribute."
  @spec hidden(t()) :: t()
  def hidden(style), do: add_attr(style, :hidden)

  @doc "Adds strikethrough attribute."
  @spec strikethrough(t()) :: t()
  def strikethrough(style), do: add_attr(style, :strikethrough)

  @doc "Adds one text attribute."
  @spec add_attr(t(), attr()) :: t()
  def add_attr(style, attr) when attr in @valid_attributes do
    %{style | attrs: MapSet.put(style.attrs, attr)}
  end

  @doc """
  Removes an attribute from the style.
  """
  @spec remove_attr(t(), attr()) :: t()
  def remove_attr(style, attr) do
    %{style | attrs: MapSet.delete(style.attrs, attr)}
  end

  @doc """
  Clears all attributes.
  """
  @spec clear_attrs(t()) :: t()
  def clear_attrs(style) do
    %{style | attrs: MapSet.new()}
  end

  @doc """
  Checks if style has an attribute.
  """
  @spec has_attr?(t(), attr()) :: boolean()
  def has_attr?(style, attr) do
    MapSet.member?(style.attrs, attr)
  end

  @doc "Returns true when two styles have the same visible values."
  @spec equal?(t(), t()) :: boolean()
  def equal?(%__MODULE__{} = left, %__MODULE__{} = right) do
    left.fg == right.fg and left.bg == right.bg and MapSet.equal?(left.attrs, right.attrs)
  end

  @doc "Returns true when a style has no color or attribute."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = style) do
    is_nil(style.fg) and is_nil(style.bg) and MapSet.size(style.attrs) == 0
  end

  @doc "Creates a cell with this style."
  @spec to_cell(t(), String.t()) :: TermUI.Cell.t()
  def to_cell(%__MODULE__{} = style, grapheme) do
    TermUI.Cell.new(grapheme,
      fg: normalize_cell_color(style.fg),
      bg: normalize_cell_color(style.bg),
      attrs: MapSet.to_list(style.attrs)
    )
  end

  # Public API - Merging and Inheritance

  @doc """
  Merges two styles, with the second overriding the first.

  Only non-nil values from the override style replace base values.
  Attributes are combined.
  """
  @spec merge(t(), t()) :: t()
  def merge(base, override) do
    %__MODULE__{
      fg: override.fg || base.fg,
      bg: override.bg || base.bg,
      attrs: MapSet.union(base.attrs, override.attrs)
    }
  end

  @doc """
  Inherits unset properties from parent style.

  Unlike merge, this only fills in nil values from parent.
  """
  @spec inherit(t(), t()) :: t()
  def inherit(child, parent) do
    %__MODULE__{
      fg: child.fg || parent.fg,
      bg: child.bg || parent.bg,
      attrs: if(MapSet.size(child.attrs) == 0, do: parent.attrs, else: child.attrs)
    }
  end

  @doc """
  Resets style to defaults, breaking inheritance.
  """
  @spec reset(t()) :: t()
  def reset(_style) do
    new()
  end

  # Public API - Variants

  @doc """
  Gets a variant style from a variant map.

  Falls back to :normal if variant not found.
  """
  @spec get_variant(map(), atom()) :: t()
  def get_variant(variants, state) do
    Map.get(variants, state) || Map.get(variants, :normal) || new()
  end

  @doc """
  Creates a variant that inherits from the normal variant.

  Only non-nil values in the variant override the normal style.
  """
  @spec create_variant(t(), t()) :: t()
  def create_variant(normal, variant) do
    merge(normal, variant)
  end

  @doc """
  Builds a complete variant map from partial definitions.

  Each variant inherits from :normal.
  """
  @spec build_variants(map()) :: map()
  def build_variants(variants) do
    normal = Map.get(variants, :normal, new())

    variants
    |> Enum.map(fn
      {:normal, style} -> {:normal, style}
      {state, style} -> {state, create_variant(normal, style)}
    end)
    |> Map.new()
  end

  # Public API - Color Conversion

  @doc """
  Converts any color to RGB tuple.
  """
  @spec to_rgb(color()) :: {integer(), integer(), integer()}
  def to_rgb({:rgb, r, g, b}), do: {r, g, b}
  def to_rgb({:indexed, idx}), do: indexed_to_rgb(idx)
  def to_rgb(:default), do: {255, 255, 255}
  def to_rgb(named) when is_atom(named), do: Map.get(@color_rgb, named, {255, 255, 255})

  @doc """
  Converts RGB to nearest 256-color palette index.
  """
  @spec rgb_to_indexed({integer(), integer(), integer()}) :: integer()
  def rgb_to_indexed({r, g, b}) do
    # Check grayscale first (232-255)
    if abs(r - g) < 10 and abs(g - b) < 10 and abs(r - b) < 10 do
      # Grayscale
      gray = div(r + g + b, 3)

      cond do
        # black
        gray < 8 -> 16
        # white
        gray > 248 -> 231
        true -> 232 + div((gray - 8) * 24, 240)
      end
    else
      # Color cube (16-231)
      # 6x6x6 color cube
      ri = color_cube_index(r)
      gi = color_cube_index(g)
      bi = color_cube_index(b)
      16 + 36 * ri + 6 * gi + bi
    end
  end

  @doc """
  Converts any color to nearest 16-color.
  """
  @spec to_named(color()) :: named_color()
  def to_named(color) when is_atom(color) and color in @named_colors, do: color
  def to_named(:default), do: :white

  def to_named(color) do
    {r, g, b} = to_rgb(color)

    # Find nearest named color
    @named_colors
    |> Enum.min_by(fn named ->
      {nr, ng, nb} = Map.get(@color_rgb, named)
      # Color distance (simplified)
      abs(r - nr) + abs(g - ng) + abs(b - nb)
    end)
  end

  @doc """
  Converts color for a specific terminal capability.

  - `:true_color` - returns as-is
  - `:color_256` - converts to indexed
  - `:color_16` - converts to named
  """
  @spec convert_for_terminal(color(), :true_color | :color_256 | :color_16) :: color()
  def convert_for_terminal(color, :true_color), do: color

  def convert_for_terminal(color, :color_256) do
    case color do
      {:rgb, r, g, b} -> {:indexed, rgb_to_indexed({r, g, b})}
      _ -> color
    end
  end

  def convert_for_terminal(color, :color_16) do
    to_named(color)
  end

  # Public API - Semantic Colors

  @doc """
  Returns a semantic color.

  These can be overridden by themes.
  """
  @spec semantic(atom()) :: named_color()
  def semantic(:primary), do: :blue
  def semantic(:secondary), do: :cyan
  def semantic(:success), do: :green
  def semantic(:warning), do: :yellow
  def semantic(:error), do: :red
  def semantic(:info), do: :cyan
  def semantic(:muted), do: :bright_black
  def semantic(_), do: :default

  # Private helpers

  defp validate_color!(nil), do: nil
  defp validate_color!(color) when color in [:default | @named_colors], do: color
  defp validate_color!({:indexed, index} = color) when index in 0..255, do: color

  defp validate_color!({:rgb, red, green, blue} = color)
       when red in 0..255 and green in 0..255 and blue in 0..255,
       do: color

  defp validate_color!(color),
    do: raise(ArgumentError, "invalid terminal style color: #{inspect(color)}")

  defp validate_attr!(attr) when attr in @valid_attributes, do: attr

  defp validate_attr!(attr),
    do: raise(ArgumentError, "invalid terminal style attribute: #{inspect(attr)}")

  defp normalize_cell_color(nil), do: :default
  defp normalize_cell_color({:rgb, red, green, blue}), do: {red, green, blue}
  defp normalize_cell_color({:indexed, index}), do: index
  defp normalize_cell_color(color), do: color

  defp color_cube_index(value) do
    # Map 0-255 to 0-5
    cond do
      value < 48 -> 0
      value < 115 -> 1
      true -> div(value - 35, 40)
    end
  end

  defp indexed_to_rgb(idx) when idx < 16 do
    # Standard 16 colors
    color = Enum.at(@named_colors, idx)
    Map.get(@color_rgb, color, {0, 0, 0})
  end

  defp indexed_to_rgb(idx) when idx < 232 do
    # 6x6x6 color cube
    idx = idx - 16
    b = rem(idx, 6)
    g = rem(div(idx, 6), 6)
    r = div(idx, 36)

    {cube_value(r), cube_value(g), cube_value(b)}
  end

  defp indexed_to_rgb(idx) do
    # Grayscale (232-255)
    gray = (idx - 232) * 10 + 8
    {gray, gray, gray}
  end

  defp cube_value(0), do: 0
  defp cube_value(n), do: 55 + n * 40
end
