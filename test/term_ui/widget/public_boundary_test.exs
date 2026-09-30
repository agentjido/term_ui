defmodule TermUI.Widget.PublicBoundaryTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame}

  alias TermUI.Widget.{
    ChartHelpers,
    ContextMenu,
    Helpers,
    LineChart,
    PickList,
    ScrollBar,
    Sparkline,
    Table,
    Toast
  }

  alias TermUI.Widget.Table.Column

  test "toast supports pointer dismissal, ignored input, and all status indicators" do
    toast = Toast.init(id: :notice, message: "Check", type: :warning)

    assert {^toast, []} = Toast.update(Event.key(:enter), toast)

    assert {dismissed, [{:dismissed, :notice}]} =
             Toast.update(Event.mouse(:release, :left, 0, 0), toast)

    refute dismissed.visible
    assert Frame.row_text(Toast.view(toast, {12, 3}), 2) =~ "! Check"

    info = Toast.init(message: "Ready", type: :info)
    assert Frame.row_text(Toast.view(info, {12, 3}), 2) =~ "i Ready"
  end

  test "table and pick list keep keyboard and zero-height boundaries safe" do
    key = make_ref()
    table = Table.init(columns: [Column.new(key, "Value")], rows: [%{}], page_size: 1)

    assert {^table, []} = Table.update(Event.key(:up), table)
    assert {^table, []} = Table.update(Event.focus(:lost), table)
    assert {^table, []} = Table.mouse(Event.focus(:lost), table, {10, 1})
    assert {^table, []} = Table.mouse(Event.mouse(:press, :left, 0, 0), table, {10, 0})
    assert Frame.row_text(Table.view(table, {10, 2}), 2) == String.duplicate(" ", 10)

    picker = PickList.init(items: ["one", "two"])
    assert {^picker, []} = PickList.update(Event.key(:up), picker)
    assert {picker, []} = PickList.update(Event.key(:down), picker)
    assert picker.cursor == 1
    assert {^picker, []} = PickList.update(Event.focus(:lost), picker)
    assert {^picker, []} = PickList.mouse(Event.focus(:lost), picker, {10, 1})
    assert %Frame{height: 1} = PickList.view(picker, {10, 1})
  end

  test "layout helpers handle empty dimensions and scalar rows" do
    rows = ["body"]

    assert Helpers.align("text", 0, :center) == ""
    assert Helpers.border(rows, {1, 1}) == rows
    assert Helpers.normalize_row(42) == ["42"]
    assert Helpers.fit_row("body", 0) == []
    assert Helpers.page([:a, :b, :c], 1, 1) == [:b]
  end

  test "chart helpers and widgets accept empty and flat public inputs" do
    assert ChartHelpers.range([]) == {0, 1}
    assert ChartHelpers.number(1.25) == "1.25"

    empty = LineChart.init(series: [], colors: [])
    assert empty.series == []
    assert empty.colors == [:cyan]
    assert {^empty, []} = LineChart.update(Event.focus(:lost), empty)
    assert %Frame{} = LineChart.view(empty, {4, 2})

    flat = LineChart.init(series: [1, 2, 3])
    assert flat.series == [[1, 2, 3]]

    sparkline = Sparkline.init(values: [1])
    assert {^sparkline, []} = Sparkline.update(Event.focus(:lost), sparkline)
    assert Sparkline.push(sparkline, 2, 1).values == [2]
  end

  test "context menu exposes separators, messages, and overlay position" do
    state =
      ContextMenu.init(
        items: [ContextMenu.action(:open, "Open"), ContextMenu.separator()],
        position: {2, 3}
      )

    assert ContextMenu.position(state) == {2, 3}
    assert ContextMenu.move_to(state, {5, 7}).position == {5, 7}

    assert {state, []} = ContextMenu.update(Event.key(:down), state)
    assert state.menu.cursor == 0
  end

  test "scroll bar supports forward keys, ignored events, and an empty track" do
    state = ScrollBar.init(content_size: 5, viewport_size: 2)

    assert {state, [{:scrolled, 1}]} = ScrollBar.update(Event.key(:down), state)
    assert {state, [{:scrolled, 2}]} = ScrollBar.update(Event.key(:right), state)
    assert {^state, []} = ScrollBar.update(Event.focus(:lost), state)
    assert {^state, []} = ScrollBar.mouse(Event.focus(:lost), state, {1, 1})
    horizontal = %{state | orientation: :horizontal}

    assert_raise ArgumentError, ~r/frame dimensions/, fn ->
      ScrollBar.view(horizontal, {0, 1})
    end
  end
end
