defmodule TermUI.Theme do
  @moduledoc """
  Pure named style and value data.

  A theme is an application-owned value. It has no registry and no process.
  Style entries can be one `TermUI.Style` or a map of variants such as
  `:normal`, `:focused`, and `:disabled`.
  """

  alias TermUI.Style

  @type style_entry :: Style.t() | %{optional(atom()) => Style.t()}
  @type t :: %__MODULE__{
          name: term(),
          styles: %{optional(term()) => style_entry()},
          values: map()
        }

  defstruct name: :default,
            styles: %{},
            values: %{}

  @doc "Creates a pure theme value."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      name: Keyword.get(opts, :name, :default),
      styles: opts |> Keyword.get(:styles, %{}) |> normalize_styles(),
      values: Keyword.get(opts, :values, %{}) |> Map.new()
    }
  end

  @doc "Returns the built-in semantic theme."
  @spec default() :: t()
  def default do
    new(
      styles: %{
        text: Style.new(),
        primary: Style.new(fg: Style.semantic(:primary)),
        secondary: Style.new(fg: Style.semantic(:secondary)),
        success: Style.new(fg: Style.semantic(:success)),
        warning: Style.new(fg: Style.semantic(:warning)),
        error: Style.new(fg: Style.semantic(:error)),
        info: Style.new(fg: Style.semantic(:info)),
        muted: Style.new(fg: Style.semantic(:muted)),
        control: %{
          normal: Style.new(),
          focused: Style.new(fg: :cyan, attrs: [:bold]),
          disabled: Style.new(fg: :bright_black)
        }
      },
      values: %{spacing: 1}
    )
  end

  @doc "Returns a style or variant, with an optional fallback."
  @spec style(t(), term(), atom(), Style.t() | nil) :: Style.t()
  def style(theme, key, variant \\ :normal, fallback \\ nil) do
    case Map.get(theme.styles, key) do
      %Style{} = style -> style
      variants when is_map(variants) -> Style.get_variant(variants, variant)
      _other -> fallback || Style.new()
    end
  end

  @doc "Adds or replaces one style entry."
  @spec put_style(t(), term(), style_entry()) :: t()
  def put_style(theme, key, entry),
    do: %{theme | styles: Map.put(theme.styles, key, normalize_style_entry(entry))}

  @doc "Returns a non-style theme value."
  @spec value(t(), term(), term()) :: term()
  def value(theme, key, fallback \\ nil), do: Map.get(theme.values, key, fallback)

  @doc "Adds or replaces one non-style theme value."
  @spec put_value(t(), term(), term()) :: t()
  def put_value(theme, key, value), do: %{theme | values: Map.put(theme.values, key, value)}

  @doc "Merges an override theme into a base theme."
  @spec merge(t(), t()) :: t()
  def merge(base, override) do
    styles =
      Map.merge(base.styles, override.styles, fn _key, left, right -> merge_entry(left, right) end)

    %__MODULE__{
      name: override.name,
      styles: styles,
      values: Map.merge(base.values, override.values)
    }
  end

  @doc "Returns a copy whose colors fit backend capabilities."
  @spec for_capabilities(t(), map()) :: t()
  def for_capabilities(theme, capabilities) do
    mode = Map.get(capabilities, :colors, :true_color)
    %{theme | styles: map_style_entries(theme.styles, &convert_style(&1, mode))}
  end

  defp normalize_styles(styles),
    do: Map.new(styles, fn {key, entry} -> {key, normalize_style_entry(entry)} end)

  defp normalize_style_entry(%Style{} = style), do: style

  defp normalize_style_entry(variants) when is_map(variants),
    do: Map.new(variants, fn {variant, style} -> {variant, normalize_style(style)} end)

  defp normalize_style_entry(other),
    do:
      raise(
        ArgumentError,
        "theme style entries must be styles or variant maps, got: #{inspect(other)}"
      )

  defp normalize_style(%Style{} = style), do: style
  defp normalize_style(opts) when is_list(opts) or is_map(opts), do: Style.new(opts)
  defp normalize_style(other), do: raise(ArgumentError, "invalid theme style: #{inspect(other)}")

  defp merge_entry(%Style{} = left, %Style{} = right), do: Style.merge(left, right)

  defp merge_entry(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _variant, base, override -> Style.merge(base, override) end)
  end

  defp merge_entry(_left, right), do: right

  defp map_style_entries(styles, function) do
    Map.new(styles, fn
      {key, %Style{} = style} ->
        {key, function.(style)}

      {key, variants} ->
        {key, Map.new(variants, fn {variant, style} -> {variant, function.(style)} end)}
    end)
  end

  defp convert_style(style, :monochrome), do: %{style | fg: nil, bg: nil}

  defp convert_style(style, mode) when mode in [:true_color, :color_256, :color_16] do
    %{
      style
      | fg: convert_color(style.fg, mode),
        bg: convert_color(style.bg, mode)
    }
  end

  defp convert_style(style, _unknown), do: style
  defp convert_color(nil, _mode), do: nil
  defp convert_color(color, mode), do: Style.convert_for_terminal(color, mode)
end
