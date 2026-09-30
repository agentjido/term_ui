defmodule Showcase.Pages.Overview do
  @moduledoc false

  @behaviour Showcase.Page

  alias Showcase.Layout
  alias TermUI.{Frame, Style}
  alias TermUI.Widget.{BarChart, Gauge, Progress, Sparkline, Table}
  alias TermUI.Widget.Table.Column

  @impl true
  def init do
    %{
      refreshes: 0,
      run_queue: Gauge.init(label: "Run queue", value: 0, max: 1),
      processes: Gauge.init(label: "Processes", value: 0, max: 1),
      schedulers: Progress.init(label: "Schedulers", value: 0, max: 1),
      history:
        Sparkline.init(
          label: "Run queue history",
          values: [0],
          min: 0,
          max: 100,
          style: Style.new(fg: :cyan)
        ),
      bars:
        BarChart.init(
          data: [
            %{label: "Processes", value: 0, color: :cyan},
            %{label: "Binaries", value: 0, color: :green},
            %{label: "ETS", value: 0, color: :yellow}
          ],
          min: 0,
          max: 100
        ),
      table: Table.init(columns: columns(), rows: [], row_id: :pid, page_size: 8)
    }
  end

  @impl true
  def update(event, state) do
    {table, messages} = Table.update(event, state.table)
    {%{state | table: table}, messages}
  end

  @impl true
  def view(state, {width, height} = dimensions, theme) do
    if width >= 72 and height >= 12 do
      wide_view(state, dimensions, theme)
    else
      compact_view(state, dimensions, theme)
    end
  end

  @impl true
  def help, do: "Live BEAM data. Use Up and Down to move in the process table."

  @doc false
  def set_snapshot(state, %{system: system, processes: processes}) do
    load = system.run_queue_load

    %{
      state
      | refreshes: state.refreshes + 1,
        run_queue: %{state.run_queue | value: system.run_queue, maximum: system.schedulers_online},
        processes: %{
          state.processes
          | value: system.process_count,
            maximum: system.process_limit
        },
        schedulers: %{
          state.schedulers
          | value: system.schedulers_online,
            maximum: system.schedulers
        },
        history: Sparkline.push(state.history, load, 80),
        bars: %{state.bars | data: memory_bars(system.memory)},
        table: Table.set_rows(state.table, process_rows(processes))
    }
  end

  defp wide_view(state, {width, height}, theme) do
    {left_width, right_width} = Layout.split_widths(width)
    top_height = min(max(div(height, 2), 7), 9)
    table_height = max(height - top_height - 1, 2)

    metrics =
      state
      |> metrics_frame({left_width - 2, top_height - 2})
      |> Layout.panel("Live metrics", {left_width, top_height}, active: true, theme: theme)

    trends =
      state
      |> trends_frame({right_width - 2, top_height - 2})
      |> Layout.panel("Workload", {right_width, top_height}, theme: theme)

    table =
      state.table
      |> Table.view({width - 2, table_height - 2})
      |> Layout.panel("Process snapshot", {width, table_height}, theme: theme)

    Frame.new(width, height)
    |> Frame.overlay(metrics, 1, 1)
    |> Frame.overlay(trends, left_width + 2, 1)
    |> Frame.overlay(table, 1, top_height + 2)
  end

  defp compact_view(state, {width, height}, theme) do
    metrics_height = min(6, max(height, 2))
    table_height = max(height - metrics_height, 2)

    metrics =
      state
      |> metrics_frame({max(width - 2, 1), max(metrics_height - 2, 1)})
      |> Layout.panel("Live metrics", {width, metrics_height}, active: true, theme: theme)

    table =
      state.table
      |> Table.view({max(width - 2, 1), max(table_height - 2, 1)})
      |> Layout.panel("Processes", {width, table_height}, theme: theme)

    Frame.new(width, height)
    |> Frame.overlay(metrics, 1, 1)
    |> Frame.overlay(table, 1, metrics_height + 1)
  end

  defp metrics_frame(state, {width, height}) do
    Frame.new(max(width, 1), max(height, 1))
    |> Frame.overlay(Gauge.view(state.run_queue, {max(width, 1), 1}), 1, 1)
    |> Frame.overlay(
      Gauge.view(state.processes, {max(width, 1), 1}),
      1,
      min(2, max(height, 1))
    )
    |> Frame.overlay(
      Progress.view(state.schedulers, {max(width, 1), 1}),
      1,
      min(3, max(height, 1))
    )
  end

  defp trends_frame(state, {width, height}) do
    width = max(width, 1)
    height = max(height, 1)
    bar_height = max(height - 2, 1)

    Frame.new(width, height)
    |> Frame.overlay(Sparkline.view(state.history, {width, 1}), 1, 1)
    |> Frame.overlay(BarChart.view(state.bars, {width, bar_height}), 1, min(3, height))
  end

  defp columns do
    [
      Column.new(:name, "Process"),
      Column.new(:memory, "Memory", width: 10, align: :right),
      Column.new(:queue, "Queue", width: 7, align: :right),
      Column.new(:status, "Status", width: 10)
    ]
  end

  defp process_rows(processes) do
    Enum.map(processes, fn process ->
      %{
        pid: process.pid,
        name: process.name,
        memory: format_bytes(process.memory),
        queue: process.message_queue_len,
        status: to_string(process.status)
      }
    end)
  end

  defp memory_bars(memory) do
    total = max(Map.get(memory, :total, 0), 1)

    [
      %{label: "Processes", value: percentage(memory, :processes, total), color: :cyan},
      %{label: "Binaries", value: percentage(memory, :binary, total), color: :green},
      %{label: "ETS", value: percentage(memory, :ets, total), color: :yellow}
    ]
  end

  defp percentage(memory, key, total), do: round(Map.get(memory, key, 0) * 100 / total)

  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
