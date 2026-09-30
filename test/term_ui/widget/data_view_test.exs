defmodule TermUI.Widget.DataViewTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame}
  alias TermUI.Widget.{ClusterDashboard, ProcessMonitor, Table}
  alias TermUI.Widget.Table.Column

  test "table normalizes columns and reads map, list, tuple, and fallback rows" do
    table =
      Table.init(
        columns: [
          Column.new(:name, "Name", width: 6),
          {:count, "Count"},
          1
        ],
        rows: [
          %{"name" => "map", count: 1},
          ["zero", "list"],
          {:zero, "tuple"},
          :fallback
        ],
        page_size: 2
      )

    assert %Frame{} = Table.view(table, {30, 4})
    assert {table, []} = Table.update(Event.key(:down), table)
    assert {table, []} = Table.update(Event.key(:page_down), table)
    assert table.cursor == 3
    assert {table, []} = Table.update(Event.key(:page_up), table)
    assert table.cursor == 1
    assert {table, []} = Table.update(Event.key(:home), table)
    assert {table, []} = Table.update(Event.key(:end), table)
    assert {_table, [{:selected, :fallback}]} = Table.update(Event.key(:enter), table)

    assert {pressed, []} =
             Table.mouse(Event.mouse(:press, :left, 0, 1), table, {30, 4})

    assert pressed.cursor >= 0
    assert {^table, []} = Table.mouse(Event.mouse(:release, :left, 0, 0), table, {30, 4})

    table = Table.set_rows(table, [])
    assert table.cursor == 0
    assert {^table, []} = Table.update(Event.key(:enter), table)

    without_header = Table.init(columns: [:value], rows: [["one"]], show_header: false)

    assert {_table, [{:selected, ["one"]}]} =
             Table.mouse(Event.mouse(:release, :left, 0, 0), without_header, {10, 1})
  end

  test "table handles sparse tuple and map data without losing false values" do
    table =
      Table.init(
        columns: [
          Column.new(2, "Missing", width: 8),
          Column.new(-1, "Negative", width: 8),
          Column.new(:enabled, "Enabled", width: 8),
          Column.new({:compound, :key}, "Compound", width: 8)
        ],
        rows: [
          {:only},
          %{{:compound, :key} => "ok", enabled: false},
          %{{:compound, :key} => %{value: 2}, enabled: {:ok, 1}}
        ]
      )

    frame = Table.view(table, {45, 4})

    assert Frame.row_text(frame, 3) =~ "false"
    assert Frame.row_text(frame, 3) =~ "ok"
    assert Frame.row_text(frame, 4) =~ "{:ok, 1}"
    assert Frame.row_text(frame, 4) =~ "%{value:"
  end

  test "process monitor sorts snapshots without inspecting processes" do
    snapshots = [
      %{pid: "<0.1.0>", memory: 10, reductions: 20, message_queue_len: 1},
      %{pid: "<0.2.0>", name: :worker, memory: 30, reductions: 5, message_queue_len: 9}
    ]

    monitor = ProcessMonitor.init(snapshots: snapshots)
    assert hd(monitor.table.rows).memory == 30
    assert %Frame{} = ProcessMonitor.view(monitor, {60, 4})
    assert {^monitor, [:refresh_requested]} = ProcessMonitor.update(Event.text("r"), monitor)

    assert {monitor, [{:sorted, :memory, false}]} =
             ProcessMonitor.update(Event.text("m"), monitor)

    assert hd(monitor.table.rows).memory == 10

    assert {monitor, [{:sorted, :message_queue_len, true}]} =
             ProcessMonitor.update(Event.text("q"), monitor)

    assert hd(monitor.table.rows).message_queue_len == 9

    assert {monitor, [{:sorted, :reductions, true}]} =
             ProcessMonitor.update(Event.text("c"), monitor)

    assert hd(monitor.table.rows).reductions == 20
    monitor = ProcessMonitor.set_snapshots(monitor, Enum.reverse(snapshots))
    assert length(monitor.snapshots) == 2

    assert {_monitor, [{:selected, _snapshot}]} =
             ProcessMonitor.update(Event.key(:enter), monitor)
  end

  test "cluster dashboard keeps refresh and help behavior in parent-owned state" do
    nodes = [%{node: :local, status: :up, processes: 10, memory: 20, uptime: "1m"}]
    dashboard = ClusterDashboard.init(nodes: nodes)

    assert %Frame{} = ClusterDashboard.view(dashboard, {50, 4})

    assert {^dashboard, [:refresh_requested]} =
             ClusterDashboard.update(Event.text("r"), dashboard)

    assert {_dashboard, [{:selected, %{node: :local}}]} =
             ClusterDashboard.update(Event.key(:enter), dashboard)

    dashboard = ClusterDashboard.set_nodes(dashboard, nodes ++ [%{node: :remote}])
    assert {dashboard, []} = ClusterDashboard.update(Event.key(:end), dashboard)
    assert dashboard.table.cursor == 1

    assert {dashboard, [{:focused, %{id: :help}}]} =
             ClusterDashboard.update(Event.key(:right), dashboard)

    assert {dashboard, [{:selected, :help}]} =
             ClusterDashboard.update(Event.key(:enter), dashboard)

    help = ClusterDashboard.view(dashboard, {30, 4})
    assert Frame.row_text(help, 1) =~ "Nodes"
    assert Frame.row_text(help, 2) =~ "refresh"
    assert {^dashboard, []} = ClusterDashboard.update(Event.key(:down), dashboard)

    assert {dashboard, [{:selected, :nodes}]} =
             ClusterDashboard.mouse(
               Event.mouse(:release, :left, 2, 0),
               dashboard,
               {30, 4}
             )

    assert {_dashboard, [{:selected, %{node: :local}}]} =
             ClusterDashboard.mouse(
               Event.mouse(:release, :left, 0, 2),
               dashboard,
               {30, 4}
             )

    dashboard = ClusterDashboard.set_nodes(dashboard, [])
    assert dashboard.nodes == []
    assert dashboard.table.rows == []
  end
end
