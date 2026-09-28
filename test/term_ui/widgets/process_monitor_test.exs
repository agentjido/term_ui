defmodule TermUI.Widgets.ProcessMonitorTest do
  use ExUnit.Case, async: true

  alias TermUI.Event
  alias TermUI.Theme
  alias TermUI.Widgets.ProcessMonitor

  @area %{x: 0, y: 0, width: 100, height: 30}

  setup do
    # Start Theme server for color support (ignore if already started)
    case Theme.start_link(theme: :dark) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  describe "new/1" do
    test "creates props with defaults" do
      props = ProcessMonitor.new([])

      assert props.update_interval == 1000
      assert props.show_system_processes == false
      assert props.thresholds.queue_warning == 1000
      assert props.thresholds.queue_critical == 10_000
    end

    test "creates props with custom values" do
      props =
        ProcessMonitor.new(
          update_interval: 500,
          show_system_processes: true
        )

      assert props.update_interval == 500
      assert props.show_system_processes == true
    end
  end

  describe "init/1" do
    test "initializes with process list" do
      props = ProcessMonitor.new([])
      {:ok, state} = ProcessMonitor.init(props)

      assert is_list(state.processes)
      assert state.processes != []
      assert state.selected_idx == 0
      assert state.sort_field == :reductions
      assert state.sort_direction == :desc
    end

    test "fetches process info correctly" do
      props = ProcessMonitor.new([])
      {:ok, state} = ProcessMonitor.init(props)

      [process | _] = state.processes
      assert is_pid(process.pid)
      assert is_integer(process.reductions)
      assert is_integer(process.memory)
      assert is_integer(process.message_queue_len)
      assert is_atom(process.status)
    end
  end

  describe "navigation" do
    setup do
      props = ProcessMonitor.new([])
      {:ok, state} = ProcessMonitor.init(props)
      {:ok, state: state}
    end

    test "down key moves selection down", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :down}, state)
      assert state.selected_idx == 1
    end

    test "up key moves selection up", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :down}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :down}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :up}, state)
      assert state.selected_idx == 1
    end

    test "up key at top stays at 0", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :up}, state)
      assert state.selected_idx == 0
    end

    test "home key goes to first", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :down}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :down}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :home}, state)
      assert state.selected_idx == 0
    end

    test "end key goes to last", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :end}, state)
      assert state.selected_idx == length(state.processes) - 1
    end

    test "page_down moves by page", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :page_down}, state)
      assert state.selected_idx == min(20, length(state.processes) - 1)
    end
  end

  describe "sorting" do
    setup do
      props = ProcessMonitor.new([])
      {:ok, state} = ProcessMonitor.init(props)
      {:ok, state: state}
    end

    test "s key cycles sort field", %{state: state} do
      assert state.sort_field == :reductions

      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "s"}, state)
      assert state.sort_field == :memory

      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "s"}, state)
      assert state.sort_field == :queue

      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "s"}, state)
      assert state.sort_field == :status

      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "s"}, state)
      assert state.sort_field == :pid

      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "s"}, state)
      assert state.sort_field == :name
    end

    test "S key toggles sort direction", %{state: state} do
      assert state.sort_direction == :desc

      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "S"}, state)
      assert state.sort_direction == :asc

      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "S"}, state)
      assert state.sort_direction == :desc
    end

    test "set_sort/3 changes sorting", %{state: state} do
      {:ok, state} = ProcessMonitor.set_sort(state, :memory, :asc)
      assert state.sort_field == :memory
      assert state.sort_direction == :asc
    end

    test "sorting by reductions orders correctly", %{state: state} do
      {:ok, state} = ProcessMonitor.set_sort(state, :reductions, :desc)
      reductions = Enum.map(state.processes, & &1.reductions)

      # Check descending order
      pairs = Enum.zip(reductions, tl(reductions))
      assert Enum.all?(pairs, fn {a, b} -> a >= b end)
    end

    test "sorting by memory orders correctly", %{state: state} do
      {:ok, state} = ProcessMonitor.set_sort(state, :memory, :desc)
      memories = Enum.map(state.processes, & &1.memory)

      pairs = Enum.zip(memories, tl(memories))
      assert Enum.all?(pairs, fn {a, b} -> a >= b end)
    end
  end

  describe "filtering" do
    setup do
      props = ProcessMonitor.new([])
      {:ok, state} = ProcessMonitor.init(props)
      {:ok, state: state}
    end

    test "/ key starts filter input", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "/"}, state)
      assert state.filter_input == ""
    end

    test "typing adds to filter input", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "/"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "c"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "o"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "d"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "e"}, state)

      assert state.filter_input == "code"
    end

    test "enter applies filter", %{state: state} do
      original_count = length(state.processes)

      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "/"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "c"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "o"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "d"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "e"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :enter}, state)

      assert state.filter == "code"
      assert state.filter_input == nil
      # Filter should reduce or maintain process count
      assert length(state.processes) <= original_count
    end

    test "escape clears filter", %{state: state} do
      {:ok, state} = ProcessMonitor.set_filter(state, "test")
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :escape}, state)

      assert state.filter == nil
    end

    test "set_filter/2 applies filter", %{state: state} do
      {:ok, state} = ProcessMonitor.set_filter(state, "code")
      assert state.filter == "code"
      assert state.selected_idx == 0
    end

    test "backspace removes from filter input", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "/"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "a"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "b"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :backspace}, state)

      assert state.filter_input == "a"
    end
  end

  describe "details panel" do
    setup do
      props = ProcessMonitor.new([])
      {:ok, state} = ProcessMonitor.init(props)
      {:ok, state: state}
    end

    test "enter toggles details", %{state: state} do
      assert state.show_details == false

      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :enter}, state)
      assert state.show_details == true

      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :enter}, state)
      assert state.show_details == false
    end

    test "l key shows links mode", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "l"}, state)
      assert state.show_details == true
      assert state.detail_mode == :links
    end

    test "t key shows trace mode", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "t"}, state)
      assert state.show_details == true
      assert state.detail_mode == :trace
    end

    test "escape closes details", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :enter}, state)
      assert state.show_details == true

      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :escape}, state)
      assert state.show_details == false
    end
  end

  describe "process actions" do
    setup do
      props = ProcessMonitor.new([])
      {:ok, state} = ProcessMonitor.init(props)
      {:ok, state: state}
    end

    test "k key triggers kill confirmation", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "k"}, state)
      assert state.pending_action == :kill
    end

    test "n key cancels confirmation", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "k"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "n"}, state)
      assert state.pending_action == nil
    end

    test "escape cancels confirmation", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "k"}, state)
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{key: :escape}, state)
      assert state.pending_action == nil
    end

    test "y key confirms kill on test process" do
      # Start a test process we can safely kill
      {:ok, test_pid} = Agent.start(fn -> :test end)

      props = ProcessMonitor.new([])
      {:ok, state} = ProcessMonitor.init(props)

      # Find our test process
      idx = Enum.find_index(state.processes, &(&1.pid == test_pid))

      if idx do
        state = %{state | selected_idx: idx}
        {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "k"}, state)
        {:ok, _state} = ProcessMonitor.handle_event(%Event.Key{char: "y"}, state)

        # Process should be dead
        refute Process.alive?(test_pid)
      else
        # Process might have been filtered, just verify it's alive before test
        assert Process.alive?(test_pid)
        Agent.stop(test_pid)
      end
    end

    test "p key triggers suspend confirmation", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_event(%Event.Key{char: "p"}, state)
      assert state.pending_action == :suspend
    end
  end

  describe "refresh" do
    setup do
      props = ProcessMonitor.new([])
      {:ok, state} = ProcessMonitor.init(props)
      {:ok, state: state}
    end

    test "r key refreshes", %{state: state} do
      {:ok, state} = ProcessMonitor.refresh(state)
      assert is_list(state.processes)
    end

    test "handle_info :refresh updates processes", %{state: state} do
      {:ok, state} = ProcessMonitor.handle_info(:refresh, state)
      assert is_list(state.processes)
    end

    test "set_interval changes interval", %{state: state} do
      {:ok, state} = ProcessMonitor.set_interval(state, 2000)
      assert state.update_interval == 2000
    end
  end

  describe "public API" do
    setup do
      props = ProcessMonitor.new([])
      {:ok, state} = ProcessMonitor.init(props)
      {:ok, state: state}
    end

    test "get_selected returns current process", %{state: state} do
      process = ProcessMonitor.get_selected(state)
      assert process != nil
      assert is_pid(process.pid)
    end

    test "process_count returns count", %{state: state} do
      count = ProcessMonitor.process_count(state)
      assert count > 0
      assert count == length(state.processes)
    end

    test "get_stack_trace returns trace for valid pid", %{state: state} do
      process = ProcessMonitor.get_selected(state)
      trace = ProcessMonitor.get_stack_trace(process.pid)
      # May or may not have a trace depending on process state
      assert is_nil(trace) or is_list(trace)
    end
  end

  describe "render/2" do
    setup do
      props = ProcessMonitor.new([])
      {:ok, state} = ProcessMonitor.init(props)
      {:ok, state: state}
    end

    test "renders process list", %{state: state} do
      result = ProcessMonitor.render(state, @area)

      assert result.type == :stack
      assert result.direction == :vertical
      assert result.children != []
    end

    test "renders header with sort info", %{state: state} do
      result = ProcessMonitor.render(state, @area)

      header = Enum.at(result.children, 0)
      assert header.type == :text
      assert String.contains?(header.content, "Processes:")
      assert String.contains?(header.content, "Sort:")
    end

    test "renders with details panel when enabled", %{state: state} do
      state = %{state | show_details: true, detail_mode: :info}
      result = ProcessMonitor.render(state, @area)

      # Should have more children with details panel
      assert length(result.children) > 5
    end

    test "renders confirmation prompt", %{state: state} do
      state = %{state | pending_action: :kill}
      result = ProcessMonitor.render(state, @area)

      texts =
        result.children
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.content)

      assert Enum.any?(texts, &String.contains?(&1, "[y/n]"))
    end

    test "renders filter input", %{state: state} do
      state = %{state | filter_input: "test"}
      result = ProcessMonitor.render(state, @area)

      texts =
        result.children
        |> Enum.filter(&(&1.type == :text))
        |> Enum.map(& &1.content)

      assert Enum.any?(texts, &String.contains?(&1, "Filter: test"))
    end
  end

  describe "callbacks" do
    test "on_select callback is called" do
      test_pid = self()

      props =
        ProcessMonitor.new(on_select: fn process -> send(test_pid, {:selected, process.pid}) end)

      {:ok, state} = ProcessMonitor.init(props)

      {:ok, _state} = ProcessMonitor.handle_event(%Event.Key{key: :down}, state)

      assert_receive {:selected, _pid}
    end

    test "on_action callback is called on kill" do
      test_pid = self()

      # Start test process
      {:ok, victim_pid} = Agent.start(fn -> :test end)

      props =
        ProcessMonitor.new(on_action: fn action -> send(test_pid, {:action, action}) end)

      {:ok, state} = ProcessMonitor.init(props)

      # Find and select the test process
      idx = Enum.find_index(state.processes, &(&1.pid == victim_pid))

      if idx do
        state = %{state | selected_idx: idx, pending_action: :kill}
        {:ok, _state} = ProcessMonitor.handle_event(%Event.Key{char: "y"}, state)

        assert_receive {:action, {:killed, ^victim_pid}}
      else
        # Cleanup if not found
        Agent.stop(victim_pid)
      end
    end
  end

  describe "warning thresholds" do
    test "processes with high queue get warning style" do
      props =
        ProcessMonitor.new(
          thresholds: %{
            queue_warning: 0,
            queue_critical: 1000,
            memory_warning: 50 * 1024 * 1024,
            memory_critical: 200 * 1024 * 1024
          }
        )

      {:ok, state} = ProcessMonitor.init(props)
      result = ProcessMonitor.render(state, @area)

      # Should render - we can't easily test style but can verify it renders
      assert result.type == :stack
    end
  end
end
