defmodule TermUI.Widget.Tabs do
  @moduledoc "A pure tab strip with optional frame or row content."

  @behaviour TermUI.Widget

  alias TermUI.{Event, Frame, Layout, Style}
  alias TermUI.Widget.Helpers

  @type tab :: %{
          required(:id) => term(),
          required(:label) => String.t(),
          optional(:content) => term(),
          optional(:icon) => String.t(),
          optional(:status) => String.t() | boolean(),
          optional(:shortcut) => String.t(),
          optional(:disabled) => boolean()
        }
  @type t :: %__MODULE__{
          tabs: [tab()],
          selected: non_neg_integer(),
          focused: non_neg_integer(),
          alignment: :left | :center | :right
        }
  defstruct tabs: [],
            selected: 0,
            focused: 0,
            alignment: :left

  @impl true
  def init(opts) do
    tabs = opts |> Keyword.get(:tabs, []) |> Enum.map(&normalize_tab/1)
    selected = selected_index(tabs, Keyword.get(opts, :selected), 0)

    %__MODULE__{
      tabs: tabs,
      selected: selected,
      focused: selected,
      alignment: Keyword.get(opts, :alignment, Keyword.get(opts, :align, :left))
    }
  end

  @impl true
  def update(%Event.Key{key: :left}, state), do: move(state, -1)
  def update(%Event.Key{key: :right}, state), do: move(state, 1)
  def update(%Event.Key{key: :home}, state), do: focus_edge(state, :first)
  def update(%Event.Key{key: :end}, state), do: focus_edge(state, :last)
  def update(%Event.Key{key: key}, state) when key in [:enter, :space], do: select_focused(state)
  def update(%Event.Text{text: " "}, state), do: select_focused(state)
  def update(_event, state), do: {state, []}

  @impl true
  def mouse(%Event.Mouse{action: action, button: :left, x: x, y: 0}, state, {width, _height})
      when action in [:press, :release] do
    case tab_at(state.tabs, x, width, state.alignment) do
      nil ->
        {state, []}

      index ->
        state = %{state | focused: index}
        if action == :release, do: select_focused(state), else: {state, []}
    end
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(state, {width, height}) do
    normal = Style.new(fg: :bright_black)
    active = Style.new(fg: :cyan, attrs: [:bold, :underline])
    focused = Style.new(attrs: [:reverse])
    disabled = Style.new(fg: :bright_black, attrs: [:dim])

    items =
      state.tabs
      |> Enum.with_index()
      |> Enum.flat_map(fn {tab, index} ->
        style =
          cond do
            Map.get(tab, :disabled, false) -> disabled
            index == state.focused -> focused
            index == state.selected -> active
            true -> normal
          end

        [{tab_text(tab), style}, " "]
      end)

    header = [String.duplicate(" ", header_origin(state.tabs, width, state.alignment)) | items]

    base = Frame.from_rows([header], width, height)

    case selected(state) do
      nil -> base
      tab -> overlay_content(base, Map.get(tab, :content), width, max(height - 1, 1))
    end
  end

  @doc "Returns the selected tab or nil."
  @spec selected(t()) :: tab() | nil
  def selected(state) do
    case Enum.at(state.tabs, state.selected) do
      %{disabled: true} -> nil
      tab -> tab
    end
  end

  @doc "Selects a tab by id."
  @spec select(t(), term()) :: t()
  def select(state, id) do
    index = selected_index(state.tabs, id, state.selected)
    %{state | selected: index, focused: index}
  end

  @doc "Returns the zero-based rectangle available to selected tab content."
  @spec content_rect(t(), TermUI.Widget.dimensions()) :: Layout.rect()
  def content_rect(_state, {width, height}), do: {0, min(height, 1), width, max(height - 1, 0)}

  @doc "Renders and clips pure child content below the tab strip."
  @spec compose(t(), TermUI.Widget.dimensions(), TermUI.Widget.renderable()) :: Frame.t()
  def compose(state, dimensions, child) do
    Helpers.compose(view(state, dimensions), content_rect(state, dimensions), child)
  end

  defp move(%{tabs: []} = state, _delta), do: {state, []}

  defp move(state, delta) do
    indices = enabled_indices(state.tabs)

    case indices do
      [] ->
        {state, []}

      _indices ->
        position =
          Enum.find_index(indices, &(&1 == state.focused)) || if(delta < 0, do: 0, else: -1)

        next = Enum.at(indices, rem(position + delta + length(indices), length(indices)))
        focus_index(state, next)
    end
  end

  defp focus_index(state, index) do
    index = Helpers.clamp(index, 0, max(length(state.tabs) - 1, 0))
    tab = Enum.at(state.tabs, index)

    if enabled?(tab),
      do: {%{state | focused: index}, [{:focused, tab}]},
      else: {state, []}
  end

  defp focus_edge(state, edge) do
    index =
      case edge do
        :first -> List.first(enabled_indices(state.tabs))
        :last -> List.last(enabled_indices(state.tabs))
      end

    if is_nil(index), do: {state, []}, else: focus_index(state, index)
  end

  defp select_focused(state) do
    tab = Enum.at(state.tabs, state.focused)

    if tab && not Map.get(tab, :disabled, false),
      do: {%{state | selected: state.focused}, [{:selected, tab.id}]},
      else: {state, []}
  end

  defp overlay_content(base, %Frame{} = content, _width, _height),
    do: Frame.overlay(base, content, 1, 2)

  defp overlay_content(base, content, width, height) do
    rows =
      cond do
        is_binary(content) -> String.split(content, "\n", trim: false)
        is_list(content) -> content
        is_nil(content) -> []
        true -> [to_string(content)]
      end

    Frame.overlay(base, Helpers.frame(rows, {width, height}), 1, 2)
  end

  defp normalize_tab(%{id: _id, label: label} = tab) do
    shortcut = Map.get(tab, :shortcut, Map.get(tab, :hotkey))

    tab
    |> Map.put(:label, to_string(label))
    |> Map.put(:shortcut, normalize_decoration(shortcut))
  end

  defp normalize_tab({id, label}), do: %{id: id, label: to_string(label)}
  defp normalize_tab(label), do: %{id: label, label: to_string(label)}

  defp tab_at(tabs, x, width, alignment) when x >= 0 and x < width do
    origin = header_origin(tabs, width, alignment)

    tabs
    |> Enum.with_index()
    |> Enum.reduce_while({:after, origin}, fn {tab, index}, {:after, start} ->
      finish = start + Helpers.text_width(tab_text(tab))

      if x >= start and x < finish,
        do: {:halt, if(enabled?(tab), do: {:found, index}, else: :none)},
        else: {:cont, {:after, finish + 1}}
    end)
    |> case do
      {:found, index} -> index
      _other -> nil
    end
  end

  defp tab_at(_tabs, _x, _width, _alignment), do: nil

  defp selected_index(tabs, nil, fallback),
    do: enabled_fallback(tabs, fallback)

  defp selected_index(tabs, id, fallback),
    do:
      Enum.find_index(tabs, &(&1.id == id and enabled?(&1))) ||
        selected_index(tabs, nil, fallback)

  defp enabled_fallback(tabs, fallback) do
    fallback = Helpers.clamp(fallback, 0, max(length(tabs) - 1, 0))

    if enabled?(Enum.at(tabs, fallback)),
      do: fallback,
      else: List.first(enabled_indices(tabs)) || 0
  end

  defp enabled_indices(tabs) do
    tabs
    |> Enum.with_index()
    |> Enum.filter(fn {tab, _index} -> enabled?(tab) end)
    |> Enum.map(&elem(&1, 1))
  end

  defp enabled?(nil), do: false
  defp enabled?(tab), do: not Map.get(tab, :disabled, false)

  defp tab_text(tab) do
    icon = optional_part(tab, :icon, :prefix)
    status = status_part(tab)
    shortcut = optional_part(tab, :shortcut, :suffix)
    " " <> icon <> tab.label <> status <> shortcut <> " "
  end

  defp status_part(%{status: true}), do: " ●"
  defp status_part(%{status: false}), do: ""
  defp status_part(tab), do: optional_part(tab, :status, :suffix)

  defp optional_part(tab, key, position) do
    case Map.get(tab, key) do
      nil -> ""
      "" -> ""
      value when position == :prefix -> to_string(value) <> " "
      value -> " " <> to_string(value)
    end
  end

  defp normalize_decoration(nil), do: nil
  defp normalize_decoration(value) when is_list(value), do: IO.iodata_to_binary(value)
  defp normalize_decoration(value), do: to_string(value)

  defp header_origin(tabs, width, alignment) do
    content_width = Enum.reduce(tabs, 0, &(Helpers.text_width(tab_text(&1)) + 1 + &2))
    room = max(width - content_width, 0)

    case alignment do
      :center -> div(room, 2)
      :right -> room
      :left -> 0
    end
  end
end
