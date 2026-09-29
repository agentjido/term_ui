defmodule TermUI.Integration.TestingFrameworkTest do
  # async: true because test utilities are stateless and create isolated resources
  use ExUnit.Case, async: true
  use TermUI.Test.Assertions

  alias TermUI.Event
  alias TermUI.Renderer.Cell
  alias TermUI.Test.{ComponentHarness, EventSimulator, TestRenderer}
  alias TermUI.Test.Components.{Counter, Label, TextInput}

  # Ensure modules are loaded for function_exported? checks in ComponentHarness
  Code.ensure_loaded!(Counter)
  Code.ensure_loaded!(TextInput)
  Code.ensure_loaded!(Label)

  describe "test renderer accuracy" do
    test "captures text content correctly" do
      {:ok, renderer} = TestRenderer.new(10, 40)

      # Write multiple strings
      TestRenderer.write_string(renderer, 1, 1, "Hello")
      TestRenderer.write_string(renderer, 2, 1, "World")
      TestRenderer.write_string(renderer, 3, 5, "Offset")

      # Verify content
      assert TestRenderer.get_text_at(renderer, 1, 1, 5) == "Hello"
      assert TestRenderer.get_text_at(renderer, 2, 1, 5) == "World"
      assert TestRenderer.get_text_at(renderer, 3, 5, 6) == "Offset"

      # Verify row retrieval
      row1 = TestRenderer.get_row_text(renderer, 1)
      assert String.starts_with?(row1, "Hello")

      TestRenderer.destroy(renderer)
    end

    test "captures styles correctly" do
      {:ok, renderer} = TestRenderer.new(10, 40)

      # Set cells with different styles
      TestRenderer.set_cell(renderer, 1, 1, Cell.new("R", fg: :red))
      TestRenderer.set_cell(renderer, 1, 2, Cell.new("G", fg: :green, attrs: [:bold]))
      TestRenderer.set_cell(renderer, 1, 3, Cell.new("B", fg: :blue, bg: :white))

      # Verify styles
      style1 = TestRenderer.get_style_at(renderer, 1, 1)
      assert style1.fg == :red

      style2 = TestRenderer.get_style_at(renderer, 1, 2)
      assert style2.fg == :green
      assert MapSet.member?(style2.attrs, :bold)

      style3 = TestRenderer.get_style_at(renderer, 1, 3)
      assert style3.fg == :blue
      assert style3.bg == :white

      TestRenderer.destroy(renderer)
    end

    test "snapshot comparison detects changes" do
      {:ok, renderer} = TestRenderer.new(5, 20)
      TestRenderer.write_string(renderer, 1, 1, "Initial")

      # Take snapshot
      snapshot = TestRenderer.snapshot(renderer)

      # Verify match
      assert TestRenderer.matches_snapshot?(renderer, snapshot)

      # Modify buffer
      TestRenderer.write_string(renderer, 1, 1, "Changed")

      # Should not match
      refute TestRenderer.matches_snapshot?(renderer, snapshot)

      # Get diffs
      diffs = TestRenderer.diff_snapshot(renderer, snapshot)
      assert diffs != []

      TestRenderer.destroy(renderer)
    end

    test "finds text in buffer" do
      {:ok, renderer} = TestRenderer.new(10, 40)

      TestRenderer.write_string(renderer, 3, 10, "Error: Something went wrong")
      TestRenderer.write_string(renderer, 7, 5, "Another Error here")

      # Find all occurrences
      positions = TestRenderer.find_text(renderer, "Error")
      assert length(positions) == 2

      # Verify positions
      assert {3, 10} in positions
      assert {7, 13} in positions

      TestRenderer.destroy(renderer)
    end
  end

  describe "event simulation produces expected changes" do
    test "key events have correct structure" do
      event = EventSimulator.simulate_key(:enter)
      assert %Event.Key{} = event
      assert event.key == :enter
      assert event.modifiers == []

      event = EventSimulator.simulate_key(:c, modifiers: [:ctrl])
      assert :ctrl in event.modifiers

      event = EventSimulator.simulate_key(:a, char: "a")
      assert event.char == "a"
    end

    test "mouse events have correct coordinates" do
      event = EventSimulator.simulate_click(15, 20)
      assert %Event.Mouse{} = event
      assert event.x == 15
      assert event.y == 20
      assert event.action == :click
      assert event.button == :left

      event = EventSimulator.simulate_click(10, 5, :right)
      assert event.button == :right
    end

    test "type simulation creates character sequence" do
      events = EventSimulator.simulate_type("Hello")
      assert length(events) == 5

      # Verify characters
      chars = Enum.map(events, & &1.char)
      assert chars == ["H", "e", "l", "l", "o"]

      # Capital H should have shift
      first = hd(events)
      assert :shift in first.modifiers
    end

    test "shortcuts create correct key combinations" do
      # Copy
      event = EventSimulator.simulate_shortcut(:copy)
      assert event.key == :c
      assert :ctrl in event.modifiers

      # Undo
      event = EventSimulator.simulate_shortcut(:undo)
      assert event.key == :z
      assert :ctrl in event.modifiers

      # Redo
      event = EventSimulator.simulate_shortcut(:redo)
      assert event.key == :z
      assert :ctrl in event.modifiers
      assert :shift in event.modifiers
    end

    test "event sequence maintains order" do
      events = EventSimulator.simulate_sequence([:tab, :down, :down, :enter])
      assert length(events) == 4

      keys = Enum.map(events, & &1.key)
      assert keys == [:tab, :down, :down, :enter]
    end
  end

  describe "assertions detect conditions" do
    test "text assertions work correctly" do
      {:ok, renderer} = TestRenderer.new(10, 40)
      TestRenderer.write_string(renderer, 1, 1, "Success")

      # Should pass
      assert_text(renderer, 1, 1, "Success")
      assert_text_contains(renderer, 1, 1, 10, "cess")
      assert_text_exists(renderer, "Success")

      # Negative assertions should pass
      refute_text(renderer, 1, 1, "Failure")
      refute_text_exists(renderer, "Failure")

      TestRenderer.destroy(renderer)
    end

    test "style assertions work correctly" do
      {:ok, renderer} = TestRenderer.new(10, 40)
      cell = Cell.new("X", fg: :red, bg: :blue, attrs: [:bold])
      TestRenderer.set_cell(renderer, 1, 1, cell)

      # Should pass
      assert_style(renderer, 1, 1, fg: :red)
      assert_style(renderer, 1, 1, bg: :blue)
      assert_style(renderer, 1, 1, attrs: [:bold])
      assert_attr(renderer, 1, 1, :bold)

      # Negative assertions
      refute_attr(renderer, 1, 1, :italic)

      TestRenderer.destroy(renderer)
    end

    test "state assertions work correctly" do
      state = %{
        user: %{
          name: "Alice",
          age: 30
        },
        items: [1, 2, 3]
      }

      # Should pass
      assert_state(state, [:user, :name], "Alice")
      assert_state(state, [:user, :age], 30)
      assert_state(state, [:items], [1, 2, 3])
      assert_state_exists(state, [:user])

      # Negative assertions
      refute_state(state, [:user, :name], "Bob")
    end

    test "snapshot assertions work correctly" do
      {:ok, renderer} = TestRenderer.new(5, 20)
      TestRenderer.write_string(renderer, 1, 1, "Test")
      snapshot = TestRenderer.snapshot(renderer)

      # Should pass - buffer unchanged
      assert_snapshot(renderer, snapshot)

      TestRenderer.destroy(renderer)
    end

    test "assertions produce clear error messages" do
      {:ok, renderer} = TestRenderer.new(5, 20)
      TestRenderer.write_string(renderer, 1, 1, "Actual")

      # Verify assertion raises with useful message
      assert_raise ExUnit.AssertionError, ~r/Text assertion failed/, fn ->
        assert_text(renderer, 1, 1, "Expected")
      end

      TestRenderer.destroy(renderer)
    end
  end

  describe "component harness isolates components" do
    test "mounts component with initial state" do
      {:ok, harness} = ComponentHarness.mount_test(Counter, initial: 5)

      assert harness.module == Counter
      assert ComponentHarness.get_state(harness) == %{count: 5}

      ComponentHarness.unmount(harness)
    end

    test "renders component to buffer" do
      {:ok, harness} = ComponentHarness.mount_test(Counter, initial: 10)
      harness = ComponentHarness.render(harness)

      renderer = ComponentHarness.get_renderer(harness)
      assert TestRenderer.text_at?(renderer, 1, 1, "Count: 10")

      ComponentHarness.unmount(harness)
    end

    test "processes events and updates state" do
      {:ok, harness} = ComponentHarness.mount_test(Counter, initial: 0)

      # Send events
      harness = ComponentHarness.send_event(harness, Event.key(:up))
      assert ComponentHarness.get_state(harness) == %{count: 1}

      harness = ComponentHarness.send_event(harness, Event.key(:up))
      assert ComponentHarness.get_state(harness) == %{count: 2}

      harness = ComponentHarness.send_event(harness, Event.key(:down))
      assert ComponentHarness.get_state(harness) == %{count: 1}

      ComponentHarness.unmount(harness)
    end

    test "tracks event history" do
      {:ok, harness} = ComponentHarness.mount_test(Counter)

      harness = ComponentHarness.send_event(harness, Event.key(:up))
      harness = ComponentHarness.send_event(harness, Event.key(:down))

      events = ComponentHarness.get_events(harness)
      assert length(events) == 2

      ComponentHarness.unmount(harness)
    end

    test "resets to initial state" do
      {:ok, harness} = ComponentHarness.mount_test(Counter, initial: 0)

      # Modify state
      harness = ComponentHarness.send_event(harness, Event.key(:up))
      harness = ComponentHarness.render(harness)
      assert ComponentHarness.get_state(harness) == %{count: 1}

      # Reset
      {:ok, harness} = ComponentHarness.reset(harness)
      assert ComponentHarness.get_state(harness) == %{count: 0}
      assert ComponentHarness.get_events(harness) == []
      assert ComponentHarness.get_renders(harness) == []

      ComponentHarness.unmount(harness)
    end

    test "complete test workflow" do
      # This demonstrates a typical test workflow
      {:ok, harness} = ComponentHarness.mount_test(Counter, initial: 0)

      # Initial render
      harness = ComponentHarness.render(harness)
      renderer = ComponentHarness.get_renderer(harness)
      assert_text(renderer, 1, 1, "Count: 0")

      # Simulate user interaction
      harness = ComponentHarness.event_cycle(harness, Event.key(:up))
      harness = ComponentHarness.event_cycle(harness, Event.key(:up))
      harness = ComponentHarness.event_cycle(harness, Event.key(:up))

      # Verify final state
      assert ComponentHarness.get_state(harness) == %{count: 3}
      assert_text(renderer, 1, 1, "Count: 3")

      ComponentHarness.unmount(harness)
    end
  end

  describe "integration between test utilities" do
    test "event simulator works with component harness" do
      {:ok, harness} = ComponentHarness.mount_test(TextInput)

      # Use event simulator to type text
      events = EventSimulator.simulate_type("hello")
      harness = ComponentHarness.send_events(harness, events)

      assert ComponentHarness.get_state(harness).text == "hello"

      ComponentHarness.unmount(harness)
    end

    test "assertions work with harness renderer" do
      {:ok, harness} = ComponentHarness.mount_test(Label, text: "Important")
      harness = ComponentHarness.render(harness)

      renderer = ComponentHarness.get_renderer(harness)

      # Use assertions
      assert_text(renderer, 1, 1, "Important")
      assert_text_exists(renderer, "Important")
      refute_text_exists(renderer, "Missing")

      ComponentHarness.unmount(harness)
    end
  end
end
