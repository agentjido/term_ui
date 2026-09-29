defmodule TermUI.Widgets.CommandPaletteTest do
  use ExUnit.Case, async: true

  alias TermUI.Theme

  setup do
    # Start Theme server for color support (ignore if already started)
    case Theme.start_link(theme: :dark) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    :ok
  end

  alias TermUI.Event
  alias TermUI.Widgets.CommandPalette

  @default_area %{width: 80, height: 24}

  defp sample_commands do
    [
      %{id: :save, label: "Save File", action: fn -> :saved end},
      %{id: :open, label: "Open File", action: fn -> :opened end},
      %{id: :close, label: "Close Tab", action: fn -> :closed end},
      %{id: :quit, label: "Quit", action: fn -> :quit end},
      %{id: :help, label: "Help", action: fn -> :help end}
    ]
  end

  describe "new/1 and init/1" do
    test "creates palette with commands" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      assert length(state.commands) == 5
      assert state.visible == true
      assert state.query == ""
      assert state.selected == 0
    end

    test "initializes with custom options" do
      props =
        CommandPalette.new(
          commands: sample_commands(),
          max_visible: 3
        )

      {:ok, state} = CommandPalette.init(props)

      assert state.max_visible == 3
    end

    test "defaults max_visible" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      assert state.max_visible == 8
    end
  end

  describe "visibility" do
    test "show makes palette visible" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)
      state = CommandPalette.hide(state)

      assert CommandPalette.visible?(state) == false

      state = CommandPalette.show(state)
      assert CommandPalette.visible?(state) == true
    end

    test "hide makes palette invisible" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      state = CommandPalette.hide(state)
      assert CommandPalette.visible?(state) == false
    end

    test "toggle flips visibility" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      assert CommandPalette.visible?(state) == true
      state = CommandPalette.toggle(state)
      assert CommandPalette.visible?(state) == false
      state = CommandPalette.toggle(state)
      assert CommandPalette.visible?(state) == true
    end

    test "show resets query and selection" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      # Type something and navigate
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "s"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :down}, state)

      assert state.query == "s"
      assert state.selected > 0 or length(state.filtered) < 5

      # Hide and show again
      state = CommandPalette.hide(state)
      state = CommandPalette.show(state)

      assert state.query == ""
      assert state.selected == 0
    end
  end

  describe "keyboard navigation" do
    test "down arrow moves selection down" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      assert state.selected == 0

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :down}, state)
      assert state.selected == 1

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :down}, state)
      assert state.selected == 2
    end

    test "up arrow moves selection up" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :down}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :down}, state)
      assert state.selected == 2

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :up}, state)
      assert state.selected == 1
    end

    test "selection doesn't go below 0" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :up}, state)
      assert state.selected == 0
    end

    test "selection doesn't exceed command count" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      # Move down past the end
      Enum.reduce(1..10, state, fn _, s ->
        {:ok, new_state} = CommandPalette.handle_event(%Event.Key{key: :down}, s)
        new_state
      end)
      |> then(fn state ->
        assert state.selected == 4
      end)
    end

    test "escape closes palette" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      assert CommandPalette.visible?(state) == true

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :escape}, state)
      assert CommandPalette.visible?(state) == false
    end

    test "enter selects command and closes palette" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :enter}, state)
      assert CommandPalette.visible?(state) == false
      # Command label should be in query
      assert CommandPalette.get_query(state) == "Save File"
    end
  end

  describe "text input" do
    test "typing filters commands" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "s"}, state)
      assert state.query == "s"
      # Should filter to commands containing 's'
      assert length(state.filtered) < 5
    end

    test "backspace removes character" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "a"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "b"}, state)
      assert state.query == "ab"

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :backspace}, state)
      assert state.query == "a"
    end

    test "backspace on empty query does nothing" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :backspace}, state)
      assert state.query == ""
    end
  end

  describe "fuzzy search" do
    test "exact match is found" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "Q"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "u"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "i"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "t"}, state)

      assert state.filtered != []
      assert Enum.any?(state.filtered, &(&1.id == :quit))
    end

    test "prefix match works" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "S"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "a"}, state)

      assert Enum.any?(state.filtered, &(&1.id == :save))
    end

    test "partial match works" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "F"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "i"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "l"}, state)

      # "File" appears in "Save File", "Open File"
      assert length(state.filtered) >= 2
    end

    test "no match returns empty" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "x"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "y"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "z"}, state)

      assert state.filtered == []
    end

    test "empty query shows all commands" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      assert length(state.filtered) == 5
    end
  end

  describe "get_selected/1" do
    test "returns selected command" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      cmd = CommandPalette.get_selected(state)
      assert cmd.id == :save
    end

    test "returns nil when no commands" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      # Filter to no results
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "z"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "z"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "z"}, state)

      assert CommandPalette.get_selected(state) == nil
    end

    test "returns correct command after navigation" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :down}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: :down}, state)

      cmd = CommandPalette.get_selected(state)
      assert cmd.id == :close
    end
  end

  describe "get_query/1" do
    test "returns current query" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      assert CommandPalette.get_query(state) == ""

      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "t"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "e"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "s"}, state)
      {:ok, state} = CommandPalette.handle_event(%Event.Key{key: "t"}, state)

      assert CommandPalette.get_query(state) == "test"
    end
  end

  describe "render/2" do
    test "returns empty when not visible" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)
      state = CommandPalette.hide(state)

      result = CommandPalette.render(state, @default_area)
      assert result.type == :empty
    end

    test "returns render tree when visible" do
      props = CommandPalette.new(commands: sample_commands())
      {:ok, state} = CommandPalette.init(props)

      result = CommandPalette.render(state, @default_area)
      assert is_list(result) or is_map(result)
    end
  end

  describe "scroll" do
    test "scrolls when selection moves past visible area" do
      commands =
        for i <- 1..20 do
          %{id: :"cmd_#{i}", label: "Command #{i}", action: fn -> i end}
        end

      props = CommandPalette.new(commands: commands, max_visible: 5)
      {:ok, state} = CommandPalette.init(props)

      assert state.scroll == 0

      # Move down past visible area
      state =
        Enum.reduce(1..6, state, fn _, s ->
          {:ok, new_state} = CommandPalette.handle_event(%Event.Key{key: :down}, s)
          new_state
        end)

      assert state.scroll > 0
    end
  end
end
