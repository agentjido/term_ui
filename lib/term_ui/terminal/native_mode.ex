defmodule TermUI.Terminal.NativeMode do
  @moduledoc false

  alias TermUI.Terminal.TtyNif

  # The signals option is newer than the minimum OTP 28 typespec.
  @dialyzer {:nowarn_function, enter: 0}

  @doc false
  @spec enter() :: :ok | {:error, term()}
  def enter do
    if signals_api?() do
      :shell.start_interactive({:noshell, %{mode: :raw, signals: false}})
    else
      :shell.start_interactive({:noshell, :raw})
    end
  end

  @doc false
  @spec acquire() ::
          {:ok, nil | {:windows, term()}}
          | {:error, :already_started | {:console_controls, term()}}
  def acquire do
    case enter() do
      :ok -> acquire_controls()
      {:error, _reason} = error -> error
    end
  end

  defp acquire_controls do
    if match?({:win32, _}, :os.type()) do
      with :ok <- TtyNif.ensure_loaded(),
           {:ok, flags} <- call_console(:disable_control_flags, []) do
        {:ok, {:windows, flags}}
      else
        {:error, reason} ->
          _ = :shell.start_interactive({:noshell, :cooked})
          {:error, {:console_controls, reason}}
      end
    else
      {:ok, nil}
    end
  end

  @doc false
  @spec restore_console(TtyNif.control_flags()) :: :ok | {:error, term()}
  def restore_console(flags), do: call_console(:restore_control_flags, [flags])

  defp call_console(function, args), do: apply(TtyNif, function, args)

  defp signals_api? do
    with {:ok, specifications} <- Code.Typespec.fetch_specs(:shell),
         {{:start_interactive, 1}, definitions} <-
           List.keyfind(specifications, {:start_interactive, 1}, 0) do
      Enum.any?(definitions, &signals_option?/1)
    else
      _unavailable -> false
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
end
