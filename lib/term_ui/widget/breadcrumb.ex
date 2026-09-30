defmodule TermUI.Widget.Breadcrumb do
  @moduledoc "A pure, width-aware breadcrumb trail."

  @behaviour TermUI.Widget

  alias TermUI.{CharacterSet, Frame, Style}
  alias TermUI.Widget.Helpers

  @type item :: %{required(:label) => String.t(), optional(:icon) => String.t()}
  @type t :: %__MODULE__{
          items: [item()],
          separator: String.t(),
          ellipsis: String.t(),
          style: Style.t(),
          current_style: Style.t(),
          separator_style: Style.t()
        }

  defstruct items: [],
            separator: "/",
            ellipsis: "…",
            style: %Style{},
            current_style: %Style{fg: :cyan, attrs: MapSet.new([:bold])},
            separator_style: %Style{fg: :bright_black}

  @doc "Creates one breadcrumb item."
  @spec item(iodata(), keyword()) :: item()
  def item(label, opts \\ []) do
    %{label: IO.iodata_to_binary(label), icon: opts |> Keyword.get(:icon, "") |> to_string()}
  end

  @impl true
  def init(opts) do
    character_set = Keyword.get(opts, :character_set, CharacterSet.current())

    %__MODULE__{
      items: opts |> Keyword.get(:items, []) |> Enum.map(&normalize_item/1),
      separator: opts |> Keyword.get(:separator, "/") |> to_string(),
      ellipsis:
        opts |> Keyword.get(:ellipsis, CharacterSet.get(character_set).ellipsis) |> to_string(),
      style: Keyword.get(opts, :style, Style.new()),
      current_style: Keyword.get(opts, :current_style, Style.new(fg: :cyan, attrs: [:bold])),
      separator_style: Keyword.get(opts, :separator_style, Style.new(fg: :bright_black))
    }
  end

  @impl true
  def update(_event, state), do: {state, []}

  @impl true
  def view(%{items: []}, dimensions), do: Helpers.frame([], dimensions)

  def view(state, {width, _height} = dimensions) do
    spans = full_spans(state)
    row = if spans_width(spans) <= width, do: spans, else: compact_spans(state, width)
    Helpers.frame([row], dimensions)
  end

  @doc "Replaces all breadcrumb items."
  @spec set_items(t(), [term()]) :: t()
  def set_items(state, items), do: %{state | items: Enum.map(items, &normalize_item/1)}

  defp full_spans(state) do
    last = length(state.items) - 1

    state.items
    |> Enum.with_index()
    |> Enum.flat_map(fn {item, index} ->
      style = if index == last, do: state.current_style, else: state.style
      item_span = {item_text(item), style}

      if index == last,
        do: [item_span],
        else: [item_span, {" " <> state.separator <> " ", state.separator_style}]
    end)
  end

  defp compact_spans(%{items: [item]} = state, width),
    do: [{Frame.fit(item_text(item), width), state.current_style}]

  defp compact_spans(%{items: [first, last]} = state, width) do
    separator = " " <> state.separator <> " "
    prefix = item_text(first) <> separator
    prefix_width = Helpers.text_width(prefix)

    if prefix_width >= width do
      [{Frame.fit(item_text(last), width), state.current_style}]
    else
      [
        {item_text(first), state.style},
        {separator, state.separator_style},
        {Frame.fit(item_text(last), width - prefix_width), state.current_style}
      ]
    end
  end

  defp compact_spans(state, width) do
    first = hd(state.items)
    last = List.last(state.items)
    separator = " " <> state.separator <> " "
    prefix = item_text(first) <> separator <> state.ellipsis <> separator
    prefix_width = Helpers.text_width(prefix)

    if prefix_width >= width do
      [{Frame.fit(item_text(last), width), state.current_style}]
    else
      [
        {item_text(first), state.style},
        {separator, state.separator_style},
        {state.ellipsis, state.separator_style},
        {separator, state.separator_style},
        {Frame.fit(item_text(last), width - prefix_width), state.current_style}
      ]
    end
  end

  defp spans_width(spans),
    do: Enum.reduce(spans, 0, fn {text, _style}, width -> width + Helpers.text_width(text) end)

  defp item_text(%{icon: icon, label: label}) when icon not in [nil, ""], do: icon <> " " <> label
  defp item_text(%{label: label}), do: label

  defp normalize_item(%{label: label} = item),
    do: %{label: to_string(label), icon: item |> Map.get(:icon, "") |> to_string()}

  defp normalize_item({icon, label}), do: %{label: to_string(label), icon: to_string(icon)}
  defp normalize_item(label), do: item(to_string(label))
end
