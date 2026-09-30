defmodule TermUI.Backend.FrameBoundaryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias TermUI.Backend.{Raw, TTY}
  alias TermUI.{Clipboard, Event, Frame, Style}

  test "production backends expose one Frame render callback" do
    for backend <- [Raw, TTY] do
      Code.ensure_loaded!(backend)
      assert function_exported?(backend, :draw, 2)
      assert function_exported?(backend, :poll_event, 2)
      assert function_exported?(backend, :shutdown, 2)
      refute function_exported?(backend, :draw_cells, 2)
    end
  end

  test "TTY draws a styled Unicode frame and tracks the canonical frame" do
    frame =
      Frame.from_rows(
        [[{"界", Style.new(fg: :green, attrs: [:bold])}], "clear"],
        8,
        2,
        cursor: {2, 2}
      )

    capture_io(fn ->
      {:ok, state} =
        TTY.init(
          size: {2, 8},
          alternate_screen: false,
          bracketed_paste: false,
          focus_events: false,
          line_mode: :incremental
        )

      assert {:ok, drawn_state} = TTY.draw(state, frame)
      assert drawn_state.rendered_frame == frame
      assert {:ok, flushed_state} = TTY.flush(drawn_state)
      assert :ok = TTY.shutdown(flushed_state, :normal)
    end)
  end

  test "TTY restores terminal modes after a failure" do
    output =
      capture_io(fn ->
        {:ok, state} =
          TTY.init(
            size: {2, 8},
            alternate_screen: true,
            bracketed_paste: true,
            focus_events: true
          )

        assert :ok = TTY.shutdown(state, {:application, :failed})
      end)

    assert output =~ "\e[?2004l"
    assert output =~ "\e[?1004l"
    assert output =~ "\e[0m"
    assert output =~ "\e[?25h"
    assert output =~ "\e[?1049l"
  end

  test "TTY keeps exact columns after a wide grapheme" do
    output =
      capture_io(fn ->
        {:ok, state} =
          TTY.init(
            size: {1, 4},
            alternate_screen: false,
            bracketed_paste: false,
            focus_events: false,
            line_mode: :incremental
          )

        frame = Frame.from_rows(["界b"], 4, 1)
        assert {:ok, state} = TTY.draw(state, frame)
        TTY.shutdown(state, :normal)
      end)

    assert output =~ "界"
    refute output =~ "\e[1;3H"
    refute output =~ "\e[1;4H"
  end

  test "TTY emits standalone Escape and retains a fragmented large paste" do
    paste = String.duplicate("A", 2_000)

    capture_io("\e", fn ->
      {:ok, state} =
        TTY.init(
          size: {2, 8},
          alternate_screen: false,
          bracketed_paste: false,
          focus_events: false
        )

      assert {:ok, %Event.Key{key: :escape}, state} = TTY.poll_event(state, 10)
      TTY.shutdown(state, :normal)
    end)

    capture_io("\e[200~" <> paste <> "\e[201~", fn ->
      {:ok, state} =
        TTY.init(
          size: {2, 8},
          alternate_screen: false,
          bracketed_paste: false,
          focus_events: false
        )

      assert {:ok, %Event.Paste{content: ^paste}, state} = await_event(TTY, state, 20)
      TTY.shutdown(state, :normal)
    end)
  end

  test "TTY normalizes line feed as Enter" do
    capture_io("\n", fn ->
      {:ok, state} =
        TTY.init(
          size: {2, 8},
          alternate_screen: false,
          bracketed_paste: false,
          focus_events: false
        )

      assert {:ok, %Event.Key{key: :enter}, state} = TTY.poll_event(state, 10)
      TTY.shutdown(state, :normal)
    end)
  end

  test "Raw resize clears stale terminal content" do
    output =
      capture_io(fn ->
        {:ok, state} =
          Raw.init(
            size: {2, 8},
            alternate_screen: false,
            bracketed_paste: false,
            focus_events: false
          )

        assert {:ok, _state} = Raw.resize(state, {1, 4})
      end)

    assert length(:binary.matches(output, "\e[2J")) >= 2
  end

  test "production backends return terminal write failures" do
    for backend <- [Raw, TTY] do
      {:ok, io} = StringIO.open("")
      original = Process.group_leader()
      Process.group_leader(self(), io)

      {:ok, state} =
        backend.init(
          size: {1, 4},
          alternate_screen: false,
          bracketed_paste: false,
          focus_events: false
        )

      Process.group_leader(self(), original)
      StringIO.close(io)

      rejecting_io = spawn(fn -> reject_io_requests() end)
      Process.group_leader(self(), rejecting_io)

      try do
        assert {:error, {:terminal_write_failed, _reason}} =
                 backend.draw(state, Frame.from_rows(["ok"], 4, 1))
      after
        Process.group_leader(self(), original)
        Process.exit(rejecting_io, :kill)
      end
    end
  end

  test "production backends write bounded clipboard operations through their state callback" do
    for backend <- [Raw, TTY] do
      output =
        capture_io(fn ->
          {:ok, state} =
            backend.init(
              size: {1, 4},
              alternate_screen: false,
              bracketed_paste: false,
              focus_events: false
            )

          assert {:ok, state} = backend.clipboard(state, Clipboard.operation("copy"))
          assert :ok = backend.shutdown(state, :normal)
        end)

      assert output =~ "\e]52;c;Y29weQ==\e\\"
    end
  end

  test "backend state reports size, capabilities, and bounded clipboard failures" do
    for backend <- [Raw, TTY] do
      capture_io(fn ->
        {:ok, state} =
          backend.init(
            size: {3, 9},
            capabilities: %{colors: :color_16},
            alternate_screen: false,
            bracketed_paste: false,
            focus_events: false
          )

        assert {:ok, {3, 9}} = backend.size(state)
        assert is_map(backend.capabilities(state))

        assert {:error, {:clipboard_too_large, 4, 1}} =
                 backend.clipboard(state, Clipboard.operation("copy", max_bytes: 1))

        assert :ok = backend.shutdown(state, :normal)
      end)
    end
  end

  test "TTY normalizes size and all supported color capability forms" do
    modes = [
      {:color_256, :color_256},
      {:color_16, :color_16},
      {:monochrome, :monochrome},
      {16_777_216, :true_color},
      {256, :color_256},
      {16, :color_16},
      {8, :monochrome}
    ]

    capture_io(fn ->
      for {colors, expected} <- modes do
        {:ok, state} =
          TTY.init(
            size: :invalid,
            capabilities: %{colors: colors, unicode: false},
            alternate_screen: false,
            bracketed_paste: false,
            focus_events: false
          )

        assert state.size == {24, 80}
        assert state.color_mode == expected
        assert state.character_set == :ascii
        assert TTY.capabilities(state).dimensions == {24, 80}
        assert :ok = TTY.shutdown(state, :normal)
      end
    end)
  end

  test "incremental backends reset changed dimensions and preserve cursor choices" do
    capture_io(fn ->
      {:ok, tty} =
        TTY.init(
          size: {2, 4},
          line_mode: :incremental,
          alternate_screen: false,
          bracketed_paste: false,
          focus_events: false
        )

      assert {:ok, tty} = TTY.draw(tty, Frame.from_rows(["a"], 4, 2))
      assert {:ok, tty} = TTY.draw(tty, Frame.from_rows(["a"], 5, 1, cursor: {2, 1}))
      assert {:ok, tty} = TTY.resize(tty, {1, 5})
      assert tty.rendered_frame == nil
      assert tty.size == {1, 5}
      TTY.shutdown(tty, :normal)

      {:ok, raw} =
        Raw.init(
          size: {2, 4},
          alternate_screen: false,
          bracketed_paste: false,
          focus_events: false
        )

      assert {:ok, raw} = Raw.draw(raw, Frame.from_rows(["a"], 4, 2))
      assert {:ok, raw} = Raw.draw(raw, Frame.from_rows(["a"], 5, 1, cursor: {2, 1}))
      assert {:ok, raw} = Raw.flush(raw)
      assert Raw.capabilities(raw).size == {2, 4}
      assert {:ok, {2, 4}} = Raw.size(raw)
      Raw.shutdown(raw, :normal)
    end)
  end

  test "backend init, resize, draw, and clipboard report closed output" do
    for backend <- [Raw, TTY] do
      {:ok, io} = StringIO.open("")
      original = Process.group_leader()
      Process.group_leader(self(), io)

      {:ok, state} =
        backend.init(
          size: {1, 4},
          alternate_screen: false,
          bracketed_paste: false,
          focus_events: false
        )

      Process.group_leader(self(), original)
      StringIO.close(io)
      rejecting_io = spawn(fn -> reject_io_requests() end)
      Process.group_leader(self(), rejecting_io)

      try do
        assert {:error, {:terminal_write_failed, _}} = backend.resize(state, {2, 5})

        assert {:error, {:terminal_write_failed, _}} =
                 backend.clipboard(state, Clipboard.operation("copy"))
      after
        Process.group_leader(self(), original)
        Process.exit(rejecting_io, :kill)
      end
    end
  end

  test "backend init failure returns a terminal write error" do
    for backend <- [Raw, TTY] do
      original = Process.group_leader()
      rejecting_io = spawn(fn -> reject_io_requests() end)
      Process.group_leader(self(), rejecting_io)

      try do
        assert {:error, {:terminal_write_failed, _}} =
                 backend.init(
                   size: {1, 4},
                   alternate_screen: false,
                   bracketed_paste: false,
                   focus_events: false
                 )
      after
        Process.group_leader(self(), original)
        Process.exit(rejecting_io, :kill)
      end
    end
  end

  defp await_event(_backend, _state, 0), do: flunk("backend did not emit a complete event")

  defp await_event(backend, state, attempts) do
    case backend.poll_event(state, 10) do
      {:timeout, state} -> await_event(backend, state, attempts - 1)
      result -> result
    end
  end

  defp reject_io_requests do
    receive do
      {:io_request, from, reply_as, _request} ->
        send(from, {:io_reply, reply_as, {:error, :closed}})
        reject_io_requests()
    end
  end
end
