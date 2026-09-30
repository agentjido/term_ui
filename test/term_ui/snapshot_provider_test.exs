defmodule TermUI.SnapshotProviderTest do
  use ExUnit.Case, async: true

  alias TermUI.{Frame, Snapshot}

  alias TermUI.Snapshot.{ClusterProvider, ProcessProvider, SupervisionTreeProvider}
  alias TermUI.Widget.{ClusterDashboard, ProcessMonitor, SupervisionTree}

  test "snapshot status reports complete, partial, and failed collections" do
    assert %Snapshot{status: :ok} = Snapshot.new([:item], [])

    assert %Snapshot{status: :partial} =
             Snapshot.new([:item], [%{source: :source, reason: :failed}])

    assert %Snapshot{status: :error} =
             Snapshot.new([], [%{source: :source, reason: :failed}])
  end

  test "process provider normalizes unavailable and partial process data" do
    info = fn
      :complete, _keys ->
        [registered_name: :worker, memory: 100, reductions: 20, message_queue_len: 2]

      :partial, _keys ->
        [registered_name: [], memory: 50]

      :unavailable, _keys ->
        nil
    end

    snapshot =
      ProcessProvider.collect([:complete, :partial, :unavailable], info: info, limit: 3)

    assert snapshot.status == :partial
    assert Enum.map(snapshot.items, & &1.pid) == [:complete, :partial]

    assert Enum.at(snapshot.items, 0) == %{
             pid: :complete,
             name: :worker,
             memory: 100,
             reductions: 20,
             message_queue_len: 2
           }

    assert Enum.at(snapshot.items, 1) == %{
             pid: :partial,
             name: nil,
             memory: 50,
             reductions: 0,
             message_queue_len: 0
           }

    assert Enum.any?(snapshot.errors, &(&1.source == :partial))
    assert Enum.any?(snapshot.errors, &(&1 == %{source: :unavailable, reason: :unavailable}))

    assert %Snapshot{status: :ok, items: [%{pid: :complete}]} =
             ProcessProvider.local(list: fn -> [:complete] end, info: info)
  end

  test "process provider bounds explicit and local collection" do
    info = fn process, _keys ->
      [registered_name: process, memory: 1, reductions: 1, message_queue_len: 0]
    end

    assert %Snapshot{status: :partial, items: [%{pid: :one}], errors: [error]} =
             ProcessProvider.collect([:one, :two], info: info, limit: 1)

    assert error == %{source: :provider, reason: {:limit, 1, 1}}

    assert %Snapshot{status: :error, items: []} =
             ProcessProvider.local(list: fn -> {:error, :denied} end)
  end

  test "supervision provider returns a partial tree for restarting children" do
    root = self()
    child_supervisor = spawn(fn -> receive do: (:stop -> :ok) end)
    worker = spawn(fn -> receive do: (:stop -> :ok) end)

    on_exit(fn ->
      send(child_supervisor, :stop)
      send(worker, :stop)
    end)

    children = fn
      ^root ->
        [
          {:worker, worker, :worker, [Worker]},
          {:branch, child_supervisor, :supervisor, [Supervisor]},
          {:starting, :restarting, :worker, [Worker]}
        ]

      ^child_supervisor ->
        [{:nested, worker, :worker, [Worker]}]
    end

    snapshot = SupervisionTreeProvider.collect(root, children: children, root_label: "Root")

    assert snapshot.status == :partial
    assert [%{label: "Root", children: [worker_node, branch, restarting]}] = snapshot.items
    assert worker_node.label == ":worker [worker]"
    assert [%{label: ":nested [worker]"}] = branch.children
    assert restarting.disabled
    assert snapshot.errors == [%{source: [root, :starting], reason: :restarting}]
  end

  test "supervision provider handles unavailable roots and depth bounds" do
    unavailable =
      SupervisionTreeProvider.collect(:missing, children: fn _root -> {:error, :noproc} end)

    assert unavailable == %Snapshot{
             status: :error,
             items: [],
             errors: [%{source: :missing, reason: :noproc}]
           }

    root = self()
    child_supervisor = spawn(fn -> receive do: (:stop -> :ok) end)
    on_exit(fn -> send(child_supervisor, :stop) end)

    bounded =
      SupervisionTreeProvider.collect(root,
        max_depth: 1,
        children: fn ^root -> [{:child, child_supervisor, :supervisor, [Supervisor]}] end
      )

    assert bounded.status == :partial
    assert [%{children: [%{disabled: true}]}] = bounded.items
    assert [%{reason: :max_depth}] = bounded.errors
  end

  test "cluster provider represents unavailable and partial nodes" do
    probe = fn
      :complete -> %{processes: 10, memory: 1_000, uptime: 20_000}
      :partial -> %{processes: 4}
      :down -> {:error, :nodedown}
    end

    snapshot = ClusterProvider.collect([:complete, :partial, :down], probe: probe)

    assert snapshot.status == :partial

    assert Enum.map(snapshot.items, &{&1.node, &1.status}) == [
             complete: :up,
             partial: :partial,
             down: :down
           ]

    assert Enum.at(snapshot.items, 1).memory == 0
    assert Enum.at(snapshot.items, 1).uptime == nil
    assert Enum.any?(snapshot.errors, &(&1.source == :partial))
    assert Enum.any?(snapshot.errors, &(&1 == %{source: :down, reason: :nodedown}))
  end

  test "remote RPC is disabled by default and explicit when supplied" do
    remote = :remote@example

    assert %Snapshot{status: :partial, items: [%{status: :down}], errors: [error]} =
             ClusterProvider.collect([remote])

    assert error == %{source: remote, reason: :rpc_disabled}

    rpc = fn node_name, module, function, arguments, timeout ->
      assert node_name == remote
      assert module == ClusterProvider
      assert function == :local_snapshot
      assert arguments == []
      assert timeout == 25
      %{processes: 5, memory: 500, uptime: 1_000}
    end

    assert %Snapshot{status: :ok, items: [%{node: ^remote, status: :up}]} =
             ClusterProvider.collect([remote], rpc: rpc, timeout: 25)
  end

  test "provider items go directly to pure widgets without hidden polling" do
    process_snapshot =
      ProcessProvider.collect([:worker],
        info: fn _process, _keys ->
          [registered_name: :worker, memory: 10, reductions: 2, message_queue_len: 0]
        end
      )

    cluster_snapshot =
      ClusterProvider.collect([:local],
        probe: fn _node -> %{processes: 10, memory: 20, uptime: 30} end
      )

    tree_snapshot =
      SupervisionTreeProvider.collect(:root, children: fn _root -> [] end)

    monitor = ProcessMonitor.init([]) |> ProcessMonitor.set_snapshots(process_snapshot.items)
    dashboard = ClusterDashboard.init([]) |> ClusterDashboard.set_nodes(cluster_snapshot.items)
    tree = SupervisionTree.init([]) |> SupervisionTree.set_nodes(tree_snapshot.items)

    assert %Frame{} = ProcessMonitor.view(monitor, {50, 3})
    assert %Frame{} = ClusterDashboard.view(dashboard, {50, 3})
    assert %Frame{} = SupervisionTree.view(tree, {50, 3})

    for provider <- [ProcessProvider, SupervisionTreeProvider, ClusterProvider] do
      refute function_exported?(provider, :start_link, 1)
    end
  end
end
