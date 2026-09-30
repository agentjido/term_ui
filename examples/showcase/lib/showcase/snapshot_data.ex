defmodule Showcase.SnapshotData do
  @moduledoc "Provides deterministic showcase data for tests and explicit snapshot mode."

  alias TermUI.Widget.TreeView

  @doc "Returns one deterministic snapshot with the live-data shape."
  @spec snapshot() :: map()
  def snapshot do
    %{
      collected_at: 1_700_000_000,
      system: %{
        memory: %{total: 96_000_000, processes: 48_000_000, binary: 12_000_000, ets: 8_000_000},
        process_count: 184,
        process_limit: 262_144,
        run_queue: 2,
        run_queue_load: 13,
        schedulers: 16,
        schedulers_online: 16
      },
      processes: process_snapshots(),
      runtime_tree: runtime_tree(),
      cluster: cluster_snapshots()
    }
  end

  defp process_snapshots do
    [
      process("<0.184.0>", "TermUI.Runtime", 148_320, 51_204, 0, :waiting),
      process("<0.185.0>", "Backend.Manager", 92_176, 22_918, 1, :waiting),
      process("<0.186.0>", "InputReader", 18_624, 4_091, 0, :waiting),
      process("<0.187.0>", "ProducerAdapter", 27_040, 9_277, 2, :running)
    ]
  end

  defp process(pid, name, memory, reductions, queue, status) do
    %{
      pid: pid,
      name: name,
      memory: memory,
      reductions: reductions,
      message_queue_len: queue,
      status: status
    }
  end

  defp runtime_tree do
    [
      TreeView.branch(:runtime, "TermUI.Runtime <0.184.0>", [
        TreeView.leaf(:backend, "TermUI.Backend.Manager <0.185.0>"),
        TreeView.leaf(:input, "TermUI.Backend.InputReader <0.186.0>")
      ])
    ]
  end

  defp cluster_snapshots do
    [
      %{node: :console@local, status: "up", processes: 184, memory: "42.0 MB", uptime: "2h 14m"},
      %{
        node: :"worker-a@local",
        status: "up",
        processes: 231,
        memory: "81.0 MB",
        uptime: "5h 02m"
      }
    ]
  end
end
