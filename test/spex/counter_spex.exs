defmodule TermUI.CounterSpex do
  use SexySpex

  alias TermUI.{Event, Frame, Runtime}
  alias TermUI.Test.DeterministicBackend

  defmodule Counter do
    use TermUI.Elm

    def init(_opts), do: %{count: 0}
    def event_to_msg(%Event.Key{key: :up}, _state), do: {:msg, :increment}
    def event_to_msg(_event, _state), do: :ignore
    def update(:increment, state), do: %{state | count: state.count + 1}
    def view(state), do: Frame.from_rows(["Count: #{state.count}"], 20, 2)
  end

  spex "a counter responds to keyboard input" do
    try do
      scenario "the user increments a new counter" do
        given_ "a counter with an initial value of zero", context do
          {:ok, runtime} =
            TermUI.start_link(Counter,
              backend: {DeterministicBackend, owner: self(), size: {2, 20}},
              backend_opts: [size_poll_interval: :disabled]
            )

          Process.unlink(runtime)
          Process.put(:counter_spex_runtime, runtime)
          assert_receive {:backend, :draw, initial}, 500
          assert Frame.row_text(initial, 1) == "Count: 0            "

          {:ok, Map.put(context, :runtime, runtime)}
        end

        when_ "the user presses the Up key", context do
          :ok = DeterministicBackend.send_event(context.runtime, Event.key(:up))
          assert_receive {:backend, :draw, incremented}, 500
          {:ok, Map.put(context, :incremented, incremented)}
        end

        then_ "the counter state changes to one", context do
          assert Runtime.get_state(context.runtime).app_state.count == 1
          {:ok, context}
        end

        and_ "the rendered output shows the new count", context do
          assert Frame.row_text(context.incremented, 1) == "Count: 1            "
          {:ok, context}
        end
      end
    after
      if runtime = Process.delete(:counter_spex_runtime) do
        reference = Process.monitor(runtime)
        Runtime.shutdown(runtime)

        receive do
          {:DOWN, ^reference, :process, ^runtime, _reason} -> :ok
        after
          1_000 -> Process.exit(runtime, :kill)
        end
      end
    end
  end
end
