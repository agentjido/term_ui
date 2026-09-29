defmodule TermUI.Widgets.TreeView do
  @moduledoc """
  TreeView widget for displaying hierarchical data with expand/collapse.

  TreeView renders a tree structure with indentation, supporting lazy loading
  for large trees, keyboard navigation, single/multi-selection, and search filtering.

  ## Usage

      TreeView.new(
        nodes: [
          TreeView.node(:root, "Root", children: [
            TreeView.node(:child1, "Child 1"),
            TreeView.node(:child2, "Child 2", children: [
              TreeView.node(:grandchild, "Grandchild")
            ])
          ])
        ],
        on_select: fn node -> handle_select(node) end,
        on_expand: fn node -> load_children(node) end
      )

  ## Node Structure

  Nodes are maps with:
  - `:id` - Unique identifier (required)
  - `:label` - Display text (required)
  - `:icon` - Optional icon string
  - `:children` - List of child nodes, `:lazy` for on-demand loading, or `nil` for leaf
  - `:disabled` - Whether node is disabled
  - `:metadata` - User-defined data

  ## Keyboard Navigation

  - Up/Down: Move cursor between visible nodes
  - Left: Collapse node or move to parent
  - Right: Expand node or move to first child
  - Enter/Space: Toggle expand or select
  - Home/End: Jump to first/last visible node
  - PageUp/PageDown: Jump by page
  - Ctrl+A: Select all (multi-select mode)
  - Shift+Up/Down: Extend selection (multi-select mode)
  - /: Start search filter
  - Escape: Clear filter or deselect

  ## Monochrome Compatibility

  This widget is fully functional in monochrome terminals:
  - Selected nodes use reverse video for visibility
  - Cursor position uses bold text for focus indication
  - Disabled nodes use dim text for de-emphasis
  - Search matches highlighted with bold
  - All interactive states remain distinguishable without color

  The widget uses theme component styles for monochrome support.
  """

  use TermUI.StatefulComponent

  alias TermUI.CharacterSet
  alias TermUI.Event
  alias TermUI.Renderer.Style
  alias TermUI.Theme

  # Dialyzer: Suppress opaque type warnings for Style helpers
  # Also suppress contract_supertype for functions returning specific struct types
  @dialyzer {:nowarn_function,
             fg_semantic: 1,
             fg_color: 1,
             fg_bold_semantic: 1,
             fg_bg_semantic: 2,
             new: 1,
             expand: 2,
             collapse: 2,
             expand_all: 1,
             collapse_all: 1,
             clear_selection: 1,
             set_filter: 2,
             clear_filter: 1,
             finish_loading: 2}

  @type node_id :: term()

  @type tree_node :: %{
          id: node_id(),
          label: String.t(),
          icon: String.t() | nil,
          children: [tree_node()] | :lazy | nil,
          disabled: boolean(),
          metadata: map()
        }

  # Helper to get default icons from CharacterSet
  defp default_icons do
    chars = CharacterSet.current_charset()

    %{
      expanded: chars.triangle_down,
      collapsed: chars.triangle_right,
      leaf: " ",
      loading: chars.loading
    }
  end

  # ----------------------------------------------------------------------------
  # Node Constructors
  # ----------------------------------------------------------------------------

  @doc """
  Creates a tree node.

  ## Options

  - `:children` - Child nodes, `:lazy` for on-demand loading, or omit for leaf
  - `:icon` - Custom icon string
  - `:disabled` - Whether node is disabled (default: false)
  - `:metadata` - User-defined data map
  """
  @spec node(node_id(), String.t(), keyword()) :: tree_node()
  def node(id, label, opts \\ []) do
    %{
      id: id,
      label: label,
      icon: Keyword.get(opts, :icon),
      children: Keyword.get(opts, :children),
      disabled: Keyword.get(opts, :disabled, false),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Creates a leaf node (no children).
  """
  @spec leaf(node_id(), String.t(), keyword()) :: tree_node()
  def leaf(id, label, opts \\ []) do
    node(id, label, Keyword.put(opts, :children, nil))
  end

  @doc """
  Creates a branch node with children.
  """
  @spec branch(node_id(), String.t(), [tree_node()], keyword()) :: tree_node()
  def branch(id, label, children, opts \\ []) do
    node(id, label, Keyword.put(opts, :children, children))
  end

  @doc """
  Creates a lazy-loading node.
  """
  @spec lazy(node_id(), String.t(), keyword()) :: tree_node()
  def lazy(id, label, opts \\ []) do
    node(id, label, Keyword.put(opts, :children, :lazy))
  end

  # ----------------------------------------------------------------------------
  # Style Helper Functions
  # ----------------------------------------------------------------------------

  @spec fg_semantic(atom()) :: Style.t()
  defp fg_semantic(color) when is_atom(color),
    do: Style.new() |> Style.fg(color)

  @spec fg_color(atom()) :: Style.t()
  defp fg_color(color) when is_atom(color),
    do: Style.new() |> Style.fg(color)

  @spec fg_bold_semantic(atom()) :: Style.t()
  defp fg_bold_semantic(color) when is_atom(color),
    do: Style.new() |> Style.fg(color) |> Style.bold()

  @spec fg_bg_semantic(atom(), atom()) :: Style.t()
  defp fg_bg_semantic(fg, bg) when is_atom(fg) and is_atom(bg),
    do: Style.new() |> Style.fg(fg) |> Style.bg(bg)

  # ----------------------------------------------------------------------------
  # Props
  # ----------------------------------------------------------------------------

  @doc """
  Creates new TreeView widget props.

  ## Options

  - `:nodes` - List of root nodes (required)
  - `:on_select` - Callback when node is selected: `fn node -> ... end`
  - `:on_expand` - Callback when node is expanded: `fn node -> children | :loading end`
  - `:on_collapse` - Callback when node is collapsed: `fn node -> ... end`
  - `:selection_mode` - `:single`, `:multi`, or `:none` (default: `:single`)
  - `:show_root` - Show root nodes (default: true)
  - `:indent_size` - Characters per indent level (default: 2)
  - `:icons` - Icon configuration map
  - `:initially_expanded` - List of node IDs to expand initially
  - `:initially_selected` - List of node IDs to select initially
  """
  @spec new(keyword()) :: map()
  def new(opts) do
    %{
      nodes: Keyword.fetch!(opts, :nodes),
      on_select: Keyword.get(opts, :on_select),
      on_expand: Keyword.get(opts, :on_expand),
      on_collapse: Keyword.get(opts, :on_collapse),
      selection_mode: Keyword.get(opts, :selection_mode, :single),
      show_root: Keyword.get(opts, :show_root, true),
      indent_size: Keyword.get(opts, :indent_size, 2),
      icons: Map.merge(default_icons(), Keyword.get(opts, :icons, %{})),
      initially_expanded: Keyword.get(opts, :initially_expanded, []),
      initially_selected: Keyword.get(opts, :initially_selected, [])
    }
  end

  # ----------------------------------------------------------------------------
  # StatefulComponent Callbacks
  # ----------------------------------------------------------------------------

  @impl true
  def init(props) do
    expanded = MapSet.new(props.initially_expanded)
    selected = MapSet.new(props.initially_selected)

    flat_nodes = flatten_nodes(props.nodes, expanded, 0, [])

    state = %{
      nodes: props.nodes,
      flat_nodes: flat_nodes,
      cursor: 0,
      selected: selected,
      expanded: expanded,
      loading: MapSet.new(),
      filter: nil,
      filter_matches: MapSet.new(),
      selection_mode: props.selection_mode,
      selection_anchor: nil,
      show_root: props.show_root,
      indent_size: props.indent_size,
      icons: props.icons,
      on_select: props.on_select,
      on_expand: props.on_expand,
      on_collapse: props.on_collapse
    }

    {:ok, state}
  end

  @impl true
  def update(new_props, state) do
    # Update nodes if provided
    nodes = Map.get(new_props, :nodes, state.nodes)

    # Recalculate flat nodes
    flat_nodes = flatten_nodes(nodes, state.expanded, 0, [])

    # Clamp cursor to valid range
    cursor = min(state.cursor, max(0, length(flat_nodes) - 1))

    state = %{state | nodes: nodes, flat_nodes: flat_nodes, cursor: cursor}

    {:ok, state}
  end

  @impl true
  def handle_event(%Event.Key{key: :up, modifiers: modifiers}, state) do
    state = move_cursor(state, -1, :shift in modifiers)
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :down, modifiers: modifiers}, state) do
    state = move_cursor(state, 1, :shift in modifiers)
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :left}, state) do
    state = handle_left(state)
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :right}, state) do
    state = handle_right(state)
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :enter}, state) do
    state = handle_select_or_toggle(state)
    {:ok, state}
  end

  def handle_event(%Event.Key{key: " "}, state) do
    state = handle_select_or_toggle(state)
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :home}, state) do
    state = %{state | cursor: 0, selection_anchor: nil}
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :end}, state) do
    max_cursor = max(0, length(state.flat_nodes) - 1)
    state = %{state | cursor: max_cursor, selection_anchor: nil}
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :page_up}, state) do
    state = move_cursor(state, -10, false)
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :page_down}, state) do
    state = move_cursor(state, 10, false)
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :escape}, state) do
    state =
      cond do
        state.filter != nil ->
          # Clear filter
          flat_nodes = flatten_nodes(state.nodes, state.expanded, 0, [])
          %{state | filter: nil, filter_matches: MapSet.new(), flat_nodes: flat_nodes}

        MapSet.size(state.selected) > 0 ->
          # Clear selection
          %{state | selected: MapSet.new()}

        true ->
          state
      end

    {:ok, state}
  end

  def handle_event(%Event.Key{key: :backspace}, state) when state.filter != nil do
    # Delete character from filter
    new_filter =
      if String.length(state.filter) > 0 do
        String.slice(state.filter, 0..-2//1)
      else
        nil
      end

    state = apply_filter(state, new_filter)
    {:ok, state}
  end

  def handle_event(%Event.Key{char: char}, state)
      when state.filter != nil and is_binary(char) and char != "" do
    # Add character to filter
    new_filter = state.filter <> char
    state = apply_filter(state, new_filter)
    {:ok, state}
  end

  def handle_event(%Event.Key{char: "a", modifiers: modifiers}, state) do
    # Select all in multi-select mode (Ctrl+A)
    if :ctrl in modifiers && state.selection_mode == :multi do
      all_ids =
        state.flat_nodes
        |> Enum.map(fn {node, _depth, _path} -> node.id end)
        |> MapSet.new()

      state = %{state | selected: all_ids}
      {:ok, state}
    else
      {:ok, state}
    end
  end

  def handle_event(%Event.Key{char: "/"}, state) when state.filter == nil do
    # Start filter mode (just set empty filter for now)
    state = %{state | filter: ""}
    {:ok, state}
  end

  def handle_event(_event, state) do
    {:ok, state}
  end

  @impl true
  def render(state, _area) do
    if state.flat_nodes == [] do
      text("(empty)")
    else
      rows =
        state.flat_nodes
        |> Enum.with_index()
        |> Enum.map(fn {{node, depth, _path}, index} ->
          render_node(node, depth, index, state)
        end)

      # Add filter indicator if filtering
      rows =
        if state.filter != nil do
          filter_row = render_filter_bar(state)
          [filter_row | rows]
        else
          rows
        end

      stack(:vertical, rows)
    end
  end

  # ----------------------------------------------------------------------------
  # Navigation Helpers
  # ----------------------------------------------------------------------------

  defp move_cursor(state, delta, extend_selection) do
    max_cursor = max(0, length(state.flat_nodes) - 1)
    old_cursor = state.cursor
    new_cursor = state.cursor + delta
    new_cursor = max(0, min(max_cursor, new_cursor))

    state = %{state | cursor: new_cursor}

    # Handle selection extension in multi-select mode
    if extend_selection && state.selection_mode == :multi do
      extend_selection_to(state, old_cursor, new_cursor)
    else
      %{state | selection_anchor: nil}
    end
  end

  defp extend_selection_to(state, old_cursor, new_cursor) do
    # Use existing anchor or the old cursor position
    anchor = state.selection_anchor || old_cursor

    # Select all nodes between anchor and new cursor
    {start_idx, end_idx} =
      if anchor <= new_cursor do
        {anchor, new_cursor}
      else
        {new_cursor, anchor}
      end

    selected_ids =
      state.flat_nodes
      |> Enum.slice(start_idx..end_idx)
      |> Enum.map(fn {node, _depth, _path} -> node.id end)
      |> MapSet.new()

    %{state | selected: selected_ids, selection_anchor: anchor}
  end

  defp handle_left(state) do
    case get_current_node(state) do
      nil ->
        state

      {node, _depth, path} ->
        cond do
          # If expanded, collapse it
          has_children?(node) && MapSet.member?(state.expanded, node.id) ->
            collapse_node(state, node)

          # If not expanded, move to parent
          path != [] ->
            parent_id = List.last(path)
            move_to_node(state, parent_id)

          true ->
            state
        end
    end
  end

  defp handle_right(state) do
    case get_current_node(state) do
      nil ->
        state

      {node, _depth, _path} ->
        cond do
          # If has children and collapsed, expand
          has_children?(node) && !MapSet.member?(state.expanded, node.id) ->
            expand_node(state, node)

          # If expanded, move to first child
          has_children?(node) && MapSet.member?(state.expanded, node.id) ->
            move_to_first_child(state)

          true ->
            state
        end
    end
  end

  defp handle_select_or_toggle(state) do
    case get_current_node(state) do
      nil ->
        state

      {node, _depth, _path} ->
        if has_children?(node) do
          toggle_node_expand(state, node)
        else
          # Select leaf node
          select_node(state, node)
        end
    end
  end

  defp toggle_node_expand(state, node) do
    if MapSet.member?(state.expanded, node.id) do
      collapse_node(state, node)
    else
      expand_node(state, node)
    end
  end

  defp expand_node(state, node) do
    cond do
      # Already expanded
      MapSet.member?(state.expanded, node.id) ->
        state

      # Lazy loading needed
      node.children == :lazy ->
        # Mark as loading and call on_expand callback
        state = %{state | loading: MapSet.put(state.loading, node.id)}

        if state.on_expand do
          try do
            state.on_expand.(node)
          rescue
            e ->
              require Logger
              Logger.error("TreeView on_expand callback error: #{inspect(e)}")
          end
        end

        state

      # Has children, expand
      is_list(node.children) ->
        expanded = MapSet.put(state.expanded, node.id)
        flat_nodes = flatten_nodes(state.nodes, expanded, 0, [])

        if state.on_expand do
          try do
            state.on_expand.(node)
          rescue
            _ -> :ok
          end
        end

        %{state | expanded: expanded, flat_nodes: flat_nodes}

      true ->
        state
    end
  end

  defp collapse_node(state, node) do
    expanded = MapSet.delete(state.expanded, node.id)
    flat_nodes = flatten_nodes(state.nodes, expanded, 0, [])

    if state.on_collapse do
      try do
        state.on_collapse.(node)
      rescue
        _ -> :ok
      end
    end

    # Clamp cursor if it was on a now-hidden node
    cursor = min(state.cursor, max(0, length(flat_nodes) - 1))

    %{state | expanded: expanded, flat_nodes: flat_nodes, cursor: cursor}
  end

  defp select_node(state, node) do
    selected =
      case state.selection_mode do
        :none ->
          state.selected

        :single ->
          MapSet.new([node.id])

        :multi ->
          if MapSet.member?(state.selected, node.id) do
            MapSet.delete(state.selected, node.id)
          else
            MapSet.put(state.selected, node.id)
          end
      end

    if state.on_select && state.selection_mode != :none do
      try do
        state.on_select.(node)
      rescue
        e ->
          require Logger
          Logger.error("TreeView on_select callback error: #{inspect(e)}")
      end
    end

    %{state | selected: selected}
  end

  defp move_to_node(state, node_id) do
    case Enum.find_index(state.flat_nodes, fn {n, _, _} -> n.id == node_id end) do
      nil -> state
      index -> %{state | cursor: index}
    end
  end

  defp move_to_first_child(state) do
    if state.cursor + 1 < length(state.flat_nodes) do
      %{state | cursor: state.cursor + 1}
    else
      state
    end
  end

  # ----------------------------------------------------------------------------
  # Filter Helpers
  # ----------------------------------------------------------------------------

  defp apply_filter(state, nil) do
    flat_nodes = flatten_nodes(state.nodes, state.expanded, 0, [])
    %{state | filter: nil, filter_matches: MapSet.new(), flat_nodes: flat_nodes}
  end

  defp apply_filter(state, "") do
    flat_nodes = flatten_nodes(state.nodes, state.expanded, 0, [])
    %{state | filter: "", filter_matches: MapSet.new(), flat_nodes: flat_nodes}
  end

  defp apply_filter(state, filter) do
    filter_lower = String.downcase(filter)

    # Find matching nodes and their ancestors
    {matches, ancestors} =
      find_filter_matches(state.nodes, filter_lower, [], MapSet.new(), MapSet.new())

    # Expand all ancestors of matches
    expanded = MapSet.union(state.expanded, ancestors)

    # Flatten with expanded ancestors
    flat_nodes = flatten_nodes(state.nodes, expanded, 0, [])

    # Filter to only show matches and their ancestors
    all_visible = MapSet.union(matches, ancestors)

    flat_nodes =
      if MapSet.size(matches) > 0 do
        Enum.filter(flat_nodes, fn {node, _depth, _path} ->
          MapSet.member?(all_visible, node.id)
        end)
      else
        flat_nodes
      end

    cursor = min(state.cursor, max(0, length(flat_nodes) - 1))

    %{
      state
      | filter: filter,
        filter_matches: matches,
        flat_nodes: flat_nodes,
        expanded: expanded,
        cursor: cursor
    }
  end

  defp find_filter_matches(nodes, filter, path, matches, ancestors) do
    Enum.reduce(nodes, {matches, ancestors}, fn node, acc ->
      process_filter_node(node, filter, path, acc)
    end)
  end

  defp process_filter_node(node, filter, path, {matches_acc, ancestors_acc}) do
    label_lower = String.downcase(node.label)
    is_match = String.contains?(label_lower, filter)

    {child_matches, child_ancestors} =
      find_child_filter_matches(node, filter, path, matches_acc, ancestors_acc)

    if should_include_in_filter?(is_match, child_matches, matches_acc) do
      new_matches = update_filter_matches(child_matches, is_match, node.id)
      new_ancestors = add_path_to_ancestors(path, child_ancestors)
      {new_matches, new_ancestors}
    else
      {child_matches, child_ancestors}
    end
  end

  defp find_child_filter_matches(node, filter, path, matches_acc, ancestors_acc) do
    case node.children do
      children when is_list(children) ->
        find_filter_matches(children, filter, path ++ [node.id], matches_acc, ancestors_acc)

      _ ->
        {matches_acc, ancestors_acc}
    end
  end

  defp should_include_in_filter?(is_match, child_matches, matches_acc) do
    has_descendant_match = MapSet.size(child_matches) > MapSet.size(matches_acc)
    is_match or has_descendant_match
  end

  defp update_filter_matches(child_matches, true, node_id) do
    MapSet.put(child_matches, node_id)
  end

  defp update_filter_matches(child_matches, false, _node_id) do
    child_matches
  end

  defp add_path_to_ancestors(path, child_ancestors) do
    Enum.reduce(path, child_ancestors, &MapSet.put(&2, &1))
  end

  # ----------------------------------------------------------------------------
  # Node Helpers
  # ----------------------------------------------------------------------------

  defp get_current_node(state) do
    Enum.at(state.flat_nodes, state.cursor)
  end

  defp has_children?(node) do
    case node.children do
      nil -> false
      :lazy -> true
      [] -> false
      [_ | _] -> true
    end
  end

  defp flatten_nodes(nodes, expanded, depth, path) do
    Enum.flat_map(nodes, fn node ->
      current = {node, depth, path}

      children_flat =
        cond do
          !MapSet.member?(expanded, node.id) ->
            []

          is_list(node.children) ->
            flatten_nodes(node.children, expanded, depth + 1, path ++ [node.id])

          true ->
            []
        end

      [current | children_flat]
    end)
  end

  # ----------------------------------------------------------------------------
  # Rendering
  # ----------------------------------------------------------------------------

  defp render_node(node, depth, index, state) do
    is_cursor = index == state.cursor
    is_selected = MapSet.member?(state.selected, node.id)
    is_loading = MapSet.member?(state.loading, node.id)
    is_match = state.filter != nil && MapSet.member?(state.filter_matches, node.id)

    indent = String.duplicate(" ", depth * state.indent_size)
    indicator = node_indicator(node, is_loading, state)
    icon = node_icon(node)
    selection_prefix = selection_prefix(is_cursor, is_selected)

    label = node.label
    line = "#{selection_prefix}#{indent}#{indicator} #{icon}#{label}"

    apply_node_style(line, node, is_cursor, is_selected, is_match)
  end

  defp node_indicator(node, is_loading, state) do
    cond do
      is_loading ->
        state.icons.loading

      has_children?(node) && MapSet.member?(state.expanded, node.id) ->
        state.icons.expanded

      has_children?(node) ->
        state.icons.collapsed

      true ->
        state.icons.leaf
    end
  end

  defp node_icon(%{icon: icon}) when is_binary(icon), do: "#{icon} "
  defp node_icon(_), do: ""

  defp selection_prefix(is_cursor, is_selected) do
    chars = CharacterSet.current_charset()

    cond do
      is_cursor && is_selected -> chars.bullet
      is_cursor -> chars.pointer
      is_selected -> chars.bullet_empty
      true -> " "
    end
  end

  defp apply_node_style(line, node, is_cursor, is_selected, is_match) do
    cond do
      node.disabled ->
        styled(text(line), fg_semantic(Theme.get_semantic(:muted)))

      is_cursor && is_match ->
        cursor_match_style =
          fg_bg_semantic(Theme.get_color(:background), Theme.get_semantic(:warning))

        styled(text(line), cursor_match_style)

      is_cursor ->
        styled(text(line), Theme.get_component_style(:item, :focused))

      is_match ->
        styled(text(line), fg_semantic(Theme.get_semantic(:warning)))

      is_selected ->
        styled(text(line), fg_color(Theme.get_color(:primary)))

      true ->
        text(line)
    end
  end

  defp render_filter_bar(state) do
    filter_text = "Filter: #{state.filter}_"
    match_count = MapSet.size(state.filter_matches)
    count_text = if match_count > 0, do: " (#{match_count} matches)", else: " (no matches)"

    filter_style = fg_bold_semantic(Theme.get_semantic(:warning))
    styled(text(filter_text <> count_text), filter_style)
  end

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Gets the currently selected node IDs.
  """
  @spec get_selected(map()) :: MapSet.t(node_id())
  def get_selected(state) do
    state.selected
  end

  @doc """
  Gets the currently focused node.
  """
  @spec get_focused(map()) :: tree_node() | nil
  def get_focused(state) do
    case get_current_node(state) do
      {node, _depth, _path} -> node
      nil -> nil
    end
  end

  @doc """
  Gets the expanded node IDs.
  """
  @spec get_expanded(map()) :: MapSet.t(node_id())
  def get_expanded(state) do
    state.expanded
  end

  @doc """
  Expands a node by ID.
  """
  @spec expand(map(), node_id()) :: map()
  def expand(state, node_id) do
    expanded = MapSet.put(state.expanded, node_id)
    flat_nodes = flatten_nodes(state.nodes, expanded, 0, [])
    %{state | expanded: expanded, flat_nodes: flat_nodes}
  end

  @doc """
  Collapses a node by ID.
  """
  @spec collapse(map(), node_id()) :: map()
  def collapse(state, node_id) do
    expanded = MapSet.delete(state.expanded, node_id)
    flat_nodes = flatten_nodes(state.nodes, expanded, 0, [])
    cursor = min(state.cursor, max(0, length(flat_nodes) - 1))
    %{state | expanded: expanded, flat_nodes: flat_nodes, cursor: cursor}
  end

  @doc """
  Expands all nodes.
  """
  @spec expand_all(map()) :: map()
  def expand_all(state) do
    all_ids = collect_all_branch_ids(state.nodes)
    expanded = MapSet.new(all_ids)
    flat_nodes = flatten_nodes(state.nodes, expanded, 0, [])
    %{state | expanded: expanded, flat_nodes: flat_nodes}
  end

  @doc """
  Collapses all nodes.
  """
  @spec collapse_all(map()) :: map()
  def collapse_all(state) do
    flat_nodes = flatten_nodes(state.nodes, MapSet.new(), 0, [])
    %{state | expanded: MapSet.new(), flat_nodes: flat_nodes, cursor: 0}
  end

  @doc """
  Sets the selection programmatically.
  """
  @spec set_selected(map(), [node_id()]) :: map()
  def set_selected(state, node_ids) do
    %{state | selected: MapSet.new(node_ids)}
  end

  @doc """
  Clears the selection.
  """
  @spec clear_selection(map()) :: map()
  def clear_selection(state) do
    %{state | selected: MapSet.new()}
  end

  @doc """
  Sets the filter programmatically.
  """
  @spec set_filter(map(), String.t() | nil) :: map()
  def set_filter(state, filter) do
    apply_filter(state, filter)
  end

  @doc """
  Clears the filter.
  """
  @spec clear_filter(map()) :: map()
  def clear_filter(state) do
    apply_filter(state, nil)
  end

  @doc """
  Updates the children of a node (for lazy loading).
  """
  @spec set_children(map(), node_id(), [tree_node()]) :: map()
  def set_children(state, node_id, children) do
    nodes = update_node_children(state.nodes, node_id, children)
    loading = MapSet.delete(state.loading, node_id)
    expanded = MapSet.put(state.expanded, node_id)
    flat_nodes = flatten_nodes(nodes, expanded, 0, [])
    %{state | nodes: nodes, flat_nodes: flat_nodes, loading: loading, expanded: expanded}
  end

  @doc """
  Marks a node as finished loading (clears loading state).
  """
  @spec finish_loading(map(), node_id()) :: map()
  def finish_loading(state, node_id) do
    %{state | loading: MapSet.delete(state.loading, node_id)}
  end

  # ----------------------------------------------------------------------------
  # Private Helpers
  # ----------------------------------------------------------------------------

  defp collect_all_branch_ids(nodes) do
    Enum.flat_map(nodes, fn node ->
      case node.children do
        children when is_list(children) and children != [] ->
          [node.id | collect_all_branch_ids(children)]

        :lazy ->
          [node.id]

        _ ->
          []
      end
    end)
  end

  defp update_node_children(nodes, target_id, new_children) do
    Enum.map(nodes, fn node ->
      cond do
        node.id == target_id ->
          %{node | children: new_children}

        is_list(node.children) ->
          %{node | children: update_node_children(node.children, target_id, new_children)}

        true ->
          node
      end
    end)
  end
end
