defmodule TermUI.LoggerControl do
  @moduledoc false

  @filter_id :term_ui_full_screen
  @state_key {__MODULE__, :state}

  @type token :: {reference(), pid()}

  @doc false
  @spec suspend() :: token() | nil
  def suspend do
    owner = self()
    token_ref = make_ref()
    watcher = spawn(fn -> watch_owner(owner, token_ref) end)

    result =
      try do
        transaction(fn -> add_token(token_ref) end)
      rescue
        _exception -> :error
      catch
        _kind, _reason -> :error
      end

    case result do
      :ok ->
        {token_ref, watcher}

      _other ->
        send(watcher, {:release, token_ref})
        nil
    end
  end

  @doc false
  @spec resume(token() | nil) :: :ok
  def resume(nil), do: :ok

  def resume({token_ref, watcher}) when is_reference(token_ref) and is_pid(watcher) do
    try do
      transaction(fn -> release_token(token_ref) end)
    rescue
      _exception -> :ok
    catch
      _kind, _reason -> :ok
    after
      send(watcher, {:release, token_ref})
    end

    :ok
  end

  @doc false
  @spec stop_event(term(), term()) :: :stop
  def stop_event(_event, _extra), do: :stop

  defp add_token(token_ref) do
    state = :persistent_term.get(@state_key, %{tokens: MapSet.new(), owns_filter?: false})
    state = if MapSet.size(state.tokens) == 0, do: install_filter(state), else: state
    :persistent_term.put(@state_key, %{state | tokens: MapSet.put(state.tokens, token_ref)})
    :ok
  end

  defp watch_owner(owner, token_ref) do
    monitor_ref = Process.monitor(owner)

    receive do
      {:release, ^token_ref} ->
        Process.demonitor(monitor_ref, [:flush])

      {:DOWN, ^monitor_ref, :process, ^owner, _reason} ->
        transaction(fn -> release_token(token_ref) end)
    end
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp install_filter(state) do
    if filter_present?() do
      %{state | owns_filter?: false}
    else
      case :logger.add_handler_filter(
             :default,
             @filter_id,
             {&__MODULE__.stop_event/2, nil}
           ) do
        :ok -> %{state | owns_filter?: true}
        {:error, _reason} -> %{state | owns_filter?: false}
      end
    end
  end

  defp release_token(token) do
    case :persistent_term.get(@state_key, nil) do
      %{tokens: tokens} = state ->
        if MapSet.member?(tokens, token) do
          finish_release(%{state | tokens: MapSet.delete(tokens, token)})
        end

      _other ->
        :ok
    end
  end

  defp finish_release(%{tokens: tokens, owns_filter?: owns_filter?} = state) do
    if MapSet.size(tokens) == 0 do
      _result = if owns_filter?, do: :logger.remove_handler_filter(:default, @filter_id)
      :persistent_term.erase(@state_key)
    else
      :persistent_term.put(@state_key, state)
    end

    :ok
  end

  defp filter_present? do
    case :logger.get_handler_config(:default) do
      {:ok, %{filters: filters}} ->
        Enum.any?(filters, fn {id, _filter} -> id == @filter_id end)

      _other ->
        false
    end
  end

  defp transaction(function) do
    :global.trans({@state_key, self()}, function)
  end
end
