defmodule TermUI.Snapshot.ProcessProvider do
  @moduledoc """
  Collects one bounded process snapshot when the application calls it.

  `collect/2` inspects only the supplied process identifiers. `local/1` is an
  explicit convenience call that lists local processes once. Neither function
  starts a process or schedules another collection.
  """

  alias TermUI.Snapshot

  @info_keys [:registered_name, :memory, :reductions, :message_queue_len]
  @default_limit 1_000

  @type item :: %{
          pid: term(),
          name: term() | nil,
          memory: non_neg_integer(),
          reductions: non_neg_integer(),
          message_queue_len: non_neg_integer()
        }

  @doc "Collects normalized data for an explicit bounded list of processes."
  @spec collect([term()], keyword()) :: Snapshot.t(item())
  def collect(processes, opts \\ []) when is_list(processes) do
    info = Keyword.get(opts, :info, &Process.info/2)
    limit = positive_limit(Keyword.get(opts, :limit, @default_limit))
    {selected, omitted} = Enum.split(processes, limit)

    {items, errors} =
      Enum.reduce(selected, {[], []}, fn process, {items, errors} ->
        case process_info(info, process) do
          {:ok, item} ->
            {[item | items], errors}

          {:partial, item, reason} ->
            {[item | items], [error(process, reason) | errors]}

          {:error, reason} ->
            {items, [error(process, reason) | errors]}
        end
      end)

    errors =
      if omitted == [],
        do: errors,
        else: [error(:provider, {:limit, limit, length(omitted)}) | errors]

    Snapshot.new(Enum.reverse(items), Enum.reverse(errors))
  end

  @doc "Lists local processes once and returns a bounded normalized snapshot."
  @spec local(keyword()) :: Snapshot.t(item())
  def local(opts \\ []) do
    list = Keyword.get(opts, :list, &Process.list/0)

    case safe_call(list, []) do
      processes when is_list(processes) -> collect(processes, opts)
      {:error, reason} -> Snapshot.new([], [error(:process_list, reason)])
      invalid -> Snapshot.new([], [error(:process_list, {:invalid_output, invalid})])
    end
  end

  defp process_info(info, process) do
    case safe_call(info, [process, @info_keys]) do
      values when is_list(values) -> normalize_info(process, values)
      nil -> {:error, :unavailable}
      {:error, reason} -> {:error, reason}
      invalid -> {:error, {:invalid_output, invalid}}
    end
  end

  defp normalize_info(process, values) do
    if Keyword.keyword?(values) do
      fields = Map.new(values)
      invalid = invalid_fields(fields)

      item = %{
        pid: process,
        name: normalize_name(Map.get(fields, :registered_name)),
        memory: counter(fields, :memory),
        reductions: counter(fields, :reductions),
        message_queue_len: counter(fields, :message_queue_len)
      }

      if invalid == [],
        do: {:ok, item},
        else: {:partial, item, {:missing_or_invalid_fields, invalid}}
    else
      {:error, {:invalid_output, values}}
    end
  end

  defp invalid_fields(fields) do
    Enum.reject(@info_keys, fn
      :registered_name -> Map.has_key?(fields, :registered_name)
      key -> is_integer(Map.get(fields, key)) and Map.get(fields, key) >= 0
    end)
  end

  defp normalize_name([]), do: nil
  defp normalize_name(nil), do: nil
  defp normalize_name(name), do: name

  defp counter(fields, key) do
    case Map.get(fields, key) do
      value when is_integer(value) and value >= 0 -> value
      _invalid -> 0
    end
  end

  defp safe_call(function, arguments) when is_function(function, length(arguments)) do
    :erlang.apply(function, arguments)
  rescue
    error -> {:error, {:exception, error}}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp safe_call(_invalid, _arguments), do: {:error, :invalid_callback}
  defp positive_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp positive_limit(_invalid), do: @default_limit
  defp error(source, reason), do: %{source: source, reason: reason}
end
