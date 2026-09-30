defmodule TermUI.Terminal.RawMode do
  @moduledoc false

  alias TermUI.Terminal.TtyNif

  @type native_flags :: TtyNif.control_flags()
  @type session :: :otp_signals | {:native, native_flags()}
  @type option ::
          {:shell_start, (term() -> :ok | {:error, term()})}
          | {:signals_api?, boolean()}
          | {:tty_nif, module()}

  @doc false
  @spec enter([option()]) :: {:ok, session()} | {:error, term()}
  def enter(opts \\ []) do
    shell_start = Keyword.get(opts, :shell_start, &:shell.start_interactive/1)

    if Keyword.get_lazy(opts, :signals_api?, &signals_api_available?/0) do
      case start_with_signals_api(shell_start) do
        :unsupported -> start_with_native_flags(shell_start, opts)
        result -> result
      end
    else
      start_with_native_flags(shell_start, opts)
    end
  end

  @doc false
  @spec exit(session(), [option()]) :: :ok | {:error, term()}
  def exit(session, opts \\ []) do
    shell_start = Keyword.get(opts, :shell_start, &:shell.start_interactive/1)
    tty_nif = Keyword.get(opts, :tty_nif, TtyNif)
    cooked_result = call_shell(shell_start, {:noshell, :cooked})
    flags_result = restore_flags(session, tty_nif)

    combine_exit_results(cooked_result, flags_result)
  end

  @doc false
  @spec resume(session(), [option()]) :: :ok | {:error, term()}
  def resume(session, opts \\ [])

  def resume(:otp_signals, _opts), do: :ok

  def resume({:native, _original_flags}, opts) do
    tty_nif = Keyword.get(opts, :tty_nif, TtyNif)

    # OTP has restored character input before this call. Disable its signal
    # and flow-control flags again, keeping the original flags for shutdown.
    case call_native(tty_nif, :disable_control_flags, []) do
      {:ok, _current_flags} -> :ok
      {:error, reason} -> {:error, {:control_flags, reason}}
    end
  end

  defp signals_api_available? do
    with {:ok, specifications} <- Code.Typespec.fetch_specs(:shell),
         {{:start_interactive, 1}, definitions} <-
           Enum.find(specifications, fn
             {{:start_interactive, 1}, _definitions} -> true
             _other -> false
           end) do
      Enum.any?(definitions, &signals_option?/1)
    else
      _error -> false
    end
  end

  defp signals_option?({:type, _line, field, [{:atom, _key_line, :signals} | _rest]})
       when field in [:map_field_assoc, :map_field_exact],
       do: true

  defp signals_option?(tuple) when is_tuple(tuple) do
    tuple |> Tuple.to_list() |> Enum.any?(&signals_option?/1)
  end

  defp signals_option?(list) when is_list(list), do: Enum.any?(list, &signals_option?/1)
  defp signals_option?(_other), do: false

  defp start_with_signals_api(shell_start) do
    argument = {:noshell, %{mode: :raw, signals: false}}

    try do
      case shell_start.(argument) do
        :ok -> {:ok, :otp_signals}
        {:error, reason} -> {:error, reason}
        other -> {:error, {:unexpected_shell_result, other}}
      end
    rescue
      FunctionClauseError -> :unsupported
      exception -> {:error, {:shell_exception, exception}}
    catch
      kind, reason -> {:error, {:shell_failure, kind, reason}}
    end
  end

  defp start_with_native_flags(shell_start, opts) do
    tty_nif = Keyword.get(opts, :tty_nif, TtyNif)

    case call_shell(shell_start, {:noshell, :raw}) do
      :ok -> disable_native_flags(shell_start, tty_nif)
      {:error, reason} -> {:error, reason}
    end
  end

  defp disable_native_flags(shell_start, tty_nif) do
    with :ok <- ensure_native_loaded(tty_nif),
         {:ok, flags} <- call_native(tty_nif, :disable_control_flags, []) do
      {:ok, {:native, flags}}
    else
      {:error, reason} ->
        rollback = call_shell(shell_start, {:noshell, :cooked})
        {:error, {:control_flags_unavailable, reason, rollback}}
    end
  end

  defp ensure_native_loaded(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        if function_exported?(module, :ensure_loaded, 0) do
          call_native(module, :ensure_loaded, [])
        else
          :ok
        end

      {:error, reason} ->
        {:error, {:native_module_unavailable, module, reason}}
    end
  end

  defp restore_flags(:otp_signals, _tty_nif), do: :ok

  defp restore_flags({:native, flags}, tty_nif) do
    case call_native(tty_nif, :restore_control_flags, [flags]) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp call_shell(shell_start, argument) do
    case shell_start.(argument) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
      other -> {:error, {:unexpected_shell_result, other}}
    end
  rescue
    exception -> {:error, {:shell_exception, exception}}
  catch
    kind, reason -> {:error, {:shell_failure, kind, reason}}
  end

  defp call_native(module, function, arguments) do
    apply(module, function, arguments)
  rescue
    exception -> {:error, {:native_exception, exception}}
  catch
    kind, reason -> {:error, {:native_failure, kind, reason}}
  end

  defp combine_exit_results(:ok, :ok), do: :ok
  defp combine_exit_results({:error, reason}, :ok), do: {:error, {:cooked_mode, reason}}
  defp combine_exit_results(:ok, {:error, reason}), do: {:error, {:control_flags, reason}}

  defp combine_exit_results({:error, cooked}, {:error, flags}) do
    {:error, {:cooked_mode, cooked, :control_flags, flags}}
  end
end
