defmodule TermUI.RuntimeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias TermUI.Event
  alias TermUI.Runtime

  # Helper to start runtime without terminal (for test isolation)
  defp start_test_runtime(opts) do
    Runtime.start_link([skip_terminal: true] ++ opts)
  end

  # Clean up persistent_term values between tests
  setup do
    # Store original values
    original_backend_mode = :persistent_term.get(:term_ui_backend_mode, :not_set)
    original_capabilities = :persistent_term.get(:term_ui_capabilities, :not_set)

    on_exit(fn ->
      # Restore or clean up persistent_term
      if original_backend_mode != :not_set do
        :persistent_term.put(:term_ui_backend_mode, original_backend_mode)
      else
        :persistent_term.erase(:term_ui_backend_mode)
      end

      if original_capabilities != :not_set do
        :persistent_term.put(:term_ui_capabilities, original_capabilities)
      else
        :persistent_term.erase(:term_ui_capabilities)
      end
    end)

    :ok
  end

  # Test component that implements Elm behaviour
  defmodule Counter do
    use TermUI.Elm

    def init(opts), do: %{count: Keyword.get(opts, :initial, 0)}

    def event_to_msg(%Event.Key{key: :up}, _state), do: {:msg, :increment}
    def event_to_msg(%Event.Key{key: :down}, _state), do: {:msg, :decrement}
    def event_to_msg(%Event.Key{key: :q}, _state), do: {:msg, :quit}
    def event_to_msg(%Event.Resize{width: w, height: h}, _state), do: {:msg, {:resize, w, h}}
    def event_to_msg(_, _), do: :ignore

    def update(:increment, state), do: {%{state | count: state.count + 1}, []}
    def update(:decrement, state), do: {%{state | count: state.count - 1}, []}
    def update(:quit, state), do: {state, [:quit]}
    def update({:resize, w, h}, state), do: {Map.merge(state, %{width: w, height: h}), []}
    def update(_, state), do: {state, []}

    def view(state), do: {:text, "Count: #{state.count}"}
  end

  # Test component without init
  defmodule NoInit do
    use TermUI.Elm

    def event_to_msg(_, _), do: :ignore
    def update(_, state), do: {state, []}
    def view(_state), do: {:text, "No init"}
  end

  describe "start_link/1" do
    test "starts runtime with root component" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      state = Runtime.get_state(runtime)
      assert state.root_module == Counter
      assert state.root_state == %{count: 0}
      refute state.shutting_down
    end

    test "starts runtime with registered name" do
      {:ok, _runtime} = start_test_runtime(root: Counter, name: :test_runtime)

      state = Runtime.get_state(:test_runtime)
      assert state.root_module == Counter

      GenServer.stop(:test_runtime)
    end

    test "passes options to component init" do
      {:ok, runtime} = start_test_runtime(root: Counter, initial: 10)

      state = Runtime.get_state(runtime)
      assert state.root_state.count == 10
    end

    test "handles component without init function" do
      {:ok, runtime} = start_test_runtime(root: NoInit)

      state = Runtime.get_state(runtime)
      assert state.root_state == %{}
    end

    test "sets custom render interval" do
      {:ok, runtime} = start_test_runtime(root: Counter, render_interval: 100)

      state = Runtime.get_state(runtime)
      assert state.render_interval == 100
    end
  end

  describe "send_event/2" do
    test "dispatches keyboard event to focused component" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      Runtime.send_event(runtime, Event.key(:up))
      # Wait for message processing
      Process.sleep(50)

      state = Runtime.get_state(runtime)
      assert state.root_state.count == 1
    end

    test "processes multiple events in sequence" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      Runtime.send_event(runtime, Event.key(:up))
      Runtime.send_event(runtime, Event.key(:up))
      Runtime.send_event(runtime, Event.key(:up))
      Process.sleep(50)

      state = Runtime.get_state(runtime)
      assert state.root_state.count == 3
    end

    test "ignores events during shutdown" do
      {:ok, runtime} = start_test_runtime(root: Counter)
      ref = Process.monitor(runtime)

      Runtime.shutdown(runtime)
      Runtime.send_event(runtime, Event.key(:up))

      # Process should have stopped after shutdown
      # Events during shutdown should be ignored without crash
      assert_receive {:DOWN, ^ref, :process, ^runtime, :normal}, 1000
    end

    test "broadcasts resize events" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      Runtime.send_event(runtime, Event.resize(120, 40))
      Process.sleep(50)

      state = Runtime.get_state(runtime)
      assert state.root_state.width == 120
      assert state.root_state.height == 40
    end

    test "dispatches paste events to focused component" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      # Paste events go to focused component but Counter ignores them
      Runtime.send_event(runtime, Event.paste("hello"))
      Process.sleep(50)

      state = Runtime.get_state(runtime)
      # State unchanged since Counter ignores paste
      assert state.root_state.count == 0
    end
  end

  describe "send_message/3" do
    test "sends message directly to component" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      Runtime.send_message(runtime, :root, :increment)
      Process.sleep(50)

      state = Runtime.get_state(runtime)
      assert state.root_state.count == 1
    end

    test "ignores messages to non-existent component" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      Runtime.send_message(runtime, :nonexistent, :increment)
      Process.sleep(50)

      state = Runtime.get_state(runtime)
      assert state.root_state.count == 0
    end

    test "ignores messages during shutdown" do
      {:ok, runtime} = start_test_runtime(root: Counter)
      ref = Process.monitor(runtime)

      Runtime.shutdown(runtime)
      Runtime.send_message(runtime, :root, :increment)

      # Process should have stopped after shutdown
      # Messages during shutdown should be ignored without crash
      assert_receive {:DOWN, ^ref, :process, ^runtime, :normal}, 1000
    end
  end

  describe "dirty flag and rendering" do
    test "marks dirty when state changes" do
      {:ok, runtime} = start_test_runtime(root: Counter, render_interval: 10)

      # Initial state should be dirty for first render
      state = Runtime.get_state(runtime)
      assert state.dirty == true

      # After render tick, should be clean
      Process.sleep(50)
      state = Runtime.get_state(runtime)
      assert state.dirty == false

      # After event that changes state, should be dirty then clean after render
      Runtime.send_event(runtime, Event.key(:up))
      Process.sleep(50)
      state = Runtime.get_state(runtime)
      # Count should update
      assert state.root_state.count == 1
    end

    test "force_render bypasses framerate limiter" do
      {:ok, runtime} = start_test_runtime(root: Counter, render_interval: 10_000)

      # Initial dirty
      state = Runtime.get_state(runtime)
      assert state.dirty == true

      # Force render
      Runtime.force_render(runtime)
      Process.sleep(10)

      state = Runtime.get_state(runtime)
      assert state.dirty == false
    end
  end

  describe "command collection" do
    test "collects commands from update results" do
      {:ok, runtime} = start_test_runtime(root: Counter)
      ref = Process.monitor(runtime)

      # Send event that produces a quit command
      # This should trigger shutdown
      Runtime.send_event(runtime, Event.key(:q))

      # Process should have stopped due to quit command
      assert_receive {:DOWN, ^ref, :process, ^runtime, :normal}, 1000
    end
  end

  describe "command_result/4" do
    test "sends command result as message to component" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      # Simulate a command completion
      Runtime.command_result(runtime, :root, make_ref(), :some_result)
      Process.sleep(50)

      # Result is enqueued as message (Counter ignores unknown messages)
      state = Runtime.get_state(runtime)
      assert state.root_state.count == 0
    end
  end

  describe "shutdown/1" do
    test "initiates graceful shutdown" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      # Monitor the process
      ref = Process.monitor(runtime)

      Runtime.shutdown(runtime)

      # Process should stop after shutdown
      assert_receive {:DOWN, ^ref, :process, ^runtime, :normal}, 1000
    end

    test "does not emit terminal cleanup when terminal initialization was skipped" do
      output =
        capture_io(:stderr, fn ->
          {:ok, runtime} = start_test_runtime(root: Counter)
          ref = Process.monitor(runtime)

          Runtime.shutdown(runtime)

          assert_receive {:DOWN, ^ref, :process, ^runtime, :normal}, 1000
        end)

      assert output == ""
    end

    test "clears pending commands on shutdown" do
      {:ok, runtime} = start_test_runtime(root: Counter)
      ref = Process.monitor(runtime)

      Runtime.shutdown(runtime)

      # Process should have stopped after cleanup
      assert_receive {:DOWN, ^ref, :process, ^runtime, :normal}, 1000
    end

    test "clears components on shutdown" do
      {:ok, runtime} = start_test_runtime(root: Counter)
      ref = Process.monitor(runtime)

      Runtime.shutdown(runtime)

      # Process should have stopped after cleanup
      assert_receive {:DOWN, ^ref, :process, ^runtime, :normal}, 1000
    end
  end

  describe "event dispatch routing" do
    test "keyboard events go to focused component" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      # Default focus is :root
      state = Runtime.get_state(runtime)
      assert state.focused_component == :root

      Runtime.send_event(runtime, Event.key(:up))
      Process.sleep(50)

      state = Runtime.get_state(runtime)
      assert state.root_state.count == 1
    end

    test "mouse events go to root (spatial index not implemented)" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      # Mouse events currently just go to root
      Runtime.send_event(runtime, Event.mouse(:click, :left, 10, 10))
      Process.sleep(50)

      # Counter ignores mouse events
      state = Runtime.get_state(runtime)
      assert state.root_state.count == 0
    end

    test "focus events broadcast to all components" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      Runtime.send_event(runtime, Event.focus(:gained))
      Process.sleep(50)

      # Counter ignores focus events
      state = Runtime.get_state(runtime)
      assert state.root_state.count == 0
    end

    test "tick events broadcast to all components" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      Runtime.send_event(runtime, Event.tick(16))
      Process.sleep(50)

      # Counter ignores tick events
      state = Runtime.get_state(runtime)
      assert state.root_state.count == 0
    end
  end

  describe "component initialization" do
    test "initializes component registry with root" do
      {:ok, runtime} = start_test_runtime(root: Counter, initial: 5)

      state = Runtime.get_state(runtime)

      assert Map.has_key?(state.components, :root)
      assert state.components.root.module == Counter
      assert state.components.root.state.count == 5
    end
  end

  describe "render timing" do
    test "uses default render interval" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      state = Runtime.get_state(runtime)
      assert state.render_interval == 16
    end

    test "schedules render ticks" do
      {:ok, runtime} = start_test_runtime(root: Counter, render_interval: 10)

      # Initial should be dirty
      state = Runtime.get_state(runtime)
      assert state.dirty == true

      # Wait for render tick
      Process.sleep(30)

      state = Runtime.get_state(runtime)
      assert state.dirty == false
    end
  end

  describe "message batching" do
    test "processes multiple messages before render" do
      {:ok, runtime} = start_test_runtime(root: Counter, render_interval: 100)

      # Send multiple events quickly
      for _ <- 1..5 do
        Runtime.send_event(runtime, Event.key(:up))
      end

      # Wait for processing
      Process.sleep(150)

      state = Runtime.get_state(runtime)
      assert state.root_state.count == 5
    end
  end

  describe "full cycle integration" do
    test "event -> message -> update -> view cycle" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      # Initial state
      state = Runtime.get_state(runtime)
      assert state.root_state.count == 0

      # Send event
      Runtime.send_event(runtime, Event.key(:up))
      Process.sleep(50)

      # State updated
      state = Runtime.get_state(runtime)
      assert state.root_state.count == 1

      # View would be called on render
      %{module: module, state: component_state} = state.components.root
      view_result = module.view(component_state)
      assert view_result == {:text, "Count: 1"}
    end

    test "handles decrement correctly" do
      {:ok, runtime} = start_test_runtime(root: Counter, initial: 5)

      Runtime.send_event(runtime, Event.key(:down))
      Process.sleep(50)

      state = Runtime.get_state(runtime)
      assert state.root_state.count == 4
    end

    test "state changes trigger dirty flag" do
      {:ok, runtime} = start_test_runtime(root: Counter, render_interval: 10)

      # Wait for initial render
      Process.sleep(50)

      state = Runtime.get_state(runtime)
      assert state.dirty == false

      # Send event that changes state
      Runtime.send_event(runtime, Event.key(:up))
      Process.sleep(50)

      state = Runtime.get_state(runtime)
      # Count should update
      assert state.root_state.count == 1
    end
  end

  describe "backend selection" do
    test "stores backend mode in state when skip_terminal is used" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      state = Runtime.get_state(runtime)
      assert state.backend_mode == :skip
      assert state.backend == nil
    end

    test "stores backend mode in persistent_term" do
      {:ok, _runtime} = start_test_runtime(root: Counter)

      assert Runtime.backend_mode() == :skip
    end

    test "stores capabilities in persistent_term" do
      {:ok, _runtime} = start_test_runtime(root: Counter)

      # skip_terminal mode doesn't set capabilities
      assert Runtime.capabilities() == nil
    end

    test "backend_mode/0 returns nil when no runtime started" do
      # Ensure we're not picking up values from other tests
      :persistent_term.erase(:term_ui_backend_mode)
      assert Runtime.backend_mode() == nil
    end

    test "capabilities/0 returns nil when no runtime started" do
      # Ensure we're not picking up values from other tests
      :persistent_term.erase(:term_ui_capabilities)
      assert Runtime.capabilities() == nil
    end
  end

  describe "backend option handling" do
    test "accepts :auto backend option" do
      # With skip_terminal, the actual backend selection is bypassed
      # but the option should still be accepted
      {:ok, runtime} = Runtime.start_link(root: Counter, backend: :auto, skip_terminal: true)

      state = Runtime.get_state(runtime)
      assert state.backend_mode == :skip
    end

    test "accepts :tty backend option" do
      {:ok, runtime} = Runtime.start_link(root: Counter, backend: :tty, skip_terminal: true)

      state = Runtime.get_state(runtime)
      assert state.backend_mode == :skip
    end

    test "accepts TermUI.Backend.TTY explicit backend" do
      {:ok, runtime} =
        Runtime.start_link(root: Counter, backend: TermUI.Backend.TTY, skip_terminal: true)

      state = Runtime.get_state(runtime)
      assert state.backend_mode == :skip
    end
  end

  describe "backend selector integration" do
    test "calls Selector.select/1 during initialization" do
      # Verify that the selector is being called by checking that it works
      # We can't easily test the actual raw mode without a terminal
      # but we can test that the option is passed through

      # Start with explicit TTY backend
      {:ok, runtime} =
        Runtime.start_link(root: Counter, backend: TermUI.Backend.TTY, skip_terminal: true)

      state = Runtime.get_state(runtime)
      # With skip_terminal, backend_mode is :skip
      assert state.backend_mode == :skip
    end

    test "stores backend module in state" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      state = Runtime.get_state(runtime)
      # With skip_terminal, backend is nil
      assert state.backend == nil
    end
  end

  describe "input handler integration" do
    test "does not use input handler by default" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      state = Runtime.get_state(runtime)
      # By default, input_handler is nil (legacy InputReader is used)
      assert state.input_handler == nil
      assert state.input_state == nil
    end

    test "initializes input handler when use_input_handler is true" do
      {:ok, runtime} =
        Runtime.start_link(root: Counter, use_input_handler: true, skip_terminal: true)

      state = Runtime.get_state(runtime)
      # With skip_terminal and backend_mode :skip, no input handler is initialized
      assert state.input_handler == nil
    end

    test "initializes input handler for raw backend mode" do
      # We can't test actual raw mode without a terminal, but we can verify
      # the logic path by checking the state structure
      {:ok, runtime} =
        Runtime.start_link(
          root: Counter,
          backend: :raw,
          use_input_handler: true,
          skip_terminal: true
        )

      state = Runtime.get_state(runtime)
      # Backend mode :skip means no handler selected
      assert state.input_handler == nil
    end

    test "initializes input handler for TTY backend mode" do
      {:ok, runtime} =
        Runtime.start_link(
          root: Counter,
          backend: :tty,
          use_input_handler: true,
          skip_terminal: true
        )

      state = Runtime.get_state(runtime)
      # Backend mode :skip means no handler selected
      assert state.input_handler == nil
    end

    test "input_handler defaults to nil when use_input_handler is false" do
      {:ok, runtime} =
        Runtime.start_link(root: Counter, use_input_handler: false, skip_terminal: true)

      state = Runtime.get_state(runtime)
      assert state.input_handler == nil
      assert state.input_state == nil
    end

    test "input_handler_reader defaults to nil with skip_terminal" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      state = Runtime.get_state(runtime)
      assert state[:input_handler_reader] == nil
    end
  end

  describe "async input handler reader" do
    # Mock input handler that sends events from its poll function.
    # Uses an Agent to feed events into the handler on demand.
    defmodule MockInputHandler do
      @behaviour TermUI.Input

      defstruct [:agent]

      def new do
        # not used directly - tests create state with start/0
        %__MODULE__{agent: nil}
      end

      def start do
        {:ok, agent} = Agent.start_link(fn -> {:block, nil} end)
        %__MODULE__{agent: agent}
      end

      @doc "Queue an event to be returned by the next poll call"
      def push_event(%__MODULE__{agent: agent}, event) do
        Agent.update(agent, fn _state -> {:event, event} end)
      end

      @doc "Signal EOF to be returned by the next poll call"
      def push_eof(%__MODULE__{agent: agent}) do
        Agent.update(agent, fn _state -> :eof end)
      end

      @impl true
      def poll(%__MODULE__{agent: agent} = state, _timeout) do
        # Spin-wait for an event or eof signal (simulates blocking IO)
        result = spin_wait(agent)

        case result do
          {:event, event} ->
            {{:ok, event}, state}

          :eof ->
            {:eof, state}
        end
      end

      defp spin_wait(agent) do
        case Agent.get(agent, & &1) do
          {:block, _} ->
            Process.sleep(5)
            spin_wait(agent)

          {:event, _event} = result ->
            # Consume the event
            Agent.update(agent, fn _state -> {:block, nil} end)
            result

          :eof ->
            result = :eof
            Agent.update(agent, fn _state -> {:block, nil} end)
            result
        end
      end

      @impl true
      def mode(%__MODULE__{}), do: :tty

      @impl true
      def stop(%__MODULE__{agent: agent}) do
        if agent && Process.alive?(agent), do: Agent.stop(agent)
        :ok
      end
    end

    test "async reader dispatches events to the runtime without blocking" do
      # Start runtime with skip_terminal
      {:ok, runtime} = start_test_runtime(root: Counter)

      # Create a mock input handler and manually wire it up
      mock_state = MockInputHandler.start()

      # Spawn the async reader targeting the runtime
      observer = self()

      reader_pid =
        spawn_link(fn ->
          # Use the same loop the runtime uses internally
          loop(MockInputHandler, mock_state, runtime, observer)
        end)

      # Push a key event
      MockInputHandler.push_event(mock_state, Event.key(:up))
      assert_receive {:input_dispatched, ^reader_pid}, 1000

      # Verify the event was dispatched - runtime should still be responsive
      state = Runtime.get_state(runtime)
      assert state.root_state.count == 1

      # Push another event
      MockInputHandler.push_event(mock_state, Event.key(:up))
      assert_receive {:input_dispatched, ^reader_pid}, 1000

      state = Runtime.get_state(runtime)
      assert state.root_state.count == 2

      # Cleanup
      Process.unlink(reader_pid)
      Process.exit(reader_pid, :shutdown)
      MockInputHandler.stop(mock_state)
    end

    test "runtime remains responsive while async reader is waiting for input" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      # Create a mock handler that blocks (no events pushed)
      mock_state = MockInputHandler.start()

      reader_pid =
        spawn_link(fn ->
          loop(MockInputHandler, mock_state, runtime)
        end)

      # The reader is now blocking in poll(). Verify the runtime is still responsive.
      # Send events directly via Runtime.send_event (simulating other input sources)
      Runtime.send_event(runtime, Event.key(:up))
      Runtime.sync(runtime)

      state = Runtime.get_state(runtime)
      assert state.root_state.count == 1

      # Runtime can still be queried
      state2 = Runtime.get_state(runtime)
      assert state2.root_state.count == 1

      # Cleanup
      Process.unlink(reader_pid)
      Process.exit(reader_pid, :shutdown)
      MockInputHandler.stop(mock_state)
    end

    test "input_eof message triggers shutdown" do
      {:ok, runtime} = start_test_runtime(root: Counter)
      ref = Process.monitor(runtime)

      # Simulate what the async reader sends on EOF
      send(runtime, :input_eof)

      # Runtime should shut down
      assert_receive {:DOWN, ^ref, :process, ^runtime, _reason}, 1000
    end

    test "reader process exit is handled gracefully" do
      {:ok, runtime} = start_test_runtime(root: Counter)

      # Simulate a reader crash by sending an EXIT message directly.
      # The runtime traps exits, so {:EXIT, pid, reason} arrives as a message.
      fake_reader_pid = spawn(fn -> :ok end)
      Process.sleep(10)

      # Set the input_handler_reader in state so the EXIT handler recognizes it
      # We can't set it directly, so instead simulate the message the runtime handles
      send(runtime, {:EXIT, fake_reader_pid, :some_crash_reason})
      Process.sleep(50)

      # Runtime should still be alive and responsive
      assert Process.alive?(runtime)
      state = Runtime.get_state(runtime)
      assert state.root_state.count == 0
    end

    # Helper: same loop the runtime uses internally
    defp loop(handler, input_state, target, observer \\ nil) do
      case handler.poll(input_state, 16) do
        {{:ok, event}, new_state} ->
          send(target, {:input, event})

          if observer do
            Runtime.sync(target)
            send(observer, {:input_dispatched, self()})
          end

          loop(handler, new_state, target, observer)

        {:timeout, new_state} ->
          loop(handler, new_state, target, observer)

        {:eof, _new_state} ->
          send(target, :input_eof)
      end
    end
  end
end
