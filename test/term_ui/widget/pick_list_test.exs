defmodule TermUI.Widget.PickListTest do
  use ExUnit.Case, async: true

  alias TermUI.Component.RenderNode
  alias TermUI.Event
  alias TermUI.Widget.PickList

  @area %{x: 0, y: 0, width: 60, height: 20}
  @items ["Apple", "Banana", "Cherry", "Date", "Elderberry", "Fig", "Grape"]

  describe "init/1" do
    test "initializes with default values" do
      {:ok, state} = PickList.init(%{})

      assert state.selected_index == 0
      assert state.scroll_offset == 0
      assert state.filter_text == ""
      assert state.filtered_items == []
      assert state.original_items == []
    end

    test "stores items from props" do
      {:ok, state} = PickList.init(%{items: @items})

      assert state.original_items == @items
      assert state.filtered_items == @items
    end

    test "stores props in state" do
      props = %{items: @items, title: "Select Item"}
      {:ok, state} = PickList.init(props)

      assert state.props == props
    end
  end

  describe "handle_event/2 navigation" do
    test "down key moves selection down" do
      {:ok, state} = PickList.init(%{items: @items})
      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :down}, state)

      assert new_state.selected_index == 1
    end

    test "up key moves selection up" do
      {:ok, state} = PickList.init(%{items: @items})
      state = %{state | selected_index: 3}
      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :up}, state)

      assert new_state.selected_index == 2
    end

    test "up key stops at top" do
      {:ok, state} = PickList.init(%{items: @items})
      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :up}, state)

      assert new_state.selected_index == 0
    end

    test "down key stops at bottom" do
      {:ok, state} = PickList.init(%{items: @items})
      state = %{state | selected_index: 6}
      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :down}, state)

      assert new_state.selected_index == 6
    end

    test "home key moves to first item" do
      {:ok, state} = PickList.init(%{items: @items})
      state = %{state | selected_index: 5}
      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :home}, state)

      assert new_state.selected_index == 0
    end

    test "end key moves to last item" do
      {:ok, state} = PickList.init(%{items: @items})
      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :end}, state)

      assert new_state.selected_index == 6
    end

    test "page_up moves up by 10" do
      {:ok, state} = PickList.init(%{items: @items})
      state = %{state | selected_index: 6}
      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :page_up}, state)

      assert new_state.selected_index == 0
    end

    test "page_down moves down by 10" do
      {:ok, state} = PickList.init(%{items: @items})
      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :page_down}, state)

      assert new_state.selected_index == 6
    end
  end

  describe "handle_event/2 selection and cancel" do
    test "enter triggers select command with current item" do
      {:ok, state} = PickList.init(%{items: @items})
      state = %{state | selected_index: 2}
      {:ok, _state, commands} = PickList.handle_event(%Event.Key{key: :enter}, state)

      assert [{:send, _pid, {:select, "Cherry"}}] = commands
    end

    test "enter does nothing on empty list" do
      {:ok, state} = PickList.init(%{items: []})
      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :enter}, state)

      assert new_state == state
    end

    test "escape triggers cancel command" do
      {:ok, state} = PickList.init(%{items: @items})
      {:ok, _state, commands} = PickList.handle_event(%Event.Key{key: :escape}, state)

      assert [{:send, _pid, :cancel}] = commands
    end
  end

  describe "handle_event/2 filtering" do
    test "typing adds to filter" do
      {:ok, state} = PickList.init(%{items: @items})
      {:ok, new_state} = PickList.handle_event(%Event.Key{char: "a"}, state)

      assert new_state.filter_text == "a"
    end

    test "typing filters items" do
      {:ok, state} = PickList.init(%{items: @items})
      {:ok, new_state} = PickList.handle_event(%Event.Key{char: "a"}, state)

      # Items containing "a": Apple, Banana, Date, Grape
      assert length(new_state.filtered_items) == 4
      assert "Apple" in new_state.filtered_items
      assert "Banana" in new_state.filtered_items
    end

    test "filter is case insensitive" do
      {:ok, state} = PickList.init(%{items: @items})
      {:ok, new_state} = PickList.handle_event(%Event.Key{char: "A"}, state)

      assert length(new_state.filtered_items) == 4
    end

    test "backspace removes from filter" do
      {:ok, state} = PickList.init(%{items: @items})
      state = %{state | filter_text: "ap", filtered_items: ["Apple", "Grape"]}
      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :backspace}, state)

      assert new_state.filter_text == "a"
    end

    test "backspace on empty filter does nothing" do
      {:ok, state} = PickList.init(%{items: @items})
      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :backspace}, state)

      assert new_state == state
    end

    test "filter resets selection to 0" do
      {:ok, state} = PickList.init(%{items: @items})
      state = %{state | selected_index: 5}
      {:ok, new_state} = PickList.handle_event(%Event.Key{char: "c"}, state)

      assert new_state.selected_index == 0
    end
  end

  describe "handle_info/2" do
    test "select message invokes callback" do
      test_pid = self()
      callback = fn item -> send(test_pid, {:selected, item}) end
      props = %{items: @items, on_select: callback}
      {:ok, state} = PickList.init(props)

      {:ok, _state} = PickList.handle_info({:select, "Cherry"}, state)
      assert_receive {:selected, "Cherry"}
    end

    test "cancel message invokes callback" do
      test_pid = self()
      callback = fn -> send(test_pid, :cancelled) end
      props = %{items: @items, on_cancel: callback}
      {:ok, state} = PickList.init(props)

      {:ok, _state} = PickList.handle_info(:cancel, state)
      assert_receive :cancelled
    end

    test "set_items updates items and reapplies filter" do
      {:ok, state} = PickList.init(%{items: @items})
      state = %{state | filter_text: "b", filtered_items: ["Banana"]}

      {:ok, new_state} =
        PickList.handle_info({:set_items, ["Blueberry", "Blackberry", "Apple"]}, state)

      assert new_state.original_items == ["Blueberry", "Blackberry", "Apple"]
      # Filter "b" applied
      assert "Blueberry" in new_state.filtered_items
      assert "Blackberry" in new_state.filtered_items
      refute "Apple" in new_state.filtered_items
    end
  end

  describe "render/2" do
    test "renders border with title" do
      props = %{items: @items, title: "Select Item", width: 40, height: 10}
      {:ok, state} = PickList.init(props)
      result = PickList.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result
      assert cells != []

      # Check title is rendered
      all_chars = Enum.map_join(cells, "", & &1.cell.char)
      assert String.contains?(all_chars, "Select Item")
    end

    test "renders items" do
      props = %{items: @items, width: 40, height: 10}
      {:ok, state} = PickList.init(props)
      result = PickList.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result

      all_chars = Enum.map_join(cells, "", & &1.cell.char)
      assert String.contains?(all_chars, "Apple")
    end

    test "renders status line with item count" do
      props = %{items: @items, width: 40, height: 10}
      {:ok, state} = PickList.init(props)
      result = PickList.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result

      all_chars = Enum.map_join(cells, "", & &1.cell.char)
      assert String.contains?(all_chars, "Item 1 of 7")
    end

    test "renders empty list message" do
      props = %{items: [], width: 40, height: 10}
      {:ok, state} = PickList.init(props)
      result = PickList.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result

      all_chars = Enum.map_join(cells, "", & &1.cell.char)
      assert String.contains?(all_chars, "No items")
    end

    test "renders filter line when filtering" do
      props = %{items: @items, width: 40, height: 10}
      {:ok, state} = PickList.init(props)
      state = %{state | filter_text: "ap", filtered_items: ["Apple", "Grape"]}
      result = PickList.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result

      all_chars = Enum.map_join(cells, "", & &1.cell.char)
      assert String.contains?(all_chars, "Filter: ap")
    end

    test "highlights selected item" do
      props = %{items: @items, width: 40, height: 10, highlight_style: %{fg: :black, bg: :white}}
      {:ok, state} = PickList.init(props)
      state = %{state | selected_index: 2}
      result = PickList.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result

      # Find cells for "Cherry" and check they have highlight style
      cherry_cells =
        cells
        |> Enum.filter(fn c -> c.cell.char == "C" and c.cell.bg == :white end)

      assert cherry_cells != []
    end

    test "centers modal in area" do
      props = %{items: @items, width: 40, height: 10}
      {:ok, state} = PickList.init(props)
      result = PickList.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result

      # Modal should be centered: x = (60 - 40) / 2 = 10
      min_x = Enum.min_by(cells, & &1.x).x
      assert min_x == 10

      # Modal should be centered: y = (20 - 10) / 2 = 5
      min_y = Enum.min_by(cells, & &1.y).y
      assert min_y == 5
    end
  end

  describe "scroll behavior" do
    test "adjusts scroll when navigating down past visible area" do
      # Use smaller height to test scrolling
      props = %{items: @items, width: 40, height: 6}
      {:ok, state} = PickList.init(props)

      # Navigate down through items
      state = %{state | selected_index: 5}
      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :down}, state)

      # Should have scrolled
      assert new_state.scroll_offset > 0
    end

    test "adjusts scroll when navigating up past visible area" do
      props = %{items: @items, width: 40, height: 6}
      {:ok, state} = PickList.init(props)
      state = %{state | selected_index: 1, scroll_offset: 2}

      {:ok, new_state} = PickList.handle_event(%Event.Key{key: :up}, state)

      assert new_state.scroll_offset == 0
    end
  end
end
