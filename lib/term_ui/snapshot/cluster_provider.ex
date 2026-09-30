defmodule TermUI.Snapshot.ClusterProvider do
  @moduledoc """
  Collects one cluster snapshot for explicit nodes.

  Local metrics need no RPC. Remote nodes return `:rpc_disabled` unless the
  parent supplies an `:rpc` function. The function receives node, module,
  function, arguments, and timeout. The provider does not call `Node.list/0`,
  monitor nodes, poll, or retry.
  """

  alias TermUI.Snapshot

  @default_limit 100
  @default_timeout 5_000
  @metric_fields [:processes, :memory, :uptime]

  @type item :: %{
          node: term(),
          status: :up | :partial | :down,
          processes: non_neg_integer(),
          memory: non_neg_integer(),
          uptime: non_neg_integer() | nil
        }

  @doc "Collects normalized metrics for an explicit bounded list of nodes."
  @spec collect([term()], keyword()) :: Snapshot.t(item())
  def collect(nodes, opts \\ []) when is_list(nodes) do
    limit = positive(Keyword.get(opts, :limit, @default_limit), @default_limit)
    {selected, omitted} = Enum.split(nodes, limit)

    {items, errors} =
      Enum.reduce(selected, {[], []}, fn node_name, {items, errors} ->
        case fetch(node_name, opts) do
          {:ok, item} ->
            {[item | items], errors}

          {:partial, item, reason} ->
            {[item | items], [error(node_name, reason) | errors]}

          {:error, reason} ->
            {[down(node_name) | items], [error(node_name, reason) | errors]}
        end
      end)

    errors =
      if omitted == [],
        do: errors,
        else: [error(:provider, {:limit, limit, length(omitted)}) | errors]

    Snapshot.new(Enum.reverse(items), Enum.reverse(errors))
  end

  @doc "Returns the local metrics shape used by an explicitly supplied RPC function."
  @spec local_snapshot() :: %{
          node: atom(),
          status: :up,
          processes: non_neg_integer(),
          memory: non_neg_integer(),
          uptime: non_neg_integer()
        }
  def local_snapshot do
    {uptime, _since_last_call} = :erlang.statistics(:wall_clock)

    %{
      node: Node.self(),
      status: :up,
      processes: :erlang.system_info(:process_count),
      memory: :erlang.memory(:total),
      uptime: uptime
    }
  end

  defp fetch(node_name, opts) do
    case Keyword.get(opts, :probe) do
      probe when is_function(probe, 1) -> safe_probe(probe, node_name)
      nil -> default_probe(node_name, opts)
      _invalid -> {:error, :invalid_probe}
    end
    |> normalize(node_name)
  end

  defp default_probe(node_name, _opts) when node_name == node(), do: local_snapshot()

  defp default_probe(node_name, opts) do
    case Keyword.get(opts, :rpc) do
      rpc when is_function(rpc, 5) ->
        timeout = positive(Keyword.get(opts, :timeout, @default_timeout), @default_timeout)
        safe_rpc(rpc, node_name, timeout)

      nil ->
        {:error, :rpc_disabled}

      _invalid ->
        {:error, :invalid_rpc}
    end
  end

  defp normalize({:ok, value}, node_name), do: normalize(value, node_name)
  defp normalize({:error, reason}, _node_name), do: {:error, reason}
  defp normalize({:badrpc, reason}, _node_name), do: {:error, {:badrpc, reason}}

  defp normalize(value, node_name) when is_map(value) do
    invalid = invalid_fields(value)

    item = %{
      node: node_name,
      status: if(invalid == [], do: :up, else: :partial),
      processes: metric(value, :processes),
      memory: metric(value, :memory),
      uptime: optional_metric(value, :uptime)
    }

    if invalid == [],
      do: {:ok, item},
      else: {:partial, item, {:missing_or_invalid_fields, invalid}}
  end

  defp normalize(invalid, _node_name), do: {:error, {:invalid_output, invalid}}

  defp invalid_fields(value) do
    Enum.reject(@metric_fields, fn key ->
      is_integer(Map.get(value, key)) and Map.get(value, key) >= 0
    end)
  end

  defp metric(value, key) do
    case Map.get(value, key) do
      metric when is_integer(metric) and metric >= 0 -> metric
      _invalid -> 0
    end
  end

  defp optional_metric(value, key) do
    case Map.get(value, key) do
      metric when is_integer(metric) and metric >= 0 -> metric
      _invalid -> nil
    end
  end

  defp safe_probe(probe, node_name) do
    probe.(node_name)
  rescue
    error -> {:error, {:exception, error}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp safe_rpc(rpc, node_name, timeout) do
    rpc.(node_name, __MODULE__, :local_snapshot, [], timeout)
  rescue
    error -> {:error, {:exception, error}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp down(node_name),
    do: %{node: node_name, status: :down, processes: 0, memory: 0, uptime: nil}

  defp positive(value, _default) when is_integer(value) and value > 0, do: value
  defp positive(_invalid, default), do: default
  defp error(source, reason), do: %{source: source, reason: reason}
end
