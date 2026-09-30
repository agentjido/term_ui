defmodule TermUI.Snapshot do
  @moduledoc """
  Stable result data returned by one-shot snapshot providers.

  `:items` is ready for a pure widget setter. `:errors` records unavailable or
  incomplete sources. `:status` is `:ok` with no errors, `:partial` when items
  and errors both exist, and `:error` when only errors exist.
  """

  @type status :: :ok | :partial | :error
  @type error :: %{required(:source) => term(), required(:reason) => term()}
  @type t(item) :: %__MODULE__{status: status(), items: [item], errors: [error()]}

  @enforce_keys [:status, :items, :errors]
  defstruct status: :ok, items: [], errors: []

  @doc "Creates a normalized snapshot result from items and source errors."
  @spec new([term()], [error()]) :: t(term())
  def new(items, errors) when is_list(items) and is_list(errors) do
    %__MODULE__{status: status(items, errors), items: items, errors: errors}
  end

  defp status(_items, []), do: :ok
  defp status([], _errors), do: :error
  defp status(_items, _errors), do: :partial
end
