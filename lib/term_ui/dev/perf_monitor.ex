defmodule TermUI.Dev.PerfMonitor do
  @moduledoc """
  Performance Monitor for development mode.

  Displays real-time performance metrics: FPS, frame time, memory usage,
  and process count. Toggle with Ctrl+Shift+P when dev mode is enabled.

  ## Metrics

  - **FPS**: Frames per second (rolling average)
  - **Frame Time**: Time to render each frame (graph)
  - **Memory**: Total BEAM memory usage
  - **Processes**: Number of BEAM processes
  """

  import TermUI.Component.Helpers

  # Dialyzer: Functions return specific map types
  @dialyzer {:nowarn_function, get_memory_breakdown: 0}

  @panel_width 35
  @graph_height 5

  @doc """
  Renders the performance monitor panel.

  Returns render nodes for the metrics display.
  """
  @spec render(map(), map()) :: term()
  def render(metrics, _area) do
    # Build panel content
    header = render_header()
    fps_line = render_fps(metrics.fps)
    frame_graph = render_frame_graph(metrics.frame_times)
    memory_line = render_memory(metrics.memory)
    process_line = render_processes(metrics.process_count)
    footer = render_footer()

    content = [header, fps_line] ++ frame_graph ++ [memory_line, process_line, footer]

    panel = stack(:vertical, content)

    # Position at bottom-left
    %{
      type: :positioned,
      content: panel,
      x: 0,
      # Will be adjusted by renderer
      y: 0,
      # Below inspectors but above content
      z: 195
    }
  end

  defp render_header do
    title = " Performance Monitor "
    remaining = @panel_width - String.length(title)
    left = div(remaining, 2)
    right = remaining - left

    text(
      "┌" <> String.duplicate("─", left - 1) <> title <> String.duplicate("─", right - 1) <> "┐"
    )
  end

  defp render_footer do
    text("└" <> String.duplicate("─", @panel_width - 2) <> "┘")
  end

  defp render_fps(fps) do
    fps_str = Float.round(fps, 1) |> to_string()
    label = "FPS: #{fps_str}"
    padded = String.pad_trailing(label, @panel_width - 4)
    text("│ " <> padded <> " │")
  end

  defp render_memory(bytes) do
    memory_str = format_bytes(bytes)
    label = "Memory: #{memory_str}"
    padded = String.pad_trailing(label, @panel_width - 4)
    text("│ " <> padded <> " │")
  end

  defp render_processes(count) do
    label = "Processes: #{count}"
    padded = String.pad_trailing(label, @panel_width - 4)
    text("│ " <> padded <> " │")
  end

  defp render_frame_graph(frame_times) when frame_times == [] do
    # Empty graph
    for _i <- 1..@graph_height do
      text("│" <> String.duplicate(" ", @panel_width - 2) <> "│")
    end
  end

  defp render_frame_graph(frame_times) do
    # Normalize frame times to graph height
    max_time = Enum.max(frame_times)
    min_time = Enum.min(frame_times)
    range = max(1, max_time - min_time)

    # Take last N frame times that fit in width
    graph_width = @panel_width - 4
    times = frame_times |> Enum.take(graph_width) |> Enum.reverse()

    # Create graph rows (top to bottom)
    for row <- (@graph_height - 1)..0//-1 do
      threshold = min_time + row / @graph_height * range

      chars =
        Enum.map_join(times, "", fn time ->
          graph_character(time, threshold)
        end)

      padded = String.pad_trailing(chars, graph_width)
      text("│ " <> padded <> " │")
    end
  end

  defp graph_character(time, threshold) when time >= threshold, do: "▄"
  defp graph_character(_time, _threshold), do: " "

  @doc """
  Formats bytes into human-readable string.
  """
  @spec format_bytes(integer()) :: String.t()
  def format_bytes(bytes) when bytes < 1024 do
    "#{bytes} B"
  end

  def format_bytes(bytes) when bytes < 1024 * 1024 do
    kb = Float.round(bytes / 1024, 1)
    "#{kb} KB"
  end

  def format_bytes(bytes) when bytes < 1024 * 1024 * 1024 do
    mb = Float.round(bytes / (1024 * 1024), 1)
    "#{mb} MB"
  end

  def format_bytes(bytes) do
    gb = Float.round(bytes / (1024 * 1024 * 1024), 2)
    "#{gb} GB"
  end

  @doc """
  Formats microseconds into human-readable string.
  """
  @spec format_time(integer()) :: String.t()
  def format_time(us) when us < 1000 do
    "#{us}μs"
  end

  def format_time(us) when us < 1_000_000 do
    ms = Float.round(us / 1000, 1)
    "#{ms}ms"
  end

  def format_time(us) do
    s = Float.round(us / 1_000_000, 2)
    "#{s}s"
  end

  @doc """
  Gets detailed BEAM memory breakdown.
  """
  @spec get_memory_breakdown() :: map()
  def get_memory_breakdown do
    %{
      total: :erlang.memory(:total),
      processes: :erlang.memory(:processes),
      atom: :erlang.memory(:atom),
      binary: :erlang.memory(:binary),
      code: :erlang.memory(:code),
      ets: :erlang.memory(:ets)
    }
  end

  @doc """
  Gets scheduler utilization.
  """
  @spec get_scheduler_utilization() :: [float()]
  def get_scheduler_utilization do
    # The :scheduler.utilization/1 function is only available in OTP 28+
    # Using apply/3 to avoid compiler warning about undefined function
    if function_exported?(:scheduler, :utilization, 1) do
      try do
        # credo:disable-for-next-line Credo.Check.Refactor.Apply
        case apply(:scheduler, :utilization, [1]) do
          [{:total, _, total} | _] -> [total]
          _ -> []
        end
      rescue
        _ -> []
      end
    else
      []
    end
  end

  @doc """
  Gets message queue length for a process.
  """
  @spec get_message_queue_length(pid()) :: integer()
  def get_message_queue_length(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> len
      _ -> 0
    end
  end

  @doc """
  Gets reduction count for a process (rough CPU usage indicator).
  """
  @spec get_reductions(pid()) :: integer()
  def get_reductions(pid) do
    case Process.info(pid, :reductions) do
      {:reductions, count} -> count
      _ -> 0
    end
  end

  @doc """
  Calculates sparkline characters for a list of values.
  """
  @spec values_to_sparkline([number()], number(), number()) :: String.t()
  def values_to_sparkline(values, min_val, max_val) do
    bars = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]
    range = max(1, max_val - min_val)

    Enum.map_join(values, "", fn value ->
      normalized = (value - min_val) / range
      index = min(7, trunc(normalized * 8))
      Enum.at(bars, index)
    end)
  end
end
