defmodule TermUIGhosttyExample.SessionTest do
  use ExUnit.Case, async: false

  alias TermUI.{Event, Frame, TerminalSession}

  defp start(opts) do
    {:ok, session} = TerminalSession.start(opts)
    on_exit(fn -> if Process.alive?(session), do: TerminalSession.stop(session) end)
    session
  end

  defp frame_until(session, predicate, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 5_000
    remaining = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {:term_ui_terminal_frame, ^session, sequence, frame, metadata} ->
        send(session, {:terminal_ack, sequence})
        if predicate.(frame, metadata), do: frame, else: frame_until(session, predicate, deadline)

      {:term_ui_terminal_closed, ^session, reason} ->
        flunk("child closed before expected frame: #{inspect(reason)}")
    after
      remaining -> flunk("no expected real PTY frame")
    end
  end

  defp record(path, predicate, attempts \\ 100)
  defp record(_path, _predicate, 0), do: flunk("PTY record condition did not pass")

  defp record(path, predicate, attempts) do
    result = with {:ok, bytes} <- File.read(path), {:ok, value} <- Jason.decode(bytes), do: value

    if is_map(result) and predicate.(result) do
      result
    else
      Process.sleep(20)
      record(path, predicate, attempts - 1)
    end
  end

  defp process_stopped(pid, attempts \\ 100)
  defp process_stopped(_pid, 0), do: flunk("PTY OS child did not stop")

  defp process_stopped(pid, attempts) do
    case System.cmd("kill", ["-0", to_string(pid)], stderr_to_stdout: true) do
      {_output, 0} ->
        Process.sleep(20)
        process_stopped(pid, attempts - 1)

      {_output, _error} ->
        :ok
    end
  end

  defp python do
    if File.exists?("/usr/bin/python3"),
      do: "/usr/bin/python3",
      else: System.find_executable("python3")
  end

  @tag :tmp_dir
  test "real child input, query replies, resize, styles, and normal cleanup", %{
    tmp_dir: directory
  } do
    path = Path.join(directory, "record.json")

    session =
      start(cmd: python(), args: [Path.expand("support/terminal_probe.py", __DIR__), path])

    %{terminal: terminal, pty: pty} = TerminalSession.info(session)
    frame = frame_until(session, fn frame, _metadata -> Frame.row_text(frame, 2) =~ "READY" end)
    assert Frame.cell(frame, 1, 1).char == "é"
    assert Frame.cell(frame, 1, 1).fg == {12, 34, 56}
    assert Frame.cell(frame, 1, 2).char == "界"
    assert Frame.cell(frame, 1, 3).wide_placeholder

    pid =
      record(path, &String.contains?(&1["input"], Base.encode16("\e[1;4R", case: :lower)))["pid"]

    assert :ok = TerminalSession.input(session, Event.text("é"))
    assert :ok = TerminalSession.input(session, Event.key(:up))
    assert :ok = TerminalSession.input(session, Event.key("o", modifiers: [:ctrl]))
    assert :ok = TerminalSession.input(session, Event.paste("one\ntwo"))
    assert :ok = TerminalSession.input(session, Event.focus(:gained))
    assert :ok = TerminalSession.input(session, Event.focus(:lost))
    assert :ok = TerminalSession.input(session, Event.mouse(:press, :left, 2, 2))
    assert :ok = TerminalSession.input(session, Event.mouse(:release, :left, 2, 2))
    assert :ok = TerminalSession.input(session, Event.resize(60, 18))

    input =
      record(
        path,
        &(&1["size"] == [18, 60] and String.contains?(&1["input"], "1b5b3c303b333b336d"))
      )

    bytes = Base.decode16!(input["input"], case: :lower)

    for expected <- [
          "é",
          "\e[A",
          <<15>>,
          "\e[200~one\ntwo\e[201~",
          "\e[I",
          "\e[O",
          "\e[<0;3;3M",
          "\e[<0;3;3m"
        ],
        do: assert(bytes =~ expected)

    refute bytes =~ "\e[?2004;1$y"
    assert TermUI.TerminalSession.Ghostty.snapshot(terminal).cells |> length() == 18
    assert :ok = TerminalSession.input(session, Event.key("d", modifiers: [:ctrl]))
    finish(session)
    refute Process.alive?(terminal)
    refute Process.alive?(pty)
    process_stopped(pid)
  end

  @tag :tmp_dir
  test "forced session exit and owner exit stop the real OS child", %{tmp_dir: directory} do
    path = Path.join(directory, "forced.json")
    opts = [cmd: python(), args: [Path.expand("support/terminal_probe.py", __DIR__), path]]
    session = start(opts)
    %{terminal: terminal, pty: pty} = TerminalSession.info(session)
    frame_until(session, fn frame, _metadata -> Frame.row_text(frame, 2) =~ "READY" end)
    pid = record(path, &is_integer(&1["pid"]))["pid"]
    monitor = Process.monitor(session)
    Process.exit(session, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^session, :killed}
    process_stopped(pid)
    refute Process.alive?(terminal)
    refute Process.alive?(pty)

    path = Path.join(directory, "owner.json")
    parent = self()

    owner =
      spawn(fn ->
        {:ok, session} =
          TerminalSession.start(
            cmd: python(),
            args: [Path.expand("support/terminal_probe.py", __DIR__), path]
          )

        send(parent, {:owned, session, TerminalSession.info(session)})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:owned, owned, info}
    pid = record(path, &is_integer(&1["pid"]))["pid"]
    monitor = Process.monitor(owned)
    send(owner, :stop)
    assert_receive {:DOWN, ^monitor, :process, ^owned, :normal}, 2_000
    process_stopped(pid)
    refute Process.alive?(info.terminal)
    refute Process.alive?(info.pty)
  end

  @tag :tmp_dir
  test "vim uses the alternate screen and writes through real keyboard input", %{
    tmp_dir: directory
  } do
    file = Path.join(directory, "vim.txt")

    vim =
      System.find_executable("vim") || flunk("vim is required for the native acceptance check")

    session = start(cmd: vim, args: ["-Nu", "NONE", "-n", "-i", "NONE", file], size: {12, 50})
    frame_until(session, fn frame, _metadata -> Frame.row_text(frame, 12) =~ "vim.txt" end)
    assert :ok = TerminalSession.input(session, Event.text("i"))
    assert :ok = TerminalSession.input(session, Event.text("Ghostty works"))
    frame_until(session, fn frame, _metadata -> Frame.row_text(frame, 1) =~ "Ghostty works" end)
    assert :ok = TerminalSession.input(session, Event.resize(60, 16))
    frame_until(session, fn frame, _metadata -> frame.width == 60 and frame.height == 16 end)
    assert :ok = TerminalSession.input(session, Event.key(:escape))
    assert :ok = TerminalSession.input(session, Event.text(":wq"))
    assert :ok = TerminalSession.input(session, Event.key(:enter))
    finish(session)
    assert File.read!(file) == "Ghostty works\n"
  end

  @tag :tmp_dir
  test "scrollback and two real shells keep their own state", %{tmp_dir: directory} do
    session =
      start(
        cmd: "/bin/sh",
        args: [
          "-c",
          "for n in 1 2 3 4 5 6 7 8 9; do printf 'ROW%s\\r\\n' \"$n\"; done; read answer"
        ],
        size: {3, 20}
      )

    frame_until(session, fn frame, _metadata ->
      Enum.any?(1..3, &(Frame.row_text(frame, &1) =~ "ROW9"))
    end)

    assert :ok = TerminalSession.input(session, Event.mouse(:scroll_up, nil, 0, 0))

    frame_until(session, fn _frame, metadata ->
      metadata.scrollbar.offset < metadata.scrollbar.total - metadata.scrollbar.len
    end)

    assert :ok = TerminalSession.input(session, Event.mouse(:scroll_down, nil, 0, 0))

    frame_until(session, fn frame, _metadata ->
      Enum.any?(1..3, &(Frame.row_text(frame, &1) =~ "ROW9"))
    end)

    other = start(cmd: "/bin/sh", args: ["-c", "printf SECOND; read answer"], size: {3, 20})
    frame_until(other, fn frame, _metadata -> Frame.row_text(frame, 1) =~ "SECOND" end)
    TerminalSession.stop(session)
    assert Process.alive?(other)
    assert :ok = TerminalSession.input(other, Event.key(:enter))
    finish(other)
    assert File.dir?(directory)
  end

  defp finish(session) do
    receive do
      {:term_ui_terminal_frame, ^session, sequence, _frame, _metadata} ->
        send(session, {:terminal_ack, sequence})
        finish(session)

      {:term_ui_terminal_closed, ^session, {:exit, 0}} ->
        :ok
    after
      5_000 -> flunk("real child did not close")
    end
  end
end
