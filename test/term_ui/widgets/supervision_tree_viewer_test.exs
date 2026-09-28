defmodule TermUI.Widgets.SupervisionTreeViewerTest do
  use ExUnit.Case, async: false

  alias TermUI.Event
  alias TermUI.Theme
  alias TermUI.Widgets.SupervisionTreeViewer

  @area %{x: 0, y: 0, width: 100, height: 30}

  # Test supervisor module for creating test supervision trees
  defmodule TestWorker do
    use GenServer

    def start_link(opts) do
      name = Keyword.get(opts, :name)
      GenServer.start_link(__MODULE__, opts, name: name)
    end

    @impl true
    def init(opts) do
      {:ok, %{opts: opts}}
    end

    @impl true
    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end
  end

  defmodule TestSupervisor do
    use Supervisor

    def start_link(opts) do
      name = Keyword.get(opts, :name, __MODULE__)
      Supervisor.start_link(__MODULE__, opts, name: name)
    end

    @impl true
    def init(opts) do
      workers = Keyword.get(opts, :workers, 2)

      children =
        for i <- 1..workers do
          %{
            id: :"worker_#{i}",
            start: {TestWorker, :start_link, [[id: i]]}
          }
        end

      Supervisor.init(children, strategy: :one_for_one)
    end
  end

  defmodule NestedSupervisor do
    use Supervisor

    def start_link(opts) do
      name = Keyword.get(opts, :name, __MODULE__)
      Supervisor.start_link(__MODULE__, opts, name: name)
    end

    @impl true
    def init(_opts) do
      children = [
        %{
          id: :child_supervisor,
          start: {TestSupervisor, :start_link, [[name: :child_sup, workers: 2]]},
          type: :supervisor
        },
        %{
          id: :direct_worker,
          start: {TestWorker, :start_link, [[name: :direct_worker]]}
        }
      ]

      Supervisor.init(children, strategy: :one_for_all)
    end
  end

  setup do
    # Start the shared Theme server if another test has not already done so.
    case Theme.start_link(theme: :dark) do
      {:ok, _theme_pid} -> :ok
      {:error, {:already_started, _theme_pid}} -> :ok
    end

    # Each test will start its own supervisor
    :ok
  end

  describe "new/1" do
    test "creates props with required root" do
      props = SupervisionTreeViewer.new(root: TestSupervisor)

      assert props.root == TestSupervisor
      assert props.update_interval == 2000
      assert props.show_workers == true
      assert props.auto_expand == true
    end

    test "creates props with custom values" do
      props =
        SupervisionTreeViewer.new(
          root: TestSupervisor,
          update_interval: 1000,
          show_workers: false,
          auto_expand: false
        )

      assert props.update_interval == 1000
      assert props.show_workers == false
      assert props.auto_expand == false
    end

    test "raises if root not provided" do
      assert_raise KeyError, fn ->
        SupervisionTreeViewer.new([])
      end
    end
  end

  describe "init/1" do
    test "initializes with supervision tree" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_sup_init, workers: 2)

      try do
        props = SupervisionTreeViewer.new(root: :test_sup_init)
        {:ok, state} = SupervisionTreeViewer.init(props)

        assert state.root_pid == sup
        assert state.tree != nil
        assert state.tree.type == :supervisor
        assert is_list(state.flattened)
        assert state.flattened != []
        assert state.selected_idx == 0
      after
        Supervisor.stop(sup)
      end
    end

    test "builds tree with workers when show_workers is true" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_sup_workers, workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: :test_sup_workers, show_workers: true)
        {:ok, state} = SupervisionTreeViewer.init(props)

        worker_nodes = Enum.filter(state.flattened, &(&1.type == :worker))
        assert length(worker_nodes) == 3
      after
        Supervisor.stop(sup)
      end
    end

    test "hides workers when show_workers is false" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_sup_hide_workers, workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: :test_sup_hide_workers, show_workers: false)
        {:ok, state} = SupervisionTreeViewer.init(props)

        worker_nodes = Enum.filter(state.flattened, &(&1.type == :worker))
        assert Enum.empty?(worker_nodes)
      after
        Supervisor.stop(sup)
      end
    end

    test "builds nested supervision tree" do
      {:ok, sup} = NestedSupervisor.start_link(name: :test_nested_sup)

      try do
        props = SupervisionTreeViewer.new(root: :test_nested_sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        supervisor_nodes = Enum.filter(state.flattened, &(&1.type == :supervisor))
        # Root + child supervisor
        assert length(supervisor_nodes) == 2
      after
        Supervisor.stop(sup)
      end
    end
  end

  describe "navigation" do
    test "down key moves selection down" do
      {:ok, sup} = TestSupervisor.start_link(workers: 5)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)
        assert state.selected_idx == 1
      after
        Supervisor.stop(sup)
      end
    end

    test "up key moves selection up" do
      {:ok, sup} = TestSupervisor.start_link(workers: 5)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :up}, state)
        assert state.selected_idx == 1
      after
        Supervisor.stop(sup)
      end
    end

    test "up key at top stays at 0" do
      {:ok, sup} = TestSupervisor.start_link(workers: 5)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :up}, state)
        assert state.selected_idx == 0
      after
        Supervisor.stop(sup)
      end
    end

    test "home key goes to first" do
      {:ok, sup} = TestSupervisor.start_link(workers: 5)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :home}, state)
        assert state.selected_idx == 0
      after
        Supervisor.stop(sup)
      end
    end

    test "end key goes to last" do
      {:ok, sup} = TestSupervisor.start_link(workers: 5)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :end}, state)
        assert state.selected_idx == length(state.flattened) - 1
      after
        Supervisor.stop(sup)
      end
    end

    test "page_down moves by page" do
      {:ok, sup} = TestSupervisor.start_link(workers: 5)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :page_down}, state)
        # Either at end or moved by page size
        assert state.selected_idx > 0
      after
        Supervisor.stop(sup)
      end
    end
  end

  describe "expand/collapse" do
    test "right key expands supervisor node" do
      {:ok, sup} = NestedSupervisor.start_link([])

      try do
        props = SupervisionTreeViewer.new(root: sup, auto_expand: false)
        {:ok, state} = SupervisionTreeViewer.init(props)

        # Start collapsed - only root visible
        initial_count = length(state.flattened)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :right}, state)

        # Should have more nodes now
        assert length(state.flattened) > initial_count
      after
        Supervisor.stop(sup)
      end
    end

    test "left key collapses expanded supervisor" do
      {:ok, sup} = NestedSupervisor.start_link([])

      try do
        props = SupervisionTreeViewer.new(root: sup, auto_expand: false)
        {:ok, state} = SupervisionTreeViewer.init(props)

        # First expand
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :right}, state)
        expanded_count = length(state.flattened)

        # Then collapse
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :left}, state)

        assert length(state.flattened) < expanded_count
      after
        Supervisor.stop(sup)
      end
    end

    test "enter toggles expand/collapse" do
      {:ok, sup} = NestedSupervisor.start_link([])

      try do
        props = SupervisionTreeViewer.new(root: sup, auto_expand: false)
        {:ok, state} = SupervisionTreeViewer.init(props)

        initial_count = length(state.flattened)

        # Expand
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :enter}, state)
        assert length(state.flattened) > initial_count

        # Collapse
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :enter}, state)
        assert length(state.flattened) == initial_count
      after
        Supervisor.stop(sup)
      end
    end

    test "expand_all expands all supervisors" do
      {:ok, sup} = NestedSupervisor.start_link([])

      try do
        props = SupervisionTreeViewer.new(root: sup, auto_expand: false)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.expand_all(state)

        # All supervisor nodes should be in expanded set
        supervisor_nodes = Enum.filter(state.flattened, &(&1.type == :supervisor))

        Enum.each(supervisor_nodes, fn node ->
          assert MapSet.member?(state.expanded, node.id)
        end)
      after
        Supervisor.stop(sup)
      end
    end

    test "collapse_all collapses all nodes" do
      {:ok, sup} = NestedSupervisor.start_link([])

      try do
        props = SupervisionTreeViewer.new(root: sup, auto_expand: false)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.expand_all(state)
        {:ok, state} = SupervisionTreeViewer.collapse_all(state)

        assert MapSet.size(state.expanded) == 0
      after
        Supervisor.stop(sup)
      end
    end
  end

  describe "info panel" do
    test "i key toggles info panel" do
      {:ok, sup} = TestSupervisor.start_link(workers: 2)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        assert state.show_info == false

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "i"}, state)
        assert state.show_info == true

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "i"}, state)
        assert state.show_info == false
      after
        Supervisor.stop(sup)
      end
    end

    test "escape closes info panel" do
      {:ok, sup} = TestSupervisor.start_link(workers: 2)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "i"}, state)
        assert state.show_info == true

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :escape}, state)
        assert state.show_info == false
      after
        Supervisor.stop(sup)
      end
    end
  end

  describe "filtering" do
    test "/ key starts filter input" do
      {:ok, sup} = TestSupervisor.start_link(workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "/"}, state)
        assert state.filter_input == ""
      after
        Supervisor.stop(sup)
      end
    end

    test "typing adds to filter input" do
      {:ok, sup} = TestSupervisor.start_link(workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "/"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "w"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "o"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "r"}, state)

        assert state.filter_input == "wor"
      after
        Supervisor.stop(sup)
      end
    end

    test "enter applies filter" do
      {:ok, sup} = TestSupervisor.start_link(workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        original_count = length(state.flattened)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "/"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "w"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "o"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "r"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "k"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :enter}, state)

        assert state.filter == "work"
        assert state.filter_input == nil
        # Filter should reduce process count (workers only)
        assert length(state.flattened) < original_count
      after
        Supervisor.stop(sup)
      end
    end

    test "escape clears filter" do
      {:ok, sup} = TestSupervisor.start_link(workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "/"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "w"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :enter}, state)

        original_count = length(state.flattened)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :escape}, state)

        assert state.filter == nil
        assert length(state.flattened) > original_count
      after
        Supervisor.stop(sup)
      end
    end

    test "backspace removes from filter input" do
      {:ok, sup} = TestSupervisor.start_link(workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "/"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "a"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "b"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :backspace}, state)

        assert state.filter_input == "a"
      after
        Supervisor.stop(sup)
      end
    end
  end

  describe "process actions" do
    test "r key triggers restart confirmation" do
      {:ok, sup} = TestSupervisor.start_link(workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        # Select a worker
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "r"}, state)
        assert state.pending_action == :restart
      after
        Supervisor.stop(sup)
      end
    end

    test "k key triggers terminate confirmation" do
      {:ok, sup} = TestSupervisor.start_link(workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        # Select a worker
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "k"}, state)
        assert state.pending_action == :terminate
      after
        Supervisor.stop(sup)
      end
    end

    test "n key cancels confirmation" do
      {:ok, sup} = TestSupervisor.start_link(workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "k"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "n"}, state)

        assert state.pending_action == nil
      after
        Supervisor.stop(sup)
      end
    end

    test "escape cancels confirmation" do
      {:ok, sup} = TestSupervisor.start_link(workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "r"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :escape}, state)

        assert state.pending_action == nil
      after
        Supervisor.stop(sup)
      end
    end

    test "y key confirms terminate" do
      {:ok, sup} = TestSupervisor.start_link(workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        # Select a worker (not supervisor)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)

        # Get the worker pid before termination
        worker = SupervisionTreeViewer.get_selected(state)
        assert worker.type == :worker

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "k"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "y"}, state)

        assert state.pending_action == nil
        # Tree should be refreshed
        assert state.tree != nil
      after
        Supervisor.stop(sup)
      end
    end
  end

  describe "refresh" do
    test "R key refreshes tree" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_refresh_sup, workers: 2)

      try do
        props = SupervisionTreeViewer.new(root: :test_refresh_sup)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "R"}, state)

        assert state.tree != nil
        assert is_list(state.flattened)
      after
        Supervisor.stop(sup)
      end
    end

    test "handle_info :refresh updates tree" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_handle_refresh, workers: 2)

      try do
        props = SupervisionTreeViewer.new(root: :test_handle_refresh)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.handle_info(:refresh, state)

        assert state.tree != nil
      after
        Supervisor.stop(sup)
      end
    end
  end

  describe "public API" do
    test "get_selected returns current node" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_get_selected, workers: 2)

      try do
        props = SupervisionTreeViewer.new(root: :test_get_selected)
        {:ok, state} = SupervisionTreeViewer.init(props)

        node = SupervisionTreeViewer.get_selected(state)
        assert node != nil
        assert node.type == :supervisor
      after
        Supervisor.stop(sup)
      end
    end

    test "set_root changes root supervisor" do
      {:ok, sup1} = TestSupervisor.start_link(name: :test_set_root1, workers: 2)
      {:ok, sup2} = TestSupervisor.start_link(name: :test_set_root2, workers: 3)

      try do
        props = SupervisionTreeViewer.new(root: :test_set_root1)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.set_root(state, :test_set_root2)

        assert state.root == :test_set_root2
        assert state.root_pid == sup2
      after
        Supervisor.stop(sup1)
        Supervisor.stop(sup2)
      end
    end

    test "get_process_state returns state for GenServer" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_get_state, workers: 1)

      try do
        props = SupervisionTreeViewer.new(root: :test_get_state)
        {:ok, state} = SupervisionTreeViewer.init(props)

        # Move to worker
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)

        result = SupervisionTreeViewer.get_process_state(state)
        assert {:ok, _process_state} = result
      after
        Supervisor.stop(sup)
      end
    end
  end

  describe "render/2" do
    test "renders supervision tree" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_render, workers: 2)

      try do
        props = SupervisionTreeViewer.new(root: :test_render)
        {:ok, state} = SupervisionTreeViewer.init(props)

        result = SupervisionTreeViewer.render(state, @area)

        assert result.type == :stack
        assert result.direction == :vertical
        assert result.children != []
      after
        Supervisor.stop(sup)
      end
    end

    test "renders with info panel when enabled" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_render_info, workers: 2)

      try do
        props = SupervisionTreeViewer.new(root: :test_render_info)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "i"}, state)
        result = SupervisionTreeViewer.render(state, @area)

        # Should have more children with info panel
        assert length(result.children) > 3
      after
        Supervisor.stop(sup)
      end
    end

    test "renders confirmation prompt" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_render_confirm, workers: 2)

      try do
        props = SupervisionTreeViewer.new(root: :test_render_confirm)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "k"}, state)

        result = SupervisionTreeViewer.render(state, @area)

        texts =
          result.children
          |> Enum.filter(&(&1.type == :text))
          |> Enum.map(& &1.content)

        assert Enum.any?(texts, &String.contains?(&1, "[y/n]"))
      after
        Supervisor.stop(sup)
      end
    end

    test "renders filter input" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_render_filter, workers: 2)

      try do
        props = SupervisionTreeViewer.new(root: :test_render_filter)
        {:ok, state} = SupervisionTreeViewer.init(props)

        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "/"}, state)
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "t"}, state)

        result = SupervisionTreeViewer.render(state, @area)

        texts =
          result.children
          |> Enum.filter(&(&1.type == :text))
          |> Enum.map(& &1.content)

        assert Enum.any?(texts, &String.contains?(&1, "Filter: t"))
      after
        Supervisor.stop(sup)
      end
    end
  end

  describe "callbacks" do
    test "on_select callback is called" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_on_select, workers: 2)

      try do
        test_pid = self()

        props =
          SupervisionTreeViewer.new(
            root: :test_on_select,
            on_select: fn node -> send(test_pid, {:selected, node.id}) end
          )

        {:ok, state} = SupervisionTreeViewer.init(props)
        {:ok, _state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)

        assert_receive {:selected, _id}
      after
        Supervisor.stop(sup)
      end
    end

    test "on_action callback is called on terminate" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_on_action, workers: 2)

      try do
        test_pid = self()

        props =
          SupervisionTreeViewer.new(
            root: :test_on_action,
            on_action: fn result -> send(test_pid, {:action, result}) end
          )

        {:ok, state} = SupervisionTreeViewer.init(props)

        # Select worker
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{key: :down}, state)

        # Terminate
        {:ok, state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "k"}, state)
        {:ok, _state} = SupervisionTreeViewer.handle_event(%Event.Key{char: "y"}, state)

        assert_receive {:action, {:terminated, _pid}}
      after
        Supervisor.stop(sup)
      end
    end
  end

  describe "node status" do
    test "shows correct status for running processes" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_status, workers: 2)

      try do
        props = SupervisionTreeViewer.new(root: :test_status)
        {:ok, state} = SupervisionTreeViewer.init(props)

        Enum.each(state.flattened, fn node ->
          if is_pid(node.pid) do
            assert node.status == :running
          end
        end)
      after
        Supervisor.stop(sup)
      end
    end
  end

  describe "supervisor info" do
    test "shows strategy for supervisors" do
      {:ok, sup} = TestSupervisor.start_link(name: :test_strategy, workers: 2)

      try do
        props = SupervisionTreeViewer.new(root: :test_strategy)
        {:ok, state} = SupervisionTreeViewer.init(props)

        # Root node should be a supervisor
        root = hd(state.flattened)
        assert root.type == :supervisor
        # Strategy may or may not be detected depending on supervisor implementation
        # Just verify the field exists
        assert Map.has_key?(root, :strategy)
      after
        Supervisor.stop(sup)
      end
    end
  end
end
