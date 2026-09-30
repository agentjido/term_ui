defmodule IExCounter.AppTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame, Runtime}
  alias TermUI.Test.DeterministicBackend

  setup do
    opts = [
      backend: {DeterministicBackend, owner: self(), size: {6, 40}},
      backend_opts: [size_poll_interval: :disabled]
    ]

    runtime =
      start_supervised!(%{
        id: IExCounter.App,
        start: {TermUI, :start_link, [IExCounter.App, opts]},
        restart: :temporary
      })

    assert_receive {:backend, :draw, %Frame{width: 40, height: 6} = initial}, 1_000
    assert String.trim(Frame.row_text(initial, 3)) == "Count: 0"

    {:ok, runtime: runtime, reference: Process.monitor(runtime)}
  end

  test "Up, Down, reset, and uppercase quit follow the documented controls", context do
    send_and_assert_count(context.runtime, Event.key(:up), 1)
    send_and_assert_count(context.runtime, Event.key(:down), 0)
    send_and_assert_count(context.runtime, Event.key(:down), -1)
    send_and_assert_count(context.runtime, Event.text("R"), 0)

    :ok = DeterministicBackend.send_event(context.runtime, Event.text("Q"))
    assert_receive {:backend, :shutdown, :normal}, 1_000
    reference = context.reference
    runtime = context.runtime
    assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}, 1_000
  end

  test "resize preserves the count and clips the complete frame", %{runtime: runtime} do
    send_and_assert_count(runtime, Event.key(:up), 1)
    :ok = DeterministicBackend.resize(runtime, 10, 3)
    assert_receive {:backend, :resize, {3, 10}}, 1_000
    assert_receive {:backend, :draw, %Frame{width: 10, height: 3} = resized}, 1_000
    assert String.trim(Frame.row_text(resized, 3)) == "Count: 1"
    assert Runtime.get_state(runtime).app_state == %{count: 1, dimensions: {10, 3}}

    assert Enum.all?(resized.cells, fn {{row, column}, _cell} ->
             column in 1..10 and row in 1..3
           end)
  end

  defp send_and_assert_count(runtime, event, count) do
    :ok = DeterministicBackend.send_event(runtime, event)
    assert_receive {:backend, :draw, frame}, 1_000
    assert String.trim(Frame.row_text(frame, 3)) == "Count: #{count}"
    assert Runtime.get_state(runtime).app_state.count == count
  end
end
