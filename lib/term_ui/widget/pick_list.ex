defmodule TermUI.Widget.PickList do
  @moduledoc "A pure searchable pick list."

  @behaviour TermUI.Widget

  alias TermUI.{Event, Style}
  alias TermUI.Widget.Helpers

  @type t :: %__MODULE__{
          items: [term()],
          query: String.t(),
          cursor: non_neg_integer(),
          page_size: pos_integer(),
          prompt: String.t()
        }

  defstruct items: [],
            query: "",
            cursor: 0,
            page_size: 8,
            prompt: "Filter: "

  @impl true
  def init(opts) do
    %__MODULE__{
      items: Keyword.get(opts, :items, []),
      query: Keyword.get(opts, :query, ""),
      cursor: 0,
      page_size: max(Keyword.get(opts, :page_size, 8), 1),
      prompt: Keyword.get(opts, :prompt, "Filter: ")
    }
  end

  @impl true
  def update(%Event.Text{text: text}, state), do: change_query(state, state.query <> clean(text))

  def update(%Event.Paste{content: text}, state),
    do: change_query(state, state.query <> clean(text))

  def update(%Event.Key{key: :backspace}, state), do: change_query(state, drop_last(state.query))
  def update(%Event.Key{key: :escape}, %{query: ""} = state), do: {state, [:cancel]}
  def update(%Event.Key{key: :escape}, state), do: change_query(state, "")
  def update(%Event.Key{key: :up}, state), do: move(state, -1)
  def update(%Event.Key{key: :down}, state), do: move(state, 1)
  def update(%Event.Key{key: :page_up}, state), do: move(state, -state.page_size)
  def update(%Event.Key{key: :page_down}, state), do: move(state, state.page_size)
  def update(%Event.Key{key: :home}, state), do: {%{state | cursor: 0}, []}
  def update(%Event.Key{key: :end}, state), do: move_to_end(state)

  def update(%Event.Key{key: :enter}, state) do
    case Enum.at(filtered(state), state.cursor) do
      nil -> {state, []}
      item -> {state, [{:picked, item}]}
    end
  end

  def update(_event, state), do: {state, []}

  @impl true
  def mouse(%Event.Mouse{action: action, button: :left, y: y}, state, {_width, height})
      when action in [:press, :release] do
    list_height = max(height - 1, 0)
    offset = visible_offset(state.cursor, list_height)
    index = offset + y - 1

    if y >= 1 and y < height and index < length(filtered(state)) do
      state = %{state | cursor: index}
      if action == :release, do: update(Event.key(:enter), state), else: {state, []}
    else
      {state, []}
    end
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(state, {_width, height} = dimensions) do
    items = filtered(state)
    list_height = max(height - 1, 0)
    offset = visible_offset(state.cursor, list_height)
    query_style = Style.new(fg: :cyan, attrs: [:bold])
    selected_style = Style.new(fg: :black, bg: :cyan, attrs: [:bold])

    rows =
      [[{state.prompt, query_style}, state.query]] ++
        (items
         |> Enum.slice(offset, list_height)
         |> Enum.with_index(offset)
         |> Enum.map(fn {item, index} ->
           prefix = if index == state.cursor, do: "> ", else: "  "
           style = if index == state.cursor, do: selected_style, else: Style.new()
           [{prefix <> item_label(item), style}]
         end))

    Helpers.frame(rows, dimensions,
      cursor: {Helpers.text_width(state.prompt <> state.query) + 1, 1}
    )
  end

  @doc "Returns the items that match the current query."
  @spec filtered(t()) :: [term()]
  def filtered(%{query: ""} = state), do: state.items

  def filtered(state) do
    query = String.downcase(state.query)
    Enum.filter(state.items, &String.contains?(String.downcase(item_label(&1)), query))
  end

  defp change_query(state, query),
    do: {%{state | query: query, cursor: 0}, [{:query_changed, query}]}

  defp move(state, delta) do
    maximum = max(length(filtered(state)) - 1, 0)
    {%{state | cursor: Helpers.clamp(state.cursor + delta, 0, maximum)}, []}
  end

  defp move_to_end(state), do: {%{state | cursor: max(length(filtered(state)) - 1, 0)}, []}
  defp visible_offset(_cursor, 0), do: 0
  defp visible_offset(cursor, height), do: max(cursor - height + 1, 0)
  defp clean(text), do: String.replace(text, ~r/[\x00-\x1F\x7F]/u, "")
  defp drop_last(text), do: text |> String.graphemes() |> Enum.drop(-1) |> Enum.join()
  defp item_label(%{label: label}), do: to_string(label)
  defp item_label({_id, label}), do: to_string(label)
  defp item_label(item), do: to_string(item)
end
