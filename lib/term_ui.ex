defmodule TermUI do
  @moduledoc """
  A small terminal runtime for Elm applications on the BEAM.

  The runtime owns application state and terminal lifecycle. An application
  receives normalized `TermUI.Event` values, returns `TermUI.Command` data,
  and renders one `TermUI.Frame`.
  """

  alias TermUI.{Config, Runtime}

  @doc "Runs an Elm application until it stops."
  @spec run(module(), keyword()) :: :ok | {:error, term()}
  def run(root, opts \\ []) when is_atom(root) and is_list(opts) do
    with {:ok, opts} <- Config.merge_runtime_options(opts) do
      Runtime.run(Keyword.put(opts, :root, root))
    end
  end

  @doc "Starts a linked Elm application runtime."
  @spec start_link(module(), keyword()) :: GenServer.on_start()
  def start_link(root, opts \\ []) when is_atom(root) and is_list(opts) do
    with {:ok, opts} <- Config.merge_runtime_options(opts) do
      Runtime.start_link(Keyword.put(opts, :root, root))
    end
  end
end
