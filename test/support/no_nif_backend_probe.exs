defmodule TermUI.Test.NoNifBackendProbe.App do
  use TermUI.Elm

  alias TermUI.Frame

  def init(opts), do: %{dimensions: Keyword.fetch!(opts, :dimensions)}
  def event_to_msg(_event, _state), do: :ignore
  def update(_message, state), do: state

  def view(%{dimensions: {width, height}}) do
    Frame.from_rows(["no-nif"], width, height)
  end
end

defmodule TermUI.Test.NoNifBackendProbe do
  alias TermUI.Backend.SSH
  alias TermUI.Runtime
  alias TermUI.Terminal.TtyNif
  alias TermUI.Test.DeterministicBackend
  alias TermUI.Test.NoNifBackendProbe.App

  def run do
    assert_nif_unloaded!(:start)

    {:ok, runtime} =
      TermUI.start_link(App,
        backend: {DeterministicBackend, owner: self(), size: {4, 20}},
        backend_opts: [size_poll_interval: :disabled]
      )

    receive do
      {:backend, :draw, _frame} -> :ok
    after
      1_000 -> raise "the deterministic backend did not draw"
    end

    :ok = Runtime.shutdown(runtime)
    assert_nif_unloaded!(:deterministic_backend)

    {:ok, session} =
      SSH.start_session(App,
        size: {4, 20},
        output: fn _data -> :ok end
      )

    :ok = SSH.stop_session(session)
    assert_nif_unloaded!(:ssh_backend)

    IO.puts("TTY NIF stayed unloaded for deterministic and SSH backends")
  end

  defp assert_nif_unloaded!(path) do
    case :code.is_loaded(TtyNif) do
      false -> :ok
      location -> raise "TTY NIF module loaded on #{path}: #{inspect(location)}"
    end
  end
end

TermUI.Test.NoNifBackendProbe.run()
