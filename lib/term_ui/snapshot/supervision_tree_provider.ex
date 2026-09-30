defmodule TermUI.Snapshot.SupervisionTreeProvider do
  @moduledoc """
  Collects one supervision-tree snapshot when the application calls it.

  The parent supplies the root and can replace the `:children` callback for
  authorization, remote access, or tests. Collection is synchronous, bounded
  by `:max_depth`, and starts no polling process.
  """

  alias TermUI.Snapshot
  alias TermUI.Widget.TreeView

  @default_max_depth 20

  @doc "Collects one normalized tree for the supplied supervisor root."
  @spec collect(term(), keyword()) :: Snapshot.t(TreeView.tree_node())
  def collect(supervisor, opts \\ []) do
    children = Keyword.get(opts, :children, &Supervisor.which_children/1)
    max_depth = positive_depth(Keyword.get(opts, :max_depth, @default_max_depth))
    root_id = {:supervision, [supervisor]}
    root_label = Keyword.get(opts, :root_label, inspect(supervisor)) |> to_string()

    case fetch_children(children, supervisor) do
      {:ok, entries} ->
        visited = if is_pid(supervisor), do: %{supervisor => true}, else: %{}

        {nodes, errors, _visited} =
          normalize_children(entries, [supervisor], children, max_depth, 1, visited)

        Snapshot.new([TreeView.branch(root_id, root_label, nodes)], errors)

      {:error, reason} ->
        Snapshot.new([], [error(supervisor, reason)])
    end
  end

  defp normalize_children(entries, path, children, max_depth, depth, visited)
       when is_list(entries) do
    Enum.reduce(entries, {[], [], visited}, fn entry, {nodes, errors, visited} ->
      case normalize_child(entry, path, children, max_depth, depth, visited) do
        {:ok, node, child_errors, visited} ->
          {nodes ++ [node], errors ++ child_errors, visited}

        {:error, source, reason} ->
          {nodes, errors ++ [error(source, reason)], visited}
      end
    end)
  end

  defp normalize_child({id, process, type, _modules}, path, children, max_depth, depth, visited) do
    child_path = path ++ [id]
    node_id = {:supervision, child_path}

    cond do
      process in [:undefined, :restarting] ->
        node = TreeView.leaf(node_id, child_label(id, process), disabled: true)
        {:ok, node, [error(child_path, process)], visited}

      type == :supervisor and is_pid(process) ->
        supervisor_child(node_id, id, process, child_path, children, max_depth, depth, visited)

      is_pid(process) ->
        {:ok, TreeView.leaf(node_id, child_label(id, type)), [], visited}

      true ->
        {:error, child_path, {:invalid_child_process, process}}
    end
  end

  defp normalize_child(invalid, path, _children, _max_depth, _depth, _visited),
    do: {:error, path, {:invalid_child, invalid}}

  defp supervisor_child(node_id, id, process, path, children, max_depth, depth, visited) do
    cond do
      depth >= max_depth ->
        node = TreeView.leaf(node_id, child_label(id, :supervisor), disabled: true)
        {:ok, node, [error(path, :max_depth)], visited}

      Map.has_key?(visited, process) ->
        node = TreeView.leaf(node_id, child_label(id, :cycle), disabled: true)
        {:ok, node, [error(path, :cycle)], visited}

      true ->
        nested_supervisor(node_id, id, process, path, children, max_depth, depth, visited)
    end
  end

  defp nested_supervisor(node_id, id, process, path, children, max_depth, depth, visited) do
    visited = Map.put(visited, process, true)

    case fetch_children(children, process) do
      {:ok, entries} ->
        {nodes, errors, visited} =
          normalize_children(entries, path, children, max_depth, depth + 1, visited)

        {:ok, TreeView.branch(node_id, child_label(id, :supervisor), nodes), errors, visited}

      {:error, reason} ->
        node = TreeView.leaf(node_id, child_label(id, :unavailable), disabled: true)
        {:ok, node, [error(path, reason)], visited}
    end
  end

  defp fetch_children(children, supervisor) when is_function(children, 1) do
    case children.(supervisor) do
      {:ok, entries} when is_list(entries) -> {:ok, entries}
      entries when is_list(entries) -> {:ok, entries}
      {:error, reason} -> {:error, reason}
      invalid -> {:error, {:invalid_output, invalid}}
    end
  rescue
    error -> {:error, {:exception, error}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp fetch_children(_invalid, _supervisor), do: {:error, :invalid_callback}

  defp child_label(id, state), do: "#{inspect(id)} [#{state}]"
  defp positive_depth(depth) when is_integer(depth) and depth > 0, do: depth
  defp positive_depth(_invalid), do: @default_max_depth
  defp error(source, reason), do: %{source: source, reason: reason}
end
