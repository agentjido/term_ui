defmodule TermUI.Widget.TreeView do
  @moduledoc "A pure expandable tree with keyboard navigation and selection."

  @behaviour TermUI.Widget

  alias TermUI.{Event, Style}
  alias TermUI.Widget.Helpers

  @type tree_node :: %{
          required(:id) => term(),
          required(:label) => String.t(),
          required(:children) => [tree_node()],
          optional(:icon) => String.t(),
          optional(:disabled) => boolean()
        }
  @type t :: %__MODULE__{
          nodes: [tree_node()],
          cursor: non_neg_integer(),
          offset: non_neg_integer(),
          expanded: MapSet.t(term()),
          selected: MapSet.t(term()),
          page_size: pos_integer()
        }

  defstruct nodes: [],
            cursor: 0,
            offset: 0,
            expanded: MapSet.new(),
            selected: MapSet.new(),
            page_size: 10

  @doc "Creates a tree leaf."
  @spec leaf(term(), iodata(), keyword()) :: tree_node()
  def leaf(id, label, opts \\ []) do
    %{
      id: id,
      label: IO.iodata_to_binary(label),
      children: [],
      disabled: Keyword.get(opts, :disabled, false)
    }
    |> put_icon(opts)
  end

  @doc "Creates a tree branch."
  @spec branch(term(), iodata(), [tree_node()], keyword()) :: tree_node()
  def branch(id, label, children, opts \\ []) do
    %{
      id: id,
      label: IO.iodata_to_binary(label),
      children: children,
      disabled: Keyword.get(opts, :disabled, false)
    }
    |> put_icon(opts)
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      nodes: Keyword.get(opts, :nodes, []),
      expanded: MapSet.new(Keyword.get(opts, :expanded, [])),
      selected: MapSet.new(Keyword.get(opts, :selected, [])),
      page_size: max(Keyword.get(opts, :page_size, 10), 1)
    }

    %{state | cursor: first_enabled(visible(state))}
  end

  @impl true
  def update(%Event.Key{key: :up}, state), do: move(state, -1)
  def update(%Event.Key{key: :down}, state), do: move(state, 1)
  def update(%Event.Key{key: :home}, state), do: move_to_edge(state, :first)
  def update(%Event.Key{key: :end}, state), do: move_to_edge(state, :last)
  def update(%Event.Key{key: :page_up}, state), do: move_by_rows(state, -state.page_size)
  def update(%Event.Key{key: :page_down}, state), do: move_by_rows(state, state.page_size)
  def update(%Event.Key{key: :right}, state), do: expand_current(state)
  def update(%Event.Key{key: :left}, state), do: collapse_current(state)
  def update(%Event.Key{key: :enter}, state), do: toggle_current(state)
  def update(%Event.Key{key: :space}, state), do: select_current(state)
  def update(%Event.Text{text: " "}, state), do: select_current(state)
  def update(_event, state), do: {state, []}

  @impl true
  def mouse(%Event.Mouse{action: action, button: :left, x: x, y: y}, state, {width, height})
      when action in [:press, :release] do
    nodes = visible(state)
    offset = visible_offset(state.cursor, state.offset, height)
    index = offset + y

    case Enum.at(nodes, index) do
      {node, depth} when x >= 0 and x < width and y >= 0 and y < height ->
        mouse_node(action, state, node, depth, index, offset, x)

      _other ->
        {state, []}
    end
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(state, {_width, height} = dimensions) do
    visible = visible(state)
    offset = visible_offset(state.cursor, state.offset, height)

    styles = %{
      cursor: Style.new(attrs: [:reverse]),
      selected: Style.new(fg: :green),
      branch: Style.new(fg: :cyan),
      disabled: Style.new(fg: :bright_black, attrs: [:dim]),
      normal: Style.new()
    }

    rows =
      visible
      |> Enum.slice(offset, height)
      |> Enum.with_index(offset)
      |> Enum.map(&node_row(&1, state, styles))

    Helpers.frame(rows, dimensions)
  end

  @doc "Returns visible nodes and their depth."
  @spec visible(t()) :: [{tree_node(), non_neg_integer()}]
  def visible(state), do: flatten(state.nodes, state.expanded, 0)

  @doc "Replaces the children of one node without performing I/O."
  @spec set_children(t(), term(), [tree_node()]) :: t()
  def set_children(state, id, children),
    do: normalize_cursor(%{state | nodes: replace_children(state.nodes, id, children)})

  defp move(state, delta), do: move_to(state, state.cursor + delta)

  defp move_by_rows(state, delta) do
    nodes = visible(state)
    indices = enabled_indices(nodes)

    case indices do
      [] ->
        {state, []}

      _indices ->
        target = Helpers.clamp(state.cursor + delta, 0, max(length(nodes) - 1, 0))
        cursor = enabled_at_or_beyond(indices, target, delta)
        offset = visible_offset(cursor, state.offset, state.page_size)
        {%{state | cursor: cursor, offset: offset}, []}
    end
  end

  defp move_to(state, cursor) do
    indices = enabled_indices(visible(state))
    cursor = next_enabled(indices, state.cursor, cursor - state.cursor)
    offset = visible_offset(cursor, state.offset, state.page_size)
    {%{state | cursor: cursor, offset: offset}, []}
  end

  defp move_to_edge(state, edge) do
    indices = enabled_indices(visible(state))
    cursor = if edge == :first, do: List.first(indices), else: List.last(indices)

    if is_nil(cursor),
      do: {state, []},
      else:
        {%{state | cursor: cursor, offset: visible_offset(cursor, state.offset, state.page_size)},
         []}
  end

  defp expand_current(state) do
    case current(state) do
      {%{disabled: true}, _depth} ->
        {state, []}

      {%{children: [_ | _], id: id}, _depth} ->
        {%{state | expanded: MapSet.put(state.expanded, id)}, [{:expanded, id}]}

      _other ->
        {state, []}
    end
  end

  defp collapse_current(state) do
    case current(state) do
      {%{disabled: true}, _depth} ->
        {state, []}

      {%{id: id}, _depth} ->
        {%{state | expanded: MapSet.delete(state.expanded, id)}, [{:collapsed, id}]}

      _other ->
        {state, []}
    end
  end

  defp toggle_current(state) do
    case current(state) do
      {%{disabled: true}, _depth} ->
        {state, []}

      {%{children: [_ | _], id: id}, _depth} ->
        if MapSet.member?(state.expanded, id),
          do: collapse_current(state),
          else: expand_current(state)

      {%{id: id} = node, _depth} ->
        {state, [{:activated, id, node}]}

      _other ->
        {state, []}
    end
  end

  defp select_current(state) do
    case current(state) do
      {%{disabled: true}, _depth} ->
        {state, []}

      {%{id: id}, _depth} ->
        {%{state | selected: MapSet.put(state.selected, id)}, [{:selected, id}]}

      _other ->
        {state, []}
    end
  end

  defp current(state), do: Enum.at(visible(state), state.cursor)

  defp mouse_node(action, state, node, depth, index, offset, x) do
    if enabled?(node) do
      state = %{state | cursor: index, offset: offset}
      mouse_node_action(action, state, node, depth, x)
    else
      {state, []}
    end
  end

  defp mouse_node_action(:press, state, _node, _depth, _x), do: {state, []}

  defp mouse_node_action(:release, state, %{children: [_ | _]}, depth, x)
       when x <= depth * 2 + 1,
       do: toggle_current(state)

  defp mouse_node_action(:release, state, _node, _depth, _x), do: select_current(state)

  defp node_row({{node, depth}, index}, state, styles) do
    branch? = node.children != []
    glyph = node_glyph(node, branch?, state.expanded)
    icon = node |> Map.get(:icon, "") |> to_string()
    icon = if icon == "", do: "", else: icon <> " "
    text = String.duplicate("  ", depth) <> glyph <> " " <> icon <> node.label
    [{text, node_style(node, index, branch?, state, styles)}]
  end

  defp node_glyph(_node, false, _expanded), do: "•"

  defp node_glyph(node, true, expanded),
    do: if(MapSet.member?(expanded, node.id), do: "▾", else: "▸")

  defp node_style(node, index, branch?, state, styles) do
    cond do
      not enabled?(node) -> styles.disabled
      index == state.cursor -> styles.cursor
      MapSet.member?(state.selected, node.id) -> styles.selected
      branch? -> styles.branch
      true -> styles.normal
    end
  end

  defp visible_offset(_cursor, offset, 0), do: offset
  defp visible_offset(cursor, offset, _height) when cursor < offset, do: cursor

  defp visible_offset(cursor, offset, height) when cursor >= offset + height,
    do: cursor - height + 1

  defp visible_offset(_cursor, offset, _height), do: offset

  defp flatten(nodes, expanded, depth) do
    Enum.flat_map(nodes, fn node ->
      children =
        if MapSet.member?(expanded, node.id),
          do: flatten(node.children, expanded, depth + 1),
          else: []

      [{node, depth} | children]
    end)
  end

  defp replace_children(nodes, id, children) do
    Enum.map(nodes, fn node ->
      if node.id == id,
        do: %{node | children: children},
        else: %{node | children: replace_children(node.children, id, children)}
    end)
  end

  defp normalize_cursor(state) do
    indices = enabled_indices(visible(state))

    if state.cursor in indices,
      do: state,
      else: %{state | cursor: List.first(indices) || 0, offset: 0}
  end

  defp enabled_indices(nodes) do
    nodes
    |> Enum.with_index()
    |> Enum.filter(fn {{node, _depth}, _index} -> enabled?(node) end)
    |> Enum.map(&elem(&1, 1))
  end

  defp first_enabled(nodes), do: List.first(enabled_indices(nodes)) || 0

  defp next_enabled([], cursor, _delta), do: cursor

  defp next_enabled(indices, cursor, delta) do
    position = Enum.find_index(indices, &(&1 == cursor)) || if(delta < 0, do: 0, else: -1)
    Enum.at(indices, Helpers.clamp(position + delta, 0, length(indices) - 1))
  end

  defp enabled_at_or_beyond(indices, target, delta) when delta < 0,
    do: Enum.find(Enum.reverse(indices), List.first(indices), &(&1 <= target))

  defp enabled_at_or_beyond(indices, target, _delta),
    do: Enum.find(indices, List.last(indices), &(&1 >= target))

  defp enabled?(node), do: not Map.get(node, :disabled, false)

  defp put_icon(node, opts) do
    case Keyword.get(opts, :icon) do
      nil -> node
      icon -> Map.put(node, :icon, to_string(icon))
    end
  end
end
