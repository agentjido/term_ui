defmodule TermUI.Terminal.NativeMode do
  @moduledoc false

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
