defmodule TermUI.Integration.RedrawRecoveryTest do
  use ExUnit.Case, async: false

  alias TermUI.Backend.{Manager, Raw, TTY}
  alias TermUI.{Event, Frame, Runtime, Style}

  defmodule Screen do
    use TermUI.Elm

    def init(_opts), do: %{rows: ["LEFT", "RIGHT", "END"]}
    def event_to_msg(_event, _state), do: :ignore
    def update({:rows, rows}, state), do: %{state | rows: rows}
    def view(state), do: Frame.from_rows(state.rows, 8, 3, cursor: {1, 3})
  end

  defmodule OutputBackend do
    @behaviour TermUI.Backend

    def init(opts) do
      backend = Keyword.fetch!(opts, :implementation)
      {:ok, state} = backend.init(opts)
      {:ok, %{backend: backend, state: state}}
    end

    def size(state), do: state.backend.size(state.state)
    def capabilities(state), do: state.backend.capabilities(state.state)
    def draw(state, frame), do: invoke(state, :draw, [frame])
    def flush(state), do: invoke(state, :flush, [])
    def invalidate(state), do: invoke(state, :invalidate, [])
    def resume(state), do: invoke(state, :resume, [])
    def resize(state, size), do: invoke(state, :resize, [size])
    def shutdown(state, reason), do: state.backend.shutdown(state.state, reason)

    def poll_event(state, timeout) do
      receive do
      after
        timeout -> {:timeout, state}
      end
    end

    defp invoke(state, callback, args) do
      case apply(state.backend, callback, [state.state | args]) do
        {:ok, next} -> {:ok, %{state | state: next}}
        error -> error
      end
    end
  end

  @tag :redraw_regression
  test "forced rendering repairs unchanged output in each incremental local backend" do
    for backend <- [Raw, TTY] do
      {runtime, device} = start_screen(backend)
      snapshot = output(device)

      Runtime.force_render(runtime)
      assert :ok = Runtime.sync(runtime)

      repaired = String.replace_prefix(output(device), snapshot, "")
      assert repaired =~ "\e[0m\e[2J"
      assert repaired =~ "LEFT"
      assert repaired =~ "RIGHT"
      assert repaired =~ "END"
      assert repaired =~ "\e[3;1H\e[?25h"
      assert Runtime.get_state(runtime).app_state.rows == ["LEFT", "RIGHT", "END"]
      stop_screen(runtime, device)
    end
  end

  @tag :redraw_regression
  test "ignored focus gain repairs the screen without an application update" do
    for backend <- [Raw, TTY] do
      {runtime, device} = start_screen(backend)
      snapshot = output(device)

      send(runtime, {:backend_event, Event.focus(:gained)})
      assert :ok = Runtime.sync(runtime)

      repaired = String.replace_prefix(output(device), snapshot, "")
      assert repaired =~ "\e[2J"
      assert repaired =~ "LEFT"
      assert repaired =~ "RIGHT"
      assert repaired =~ "END"
      stop_screen(runtime, device)
    end
  end

  test "ordinary updates erase removed cells without a full redraw" do
    for backend <- [Raw, TTY] do
      {:ok, device} = StringIO.open("")
      previous = Process.group_leader()
      Process.group_leader(self(), device)

      try do
        {:ok, state} = backend.init(backend_options())
        {:ok, state} = backend.draw(state, Frame.from_rows(["LEFT", "RIGHT", "END"], 8, 3))
        snapshot = output(device)
        {:ok, _state} = backend.draw(state, Frame.from_rows(["X"], 8, 3))

        changed = String.replace_prefix(output(device), snapshot, "")
        assert changed =~ "X"
        assert changed =~ " "
        refute changed =~ "\e[2J"
      after
        Process.group_leader(self(), previous)
        StringIO.close(device)
      end
    end
  end

  test "resume restores terminal features and complete unchanged output" do
    for backend <- [Raw, TTY] do
      {runtime, device} =
        start_screen(backend, alternate_screen: true, bracketed_paste: true, focus_events: true)

      snapshot = output(device)
      manager = Runtime.get_state(runtime).backend_manager

      send(manager, :terminal_resume)
      assert %{size: {3, 8}} = Manager.info(manager)
      assert :ok = Runtime.sync(runtime)

      repaired = String.replace_prefix(output(device), snapshot, "")
      assert repaired =~ "\e[0m\e[?1049h"
      assert repaired =~ "\e[?2004h"
      assert repaired =~ "\e[?1004h"
      assert repaired =~ "LEFT"
      assert repaired =~ "RIGHT"
      assert repaired =~ "END"
      assert Runtime.get_state(runtime).app_state.rows == ["LEFT", "RIGHT", "END"]
      stop_screen(runtime, device)
    end
  end

  test "raw resume preserves queued input and the existing OTP signals session" do
    {:ok, device} = StringIO.open("complete\e[201~")
    previous = Process.group_leader()
    Process.group_leader(self(), device)

    try do
      {:ok, state} = Raw.init(backend_options() ++ [raw_mode_session: :otp_signals])
      event = Event.text("pending")
      state = %{state | event_queue: [event], input_buffer: "\e[200~unfinished"}

      assert {:ok, resumed} = Raw.resume(state)
      assert resumed.raw_mode_session == :otp_signals
      assert {:ok, ^event, next} = Raw.poll_event(resumed, 0)
      assert next.input_buffer == "\e[200~unfinished"

      assert {:ok, %Event.Paste{content: "unfinishedcomplete"}, next} =
               Raw.poll_event(next, 1_000)

      assert next.input_buffer == ""
      Raw.shutdown(next, :normal)
    after
      Process.group_leader(self(), previous)
      StringIO.close(device)
    end
  end

  test "invalidation restores a styled frame after external ANSI state changes" do
    for backend <- [Raw, TTY] do
      {:ok, device} = StringIO.open("")
      previous = Process.group_leader()
      Process.group_leader(self(), device)

      try do
        {:ok, state} = backend.init(backend_options())
        frame = Frame.from_rows([[{"界", Style.new(fg: :green)}], "plain"], 8, 3)
        {:ok, state} = backend.draw(state, frame)
        snapshot = output(device)
        {:ok, state} = backend.invalidate(state)
        {:ok, _state} = backend.draw(state, frame)

        repaired = String.replace_prefix(output(device), snapshot, "")
        assert repaired =~ "\e[0m\e[2J"
        assert repaired =~ "界"
        assert repaired =~ "plain"
      after
        Process.group_leader(self(), previous)
        StringIO.close(device)
      end
    end
  end

  test "resume reports a lost output device without changing cached state" do
    for backend <- [Raw, TTY] do
      {:ok, device} = StringIO.open("")
      previous = Process.group_leader()
      Process.group_leader(self(), device)

      try do
        {:ok, state} = backend.init(backend_options())
        {:ok, state} = backend.draw(state, Frame.from_rows(["UNCHANGED"], 8, 3))
        StringIO.close(device)
        assert {:error, _reason} = backend.resume(state)
        assert {:ok, {3, 8}} = backend.size(state)
      after
        Process.group_leader(self(), previous)
      end
    end
  end

  defp start_screen(backend, opts \\ []) do
    {:ok, device} = StringIO.open("")
    previous = Process.group_leader()
    Process.group_leader(self(), device)

    try do
      {:ok, runtime} =
        Runtime.start_link(
          root: Screen,
          backend:
            {OutputBackend, [implementation: backend] ++ Keyword.merge(backend_options(), opts)},
          suppress_logger: false,
          render_interval: 60_000
        )

      assert :ok = Runtime.sync(runtime)

      on_exit(fn ->
        if Process.alive?(runtime), do: GenServer.stop(runtime)
        if Process.alive?(device), do: StringIO.close(device)
      end)

      {runtime, device}
    after
      Process.group_leader(self(), previous)
    end
  end

  defp backend_options do
    [
      size: {3, 8},
      line_mode: :incremental,
      alternate_screen: false,
      bracketed_paste: false,
      focus_events: false
    ]
  end

  defp stop_screen(runtime, device) do
    reference = Process.monitor(runtime)
    Runtime.shutdown(runtime)
    assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}, 1_000
    StringIO.close(device)
  end

  defp output(device), do: device |> StringIO.contents() |> elem(1)
end
