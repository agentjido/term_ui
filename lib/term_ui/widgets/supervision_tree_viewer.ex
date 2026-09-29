defmodule TermUI.Widgets.SupervisionTreeViewer do
  @moduledoc """
  SupervisionTreeViewer widget for OTP supervision hierarchy visualization.

  SupervisionTreeViewer displays the supervision tree with live status indicators,
  restart counts, and provides controls for process management and inspection.

  ## Usage

      SupervisionTreeViewer.new(
        root: MyApp.Supervisor,
        update_interval: 2000,
        on_select: fn node -> handle_select(node) end
      )

  ## Features

  - Tree view of supervision hierarchy
  - Live status indicators (running, restarting, terminated)
  - Restart count and history display
  - Supervisor strategy display
  - Process state inspection
  - Restart/terminate controls with confirmation
  - Explicit refresh API for supervision tree changes

  ## Keyboard Controls

  - Up/Down: Move selection
  - Left: Collapse node or move to parent
  - Right: Expand node or move to first child
  - Enter: Toggle expand/collapse
  - i: Show process info panel
  - r: Restart selected process (with confirmation)
  - k: Terminate selected process (with confirmation)
  - R: Refresh tree
  - /: Filter by name
  - Escape: Clear filter/close panel

  ## Monochrome Compatibility

  This widget is fully functional in monochrome terminals:
  - Process status indicated by both color AND text markers:
    - `[R]` for running processes
    - `[Y]` for restarting processes
    - `[T]` for terminated processes
    - `[U]` for undefined status
  - Selected items use reverse video for visibility
  - Error states (terminated) use underline for emphasis
  - All critical information remains accessible without color

  The widget uses both theme component styles and explicit text indicators
  for complete monochrome compatibility.

  The `:update_interval` option is stored as refresh metadata but does not start
  a timer. In an Elm root, schedule `Command.interval/2` yourself and call
  `refresh/1` for each message. `TermUI.Runtime` does not invoke this widget's
  `handle_info/2` callback automatically.
  """

  use TermUI.StatefulComponent

  alias TermUI.CharacterSet
  alias TermUI.Event
  alias TermUI.Renderer.Style
  alias TermUI.Theme

  # Dialyzer: Suppress opaque type warnings for Style helpers and contract warnings for specific map types
  @dialyzer {:nowarn_function,
             fg_semantic: 1,
             fg_bold_semantic: 1,
             fg_dim_semantic: 1,
             fg_bold_help: 0,
             collect_supervisor_ids: 1,
             collect_children_supervisor_ids: 1,
             new: 1,
             refresh: 1,
             set_root: 2,
             expand_all: 1,
             collapse_all: 1,
             flatten_tree: 3}

  @type node_type :: :supervisor | :worker
  @type node_status :: :running | :restarting | :terminated | :undefined

  @type sup_node :: %{
          id: term(),
          pid: pid() | :restarting | :undefined,
          name: atom() | nil,
          type: node_type(),
          status: node_status(),
          child_spec: map() | nil,
          strategy: atom() | nil,
          restart_count: non_neg_integer(),
          max_restarts: non_neg_integer() | nil,
          max_seconds: non_neg_integer() | nil,
          children: [sup_node()] | nil,
          memory: non_neg_integer(),
          reductions: non_neg_integer(),
          message_queue_len: non_neg_integer(),
          depth: non_neg_integer(),
          parent_pid: pid() | nil
        }

  @default_interval 2000
  @page_size 15

  # ASCII-friendly icons for universal compatibility
  defp get_status_icons do
    %{
      running: "o",
      restarting: "~",
      terminated: "x",
      undefined: "?"
    }
  end

  @status_text %{
    running: "[R]",
    restarting: "[Y]",
    terminated: "[T]",
    undefined: "[U]"
  }

  # ----------------------------------------------------------------------------
  # Style Helper Functions
  # ----------------------------------------------------------------------------

  @spec fg_semantic(atom()) :: Style.t()
  defp fg_semantic(color) when is_atom(color),
    do: Style.new() |> Style.fg(color)

  @spec fg_bold_semantic(atom()) :: Style.t()
  defp fg_bold_semantic(color) when is_atom(color),
    do: Style.new() |> Style.fg(color) |> Style.bold()

  @spec fg_dim_semantic(atom()) :: Style.t()
  defp fg_dim_semantic(color) when is_atom(color),
    do: Style.new() |> Style.fg(color) |> Style.dim()

  @spec fg_bold_help() :: Style.t()
  defp fg_bold_help do
    Style.new() |> Style.fg(Theme.get_semantic(:help)) |> Style.dim()
  end

  # ----------------------------------------------------------------------------
  # Icon Functions
  # ----------------------------------------------------------------------------

  defp get_type_icons do
    %{
      supervisor: "S",
      worker: "W"
    }
  end

  defp get_strategy_display do
    chars = CharacterSet.current_charset()

    %{
      one_for_one: "1:1",
      one_for_all: "1:*",
      rest_for_one: "1:#{chars.arrow_right}",
      simple_one_for_one: "1:1+"
    }
  end

  # ----------------------------------------------------------------------------
  # Props
  # ----------------------------------------------------------------------------

  @doc """
  Creates new SupervisionTreeViewer widget props.

  ## Options

  - `:root` - Root supervisor (pid, registered name, or module) - required
  - `:update_interval` - Refresh interval metadata in ms (default: 2000); no
    timer is started by the widget
  - `:on_select` - Callback when node is selected: `fn node -> ... end`
  - `:on_action` - Callback when action is performed: `fn {:restarted | :terminated, pid} -> ... end`
  - `:show_workers` - Show worker processes (default: true)
  - `:auto_expand` - Expand all nodes initially (default: true)
  """
  @spec new(keyword()) :: map()
  def new(opts) do
    root = Keyword.fetch!(opts, :root)

    %{
      root: root,
      update_interval: Keyword.get(opts, :update_interval, @default_interval),
      on_select: Keyword.get(opts, :on_select),
      on_action: Keyword.get(opts, :on_action),
      show_workers: Keyword.get(opts, :show_workers, true),
      auto_expand: Keyword.get(opts, :auto_expand, true)
    }
  end

  # ----------------------------------------------------------------------------
  # State Initialization
  # ----------------------------------------------------------------------------

  @doc """
  Initializes the SupervisionTreeViewer state.
  """
  @impl true
  def init(props) do
    root_pid = resolve_supervisor(props.root)
    tree = build_tree(root_pid, nil, 0, props.show_workers)

    expanded =
      if props.auto_expand do
        collect_supervisor_ids(tree)
      else
        MapSet.new()
      end

    flattened = flatten_tree(tree, expanded, true)

    state = %{
      root: props.root,
      root_pid: root_pid,
      tree: tree,
      flattened: flattened,
      expanded: expanded,
      selected_idx: 0,
      scroll_offset: 0,
      update_interval: props.update_interval,
      on_select: props.on_select,
      on_action: props.on_action,
      show_workers: props.show_workers,
      show_info: false,
      pending_action: nil,
      filter: nil,
      filter_input: nil
    }

    {:ok, state}
  end

  # ----------------------------------------------------------------------------
  # Event Handling
  # ----------------------------------------------------------------------------

  @impl true
  def handle_event(%Event.Key{key: key}, state) when key in [:up, :down] do
    max_idx = max(0, length(state.flattened) - 1)

    new_idx =
      case key do
        :up -> max(0, state.selected_idx - 1)
        :down -> min(max_idx, state.selected_idx + 1)
      end

    state = %{state | selected_idx: new_idx}
    state = maybe_call_on_select(state)
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :page_up}, state) do
    new_idx = max(0, state.selected_idx - @page_size)
    state = %{state | selected_idx: new_idx}
    state = maybe_call_on_select(state)
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :page_down}, state) do
    max_idx = max(0, length(state.flattened) - 1)
    new_idx = min(max_idx, state.selected_idx + @page_size)
    state = %{state | selected_idx: new_idx}
    state = maybe_call_on_select(state)
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :home}, state) do
    state = %{state | selected_idx: 0}
    state = maybe_call_on_select(state)
    {:ok, state}
  end

  def handle_event(%Event.Key{key: :end}, state) do
    max_idx = max(0, length(state.flattened) - 1)
    state = %{state | selected_idx: max_idx}
    state = maybe_call_on_select(state)
    {:ok, state}
  end

  # Left - collapse or move to parent
  def handle_event(%Event.Key{key: :left}, state) do
    case get_selected(state) do
      nil -> {:ok, state}
      node -> handle_left_key(node, state)
    end
  end

  # Right - expand or move to first child
  def handle_event(%Event.Key{key: :right}, state) do
    case get_selected(state) do
      nil -> {:ok, state}
      node -> handle_right_key(node, state)
    end
  end

  # Enter - toggle expand/collapse
  def handle_event(%Event.Key{key: :enter}, state) when state.filter_input != nil do
    # Apply filter
    filter = if state.filter_input == "", do: nil, else: state.filter_input
    flattened = flatten_tree(state.tree, state.expanded, true)

    flattened =
      if filter do
        Enum.filter(flattened, fn node ->
          name_str = node_display_name(node)
          String.contains?(String.downcase(name_str), String.downcase(filter))
        end)
      else
        flattened
      end

    {:ok, %{state | filter: filter, filter_input: nil, flattened: flattened, selected_idx: 0}}
  end

  def handle_event(%Event.Key{key: :enter}, state) do
    case get_selected(state) do
      nil ->
        {:ok, state}

      node ->
        if node.type == :supervisor do
          expanded =
            if MapSet.member?(state.expanded, node.id) do
              MapSet.delete(state.expanded, node.id)
            else
              MapSet.put(state.expanded, node.id)
            end

          flattened = flatten_tree(state.tree, expanded, true)
          {:ok, %{state | expanded: expanded, flattened: flattened}}
        else
          # Toggle info panel for workers
          {:ok, %{state | show_info: not state.show_info}}
        end
    end
  end

  # i - show info panel
  def handle_event(%Event.Key{char: "i"}, state) do
    {:ok, %{state | show_info: not state.show_info}}
  end

  # R - force refresh
  def handle_event(%Event.Key{char: "R"}, state) do
    refresh(state)
  end

  # r - restart process (with confirmation)
  def handle_event(%Event.Key{char: "r"}, state)
      when state.pending_action == nil and state.filter_input == nil do
    case get_selected(state) do
      nil -> {:ok, state}
      _node -> {:ok, %{state | pending_action: :restart}}
    end
  end

  # k - terminate process (with confirmation)
  def handle_event(%Event.Key{char: "k"}, state)
      when state.pending_action == nil and state.filter_input == nil do
    case get_selected(state) do
      nil -> {:ok, state}
      _node -> {:ok, %{state | pending_action: :terminate}}
    end
  end

  # y - confirm action
  def handle_event(%Event.Key{char: "y"}, state) when state.pending_action != nil do
    case get_selected(state) do
      nil ->
        {:ok, %{state | pending_action: nil}}

      node ->
        result = execute_action(state.pending_action, node)

        if state.on_action do
          state.on_action.(result)
        end

        # Refresh after action
        {:ok, state} = refresh(%{state | pending_action: nil})
        {:ok, state}
    end
  end

  # n - cancel action
  def handle_event(%Event.Key{char: "n"}, state) when state.pending_action != nil do
    {:ok, %{state | pending_action: nil}}
  end

  # / - start filter input
  def handle_event(%Event.Key{char: "/"}, state) when state.filter_input == nil do
    {:ok, %{state | filter_input: ""}}
  end

  # Filter input handling
  def handle_event(%Event.Key{char: char}, state)
      when state.filter_input != nil and char != nil do
    {:ok, %{state | filter_input: state.filter_input <> char}}
  end

  def handle_event(%Event.Key{key: :backspace}, state) when state.filter_input != nil do
    new_input =
      if String.length(state.filter_input) > 0 do
        String.slice(state.filter_input, 0..-2//1)
      else
        state.filter_input
      end

    {:ok, %{state | filter_input: new_input}}
  end

  # Escape - close panel, clear filter, cancel action
  def handle_event(%Event.Key{key: :escape}, state) do
    cond do
      state.pending_action != nil ->
        {:ok, %{state | pending_action: nil}}

      state.filter_input != nil ->
        {:ok, %{state | filter_input: nil}}

      state.show_info ->
        {:ok, %{state | show_info: false}}

      state.filter != nil ->
        flattened = flatten_tree(state.tree, state.expanded, true)
        {:ok, %{state | filter: nil, flattened: flattened, selected_idx: 0}}

      true ->
        {:ok, state}
    end
  end

  def handle_event(_event, state) do
    {:ok, state}
  end

  # ----------------------------------------------------------------------------
  # Private Helpers for Event Handling
  # ----------------------------------------------------------------------------

  defp handle_left_key(%{type: :supervisor, id: id}, state) do
    if MapSet.member?(state.expanded, id) do
      collapse_node(id, state)
    else
      move_to_parent(state)
    end
  end

  defp handle_left_key(_node, state), do: move_to_parent(state)

  defp collapse_node(node_id, state) do
    expanded = MapSet.delete(state.expanded, node_id)
    flattened = flatten_tree(state.tree, expanded, true)
    {:ok, %{state | expanded: expanded, flattened: flattened}}
  end

  defp move_to_parent(state) do
    parent_idx = find_parent_idx(state.flattened, state.selected_idx)

    if parent_idx do
      {:ok, %{state | selected_idx: parent_idx}}
    else
      {:ok, state}
    end
  end

  defp handle_right_key(%{type: :supervisor, id: id}, state) do
    if MapSet.member?(state.expanded, id) do
      move_to_first_child(state)
    else
      expand_node(id, state)
    end
  end

  defp handle_right_key(_node, state), do: {:ok, state}

  defp move_to_first_child(state) do
    child_idx = state.selected_idx + 1

    if child_idx < length(state.flattened) do
      {:ok, %{state | selected_idx: child_idx}}
    else
      {:ok, state}
    end
  end

  defp expand_node(node_id, state) do
    expanded = MapSet.put(state.expanded, node_id)
    flattened = flatten_tree(state.tree, expanded, true)
    {:ok, %{state | expanded: expanded, flattened: flattened}}
  end

  # ----------------------------------------------------------------------------
  # Handle Info (Timer)
  # ----------------------------------------------------------------------------

  @impl true
  def handle_info(:refresh, state) do
    refresh(state)
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  # ----------------------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------------------

  @doc """
  Forces a refresh of the supervision tree.
  """
  @spec refresh(map()) :: {:ok, map()}
  def refresh(state) do
    root_pid = resolve_supervisor(state.root)
    tree = build_tree(root_pid, nil, 0, state.show_workers)
    flattened = flatten_tree(tree, state.expanded, true)

    # Apply filter if active
    flattened =
      if state.filter do
        Enum.filter(flattened, fn node ->
          name_str = node_display_name(node)
          String.contains?(String.downcase(name_str), String.downcase(state.filter))
        end)
      else
        flattened
      end

    # Adjust selected_idx if out of bounds
    max_idx = max(0, length(flattened) - 1)
    selected_idx = min(state.selected_idx, max_idx)

    {:ok,
     %{state | root_pid: root_pid, tree: tree, flattened: flattened, selected_idx: selected_idx}}
  end

  @doc """
  Sets the root supervisor.
  """
  @spec set_root(map(), term()) :: {:ok, map()}
  def set_root(state, root) do
    state = %{state | root: root, expanded: MapSet.new(), selected_idx: 0}
    refresh(state)
  end

  @doc """
  Gets the currently selected node.
  """
  @spec get_selected(map()) :: sup_node() | nil
  def get_selected(state) do
    Enum.at(state.flattened, state.selected_idx)
  end

  @doc """
  Expands all supervisor nodes.
  """
  @spec expand_all(map()) :: {:ok, map()}
  def expand_all(state) do
    expanded = collect_supervisor_ids(state.tree)
    flattened = flatten_tree(state.tree, expanded, true)
    {:ok, %{state | expanded: expanded, flattened: flattened}}
  end

  @doc """
  Collapses all nodes.
  """
  @spec collapse_all(map()) :: {:ok, map()}
  def collapse_all(state) do
    expanded = MapSet.new()
    flattened = flatten_tree(state.tree, expanded, true)
    {:ok, %{state | expanded: expanded, flattened: flattened}}
  end

  @doc """
  Gets the process state for the selected node.
  """
  @spec get_process_state(map()) :: {:ok, term()} | {:error, term()}
  def get_process_state(state) do
    case get_selected(state) do
      nil ->
        {:error, :no_selection}

      node ->
        if is_pid(node.pid) and Process.alive?(node.pid) do
          try do
            {:ok, :sys.get_state(node.pid, 1000)}
          catch
            :exit, reason -> {:error, reason}
          end
        else
          {:error, :not_alive}
        end
    end
  end

  # ----------------------------------------------------------------------------
  # Tree Building
  # ----------------------------------------------------------------------------

  defp resolve_supervisor(sup) when is_pid(sup), do: sup
  defp resolve_supervisor(sup) when is_atom(sup), do: Process.whereis(sup)

  defp resolve_supervisor({:via, _, _} = sup) do
    GenServer.whereis(sup)
  end

  defp resolve_supervisor({:global, name}) do
    :global.whereis_name(name)
  end

  defp build_tree(nil, _parent_pid, _depth, _show_workers), do: nil

  defp build_tree(sup_pid, parent_pid, depth, show_workers) do
    children =
      try do
        Supervisor.which_children(sup_pid)
      catch
        :exit, _ -> []
      end

    # Get supervisor info
    {strategy, max_restarts, max_seconds} = get_supervisor_flags(sup_pid)
    process_info = get_process_info(sup_pid)

    child_nodes =
      children
      |> Enum.map(fn {id, child_pid, type, _modules} ->
        build_child_node(%{
          id: id,
          child_pid: child_pid,
          type: type,
          parent_pid: sup_pid,
          depth: depth + 1,
          show_workers: show_workers
        })
      end)
      |> Enum.reject(&is_nil/1)

    %{
      id: sup_pid,
      pid: sup_pid,
      name: get_registered_name(sup_pid),
      type: :supervisor,
      status: :running,
      child_spec: nil,
      strategy: strategy,
      restart_count: 0,
      max_restarts: max_restarts,
      max_seconds: max_seconds,
      children: child_nodes,
      memory: process_info[:memory] || 0,
      reductions: process_info[:reductions] || 0,
      message_queue_len: Keyword.get(process_info, :message_queue_len, 0),
      depth: depth,
      parent_pid: parent_pid
    }
  end

  defp build_child_node(params) do
    %{
      id: id,
      child_pid: child_pid,
      type: type,
      parent_pid: parent_pid,
      depth: depth,
      show_workers: show_workers
    } = params

    case {type, child_pid} do
      {:supervisor, pid} when is_pid(pid) ->
        build_tree(pid, parent_pid, depth, show_workers)

      {:supervisor, :restarting} ->
        build_status_node(id, :restarting, :supervisor, depth, parent_pid)

      {:supervisor, :undefined} ->
        build_status_node(id, :undefined, :supervisor, depth, parent_pid)

      {:worker, pid} when is_pid(pid) ->
        maybe_build_worker_node(id, pid, depth, parent_pid, show_workers)

      {:worker, :restarting} ->
        maybe_build_status_worker(id, :restarting, depth, parent_pid, show_workers)

      {:worker, :undefined} ->
        maybe_build_status_worker(id, :undefined, depth, parent_pid, show_workers)
    end
  end

  # Builds a node with a specific status (restarting or undefined).
  defp build_status_node(id, status, type, depth, parent_pid) do
    %{
      id: id,
      pid: status,
      name: nil,
      type: type,
      status: status,
      child_spec: nil,
      strategy: nil,
      restart_count: 0,
      max_restarts: nil,
      max_seconds: nil,
      children: nil,
      memory: 0,
      reductions: 0,
      message_queue_len: 0,
      depth: depth,
      parent_pid: parent_pid
    }
  end

  # Builds a worker node with process info if show_workers is true.
  defp maybe_build_worker_node(id, pid, depth, parent_pid, true) do
    process_info = get_process_info(pid)

    %{
      id: id,
      pid: pid,
      name: get_registered_name(pid),
      type: :worker,
      status: :running,
      child_spec: nil,
      strategy: nil,
      restart_count: 0,
      max_restarts: nil,
      max_seconds: nil,
      children: nil,
      memory: process_info[:memory] || 0,
      reductions: process_info[:reductions] || 0,
      message_queue_len: Keyword.get(process_info, :message_queue_len, 0),
      depth: depth,
      parent_pid: parent_pid
    }
  end

  defp maybe_build_worker_node(_id, _pid, _depth, _parent_pid, false), do: nil

  # Builds a worker node with a specific status if show_workers is true.
  defp maybe_build_status_worker(id, status, depth, parent_pid, true) do
    %{
      id: id,
      pid: status,
      name: nil,
      type: :worker,
      status: status,
      child_spec: nil,
      strategy: nil,
      restart_count: 0,
      max_restarts: nil,
      max_seconds: nil,
      children: nil,
      memory: 0,
      reductions: 0,
      message_queue_len: 0,
      depth: depth,
      parent_pid: parent_pid
    }
  end

  defp maybe_build_status_worker(_id, _status, _depth, _parent_pid, false), do: nil

  defp get_supervisor_flags(sup_pid) do
    # Try to get supervisor init args
    case :sys.get_state(sup_pid, 500) do
      %{strategy: strategy, intensity: intensity, period: period} ->
        {strategy, intensity, period}

      # For older supervisor state format
      state when is_tuple(state) ->
        # Try to extract from supervisor internal state
        {:one_for_one, nil, nil}

      _ ->
        {:one_for_one, nil, nil}
    end
  catch
    :exit, _ -> {:one_for_one, nil, nil}
  end

  defp get_process_info(pid) when is_pid(pid) do
    case Process.info(pid, [:memory, :reductions, :message_queue_len, :registered_name]) do
      nil -> []
      info -> info
    end
  end

  defp get_process_info(_), do: []

  defp get_registered_name(pid) when is_pid(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, name} -> name
      _ -> nil
    end
  end

  defp get_registered_name(_), do: nil

  # ----------------------------------------------------------------------------
  # Tree Flattening
  # ----------------------------------------------------------------------------

  defp flatten_tree(nil, _expanded, _visible), do: []

  defp flatten_tree(node, expanded, visible) do
    if visible do
      children_visible = MapSet.member?(expanded, node.id) and node.children != nil

      children_nodes =
        if children_visible and node.children do
          Enum.flat_map(node.children, &flatten_tree(&1, expanded, true))
        else
          []
        end

      [node | children_nodes]
    else
      []
    end
  end

  @spec collect_supervisor_ids(term() | nil) :: MapSet.t()
  defp collect_supervisor_ids(nil), do: MapSet.new()

  @spec collect_supervisor_ids(term()) :: MapSet.t()
  defp collect_supervisor_ids(node) do
    if node.type == :supervisor do
      children_ids = collect_children_supervisor_ids(node.children)
      MapSet.put(children_ids, node.id)
    else
      MapSet.new()
    end
  end

  defp collect_children_supervisor_ids(children) when is_list(children) do
    Enum.reduce(children, MapSet.new(), fn child, acc ->
      MapSet.union(acc, collect_supervisor_ids(child))
    end)
  end

  defp collect_children_supervisor_ids(_), do: MapSet.new()

  defp find_parent_idx(flattened, current_idx) do
    case Enum.at(flattened, current_idx) do
      nil -> nil
      current -> find_shallower_node_idx(flattened, current.depth, current_idx)
    end
  end

  defp find_shallower_node_idx(flattened, current_depth, current_idx) do
    flattened
    |> Enum.take(current_idx)
    |> Enum.with_index()
    |> Enum.reverse()
    |> Enum.find_value(fn {node, idx} ->
      if node.depth < current_depth, do: idx, else: nil
    end)
  end

  # ----------------------------------------------------------------------------
  # Actions
  # ----------------------------------------------------------------------------

  defp execute_action(:restart, node) do
    case {node.parent_pid, node.id} do
      {nil, _} ->
        {:error, :no_parent}

      {parent_pid, child_id} ->
        try do
          case Supervisor.restart_child(parent_pid, child_id) do
            {:ok, _pid} -> {:restarted, node.pid}
            {:ok, _pid, _info} -> {:restarted, node.pid}
            {:error, reason} -> {:error, reason}
          end
        catch
          :exit, reason -> {:error, reason}
        end
    end
  end

  defp execute_action(:terminate, node) do
    case {node.parent_pid, node.id} do
      {nil, _} ->
        {:error, :no_parent}

      {parent_pid, child_id} ->
        try do
          case Supervisor.terminate_child(parent_pid, child_id) do
            :ok -> {:terminated, node.pid}
            {:error, reason} -> {:error, reason}
          end
        catch
          :exit, reason -> {:error, reason}
        end
    end
  end

  # ----------------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------------

  defp status_style(status) do
    case status do
      :running -> Theme.get_component_style(:status, :running)
      :restarting -> Theme.get_component_style(:status, :warning)
      :terminated -> Theme.get_component_style(:status, :error)
      :undefined -> Theme.get_component_style(:status, :unknown)
      _ -> Theme.get_component_style(:status, :unknown)
    end
  end

  defp status_indicator(status, status_icons) do
    icon = Map.get(status_icons, status, "?")
    text = Map.get(@status_text, status, "[?]")
    "#{icon} #{text}"
  end

  defp maybe_call_on_select(state) do
    if state.on_select do
      case get_selected(state) do
        nil -> state
        node -> state.on_select.(node)
      end
    end

    state
  end

  defp node_display_name(node) do
    cond do
      node.name != nil ->
        inspect(node.name)

      is_pid(node.pid) ->
        inspect(node.pid)

      true ->
        inspect(node.id)
    end
  end

  # ----------------------------------------------------------------------------
  # Rendering
  # ----------------------------------------------------------------------------

  @impl true
  def render(state, area) do
    # Get character set for indicators
    chars = CharacterSet.current_charset()
    status_icons = get_status_icons()
    type_icons = get_type_icons()
    strategy_display = get_strategy_display()

    header = render_header(state)
    tree_view = render_tree_view(state, area, chars, status_icons, type_icons, strategy_display)
    filter_line = render_filter_line(state)
    info_panel = render_info_panel(state, chars)
    confirmation = render_confirmation(state)
    footer = render_footer(state, chars)

    children =
      [header, tree_view, filter_line, info_panel, confirmation, footer]
      |> Enum.reject(&is_nil/1)

    stack(:vertical, children)
  end

  defp render_header(state) do
    root_name =
      if state.tree do
        node_display_name(state.tree)
      else
        "No supervisor"
      end

    count = length(state.flattened)

    style = fg_bold_semantic(Theme.get_semantic(:info))

    text(
      "Supervision Tree: #{root_name} | Nodes: #{count}",
      style
    )
  end

  defp render_tree_view(state, area, chars, status_icons, type_icons, strategy_display) do
    visible_height = min(area.height - 4, length(state.flattened))

    # Calculate scroll offset to keep selected in view
    scroll_offset =
      cond do
        state.selected_idx < state.scroll_offset ->
          state.selected_idx

        state.selected_idx >= state.scroll_offset + visible_height ->
          state.selected_idx - visible_height + 1

        true ->
          state.scroll_offset
      end

    visible_nodes =
      state.flattened
      |> Enum.drop(scroll_offset)
      |> Enum.take(visible_height)
      |> Enum.with_index(scroll_offset)

    if Enum.empty?(visible_nodes) do
      muted_color = Theme.get_semantic(:muted)
      style = fg_dim_semantic(muted_color)
      text("  No processes found", style)
    else
      lines =
        Enum.map(visible_nodes, fn {node, idx} ->
          render_node_line(
            node,
            idx == state.selected_idx,
            state.expanded,
            chars,
            status_icons,
            type_icons,
            strategy_display
          )
        end)

      stack(:vertical, lines)
    end
  end

  defp render_node_line(
         node,
         selected,
         expanded,
         chars,
         status_icons,
         type_icons,
         strategy_display
       ) do
    indent = String.duplicate("  ", node.depth)
    expand_indicator = expand_indicator(node, expanded, chars)
    status_ind = status_indicator(node.status, status_icons)
    type_icon = Map.get(type_icons, node.type, " ")
    name = node_display_name(node)
    strategy_str = strategy_string(node, strategy_display)
    memory_str = memory_string(node)

    content = "#{indent}#{expand_indicator}#{type_icon} #{name}#{strategy_str}#{memory_str}"
    full_content = "#{status_ind} #{content}"

    style = node_line_style(selected, node.status)
    text(full_content, style)
  end

  defp expand_indicator(node, expanded, chars) do
    case {node.type, node.children} do
      {:supervisor, children} when is_list(children) and children != [] ->
        if MapSet.member?(expanded, node.id),
          do: "#{chars.arrow_down} ",
          else: "#{chars.arrow_right} "

      {:supervisor, _} ->
        "#{chars.arrow_right} "

      _ ->
        "  "
    end
  end

  defp strategy_string(%{type: :supervisor, strategy: strategy}, strategy_display)
       when is_binary(strategy) do
    " [#{Map.get(strategy_display, strategy, "?")}]"
  end

  defp strategy_string(_, _), do: ""

  defp memory_string(%{memory: memory}) when memory > 0, do: " #{format_bytes(memory)}"
  defp memory_string(_), do: ""

  defp node_line_style(true, _status), do: Theme.get_component_style(:item, :selected)
  defp node_line_style(false, status), do: status_style(status)

  defp render_filter_line(state) do
    cond do
      state.filter_input != nil ->
        style = fg_semantic(Theme.get_semantic(:warning))
        text("Filter: #{state.filter_input}_", style)

      state.filter != nil ->
        style = fg_dim_semantic(Theme.get_semantic(:warning))
        text("Filter: #{state.filter} (Esc to clear)", style)

      true ->
        nil
    end
  end

  defp render_info_panel(state, chars) do
    if state.show_info do
      case get_selected(state) do
        nil ->
          nil

        node ->
          info_style = fg_semantic(Theme.get_semantic(:info))

          lines = [
            text(
              "#{String.duplicate(chars.h_line, 3)} Process Info #{String.duplicate(chars.h_line, 3)}",
              info_style
            ),
            text("  ID: #{inspect(node.id)}", nil),
            text("  PID: #{inspect(node.pid)}", nil),
            text("  Name: #{inspect(node.name)}", nil),
            text("  Type: #{node.type}", nil),
            text(
              "  Status: #{node.status}",
              status_style(node.status)
            )
          ]

          lines = add_supervisor_info(lines, node)
          lines = add_node_metrics(lines, node)

          stack(:vertical, lines)
      end
    else
      nil
    end
  end

  defp add_supervisor_info(lines, %{type: :supervisor} = node) do
    lines ++
      [
        text("  Strategy: #{node.strategy || "unknown"}", nil),
        text(
          "  Max restarts: #{node.max_restarts || "?"}/#{node.max_seconds || "?"}s",
          nil
        )
      ]
  end

  defp add_supervisor_info(lines, _node), do: lines

  defp add_node_metrics(lines, node) do
    lines ++
      [
        text("  Memory: #{format_bytes(node.memory)}", nil),
        text("  Reductions: #{format_number(node.reductions)}", nil),
        text("  Msg Queue: #{node.message_queue_len}", nil)
      ]
  end

  defp render_confirmation(state) do
    case state.pending_action do
      nil ->
        nil

      :restart ->
        node = get_selected(state)
        name = if node, do: node_display_name(node), else: "?"
        style = fg_bold_semantic(Theme.get_semantic(:warning))
        text("Restart #{name}? [y/n]", style)

      :terminate ->
        node = get_selected(state)
        name = if node, do: node_display_name(node), else: "?"
        style = fg_bold_semantic(Theme.get_semantic(:error))
        text("Terminate #{name}? [y/n]", style)
    end
  end

  defp render_footer(_state, chars) do
    style = fg_bold_help()

    text(
      "[#{chars.arrow_up}#{chars.arrow_down}] Navigate [#{chars.arrow_left}#{chars.arrow_right}] Expand/Collapse [i] Info [r] Restart [k] Kill [R] Refresh [/] Filter",
      style
    )
  end

  # ----------------------------------------------------------------------------
  # Formatting Helpers
  # ----------------------------------------------------------------------------

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)}KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)}MB"

  defp format_number(n) when n < 1000, do: "#{n}"
  defp format_number(n) when n < 1_000_000, do: "#{Float.round(n / 1000, 1)}K"
  defp format_number(n), do: "#{Float.round(n / 1_000_000, 1)}M"
end
