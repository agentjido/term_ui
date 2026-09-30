defmodule TermUI.PublicTestBackendTest do
  use ExUnit.Case, async: true

  alias TermUI.{Command, Event, Frame, Runtime}
  alias TermUI.Test.DeterministicBackend

  defmodule App do
    use TermUI.Elm

    def init(opts), do: %{count: 0, dimensions: Keyword.fetch!(opts, :dimensions), stopped: false}

    def event_to_msg(%Event.Key{key: :enter}, _state), do: {:msg, :increment}

    def event_to_msg(%Event.Resize{width: width, height: height}, _state),
      do: {:msg, {:resize, {width, height}}}

    def event_to_msg(%Event.Text{text: "q"}, _state), do: {:msg, :stop}
    def event_to_msg(_event, _state), do: :ignore

    def update(:increment, state), do: %{state | count: state.count + 1}
    def update({:resize, dimensions}, state), do: %{state | dimensions: dimensions}
    def update(:stop, state), do: {%{state | stopped: true}, [Command.shutdown()]}

    def view(state) do
      {width, height} = state.dimensions
      text = if state.stopped, do: "stopped", else: "count=#{state.count}"
      Frame.from_rows([text], width, height)
    end
  end

  test "injects events and resize values and captures complete shutdown state" do
    capabilities = %{colors: :ansi_16, unicode: false}

    assert {:ok, runtime} =
             TermUI.start_link(App,
               backend: {
                 DeterministicBackend,
                 owner: self(), size: {2, 10}, capabilities: capabilities
               },
               backend_opts: [size_poll_interval: :disabled]
             )

    runtime_reference = Process.monitor(runtime)
    assert_receive {:backend, :init, backend_owner}, 500
    assert is_pid(backend_owner)

    assert_receive {:backend, :draw, %Frame{width: 10, height: 2} = initial}, 500
    assert Frame.row_text(initial, 1) == "count=0   "
    assert Runtime.capabilities(runtime) == capabilities

    assert :ok = DeterministicBackend.send_event(runtime, Event.key(:enter))
    assert_receive {:backend, :draw, incremented}, 500
    assert Frame.row_text(incremented, 1) == "count=1   "

    assert :ok = DeterministicBackend.resize(runtime, 8, 3)
    assert_receive {:backend, :resize, {3, 8}}, 500
    assert_receive {:backend, :draw, %Frame{width: 8, height: 3}}, 500

    assert :ok = DeterministicBackend.send_event(runtime, Event.text("q"))
    assert_receive {:backend, :draw, final}, 500
    assert Frame.row_text(final, 1) == "stopped "
    assert_receive {:backend, :shutdown, :normal}, 500

    assert_receive {:backend, :shutdown_snapshot, snapshot}, 500
    assert snapshot.size == {3, 8}
    assert snapshot.capabilities == capabilities
    assert snapshot.pending_events == []
    assert snapshot.queued_events_delivered == 0
    assert snapshot.shutdown_reason == :normal
    assert Enum.all?(snapshot.frames, &match?(%Frame{}, &1))
    assert snapshot.frames |> List.first() |> Frame.row_text(1) == "count=0   "
    assert snapshot.frames |> List.last() |> Frame.row_text(1) == "stopped "

    assert_receive {:DOWN, ^runtime_reference, :process, ^runtime, :normal}, 500
  end
end
