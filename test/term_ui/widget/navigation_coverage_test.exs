defmodule TermUI.Widget.NavigationCoverageTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame, Style}
  alias TermUI.Widget.{List, Viewport}

  test "list navigation keeps the cursor visible and selects public item forms" do
    items = [%{label: "map"}, {:tuple, "tuple"}, "plain", "last"]
    state = List.init(items: items, page_size: 2)

    {state, []} = List.update(Event.key(:end), state)
    assert state.cursor == 3
    assert state.offset == 2
    {state, []} = List.update(Event.key(:page_up), state)
    assert state.cursor == 1
    {state, []} = List.update(Event.key(:home), state)
    assert state.cursor == 0
    {state, []} = List.update(Event.key(:up), state)
    assert state.cursor == 0
    {state, []} = List.update(Event.key(:page_down), state)
    assert state.cursor == 2

    assert {selected, [{:selected, "plain"}]} = List.update(Event.key(:enter), state)
    assert MapSet.member?(selected.selected, 2)
    assert Frame.row_text(List.view(selected, {20, 2}), 1) =~ "tuple"
  end

  test "multiple lists toggle with key, text, and mouse" do
    state = List.init(items: ["a", "b", "c"], mode: :multiple, page_size: 2)
    {state, [{:toggled, "a"}]} = List.update(Event.key(:space), state)
    assert Frame.row_text(List.view(state, {12, 2}), 1) =~ "[x]"
    {state, [{:toggled, "a"}]} = List.update(Event.text(" "), state)
    refute MapSet.member?(state.selected, 0)

    {pressed, []} = List.mouse(Event.mouse(:press, :left, 0, 1), state, {12, 2})
    assert pressed.cursor == 1

    assert {released, [{:toggled, "b"}]} =
             List.mouse(Event.mouse(:release, :left, 0, 1), state, {12, 2})

    assert MapSet.member?(released.selected, 1)
    assert {^state, []} = List.mouse(Event.mouse(:release, :left, 0, 3), state, {12, 2})
    assert {^state, []} = List.mouse(Event.focus(:gained), state, {12, 2})
  end

  test "an empty list and replacement keep selection and cursor safe" do
    empty = List.init(items: [], mode: :multiple)
    assert {^empty, []} = List.update(Event.key(:enter), empty)
    assert {empty, []} = List.update(Event.key(:space), empty)
    assert empty.selected == MapSet.new()

    state = List.init(items: ["a", "b"], cursor: 1, mode: :multiple)
    {state, _messages} = List.update(Event.key(:space), state)
    reset = List.set_items(state, ["only"])
    assert reset.cursor == 0
    assert reset.selected == MapSet.new()
    assert List.current(reset) == "only"
  end

  test "viewport navigation, geometry, and reveal work at all edges" do
    state = Viewport.init(content: "one\ntwo\nthree\nfour", page_size: 2, scroll_x: 2)
    {state, _} = Viewport.update(Event.key(:down), state)
    {state, _} = Viewport.update(Event.key(:page_down), state)
    assert Viewport.position(state) == {2, 2}
    {state, _} = Viewport.update(Event.key(:page_up), state)
    {state, _} = Viewport.update(Event.key(:up), state)
    assert state.scroll_y == 0
    {state, _} = Viewport.update(Event.key(:left), state)
    {state, _} = Viewport.update(Event.key(:right), state)
    {state, []} = Viewport.update(Event.key(:home), state)
    assert state.scroll_x == 0
    {state, []} = Viewport.update(Event.key(:end), state)
    assert state.scroll_x == 0
    {state, []} = Viewport.update(Event.key(:end, modifiers: [:ctrl]), state)
    assert state.scroll_y == 2
    {state, []} = Viewport.update(Event.key(:home, modifiers: [:ctrl]), state)
    assert state.scroll_y == 0
    assert {^state, []} = Viewport.update(Event.focus(:gained), state)

    state = Viewport.scroll_into_view(state, {8, 3}, {4, 2})
    assert state.scroll_x > 0
    assert state.scroll_y == 2
    state = Viewport.scroll_into_view(state, {0, 0}, {4, 2})
    assert Viewport.position(state) == {0, 0}
  end

  test "viewport content forms, empty geometry, and horizontal clipping are visible" do
    empty = Viewport.init(content: [], scrollbars: false)
    assert Viewport.content_dimensions(empty) == {0, 0}
    assert %{visible_rows: nil, visible_columns: nil} = Viewport.geometry(empty, {4, 2})

    styled = [[{"界x", Style.new(fg: :red)}, "y"]]
    state = Viewport.init(content: styled, scroll_x: 1, scrollbars: true)
    assert Viewport.content_dimensions(state) == {4, 1}
    frame = Viewport.view(state, {3, 2})
    assert %Frame{} = frame
    assert frame.width == 3

    converted = Viewport.init(content: 123)
    assert Viewport.content_dimensions(converted) == {3, 1}

    assert_raise ArgumentError, ~r/viewport scrollbars must be/, fn ->
      Viewport.init(scrollbars: :invalid)
    end
  end

  test "viewport scrollbar press, drag, release, wheel, and fallback paths are deterministic" do
    state =
      Viewport.init(
        content: Enum.map_join(1..10, "\n", &"row #{&1} long"),
        page_size: 3,
        scrollbars: :both
      )

    {vertical, [{:scrolled, {_x, y}}]} =
      Viewport.mouse(Event.mouse(:press, :left, 9, 2), state, {10, 5})

    assert vertical.dragging == :vertical
    assert y > 0

    {vertical, [{:scrolled, _position}]} =
      Viewport.mouse(Event.mouse(:drag, :left, 9, 0), vertical, {10, 5})

    {released, []} = Viewport.mouse(Event.mouse(:release, :left, 9, 0), vertical, {10, 5})
    assert released.dragging == nil

    {horizontal, [{:scrolled, {x, _y}}]} =
      Viewport.mouse(Event.mouse(:press, :left, 7, 4), state, {10, 5})

    assert horizontal.dragging == :horizontal
    assert x > 0

    {wheel, _} = Viewport.mouse(Event.mouse(:scroll_down, nil, 0, 0), state, {10, 5})
    assert wheel.scroll_y == 3
    {wheel, _} = Viewport.mouse(Event.mouse(:scroll_up, nil, 0, 0), wheel, {10, 5})
    assert wheel.scroll_y == 0
    assert {^state, []} = Viewport.mouse(Event.focus(:lost), state, {10, 5})
  end

  test "follow-end content replacement moves to the latest page" do
    state = Viewport.init(content: ["old"], follow_end: true, page_size: 2)
    state = Viewport.set_content(state, ["a", "b", "c", "d"])
    assert state.scroll_y == 2
    assert Frame.row_text(Viewport.view(state, {4, 2}), 1) == "c   "
  end
end
