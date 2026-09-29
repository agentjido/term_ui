defmodule TermUI.Integration.EventSystemTest do
  @moduledoc """
  Integration tests for the Phase 5 Event System.

  Tests realistic workflows that involve multiple subsystems working together,
  such as shortcuts triggering clipboard operations, mouse events with
  coordinate transformation, and focus changes affecting application state.
  """

  use ExUnit.Case, async: false

  # Timeout constants for assertions
  @short_timeout 50
  @default_timeout 100
  @medium_timeout 150
  @extended_timeout 250
  @eventual_timeout 1_000

  alias TermUI.Clipboard
  alias TermUI.Clipboard.Selection
  alias TermUI.Command
  alias TermUI.Command.Executor
  alias TermUI.ComponentRegistry
  alias TermUI.Event
  alias TermUI.Event.Propagation
  alias TermUI.Event.Transformation
  alias TermUI.Focus
  alias TermUI.Mouse.Router, as: MouseRouter
  alias TermUI.Mouse.Tracker, as: MouseTracker
  alias TermUI.Shortcut

  describe "command execution workflows" do
    setup do
      executor = start_supervised!(Executor)
      %{executor: executor}
    end

    test "timer command executes and delivers result to component", %{executor: executor} do
      cmd = Command.timer(10, {:timer_done, :test})
      Executor.execute(executor, cmd, self(), :test_component)

      assert_receive {:command_result, :test_component, _ref, {:timer_done, :test}},
                     @default_timeout
    end

    test "multiple commands execute concurrently and deliver results", %{executor: executor} do
      cmd1 = Command.timer(10, :first)
      cmd2 = Command.timer(10, :second)

      Executor.execute(executor, cmd1, self(), :comp1)
      Executor.execute(executor, cmd2, self(), :comp2)

      results = receive_results_with_ref(2, 200)
      assert length(results) == 2
    end

    test "command cancellation prevents result delivery", %{executor: executor} do
      cmd = Command.timer(100, :should_not_receive)
      {:ok, ref} = Executor.execute(executor, cmd, self(), :test)

      Executor.cancel(executor, ref)

      refute_receive {:command_result, _, _, _}, @medium_timeout
    end

    test "cancel_all_for_component cancels multiple pending commands", %{executor: executor} do
      # Start multiple commands for same component
      cmd1 = Command.timer(100, :first)
      cmd2 = Command.timer(100, :second)
      cmd3 = Command.timer(100, :third)

      Executor.execute(executor, cmd1, self(), :my_component)
      Executor.execute(executor, cmd2, self(), :my_component)
      Executor.execute(executor, cmd3, self(), :other_component)

      # Cancel all for my_component
      :ok = Executor.cancel_all_for_component(executor, :my_component)

      # Should only receive result from other_component
      assert_receive {:command_result, :other_component, _, :third}, @eventual_timeout
      refute_receive {:command_result, :my_component, _, _}, @short_timeout
    end

    test "max_concurrent limit returns error when exceeded" do
      # Start executor with low limit (use unique id to avoid conflict with setup executor)
      executor = start_supervised!({Executor, max_concurrent: 2}, id: :limited_executor)

      cmd1 = Command.timer(100, :first)
      cmd2 = Command.timer(100, :second)
      cmd3 = Command.timer(100, :third)

      {:ok, _} = Executor.execute(executor, cmd1, self(), :comp1)
      {:ok, _} = Executor.execute(executor, cmd2, self(), :comp2)

      # Third should fail
      assert {:error, :max_concurrent_reached} = Executor.execute(executor, cmd3, self(), :comp3)

      # After one completes, should be able to execute another
      assert_receive {:command_result, _, _, _}, @eventual_timeout

      cmd4 = Command.timer(10, :fourth)
      assert {:ok, _} = Executor.execute(executor, cmd4, self(), :comp4)
    end

    test "command timeout delivers error result", %{executor: executor} do
      # Create a command that would take longer than timeout
      cmd = %Command{
        type: :timer,
        payload: 200,
        on_result: :should_timeout,
        timeout: 50
      }

      Executor.execute(executor, cmd, self(), :test)

      # The executor's 50 ms deadline is the behavior under test. Give a loaded
      # CI scheduler enough time to deliver the resulting message.
      assert_receive {:command_result, :test, _, {:error, :timeout}}, @eventual_timeout
      refute_receive {:command_result, :test, _, :should_timeout}, @extended_timeout
    end
  end

  describe "mouse drag with routing and tracking" do
    test "tracks complete drag sequence with coordinate transformation" do
      components = %{
        panel: %{bounds: %{x: 100, y: 50, width: 200, height: 100}, z_index: 0}
      }

      tracker = MouseTracker.new(drag_threshold: 1)

      # Press at global coordinates - route to component
      press = Event.mouse(:press, :left, 120, 70)
      {component_id, local_event} = MouseRouter.route(components, press)

      assert component_id == :panel
      assert local_event.x == 20
      assert local_event.y == 20

      # Track drag state
      {tracker, _events} = MouseTracker.process(tracker, press)
      assert MouseTracker.button_down(tracker) == :left

      # Move beyond threshold - drag starts
      move = Event.mouse(:move, nil, 150, 90)
      {tracker, events} = MouseTracker.process(tracker, move)

      assert MouseTracker.dragging?(tracker)
      assert [{:drag_start, :left, 120, 70}, {:drag_move, :left, 150, 90, 30, 20}] = events

      # Release - drag ends
      release = Event.mouse(:release, :left, 180, 100)
      {tracker, events} = MouseTracker.process(tracker, release)

      refute MouseTracker.dragging?(tracker)
      assert [{:drag_end, :left, 180, 100}] = events
    end

    test "tracks hover state with component routing" do
      components = %{
        button1: %{bounds: %{x: 0, y: 0, width: 50, height: 30}, z_index: 0},
        button2: %{bounds: %{x: 60, y: 0, width: 50, height: 30}, z_index: 0}
      }

      tracker = MouseTracker.new()

      # Move over button1
      move1 = Event.mouse(:move, nil, 25, 15)
      {id1, _} = MouseRouter.route(components, move1)
      {tracker, events} = MouseTracker.update_hover(tracker, id1)

      assert id1 == :button1
      assert events == [{:hover_enter, :button1}]

      # Move to button2 - leave button1, enter button2
      move2 = Event.mouse(:move, nil, 85, 15)
      {id2, _} = MouseRouter.route(components, move2)
      {_tracker, events} = MouseTracker.update_hover(tracker, id2)

      assert id2 == :button2
      assert events == [{:hover_leave, :button1}, {:hover_enter, :button2}]
    end

    test "routes to highest z-order with overlapping components" do
      components = %{
        background: %{bounds: %{x: 0, y: 0, width: 100, height: 100}, z_index: 0},
        dialog: %{bounds: %{x: 20, y: 20, width: 60, height: 60}, z_index: 10}
      }

      # Click in overlap area routes to higher z-index
      event = Event.mouse(:click, :left, 50, 50)
      {id, local_event} = MouseRouter.route(components, event)

      assert id == :dialog
      assert local_event.x == 30
      assert local_event.y == 30
    end
  end

  describe "shortcut system workflows" do
    setup do
      registry = start_supervised!(Shortcut)
      %{registry: registry}
    end

    test "global shortcut triggers from any context", %{registry: registry} do
      Shortcut.register(registry, %Shortcut{
        key: :q,
        modifiers: [:ctrl],
        action: {:function, fn -> :quit end},
        scope: :global
      })

      event = Event.key(:q, modifiers: [:ctrl])

      # Matches in any mode or focused component
      assert {:ok, _} = Shortcut.match(registry, event, %{mode: :normal})
      assert {:ok, _} = Shortcut.match(registry, event, %{mode: :edit})
      assert {:ok, _} = Shortcut.match(registry, event, %{focused_component: :editor})
    end

    test "mode-scoped shortcut respects application mode", %{registry: registry} do
      Shortcut.register(registry, %Shortcut{
        key: :i,
        modifiers: [],
        action: {:function, fn -> :insert end},
        scope: {:mode, :normal}
      })

      event = Event.key(:i)

      # Only matches in normal mode
      assert :no_match = Shortcut.match(registry, event, %{mode: :edit})
      assert {:ok, _} = Shortcut.match(registry, event, %{mode: :normal})
    end

    test "component-scoped shortcut respects focus", %{registry: registry} do
      Shortcut.register(registry, %Shortcut{
        key: :enter,
        modifiers: [],
        action: {:function, fn -> :submit end},
        scope: {:component, :form}
      })

      event = Event.key(:enter)

      # Only matches when form is focused
      assert :no_match = Shortcut.match(registry, event, %{focused_component: :list})
      assert {:ok, _} = Shortcut.match(registry, event, %{focused_component: :form})
    end

    test "key sequence completes across multiple key events", %{registry: registry} do
      Shortcut.register(registry, %Shortcut{
        key: :g,
        modifiers: [],
        action: {:function, fn -> :go_top end},
        sequence: [:g, :g]
      })

      event = Event.key(:g)

      # First key starts sequence
      assert :no_match = Shortcut.match(registry, event)

      # Second key completes sequence
      assert {:ok, shortcut} = Shortcut.match(registry, event)
      assert shortcut.sequence == [:g, :g]
      assert Shortcut.execute(shortcut) == :go_top
    end

    test "priority resolves conflicting shortcuts", %{registry: registry} do
      Shortcut.register(registry, %Shortcut{
        key: :s,
        modifiers: [:ctrl],
        action: {:function, fn -> :low_priority end},
        priority: 0
      })

      Shortcut.register(registry, %Shortcut{
        key: :s,
        modifiers: [:ctrl],
        action: {:function, fn -> :high_priority end},
        priority: 10
      })

      event = Event.key(:s, modifiers: [:ctrl])
      {:ok, shortcut} = Shortcut.match(registry, event)

      assert Shortcut.execute(shortcut) == :high_priority
    end

    test "shortcut triggers clipboard copy operation", %{registry: registry} do
      # Register Ctrl+C shortcut that performs copy
      Shortcut.register(registry, %Shortcut{
        key: :c,
        modifiers: [:ctrl],
        action:
          {:function,
           fn ->
             text = "Document content here"
             selection = Selection.new() |> Selection.start(9) |> Selection.extend(16)
             content = Selection.extract(selection, text)
             sequence = Clipboard.write_sequence(content)
             {:copied, content, sequence}
           end},
        description: "Copy selection to clipboard"
      })

      event = Event.key(:c, modifiers: [:ctrl])
      {:ok, shortcut} = Shortcut.match(registry, event)
      {:copied, content, sequence} = Shortcut.execute(shortcut)

      assert content == "content"
      assert String.contains?(sequence, Base.encode64("content"))
    end
  end

  describe "clipboard workflow integration" do
    test "complete copy workflow: select, extract, write to clipboard" do
      text = "The quick brown fox jumps over the lazy dog"

      # Select "quick brown"
      selection =
        Selection.new()
        |> Selection.start(4)
        |> Selection.extend(15)

      # Extract selected content
      content = Selection.extract(selection, text)
      assert content == "quick brown"

      # Generate clipboard write sequence
      sequence = Clipboard.write_sequence(content)
      assert String.contains?(sequence, Base.encode64("quick brown"))
    end

    test "complete cut workflow: select, copy, delete" do
      text = "Hello World"

      # Select "World"
      selection =
        Selection.new()
        |> Selection.start(6)
        |> Selection.extend(11)

      # Extract for clipboard
      content = Selection.extract(selection, text)
      assert content == "World"

      # Generate clipboard sequence
      _sequence = Clipboard.write_sequence(content)

      # Delete selected content
      {start_pos, end_pos} = Selection.range(selection)
      remaining = String.slice(text, 0, start_pos) <> String.slice(text, end_pos..-1//1)

      assert remaining == "Hello "
    end

    test "selection expansion simulates shift+arrow navigation" do
      text = "Hello World Example"

      # Start with cursor at position 6 (beginning of "World")
      # Simulate Shift+Right five times to select "World"
      selection =
        Selection.new()
        |> Selection.start(6)
        |> Selection.extend(7)
        |> Selection.extend(8)
        |> Selection.extend(9)
        |> Selection.extend(10)
        |> Selection.extend(11)

      assert Selection.extract(selection, text) == "World"
    end
  end

  describe "focus event workflows" do
    test "focus lost triggers registered actions" do
      tracker = start_supervised!({Focus.Tracker, initial_focus: true})
      test_pid = self()

      # Register multiple focus lost actions
      Focus.Tracker.on_focus_lost(tracker, fn ->
        send(test_pid, :autosave_triggered)
      end)

      Focus.Tracker.on_focus_lost(tracker, fn ->
        send(test_pid, :cleanup_triggered)
      end)

      # Lose focus
      Focus.Tracker.set_focus(tracker, false)

      # Both actions should execute
      assert_receive :autosave_triggered, @default_timeout
      assert_receive :cleanup_triggered, @default_timeout
    end

    test "focus gained triggers refresh actions" do
      tracker = start_supervised!({Focus.Tracker, initial_focus: false})
      test_pid = self()

      Focus.Tracker.on_focus_gained(tracker, fn ->
        send(test_pid, :refresh_triggered)
      end)

      # Gain focus
      Focus.Tracker.set_focus(tracker, true)

      assert_receive :refresh_triggered, @default_timeout
    end

    test "auto-pause pauses on focus lost and resumes on focus gained" do
      tracker = start_supervised!({Focus.Tracker, initial_focus: true})

      Focus.Tracker.enable_auto_pause(tracker)

      # Initially not paused
      refute Focus.Tracker.paused?(tracker)

      # Lose focus - should pause
      Focus.Tracker.set_focus(tracker, false)
      assert Focus.Tracker.paused?(tracker)

      # Gain focus - should resume
      Focus.Tracker.set_focus(tracker, true)
      refute Focus.Tracker.paused?(tracker)
    end

    test "focus lost triggers autosave then pauses animations" do
      tracker = start_supervised!({Focus.Tracker, initial_focus: true})
      test_pid = self()

      # Register autosave action
      Focus.Tracker.on_focus_lost(tracker, fn ->
        send(test_pid, :autosave)
      end)

      # Enable auto-pause
      Focus.Tracker.enable_auto_pause(tracker)

      # Lose focus
      Focus.Tracker.set_focus(tracker, false)

      # Both should happen
      assert_receive :autosave, @default_timeout
      assert Focus.Tracker.paused?(tracker)
    end
  end

  describe "cross-system integration" do
    test "executes shortcut with command execution workflow" do
      registry = start_supervised!(Shortcut)
      executor = start_supervised!(Executor)

      # Register shortcut that returns a command
      Shortcut.register(registry, %Shortcut{
        key: :r,
        modifiers: [:ctrl],
        action: {:command, Command.timer(10, :refreshed)},
        description: "Refresh"
      })

      # Match shortcut
      event = Event.key(:r, modifiers: [:ctrl])
      {:ok, shortcut} = Shortcut.match(registry, event)

      # Execute shortcut returns command
      {:execute_command, cmd} = Shortcut.execute(shortcut)

      # Execute command
      Executor.execute(executor, cmd, self(), :app)

      # Receive command result
      assert_receive {:command_result, :app, _ref, :refreshed}, @eventual_timeout
    end

    test "mouse click triggers shortcut-like action via routing" do
      components = %{
        save_button: %{bounds: %{x: 10, y: 10, width: 80, height: 30}, z_index: 0}
      }

      # Click on button
      event = Event.mouse(:click, :left, 50, 25)
      {component_id, local_event} = MouseRouter.route(components, event)

      assert component_id == :save_button
      assert local_event.action == :click

      # Component could register a shortcut or handle the click directly
      # This demonstrates routing working with events
    end

    test "focus change affects shortcut scope matching" do
      registry = start_supervised!(Shortcut)
      _tracker = start_supervised!({Focus.Tracker, initial_focus: true})

      # Register component-scoped shortcut
      Shortcut.register(registry, %Shortcut{
        key: :enter,
        modifiers: [],
        action: {:function, fn -> :submit end},
        scope: {:component, :form}
      })

      event = Event.key(:enter)

      # When form is focused, shortcut matches
      context = %{focused_component: :form}
      assert {:ok, _} = Shortcut.match(registry, event, context)

      # When something else is focused, shortcut doesn't match
      context = %{focused_component: :list}
      assert :no_match = Shortcut.match(registry, event, context)
    end
  end

  describe "event propagation and transformation" do
    # Test component that handles events
    defmodule HandlingComponent do
      use GenServer

      def start_link(opts) do
        test_pid = Keyword.fetch!(opts, :test_pid)
        id = Keyword.fetch!(opts, :id)
        GenServer.start_link(__MODULE__, %{test_pid: test_pid, id: id})
      end

      @impl true
      def init(state), do: {:ok, state}

      @impl true
      def handle_call({:event, event}, _from, state) do
        send(state.test_pid, {:handled_by, state.id, event})
        {:reply, :handled, state}
      end
    end

    # Test component that bubbles events
    defmodule BubblingComponent do
      use GenServer

      def start_link(opts) do
        test_pid = Keyword.fetch!(opts, :test_pid)
        id = Keyword.fetch!(opts, :id)
        GenServer.start_link(__MODULE__, %{test_pid: test_pid, id: id})
      end

      @impl true
      def init(state), do: {:ok, state}

      @impl true
      def handle_call({:event, event}, _from, state) do
        send(state.test_pid, {:bubbled_through, state.id, event})
        {:reply, :unhandled, state}
      end
    end

    setup do
      start_supervised!(ComponentRegistry)
      :ok
    end

    test "event bubbles through component hierarchy until handled" do
      {:ok, button_pid} = BubblingComponent.start_link(test_pid: self(), id: :button)
      {:ok, panel_pid} = BubblingComponent.start_link(test_pid: self(), id: :panel)
      {:ok, root_pid} = HandlingComponent.start_link(test_pid: self(), id: :root)

      :ok = ComponentRegistry.register(:button, button_pid, BubblingComponent)
      :ok = ComponentRegistry.register(:panel, panel_pid, BubblingComponent)
      :ok = ComponentRegistry.register(:root, root_pid, HandlingComponent)

      :ok = Propagation.set_parent(:button, :panel)
      :ok = Propagation.set_parent(:panel, :root)
      :ok = Propagation.set_parent(:root, nil)

      event = Event.key(:enter)
      assert :handled = Propagation.bubble(event, :button)

      # Event should bubble through all components in order
      assert_receive {:bubbled_through, :button, ^event}
      assert_receive {:bubbled_through, :panel, ^event}
      assert_receive {:handled_by, :root, ^event}
    end

    test "mouse event transforms coordinates through routing and propagation" do
      components = %{
        button: %{bounds: %{x: 50, y: 30, width: 100, height: 40}, z_index: 0}
      }

      # Global mouse click
      event = Event.mouse(:click, :left, 75, 45)

      # Route to component
      {component_id, local_event} = MouseRouter.route(components, event)

      assert component_id == :button
      assert local_event.x == 25
      assert local_event.y == 15

      # Transform with metadata for routing
      envelope = Transformation.envelope(local_event, source: :terminal, target: :button)

      assert Transformation.get_metadata(envelope, :source) == :terminal
      assert Transformation.get_metadata(envelope, :target) == :button
    end

    test "event filtering finds matching events from batch" do
      events = [
        Event.key(:a),
        Event.key(:c, modifiers: [:ctrl]),
        Event.mouse(:click, :left, 10, 20),
        Event.key(:v, modifiers: [:ctrl])
      ]

      # Filter for Ctrl+key combinations
      ctrl_keys = Transformation.filter(events, type: :key, modifiers_all: [:ctrl])

      assert length(ctrl_keys) == 2
      assert Enum.all?(ctrl_keys, fn e -> :ctrl in e.modifiers end)
    end

    test "coordinate transformation roundtrip preserves position" do
      bounds = %{x: 100, y: 50, width: 200, height: 100}

      # Create event at screen coordinates
      original = Event.mouse(:click, :left, 150, 80)

      # Transform to local coordinates
      local = Transformation.to_local(original, bounds)
      assert local.x == 50
      assert local.y == 30

      # Transform back to screen
      screen = Transformation.to_screen(local, bounds)
      assert screen.x == original.x
      assert screen.y == original.y
    end
  end

  # Helper Functions

  defp receive_results_with_ref(count, timeout) do
    receive_results_with_ref(count, timeout, [])
  end

  defp receive_results_with_ref(0, _timeout, acc), do: Enum.reverse(acc)

  defp receive_results_with_ref(count, timeout, acc) do
    receive do
      {:command_result, component, _ref, result} ->
        receive_results_with_ref(count - 1, timeout, [{component, result} | acc])
    after
      timeout -> Enum.reverse(acc)
    end
  end
end
