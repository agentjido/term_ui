defmodule TermUI.Widget.List do
  @moduledoc "A pure, scrollable item list with single or multiple selection."

  @behaviour TermUI.Widget

  alias TermUI.{Event, Frame, Style}
  alias TermUI.Widget.Helpers

  # Dialyzer loses the MapSet opaque type when the selection becomes empty.
  @dialyzer {:nowarn_function, set_items: 2}

  @type item :: term()
  @type t :: %__MODULE__{
          items: [item()],
          cursor: non_neg_integer(),
          offset: non_neg_integer(),
          selected: MapSet.t(non_neg_integer()),
          mode: :single | :multiple,
          page_size: pos_integer(),
          marker: String.t(),
          style: Style.t(),
          cursor_style: Style.t(),
          selected_style: Style.t()
        }

  defstruct items: [],
            cursor: 0,
            offset: 0,
            selected: MapSet.new(),
            mode: :single,
            page_size: 10,
            marker: "> ",
            style: %Style{},
            cursor_style: %Style{fg: :cyan, attrs: MapSet.new([:bold])},
            selected_style: %Style{fg: :green}

  @impl true
  def init(opts) do
    %__MODULE__{
      items: Keyword.get(opts, :items, []),
      cursor: max(Keyword.get(opts, :cursor, 0), 0),
      mode: Keyword.get(opts, :mode, :single),
      page_size: max(Keyword.get(opts, :page_size, 10), 1),
      marker: Keyword.get(opts, :marker, "> "),
      style: Keyword.get(opts, :style, Style.new()),
      cursor_style: Keyword.get(opts, :cursor_style, Style.new(fg: :cyan, attrs: [:bold])),
      selected_style: Keyword.get(opts, :selected_style, Style.new(fg: :green))
    }
    |> normalize_cursor()
  end

  @impl true
  def update(%Event.Key{key: :up}, state), do: move(state, -1)
  def update(%Event.Key{key: :down}, state), do: move(state, 1)
  def update(%Event.Key{key: :home}, state), do: move_to(state, 0)
  def update(%Event.Key{key: :end}, state), do: move_to(state, length(state.items) - 1)
  def update(%Event.Key{key: :page_up}, state), do: move(state, -state.page_size)
  def update(%Event.Key{key: :page_down}, state), do: move(state, state.page_size)
  def update(%Event.Key{key: :space}, %{mode: :multiple} = state), do: toggle(state)
  def update(%Event.Text{text: " "}, %{mode: :multiple} = state), do: toggle(state)
  def update(%Event.Key{key: :enter}, state), do: select(state)
  def update(_event, state), do: {state, []}

  @impl true
  def mouse(%Event.Mouse{action: action, button: :left, y: y}, state, {_width, height})
      when action in [:press, :release] do
    offset = visible_offset(state.cursor, state.offset, height)
    index = offset + y

    if y >= 0 and y < height and index < length(state.items) do
      state = %{state | cursor: index, offset: offset}

      cond do
        action == :press -> {state, []}
        state.mode == :multiple -> toggle(state)
        true -> select(state)
      end
    else
      {state, []}
    end
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(state, {width, height} = dimensions) do
    offset = visible_offset(state.cursor, state.offset, height)

    rows =
      state.items
      |> Enum.slice(offset, height)
      |> Enum.with_index(offset)
      |> Enum.map(&render_item(&1, state, width))

    Helpers.frame(rows, dimensions)
  end

  @doc "Replaces all items and keeps the cursor in range."
  @spec set_items(t(), [item()]) :: t()
  def set_items(state, items),
    do: normalize_cursor(%{state | items: items, selected: MapSet.new()})

  @doc "Returns the item under the cursor."
  @spec current(t()) :: item() | nil
  def current(state), do: Enum.at(state.items, state.cursor)

  defp render_item({item, index}, state, width) do
    cursor? = index == state.cursor
    selected? = MapSet.member?(state.selected, index)

    prefix =
      if cursor?, do: state.marker, else: String.duplicate(" ", Helpers.text_width(state.marker))

    check = selection_mark(state.mode, selected?)
    style = item_style(state, cursor?, selected?)
    {label, icon, shortcut} = item_display(item)
    icon = if icon == "", do: "", else: icon <> " "
    text = prefix <> check <> icon <> label
    [{with_shortcut(text, shortcut, width), style}]
  end

  defp selection_mark(:multiple, true), do: "[x] "
  defp selection_mark(:multiple, false), do: "[ ] "
  defp selection_mark(_mode, _selected?), do: ""

  defp item_style(state, true, _selected?), do: state.cursor_style
  defp item_style(state, false, true), do: state.selected_style
  defp item_style(state, false, false), do: state.style

  defp move(state, delta), do: move_to(state, state.cursor + delta)

  defp move_to(state, cursor) do
    state = %{state | cursor: Helpers.clamp(cursor, 0, max(length(state.items) - 1, 0))}
    offset = visible_offset(state.cursor, state.offset, state.page_size)
    {%{state | offset: offset}, []}
  end

  defp select(state) do
    case current(state) do
      nil -> {state, []}
      item -> {%{state | selected: MapSet.new([state.cursor])}, [{:selected, item}]}
    end
  end

  defp toggle(state) do
    case current(state) do
      nil ->
        {state, []}

      item ->
        selected =
          if MapSet.member?(state.selected, state.cursor),
            do: MapSet.delete(state.selected, state.cursor),
            else: MapSet.put(state.selected, state.cursor)

        {%{state | selected: selected}, [{:toggled, item}]}
    end
  end

  defp normalize_cursor(state),
    do: %{state | cursor: min(state.cursor, max(length(state.items) - 1, 0))}

  defp visible_offset(cursor, offset, _height) when cursor < offset, do: cursor

  defp visible_offset(cursor, offset, height) when cursor >= offset + height,
    do: cursor - height + 1

  defp visible_offset(_cursor, offset, _height), do: offset

  defp item_display(%{label: label} = item) do
    icon = item |> Map.get(:icon, "") |> to_string()
    shortcut = Map.get(item, :shortcut, Map.get(item, :hotkey))
    {to_string(label), icon, shortcut && to_string(shortcut)}
  end

  defp item_display({_id, label}), do: {to_string(label), "", nil}
  defp item_display(item), do: {to_string(item), "", nil}

  defp with_shortcut(text, nil, _width), do: text

  defp with_shortcut(text, shortcut, width) do
    shortcut_width = Helpers.text_width(shortcut)
    label_width = max(width - shortcut_width - 1, 0)

    if label_width == 0,
      do: Frame.fit(shortcut, width),
      else: Frame.fit(text, label_width) <> " " <> shortcut
  end
end
