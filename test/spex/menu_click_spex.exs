defmodule TermUI.MenuClickSpex do
  use SexySpex

  alias TermUI.{Event, Frame, Runtime}
  alias TermUI.Test.DeterministicBackend
  alias TermUI.Widget.Menu

  defmodule App do
    use TermUI.Elm

    def init(_opts) do
      menu =
        Menu.init(
          items: [
            Menu.submenu(:file, "File", [Menu.action(:a, "A"), Menu.action(:b, "B")]),
            Menu.action(:help, "Help"),
            Menu.action(:exit, "Exit"),
            Menu.action(:delete, "Delete")
          ]
        )
        |> Menu.open_submenu()

      %{menu: menu, selected: nil}
    end

    def event_to_msg(%Event.Resize{}, _), do: :ignore
    def event_to_msg(event, _), do: {:msg, event}

    def update(%Event.Mouse{} = event, state) do
      {menu, messages} = Menu.mouse(event, state.menu, {24, 10})
      selected = Keyword.get(messages, :selected, state.selected)
      %{state | menu: menu, selected: selected}
    end

    def update(_, state), do: state
    def view(%{selected: nil} = state), do: Menu.view(state.menu, {24, 10})
    def view(state), do: Frame.from_rows(["Selected: #{state.selected}"], 24, 10)
  end

  spex "a complete click selects the action displayed below an open submenu" do
    scenario "resize then press and release Help" do
      given_ "the File submenu has two rows above Help", context do
        runtime =
          start_supervised!(%{
            id: App,
            start:
              {TermUI, :start_link,
               [
                 App,
                 [
                   backend: {DeterministicBackend, owner: self(), size: {10, 24}},
                   backend_opts: [size_poll_interval: :disabled]
                 ]
               ]},
            restart: :temporary
          })

        assert_receive {:backend, :draw, frame}, 1000
        assert Frame.row_text(frame, 5) =~ "Help"
        {:ok, Map.put(context, :runtime, runtime)}
      end

      when_ "the application ignores a resize event", context do
        DeterministicBackend.send_event(context.runtime, Event.resize(30, 12))
        assert_receive {:backend, :draw, frame}, 1000
        assert Frame.row_text(frame, 5) =~ "Help"
        {:ok, context}
      end

      when_ "the user presses the displayed Help row", context do
        DeterministicBackend.send_event(context.runtime, Event.mouse(:press, :left, 2, 4))
        assert_receive {:backend, :draw, frame}, 1000
        assert Frame.row_text(frame, 5) =~ "Help"
        assert Runtime.get_state(context.runtime).app_state.selected == nil
        {:ok, context}
      end

      then_ "release selects Help exactly once", context do
        DeterministicBackend.send_event(context.runtime, Event.mouse(:release, :left, 2, 4))
        assert_receive {:backend, :draw, frame}, 1000
        assert Frame.row_text(frame, 1) =~ "Selected: help"
        assert Runtime.get_state(context.runtime).app_state.selected == :help
        reference = Process.monitor(context.runtime)
        Runtime.shutdown(context.runtime)
        assert_receive {:backend, :shutdown, :normal}, 1000
        runtime = context.runtime
        assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}, 1000
        {:ok, context}
      end
    end
  end
end
