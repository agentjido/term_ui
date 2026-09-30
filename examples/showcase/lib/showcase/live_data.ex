defmodule Showcase.LiveData do
  @moduledoc "Collects live BEAM snapshots outside the showcase update and view functions."

  alias TermUI.Widget.TreeView

  @process_limit 40
  @rpc_timeout 500

  @doc "Collects one live snapshot for the showcase application."
  @spec collect(pid()) :: map()
  def collect(runtime) when is_pid(runtime) do
    system = system_snapshot()

    %{
      collected_at: System.system_time(:second),
      system: system,
      processes: process_snapshots(runtime),
      runtime_tree: runtime_tree(runtime),
      cluster: cluster_snapshots()
    }
  end

  defp system_snapshot do
    memory = :erlang.memory() |> Map.new()
    schedulers = :erlang.system_info(:schedulers)
    schedulers_online = :erlang.system_info(:schedulers_online)
    process_count = :erlang.system_info(:process_count)
    process_limit = :erlang.system_info(:process_limit)
    run_queue = :erlang.statistics(:run_queue)

    %{
      memory: memory,
      process_count: process_count,
      process_limit: process_limit,
      run_queue: run_queue,
      run_queue_load: percent(run_queue, max(schedulers_online, 1)),
      schedulers: schedulers,
      schedulers_online: schedulers_online
    }
  end

  defp process_snapshots(runtime) do
    snapshots =
      Process.list()
      |> Enum.map(&process_snapshot/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.memory, :desc)

    top = Enum.take(snapshots, @process_limit)
    runtime_pid = inspect(runtime)

    if Enum.any?(top, &(&1.pid == runtime_pid)) do
      top
    else
      runtime_snapshot = Enum.find(snapshots, &(&1.pid == runtime_pid))
      [runtime_snapshot | Enum.take(top, @process_limit - 1)] |> Enum.reject(&is_nil/1)
    end
  end

  defp process_snapshot(pid) do
    fields = [
      :registered_name,
      :memory,
      :reductions,
      :message_queue_len,
      :status,
      :current_function
    ]

    case Process.info(pid, fields) do
      nil ->
        nil

      info ->
        %{
          pid: inspect(pid),
          name: process_name(info),
          memory: Keyword.fetch!(info, :memory),
          reductions: Keyword.fetch!(info, :reductions),
          message_queue_len: Keyword.fetch!(info, :message_queue_len),
          status: Keyword.fetch!(info, :status)
        }
    end
  end

  defp process_name(info) do
    case Keyword.fetch!(info, :registered_name) do
      name when is_atom(name) -> Atom.to_string(name)
      _other -> info |> Keyword.fetch!(:current_function) |> elem(0) |> inspect()
    end
  end

  defp runtime_tree(runtime) do
    children =
      case Process.info(runtime, :links) do
        {:links, links} -> links |> Enum.filter(&is_pid/1) |> Enum.map(&runtime_link/1)
        nil -> []
      end

    [TreeView.branch(:runtime, "TermUI.Runtime #{inspect(runtime)}", children)]
  end

  defp runtime_link(pid) do
    label =
      case Process.info(pid, [:registered_name, :current_function]) do
        nil ->
          "stopped #{inspect(pid)}"

        info ->
          name = process_name(info)
          "#{name} #{inspect(pid)}"
      end

    TreeView.leaf(pid, label)
  end

  defp cluster_snapshots do
    [node() | Node.list(:connected)]
    |> Enum.uniq()
    |> Enum.map(&cluster_snapshot/1)
  end

  defp cluster_snapshot(node) when node == node() do
    {uptime, _since_last_call} = :erlang.statistics(:wall_clock)

    %{
      node: node,
      status: "up",
      processes: :erlang.system_info(:process_count),
      memory: format_bytes(:erlang.memory(:total)),
      uptime: format_duration(uptime)
    }
  end

  defp cluster_snapshot(node) do
    processes = remote(node, :system_info, [:process_count])
    memory = remote(node, :memory, [:total])
    wall_clock = remote(node, :statistics, [:wall_clock])

    if is_integer(processes) and is_integer(memory) and is_tuple(wall_clock) do
      %{
        node: node,
        status: "up",
        processes: processes,
        memory: format_bytes(memory),
        uptime: wall_clock |> elem(0) |> format_duration()
      }
    else
      %{node: node, status: "unavailable", processes: 0, memory: "-", uptime: "-"}
    end
  end

  defp remote(node, function, args) do
    case :rpc.call(node, :erlang, function, args, @rpc_timeout) do
      {:badrpc, _reason} -> nil
      value -> value
    end
  end

  defp percent(value, total) when total > 0,
    do: value |> Kernel.*(100) |> Kernel./(total) |> round() |> min(100) |> max(0)

  defp format_bytes(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1_024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_duration(milliseconds) do
    seconds = div(milliseconds, 1_000)
    hours = div(seconds, 3_600)
    minutes = seconds |> rem(3_600) |> div(60)
    "#{hours}h #{String.pad_leading(Integer.to_string(minutes), 2, "0")}m"
  end
end
