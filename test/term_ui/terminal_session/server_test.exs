defmodule TermUI.TerminalSession.ServerTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame, TerminalSession}

  defmodule Driver do
    def available, do: :ok

    def start_terminal(opts) do
      Agent.start_link(fn -> snapshot(opts[:cols], opts[:rows], " ") end)
    end

    def start_pty(opts) do
      if opts[:cmd] == "fail" do
        {:error, :pty_open_failed}
      else
        Agent.start_link(fn -> %{writes: [], size: {opts[:rows], opts[:cols]}} end)
      end
    end

    def snapshot(terminal), do: Agent.get(terminal, & &1)

    def write_terminal(terminal, text) do
      Agent.update(terminal, fn %{cells: rows} ->
        snapshot(length(hd(rows)), length(rows), text)
      end)
    end

    def write_pty(pty, bytes), do: Agent.update(pty, &%{&1 | writes: &1.writes ++ [bytes]})

    def resize_terminal(terminal, columns, rows),
      do: Agent.update(terminal, fn _state -> snapshot(columns, rows, "R") end)

    def resize_pty(pty, columns, rows),
      do: Agent.update(pty, &%{&1 | size: {rows, columns}})

    def scroll(terminal, delta), do: write_terminal(terminal, if(delta < 0, do: "U", else: "D"))
    def key(_terminal, %Event.Text{text: text}), do: {:ok, text}
    def key(_terminal, %Event.Key{key: :up}), do: {:ok, "\e[A"}
    def key(_terminal, _event), do: {:error, :unsupported_key}
    def mouse(_terminal, _event), do: :none
    def focus(_terminal, _event), do: :none
    def paste(_terminal, _pty, content), do: {:ok, content}

    def stop(pid) do
      if Process.alive?(pid), do: Agent.stop(pid), else: :ok
    end

    defp snapshot(columns, rows, text) do
      %{
        cells: List.duplicate(List.duplicate({text, nil, nil, 0}, columns), rows),
        cursor: %{x: 0, y: 0, visible: true},
        scrollbar: %{total: rows, offset: 0, len: rows}
      }
    end
  end

  defp start(opts \\ []) do
    {:ok, session} = TerminalSession.start(Keyword.merge([driver: Driver, size: {2, 4}], opts))

    on_exit(fn ->
      if Process.alive?(session), do: TerminalSession.stop(session)
    end)

    session
  end

  defp frame(session) do
    assert_receive {:term_ui_terminal_frame, ^session, sequence, %Frame{} = frame, metadata},
                   1_000

    {sequence, frame, metadata}
  end

  test "keeps one frame in flight and only the latest waiting frame" do
    session = start()
    {first, _frame, _metadata} = frame(session)

    for text <- ["A", "B", "C"] do
      send(session, {:data, text})
      send(session, :render)
      assert %{output_queue: %{in_flight: 1, pending_frames: 1}} = TerminalSession.info(session)
    end

    refute_receive {:term_ui_terminal_frame, ^session, _sequence, _frame, _metadata}, 20
    assert {:error, :future_acknowledgement} = TerminalSession.acknowledge(session, first + 1)
    assert :ok = TerminalSession.acknowledge(session, first)
    {second, latest, _metadata} = frame(session)
    assert second == first + 1
    assert Frame.row_text(latest, 1) == "CCCC"
    assert :ok = TerminalSession.acknowledge(session, first)
    assert {:error, :invalid_acknowledgement} = TerminalSession.acknowledge(session, 0)
  end

  test "input and query replies go to one PTY and resize updates both owners" do
    session = start()
    %{terminal: terminal, pty: pty} = TerminalSession.info(session)
    {sequence, _frame, _metadata} = frame(session)
    assert :ok = TerminalSession.acknowledge(session, sequence)
    assert :ok = TerminalSession.input(session, Event.text("é"))
    assert :ok = TerminalSession.input(session, Event.key(:up))
    assert :ok = TerminalSession.input(session, Event.paste("one\ntwo"))
    assert :ok = TerminalSession.input(session, Event.focus(:gained))
    assert :ok = TerminalSession.input(session, Event.mouse(:press, :left, 1, 1))
    assert {:error, :invalid_input} = TerminalSession.input(session, Event.resize(301, 121))
    assert {:error, :unsupported_key} = TerminalSession.input(session, Event.key(:f12))
    assert {:error, :invalid_input} = TerminalSession.input(session, :bad)
    send(session, {:pty_write, "reply"})
    assert :ok = TerminalSession.input(session, Event.resize(6, 3))
    assert Agent.get(pty, & &1) == %{writes: ["é", "\e[A", "one\ntwo", "reply"], size: {3, 6}}
    assert length(Driver.snapshot(terminal).cells) == 3
    send(session, {:terminal_input, Event.key(:f12)})
    assert_receive {:term_ui_terminal_error, ^session, {:error, :unsupported_key}}
    send(session, {:terminal_input, Event.text("X")})
    send(session, {:terminal_ack, 9_999})
    assert_receive {:term_ui_terminal_error, ^session, {:error, :future_acknowledgement}}
    send(session, :bell)
    send(session, :title_changed)
    assert_receive {:term_ui_terminal_effect, ^session, :bell}
    assert_receive {:term_ui_terminal_effect, ^session, :title_changed}
    assert :ok = TerminalSession.input(session, Event.mouse(:scroll_up, nil, 0, 0))
    assert :ok = TerminalSession.input(session, Event.mouse(:scroll_down, nil, 0, 0))
    assert Driver.snapshot(terminal).cells |> hd() |> hd() == {"D", nil, nil, 0}
  end

  test "child exit sends its final frame before closing both children" do
    session = start()
    %{terminal: terminal, pty: pty} = TerminalSession.info(session)
    monitor = Process.monitor(session)
    {sequence, _frame, _metadata} = frame(session)
    send(session, {:data, "Z"})
    send(session, {:exit, 0})
    send(session, :render)
    assert %{exit_status: 0} = TerminalSession.info(session)
    assert {:error, :child_exited} = TerminalSession.input(session, Event.text("x"))
    assert :ok = TerminalSession.acknowledge(session, sequence)
    {last, final, _metadata} = frame(session)
    assert Frame.row_text(final, 1) == "ZZZZ"
    send(session, {:terminal_ack, last})
    # A queued render can produce one more identical final frame.
    drain_until_closed(session)
    assert_receive {:DOWN, ^monitor, :process, ^session, :normal}
    refute Process.alive?(terminal)
    refute Process.alive?(pty)
  end

  test "confirmation timeout stops the session and its children" do
    session = start(output_timeout: 100)
    %{terminal: terminal, pty: pty} = TerminalSession.info(session)
    frame(session)
    assert_receive {:term_ui_terminal_closed, ^session, :output_timeout}, 1_000
    refute Process.alive?(terminal)
    refute Process.alive?(pty)

    session = start(output_timeout: 100)
    frame(session)
    send(session, {:exit, 0})
    assert_receive {:term_ui_terminal_closed, ^session, :output_timeout}, 1_000
  end

  test "owner exit and forced session exit cannot leave linked children" do
    parent = self()

    owner =
      spawn(fn ->
        {:ok, session} = TerminalSession.start(driver: Driver, size: {2, 4})
        send(parent, {:owned, session, TerminalSession.info(session)})

        receive do
          :exit -> :ok
        end
      end)

    assert_receive {:owned, session, %{terminal: terminal, pty: pty}}
    monitors = Enum.map([session, terminal, pty], &{&1, Process.monitor(&1)})
    send(owner, :exit)
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, _reason}, 1_000)

    other = start()
    %{terminal: terminal, pty: pty} = TerminalSession.info(other)
    monitors = Enum.map([terminal, pty], &{&1, Process.monitor(&1)})
    Process.exit(other, :kill)
    for {pid, ref} <- monitors, do: assert_receive({:DOWN, ^ref, :process, ^pid, :killed}, 1_000)
  end

  test "separate sessions keep separate frames, input, and cleanup" do
    first = start()
    second = start()
    %{pty: first_pty} = TerminalSession.info(first)
    %{pty: second_pty} = TerminalSession.info(second)
    assert :ok = TerminalSession.input(first, Event.text("A"))
    assert :ok = TerminalSession.input(second, Event.text("B"))
    assert Agent.get(first_pty, & &1.writes) == ["A"]
    assert Agent.get(second_pty, & &1.writes) == ["B"]
    send(first, :terminal_stop)
    assert_receive {:term_ui_terminal_closed, ^first, :normal}
    assert :ok = TerminalSession.stop(first)
    assert Process.alive?(second)
  end

  test "invalid size and failed PTY start return errors" do
    assert {:error, :invalid_session_options} =
             TerminalSession.start(driver: Driver, size: {0, 80})

    assert {:error, :pty_open_failed} = TerminalSession.start(driver: Driver, cmd: "fail")
  end

  test "child failure and oversized output close the whole session" do
    session = start()
    %{pty: pty} = TerminalSession.info(session)
    Agent.stop(pty)
    assert_receive {:term_ui_terminal_closed, ^session, {:child_exit, :normal}}, 1_000
    session = start()
    send(session, {:data, String.duplicate("x", 65_537)})
    assert_receive {:term_ui_terminal_closed, ^session, :output_chunk_limit}, 1_000
  end

  test "excess queued child output closes the session instead of keeping an unbounded mailbox" do
    session = start()
    :ok = :sys.suspend(session)
    for _index <- 1..1_026, do: send(session, {:data, "X"})
    :ok = :sys.resume(session)
    assert_receive {:term_ui_terminal_closed, ^session, :input_overflow}, 1_000
  end

  defp drain_until_closed(session) do
    receive do
      {:term_ui_terminal_frame, ^session, sequence, _frame, _metadata} ->
        send(session, {:terminal_ack, sequence})
        drain_until_closed(session)

      {:term_ui_terminal_closed, ^session, {:exit, 0}} ->
        :ok
    after
      1_000 -> flunk("session did not close after final confirmation")
    end
  end
end
