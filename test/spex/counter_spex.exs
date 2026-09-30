Code.require_file("../../examples/iex_counter/lib/iex_counter/app.ex", __DIR__)

defmodule TermUI.CounterSpex do
  use SexySpex

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

    {:ok, runtime: runtime, reference: Process.monitor(runtime)}
  end

  spex "the shipped counter responds to input and quits normally" do
    scenario "the user increments the counter and quits" do
      given_ "the counter starts at zero", context do
        assert_receive {:backend, :draw, %Frame{width: 40, height: 6} = initial}, 1_000
        assert String.trim(Frame.row_text(initial, 3)) == "Count: 0"
        {:ok, context}
      end

      when_ "the user presses Up", context do
        :ok = DeterministicBackend.send_event(context.runtime, Event.key(:up))
        assert_receive {:backend, :draw, incremented}, 1_000
        {:ok, Map.put(context, :incremented, incremented)}
      end

      then_ "the state and visible count are one", context do
        assert Runtime.get_state(context.runtime).app_state.count == 1
        assert String.trim(Frame.row_text(context.incremented, 3)) == "Count: 1"
        {:ok, context}
      end

      when_ "the user presses q", context do
        :ok = DeterministicBackend.send_event(context.runtime, Event.text("q"))
        {:ok, context}
      end

      then_ "the backend is cleaned up and the runtime exits normally", context do
        assert_receive {:backend, :shutdown, :normal}, 1_000
        reference = context.reference
        runtime = context.runtime
        assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}, 1_000
        {:ok, context}
      end
    end
  end
end
