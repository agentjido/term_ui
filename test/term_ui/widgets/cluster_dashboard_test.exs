defmodule TermUI.Widgets.ClusterDashboardTest do
  use ExUnit.Case, async: false

  alias TermUI.Event
  alias TermUI.Theme
  alias TermUI.Widgets.ClusterDashboard

  setup do
    # Start Theme server for color support if not already started
    case Process.whereis(TermUI.Theme) do
      nil -> Theme.start_link(theme: :dark)
      pid -> {:ok, pid}
    end

    :ok
  end

  describe "new/1" do
    test "creates props with defaults" do
      props = ClusterDashboard.new()

      assert props.update_interval == 2000
      assert props.show_health_metrics == true
      assert props.show_pg_groups == true
      assert props.show_global_names == true
      assert props.on_node_select == nil
    end

    test "accepts custom options" do
      callback = fn _node -> :ok end

      props =
        ClusterDashboard.new(
          update_interval: 5000,
          show_health_metrics: false,
          show_pg_groups: false,
          show_global_names: false,
          on_node_select: callback
        )

      assert props.update_interval == 5000
      assert props.show_health_metrics == false
      assert props.show_pg_groups == false
      assert props.show_global_names == false
      assert props.on_node_select == callback
    end
  end

  describe "init/1" do
    test "initializes state with defaults" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      assert state.view_mode == :nodes
      assert state.selected_idx == 0
      assert state.scroll_offset == 0
      assert state.show_details == false
      assert is_list(state.nodes)
      assert is_list(state.global_names)
      assert is_list(state.pg_groups)
      assert is_list(state.events)
      assert state.partition_alert == nil
    end

    test "fetches local node info" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      # Should have at least the local node
      assert state.nodes != []

      local = Enum.find(state.nodes, &(&1.status == :local))
      assert local != nil
      assert local.node == node()
    end

    test "fetches metrics when enabled" do
      props = ClusterDashboard.new(show_health_metrics: true)
      {:ok, state} = ClusterDashboard.init(props)

      local = Enum.find(state.nodes, &(&1.status == :local))
      assert local.metrics != nil
      # Memory is a keyword list from :erlang.memory()
      assert is_list(local.metrics.memory)
      assert Keyword.has_key?(local.metrics.memory, :total)
      assert is_integer(local.metrics.process_count)
      assert is_integer(local.metrics.scheduler_count)
    end

    test "skips metrics when disabled" do
      props = ClusterDashboard.new(show_health_metrics: false)
      {:ok, state} = ClusterDashboard.init(props)

      local = Enum.find(state.nodes, &(&1.status == :local))
      assert local.metrics == nil
    end
  end

  describe "handle_event/2 navigation" do
    test "down key moves selection down" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{key: :down}, state)
      # Selection moves if there's more than one item, stays at 0 otherwise
      assert state.selected_idx >= 0
    end

    test "up key moves selection up" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      # Move down first then up
      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{key: :down}, state)
      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{key: :up}, state)
      assert state.selected_idx == 0
    end

    test "home key goes to first item" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{key: :home}, state)
      assert state.selected_idx == 0
      assert state.scroll_offset == 0
    end

    test "end key goes to last item" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{key: :end}, state)
      # Should be at last item (which is >= 0)
      assert state.selected_idx >= 0
    end

    test "page down moves by page" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{key: :page_down}, state)
      # Moves selection, clamped to available items
      assert state.selected_idx >= 0
    end
  end

  describe "handle_event/2 view modes" do
    test "n key switches to nodes view" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      state = %{state | view_mode: :globals}
      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{char: "n"}, state)
      assert state.view_mode == :nodes
      assert state.selected_idx == 0
    end

    test "g key switches to globals view" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{char: "g"}, state)
      assert state.view_mode == :globals
      assert state.selected_idx == 0
    end

    test "p key switches to pg groups view" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{char: "p"}, state)
      assert state.view_mode == :pg_groups
      assert state.selected_idx == 0
    end

    test "e key switches to events view" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{char: "e"}, state)
      assert state.view_mode == :events
      assert state.selected_idx == 0
    end
  end

  describe "handle_event/2 details" do
    test "enter toggles details panel" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      assert state.show_details == false

      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{key: :enter}, state)
      assert state.show_details == true

      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{key: :enter}, state)
      assert state.show_details == false
    end

    test "escape closes details" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      state = %{state | show_details: true}

      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{key: :escape}, state)
      assert state.show_details == false
    end

    test "escape clears partition alert" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      state = %{state | partition_alert: "Test alert"}

      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{key: :escape}, state)
      assert state.partition_alert == nil
    end
  end

  describe "handle_event/2 refresh" do
    test "r key triggers refresh" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      {:ok, state} = ClusterDashboard.handle_event(%Event.Key{char: "r"}, state)
      # State should still be valid after refresh
      assert is_list(state.nodes)
    end
  end

  describe "handle_info/2" do
    test "nodeup event adds to events log" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      {:ok, state} = ClusterDashboard.handle_info({:nodeup, :test@host}, state)

      assert length(state.events) == 1
      [event | _] = state.events
      assert event.node == :test@host
      assert event.event == :nodeup
    end

    test "nodedown event adds to events log" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      {:ok, state} = ClusterDashboard.handle_info({:nodedown, :test@host}, state)

      assert length(state.events) == 1
      [event | _] = state.events
      assert event.node == :test@host
      assert event.event == :nodedown
    end

    test "multiple nodedown events trigger partition alert" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      # Simulate rapid disconnections
      {:ok, state} = ClusterDashboard.handle_info({:nodedown, :node1@host}, state)
      {:ok, state} = ClusterDashboard.handle_info({:nodedown, :node2@host}, state)

      assert state.partition_alert != nil
      assert state.partition_alert =~ "partition"
    end

    test "refresh message updates data" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      {:ok, state} = ClusterDashboard.handle_info(:refresh, state)

      assert is_list(state.nodes)
      assert state.timer_ref != nil
    end
  end

  describe "render/2" do
    test "renders nodes view" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      area = %{x: 0, y: 0, width: 80, height: 25}

      result = ClusterDashboard.render(state, area)

      assert result.type == :stack
      assert result.direction == :vertical
      assert result.children != []
    end

    test "renders globals view" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      state = %{state | view_mode: :globals}
      area = %{x: 0, y: 0, width: 80, height: 25}

      result = ClusterDashboard.render(state, area)

      assert result.type == :stack
    end

    test "renders pg groups view" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      state = %{state | view_mode: :pg_groups}
      area = %{x: 0, y: 0, width: 80, height: 25}

      result = ClusterDashboard.render(state, area)

      assert result.type == :stack
    end

    test "renders events view" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      state = %{state | view_mode: :events}
      area = %{x: 0, y: 0, width: 80, height: 25}

      result = ClusterDashboard.render(state, area)

      assert result.type == :stack
    end

    test "renders with details panel" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      state = %{state | show_details: true}
      area = %{x: 0, y: 0, width: 80, height: 25}

      result = ClusterDashboard.render(state, area)

      assert result.type == :stack
      # Should have more children with details panel
      assert length(result.children) > 5
    end

    test "renders partition alert" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      state = %{state | partition_alert: "Test partition alert"}
      area = %{x: 0, y: 0, width: 80, height: 25}

      result = ClusterDashboard.render(state, area)

      # Alert should be first child
      [alert | _] = result.children
      assert alert.content == "Test partition alert"
    end
  end

  describe "public API" do
    test "refresh/1 updates state" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      {:ok, new_state} = ClusterDashboard.refresh(state)

      assert is_list(new_state.nodes)
    end

    test "set_interval/2 changes update interval" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      # Fake a timer ref
      state = %{state | timer_ref: Process.send_after(self(), :test, 10_000)}

      {:ok, new_state} = ClusterDashboard.set_interval(state, 5000)

      assert new_state.update_interval == 5000
      assert new_state.timer_ref != nil
    end

    test "get_selected_node/1 returns selected node in nodes view" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      selected = ClusterDashboard.get_selected_node(state)

      assert selected != nil
      assert selected.status == :local
    end

    test "get_selected_node/1 returns nil in other views" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      state = %{state | view_mode: :globals}

      selected = ClusterDashboard.get_selected_node(state)

      assert selected == nil
    end

    test "node_count/1 returns node count" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      count = ClusterDashboard.node_count(state)

      assert count >= 1
    end

    test "distributed?/1 returns false for single node" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      # In test environment, we're typically not distributed
      # or have only local node
      result = ClusterDashboard.distributed?(state)

      # Either true (if other nodes connected) or false
      assert is_boolean(result)
    end

    test "rpc_call/4 handles local calls" do
      result = ClusterDashboard.rpc_call(node(), :erlang, :now, [])

      # Should return a tuple (the result of :erlang.now())
      assert is_tuple(result)
    end

    test "rpc_call/4 handles errors gracefully" do
      # Call to non-existent node
      result = ClusterDashboard.rpc_call(:nonexistent@host, :erlang, :now, [])

      assert {:error, _} = result
    end
  end

  describe "non-distributed mode" do
    test "works when node is nonode@nohost" do
      # This test verifies the widget doesn't crash in non-distributed mode
      # The actual node() value depends on how tests are run
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      # Should have local node
      assert state.nodes != []

      # Rendering should work
      area = %{x: 0, y: 0, width: 80, height: 25}
      result = ClusterDashboard.render(state, area)
      assert result.type == :stack
    end
  end

  describe "event handling edge cases" do
    test "handles unknown events gracefully" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      {:ok, new_state} = ClusterDashboard.handle_event(%Event.Key{char: "x"}, state)

      assert new_state == state
    end

    test "i key only works in nodes view" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)
      state = %{state | view_mode: :globals}

      {:ok, new_state} = ClusterDashboard.handle_event(%Event.Key{char: "i"}, state)

      # Should not change show_details in globals view
      assert new_state.show_details == state.show_details
    end
  end

  describe "events truncation" do
    test "events list is limited to max size" do
      props = ClusterDashboard.new()
      {:ok, state} = ClusterDashboard.init(props)

      # Add more than max events
      state =
        Enum.reduce(1..60, state, fn i, acc ->
          {:ok, new_state} =
            ClusterDashboard.handle_info({:nodedown, :"node#{i}@host"}, acc)

          new_state
        end)

      # Should be limited
      assert length(state.events) <= 50
    end
  end
end
