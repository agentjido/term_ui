defmodule TermUI.App do
  @moduledoc """
  Deprecated v1 entry points for the v2 runtime.

  This facade starts only `TermUI.Runtime`. It does not provide the v1
  component process model. These functions will remain available for all v2
  releases so applications can move to the direct API in small steps.

  The v1 global `backend_mode/0` and `supports?/1` queries are not available.
  Their meaning is not valid when more than one v2 runtime is active. Use
  `TermUI.Runtime.capabilities/1` for one runtime.
  """

  alias TermUI.Runtime

  @type root_module :: module()

  @doc "Starts a linked v2 runtime. Use `TermUI.start_link/2` for new code."
  @deprecated "Use TermUI.start_link/2 instead."
  @spec start(root_module(), keyword()) :: GenServer.on_start()
  def start(root, opts \\ []), do: TermUI.start_link(root, opts)

  @doc "Runs a v2 runtime and keeps the v1 normal-exit value. Use `TermUI.run/2` for new code."
  @deprecated "Use TermUI.run/2 instead. It returns :ok after a normal exit."
  @spec run(root_module(), keyword()) :: {:ok, :exited_normally} | {:error, term()}
  def run(root, opts \\ []) do
    case TermUI.run(root, opts) do
      :ok -> {:ok, :exited_normally}
      {:error, _reason} = error -> error
    end
  end

  @doc "Stops one v2 runtime. Use `TermUI.Runtime.shutdown/1` for new code."
  @deprecated "Use TermUI.Runtime.shutdown/1 instead."
  @spec shutdown(GenServer.server()) :: :ok
  def shutdown(runtime), do: Runtime.shutdown(runtime)
end
