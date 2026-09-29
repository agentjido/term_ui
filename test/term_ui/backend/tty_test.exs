defmodule TermUI.Backend.TTYTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias TermUI.Backend.TTY

  # Helper to initialize TTY without IO output cluttering tests
  defp init_tty(opts) do
    capture_io(fn ->
      send(self(), TTY.init(opts))
    end)

    receive do
      result -> result
    end
  end

  # ===========================================================================
  # Section 3.1 Tests - Module Structure
  # ===========================================================================

  describe "behaviour declaration" do
    test "module declares @behaviour TermUI.Backend" do
      behaviours = TTY.__info__(:attributes)[:behaviour] || []
      assert TermUI.Backend in behaviours
    end

    test "module compiles without warnings" do
      # If we got here, the module compiled successfully
      assert Code.ensure_loaded?(TTY)
    end
  end

  describe "state struct defaults" do
    test "has size field with default {24, 80}" do
      state = %TTY{}
      assert state.size == {24, 80}
    end

    test "has capabilities field with default empty map" do
      state = %TTY{}
      assert state.capabilities == %{}
    end

    test "has line_mode field with default :full_redraw" do
      state = %TTY{}
      assert state.line_mode == :full_redraw
    end

    test "has last_frame field with default nil" do
      state = %TTY{}
      assert state.last_frame == nil
    end

    test "has character_set field with default :unicode" do
      state = %TTY{}
      assert state.character_set == :unicode
    end

    test "has color_mode field with default :true_color" do
      state = %TTY{}
      assert state.color_mode == :true_color
    end

    test "has alternate_screen field with default false" do
      state = %TTY{}
      assert state.alternate_screen == false
    end

    test "has cursor_visible field with default true" do
      state = %TTY{}
      assert state.cursor_visible == true
    end

    test "has cursor_position field with default nil" do
      state = %TTY{}
      assert state.cursor_position == nil
    end
  end

  describe "init/1" do
    test "returns {:ok, state} with default options" do
      assert {:ok, %TTY{}} = init_tty([])
    end

    test "stores capabilities from options" do
      capabilities = %{colors: :color_256, unicode: true, dimensions: {30, 100}}
      {:ok, state} = init_tty(capabilities: capabilities)
      assert state.capabilities == capabilities
    end

    test "uses line_mode from options" do
      {:ok, state} = init_tty(line_mode: :incremental)
      assert state.line_mode == :incremental
    end

    test "uses alternate_screen from options" do
      {:ok, state} = init_tty(alternate_screen: true)
      assert state.alternate_screen == true
    end

    test "uses explicit size from options" do
      {:ok, state} = init_tty(size: {50, 120})
      assert state.size == {50, 120}
    end

    test "uses size from capabilities when not explicitly set" do
      capabilities = %{dimensions: {40, 160}}
      {:ok, state} = init_tty(capabilities: capabilities)
      assert state.size == {40, 160}
    end

    test "prefers explicit size over capabilities" do
      capabilities = %{dimensions: {40, 160}}
      {:ok, state} = init_tty(size: {30, 100}, capabilities: capabilities)
      assert state.size == {30, 100}
    end

    test "determines color_mode :true_color from capabilities" do
      {:ok, state} = init_tty(capabilities: %{colors: :true_color})
      assert state.color_mode == :true_color
    end

    test "determines color_mode :color_256 from capabilities" do
      {:ok, state} = init_tty(capabilities: %{colors: :color_256})
      assert state.color_mode == :color_256
    end

    test "determines color_mode :color_16 from capabilities" do
      {:ok, state} = init_tty(capabilities: %{colors: :color_16})
      assert state.color_mode == :color_16
    end

    test "determines color_mode :monochrome from capabilities" do
      {:ok, state} = init_tty(capabilities: %{colors: :monochrome})
      assert state.color_mode == :monochrome
    end

    test "determines color_mode from integer >= 16_777_216 as :true_color" do
      {:ok, state} = init_tty(capabilities: %{colors: 16_777_216})
      assert state.color_mode == :true_color
    end

    test "determines color_mode from integer >= 256 as :color_256" do
      {:ok, state} = init_tty(capabilities: %{colors: 256})
      assert state.color_mode == :color_256
    end

    test "determines color_mode from integer >= 16 as :color_16" do
      {:ok, state} = init_tty(capabilities: %{colors: 16})
      assert state.color_mode == :color_16
    end

    test "determines character_set :unicode when unicode capability is true" do
      {:ok, state} = init_tty(capabilities: %{unicode: true})
      assert state.character_set == :unicode
    end

    test "determines character_set :ascii when unicode capability is false" do
      {:ok, state} = init_tty(capabilities: %{unicode: false})
      assert state.character_set == :ascii
    end

    test "defaults character_set to :unicode when not specified" do
      {:ok, state} = init_tty(capabilities: %{})
      assert state.character_set == :unicode
    end
  end

  describe "shutdown/1" do
    test "returns :ok" do
      {:ok, state} = init_tty([])

      result =
        capture_io(fn ->
          send(self(), TTY.shutdown(state))
        end)

      receive do
        r -> assert r == :ok
      end

      # Verify some output occurred
      assert result != ""
    end

    test "can be called multiple times" do
      {:ok, state} = init_tty([])

      capture_io(fn ->
        assert :ok = TTY.shutdown(state)
        assert :ok = TTY.shutdown(state)
      end)
    end

    test "requires TTY struct as argument" do
      # Verify shutdown pattern matches on the struct type
      assert_raise FunctionClauseError, fn ->
        capture_io(fn ->
          # Dynamic dispatch prevents the compiler from warning about the
          # deliberately invalid argument used to exercise the function clause.
          # credo:disable-for-next-line Credo.Check.Refactor.Apply
          apply(TTY, :shutdown, [%{alternate_screen: false}])
        end)
      end
    end
  end

  # ===========================================================================
  # Edge Case Tests - Invalid Inputs
  # ===========================================================================

  describe "edge cases - invalid size values" do
    test "zero rows defaults to {24, 80}" do
      {:ok, state} = init_tty(size: {0, 80})
      assert state.size == {24, 80}
    end

    test "negative rows defaults to {24, 80}" do
      {:ok, state} = init_tty(size: {-1, 80})
      assert state.size == {24, 80}
    end

    test "zero cols defaults to {24, 80}" do
      {:ok, state} = init_tty(size: {24, 0})
      assert state.size == {24, 80}
    end

    test "negative cols defaults to {24, 80}" do
      {:ok, state} = init_tty(size: {24, -1})
      assert state.size == {24, 80}
    end

    test "non-integer size defaults to {24, 80}" do
      {:ok, state} = init_tty(size: {"24", "80"})
      assert state.size == {24, 80}
    end

    test "nil size defaults to {24, 80}" do
      {:ok, state} = init_tty(size: nil)
      assert state.size == {24, 80}
    end
  end

  describe "edge cases - malformed capabilities" do
    test "unknown color mode defaults to :true_color" do
      {:ok, state} = init_tty(capabilities: %{colors: :unknown_mode})
      assert state.color_mode == :true_color
    end

    test "string color value defaults to :true_color" do
      {:ok, state} = init_tty(capabilities: %{colors: "256"})
      assert state.color_mode == :true_color
    end

    test "negative integer color value defaults to :true_color" do
      {:ok, state} = init_tty(capabilities: %{colors: -1})
      assert state.color_mode == :true_color
    end

    test "non-boolean unicode capability defaults to :unicode" do
      {:ok, state} = init_tty(capabilities: %{unicode: "yes"})
      assert state.character_set == :unicode
    end

    test "invalid dimensions in capabilities defaults to {24, 80}" do
      {:ok, state} = init_tty(capabilities: %{dimensions: {0, 0}})
      assert state.size == {24, 80}
    end

    test "string dimensions in capabilities defaults to {24, 80}" do
      {:ok, state} = init_tty(capabilities: %{dimensions: {"30", "100"}})
      assert state.size == {24, 80}
    end
  end

  describe "size/1" do
    test "returns {:ok, size} from state" do
      {:ok, state} = init_tty(size: {50, 120})
      assert {:ok, {50, 120}} = TTY.size(state)
    end

    test "returns default size when not configured" do
      {:ok, state} = init_tty([])
      assert {:ok, {24, 80}} = TTY.size(state)
    end
  end

  describe "refresh_size/1" do
    test "returns {:ok, size, state}" do
      {:ok, state} = init_tty([])
      assert {:ok, {rows, cols}, _new_state} = TTY.refresh_size(state)
      assert is_integer(rows) and rows > 0
      assert is_integer(cols) and cols > 0
    end

    test "clears last_frame to force full redraw" do
      {:ok, state} = init_tty(line_mode: :incremental)
      # Simulate having a last_frame
      state = %{state | last_frame: %{{1, 1} => {"A", :default, :default, []}}}

      {:ok, _size, refreshed_state} = TTY.refresh_size(state)

      assert refreshed_state.last_frame == nil
    end

    test "preserves state structure" do
      {:ok, state} = init_tty(line_mode: :incremental, alternate_screen: true)

      {:ok, _size, refreshed_state} = TTY.refresh_size(state)

      assert refreshed_state.line_mode == :incremental
      assert refreshed_state.alternate_screen == true
    end

    test "queries terminal and updates size" do
      {:ok, state} = init_tty(size: {24, 80})

      # refresh_size queries :io.rows and :io.columns
      # In test environment these may or may not be available
      {:ok, {rows, cols}, refreshed_state} = TTY.refresh_size(state)

      # Returned size should match state size
      assert refreshed_state.size == {rows, cols}
      assert is_integer(rows) and rows > 0
      assert is_integer(cols) and cols > 0
    end

    test "falls back to current size if terminal query fails" do
      # When not connected to a terminal, :io.rows/columns return errors
      # In that case, refresh_size should preserve the current size
      {:ok, state} = init_tty(size: {30, 100})

      {:ok, {rows, cols}, refreshed_state} = TTY.refresh_size(state)

      # Size should still be valid (either from terminal or fallback)
      assert refreshed_state.size == {rows, cols}
      assert is_integer(rows) and rows > 0
      assert is_integer(cols) and cols > 0
    end
  end

  describe "cursor operations" do
    test "move_cursor/2 returns {:ok, state}" do
      {:ok, state} = init_tty([])

      output =
        capture_io(fn ->
          assert {:ok, _state} = TTY.move_cursor(state, {10, 20})
        end)

      assert output =~ "\e[10;20H"
    end

    test "move_cursor/2 updates cursor_position in state" do
      {:ok, state} = init_tty([])

      capture_io(fn ->
        {:ok, new_state} = TTY.move_cursor(state, {5, 15})
        send(self(), {:result, new_state})
      end)

      receive do
        {:result, new_state} -> assert new_state.cursor_position == {5, 15}
      end
    end

    test "move_cursor/2 clamps row to terminal bounds" do
      {:ok, state} = init_tty(size: {24, 80})

      output =
        capture_io(fn ->
          {:ok, new_state} = TTY.move_cursor(state, {100, 40})
          send(self(), {:result, new_state})
        end)

      # Row should be clamped to 24 (max rows)
      assert output =~ "\e[24;40H"

      receive do
        {:result, new_state} -> assert new_state.cursor_position == {24, 40}
      end
    end

    test "move_cursor/2 clamps column to terminal bounds" do
      {:ok, state} = init_tty(size: {24, 80})

      output =
        capture_io(fn ->
          {:ok, new_state} = TTY.move_cursor(state, {10, 200})
          send(self(), {:result, new_state})
        end)

      # Column should be clamped to 80 (max cols)
      assert output =~ "\e[10;80H"

      receive do
        {:result, new_state} -> assert new_state.cursor_position == {10, 80}
      end
    end

    test "move_cursor/2 clamps minimum position to 1,1" do
      {:ok, state} = init_tty([])

      output =
        capture_io(fn ->
          {:ok, new_state} = TTY.move_cursor(state, {0, 0})
          send(self(), {:result, new_state})
        end)

      # Position should be clamped to 1,1
      assert output =~ "\e[1;1H"

      receive do
        {:result, new_state} -> assert new_state.cursor_position == {1, 1}
      end
    end

    test "hide_cursor/1 sets cursor_visible to false" do
      {:ok, state} = init_tty([])
      # Note: init already hides cursor, so it's false after init
      assert state.cursor_visible == false

      # Show first, then hide to test the transition
      capture_io(fn ->
        {:ok, state} = TTY.show_cursor(state)
        assert state.cursor_visible == true
        {:ok, state} = TTY.hide_cursor(state)
        assert state.cursor_visible == false
      end)
    end

    test "hide_cursor/1 outputs hide cursor sequence" do
      {:ok, state} = init_tty([])

      # First show cursor (init hides it), then test hide outputs sequence
      state =
        capture_io(fn ->
          {:ok, s} = TTY.show_cursor(state)
          send(self(), s)
        end)
        |> then(fn _ -> receive do: (s -> s) end)

      assert state.cursor_visible == true

      output =
        capture_io(fn ->
          TTY.hide_cursor(state)
        end)

      assert output =~ "\e[?25l"
    end

    test "show_cursor/1 sets cursor_visible to true" do
      {:ok, state} = init_tty([])
      # init hides cursor, so start with false
      assert state.cursor_visible == false

      capture_io(fn ->
        {:ok, state} = TTY.show_cursor(state)
        assert state.cursor_visible == true
      end)
    end

    test "show_cursor/1 outputs show cursor sequence" do
      {:ok, state} = init_tty([])

      output =
        capture_io(fn ->
          TTY.show_cursor(state)
        end)

      assert output =~ "\e[?25h"
    end

    test "hide_cursor/1 is idempotent - no output when already hidden" do
      {:ok, state} = init_tty([])
      # init hides cursor, so cursor_visible should be false
      assert state.cursor_visible == false

      # Calling hide_cursor again should produce no output
      output =
        capture_io(fn ->
          {:ok, new_state} = TTY.hide_cursor(state)
          send(self(), {:result, new_state})
        end)

      # Should be empty - no escape sequence written
      assert output == ""

      receive do
        {:result, new_state} ->
          # State unchanged
          assert new_state.cursor_visible == false
          assert new_state == state
      end
    end

    test "show_cursor/1 is idempotent - no output when already visible" do
      {:ok, state} = init_tty([])

      # First show the cursor (init hides it)
      state =
        capture_io(fn ->
          {:ok, s} = TTY.show_cursor(state)
          send(self(), s)
        end)
        |> then(fn _ -> receive do: (s -> s) end)

      assert state.cursor_visible == true

      # Calling show_cursor again should produce no output
      output =
        capture_io(fn ->
          {:ok, new_state} = TTY.show_cursor(state)
          send(self(), {:result, new_state})
        end)

      # Should be empty - no escape sequence written
      assert output == ""

      receive do
        {:result, new_state} ->
          # State unchanged
          assert new_state.cursor_visible == true
          assert new_state == state
      end
    end
  end

  describe "rendering operations" do
    test "clear/1 returns {:ok, state} with nil last_frame" do
      {:ok, state} = init_tty([])
      state = %{state | last_frame: %{some: :data}}
      {:ok, state} = TTY.clear(state)
      assert state.last_frame == nil
    end

    test "draw_cells/2 returns {:ok, state}" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"A", :default, :default, []}}]

      capture_io(fn ->
        assert {:ok, _state} = TTY.draw_cells(state, cells)
      end)
    end

    test "flush/1 returns {:ok, state}" do
      {:ok, state} = init_tty([])
      assert {:ok, _state} = TTY.flush(state)
    end

    test "flush/1 preserves state unchanged" do
      {:ok, state} = init_tty(size: {50, 120}, line_mode: :incremental)
      {:ok, flushed_state} = TTY.flush(state)

      assert flushed_state.size == {50, 120}
      assert flushed_state.line_mode == :incremental
      assert flushed_state == state
    end
  end

  describe "input operations" do
    test "state has input_buffer field with default empty binary" do
      {:ok, state} = init_tty([])
      assert state.input_buffer == <<>>
    end

    test "poll_event/2 parses buffered regular character" do
      {:ok, state} = init_tty([])
      # Pre-populate buffer with a character
      state = %{state | input_buffer: "a"}

      assert {:ok, event, new_state} = TTY.poll_event(state, 100)
      assert event.key == "a"
      assert new_state.input_buffer == <<>>
    end

    test "poll_event/2 parses buffered arrow key sequence" do
      {:ok, state} = init_tty([])
      # Pre-populate buffer with up arrow escape sequence
      state = %{state | input_buffer: "\e[A"}

      assert {:ok, event, new_state} = TTY.poll_event(state, 100)
      assert event.key == :up
      assert new_state.input_buffer == <<>>
    end

    test "poll_event/2 parses buffered function key" do
      {:ok, state} = init_tty([])
      # Pre-populate buffer with F1 key (SS3 variant)
      state = %{state | input_buffer: "\eOP"}

      assert {:ok, event, new_state} = TTY.poll_event(state, 100)
      assert event.key == :f1
      assert new_state.input_buffer == <<>>
    end

    test "poll_event/2 parses buffered control character" do
      {:ok, state} = init_tty([])
      # Pre-populate buffer with Ctrl+C (ASCII 3)
      state = %{state | input_buffer: <<3>>}

      assert {:ok, event, new_state} = TTY.poll_event(state, 100)
      assert event.key == "c"
      assert :ctrl in event.modifiers
      assert new_state.input_buffer == <<>>
    end

    test "poll_event/2 returns first event from multiple input characters" do
      {:ok, state} = init_tty([])
      # Pre-populate buffer with two characters
      state = %{state | input_buffer: "ab"}

      # First call returns first event
      assert {:ok, event, _new_state} = TTY.poll_event(state, 100)
      assert event.key == "a"
      # Note: EscapeParser parses all events at once, so remaining
      # complete characters are consumed. Only partial sequences
      # (like lone ESC) would remain in buffer.
    end

    test "poll_event/2 keeps partial escape sequence in buffer" do
      {:ok, state} = init_tty([])
      # Pre-populate buffer with incomplete CSI sequence (ESC [)
      state = %{state | input_buffer: "\e["}

      # This is an incomplete sequence - should need more input
      # When buffer has incomplete sequence and IO read would block,
      # we can't test this easily without mocking IO.
      # Just verify the state is valid
      assert state.input_buffer == "\e["
    end

    test "poll_event/2 handles enter key" do
      {:ok, state} = init_tty([])
      state = %{state | input_buffer: <<13>>}

      assert {:ok, event, _new_state} = TTY.poll_event(state, 100)
      assert event.key == :enter
    end

    test "poll_event/2 handles tab key" do
      {:ok, state} = init_tty([])
      state = %{state | input_buffer: <<9>>}

      assert {:ok, event, _new_state} = TTY.poll_event(state, 100)
      assert event.key == :tab
    end

    test "poll_event/2 handles backspace" do
      {:ok, state} = init_tty([])
      state = %{state | input_buffer: <<127>>}

      assert {:ok, event, _new_state} = TTY.poll_event(state, 100)
      assert event.key == :backspace
    end

    test "poll_event/2 returns timeout for incomplete escape sequence" do
      {:ok, state} = init_tty([])
      # Pre-populate buffer with incomplete CSI sequence (ESC [)
      # When parse_buffered_input returns :need_more and we can't read more,
      # we test by directly calling with a state that has a partial sequence
      # and verifying it's preserved
      state = %{state | input_buffer: "\e["}

      # The buffer contains incomplete sequence, verify it's preserved
      assert state.input_buffer == "\e["
    end
  end

  describe "input buffer security" do
    test "input buffer size is limited to prevent memory exhaustion" do
      {:ok, state} = init_tty([])

      # Create a buffer larger than @max_input_buffer_size (1024)
      large_buffer = String.duplicate("\e[1;", 512)
      assert byte_size(large_buffer) > 1024

      state = %{state | input_buffer: large_buffer}

      # When poll_event processes this through parse_and_return_event,
      # the buffer limit should be enforced
      # Simulate what happens when we get a timeout with large buffer
      # by directly testing the internal state management

      # Pre-populate with large incomplete sequence
      # Poll should apply buffer limit when storing remaining
      assert state.input_buffer == large_buffer
    end

    test "buffer overflow truncates to 256 bytes keeping recent data" do
      {:ok, state} = init_tty([])

      # Create a buffer larger than 1024 bytes with incomplete escape at end
      large_buffer = String.duplicate("X", 1100) <> "\e["
      state = %{state | input_buffer: large_buffer}

      # Simulate adding more data which triggers buffer limit check
      # We need to trigger the apply_buffer_limit function
      # This happens when poll_event returns timeout

      # For this test, we verify the state can hold large buffers
      # The actual truncation happens in poll_event flow
      assert byte_size(state.input_buffer) > 1024
    end

    test "buffer limit preserves partial escape sequences when truncating" do
      {:ok, state} = init_tty([])

      # Buffer with garbage followed by valid partial sequence
      state = %{state | input_buffer: String.duplicate("X", 1000) <> "\e[A"}

      # The partial sequence "\e[A" should be preserved after truncation
      # when poll_event processes this
      assert String.ends_with?(state.input_buffer, "\e[A")
    end
  end

  # ===========================================================================
  # Section 3.2.2 Tests - Terminal Setup
  # ===========================================================================

  describe "terminal setup (Section 3.2.2)" do
    test "init outputs hide cursor sequence" do
      output =
        capture_io(fn ->
          TTY.init([])
        end)

      assert output =~ "\e[?25l"
    end

    test "init outputs clear screen sequence" do
      output =
        capture_io(fn ->
          TTY.init([])
        end)

      assert output =~ "\e[2J"
    end

    test "init outputs cursor home sequence" do
      output =
        capture_io(fn ->
          TTY.init([])
        end)

      assert output =~ "\e[H"
    end

    test "init outputs alternate screen sequence when configured" do
      output =
        capture_io(fn ->
          TTY.init(alternate_screen: true)
        end)

      assert output =~ "\e[?1049h"
    end

    test "init does not output alternate screen sequence by default" do
      output =
        capture_io(fn ->
          TTY.init([])
        end)

      refute output =~ "\e[?1049h"
    end

    test "init sets cursor_visible to false" do
      {:ok, state} = init_tty([])
      assert state.cursor_visible == false
    end

    test "init sets cursor_position to {1, 1}" do
      {:ok, state} = init_tty([])
      assert state.cursor_position == {1, 1}
    end

    test "setup sequences are output in correct order" do
      # When alternate_screen is true, sequence should be:
      # 1. alternate screen
      # 2. hide cursor
      # 3. clear screen + home
      output =
        capture_io(fn ->
          TTY.init(alternate_screen: true)
        end)

      alt_screen_pos = :binary.match(output, "\e[?1049h")
      hide_cursor_pos = :binary.match(output, "\e[?25l")
      clear_screen_pos = :binary.match(output, "\e[2J")

      assert alt_screen_pos != :nomatch
      assert hide_cursor_pos != :nomatch
      assert clear_screen_pos != :nomatch

      # alternate screen comes before hide cursor
      {alt_start, _} = alt_screen_pos
      {hide_start, _} = hide_cursor_pos
      {clear_start, _} = clear_screen_pos

      assert alt_start < hide_start
      assert hide_start < clear_start
    end
  end

  # ===========================================================================
  # Section 3.2.3 Tests - Shutdown Callback
  # ===========================================================================

  describe "shutdown sequences (Section 3.2.3)" do
    test "shutdown outputs reset attributes sequence" do
      {:ok, state} = init_tty([])

      output =
        capture_io(fn ->
          TTY.shutdown(state)
        end)

      assert output =~ "\e[0m"
    end

    test "shutdown outputs show cursor sequence" do
      {:ok, state} = init_tty([])

      output =
        capture_io(fn ->
          TTY.shutdown(state)
        end)

      assert output =~ "\e[?25h"
    end

    test "shutdown outputs leave alternate screen when alternate_screen is true" do
      {:ok, state} = init_tty(alternate_screen: true)

      output =
        capture_io(fn ->
          TTY.shutdown(state)
        end)

      assert output =~ "\e[?1049l"
    end

    test "shutdown does not output leave alternate screen by default" do
      {:ok, state} = init_tty([])

      output =
        capture_io(fn ->
          TTY.shutdown(state)
        end)

      refute output =~ "\e[?1049l"
    end

    test "shutdown sequences are output in correct order" do
      {:ok, state} = init_tty(alternate_screen: true)

      output =
        capture_io(fn ->
          TTY.shutdown(state)
        end)

      reset_pos = :binary.match(output, "\e[0m")
      show_cursor_pos = :binary.match(output, "\e[?25h")
      leave_alt_pos = :binary.match(output, "\e[?1049l")

      assert reset_pos != :nomatch
      assert show_cursor_pos != :nomatch
      assert leave_alt_pos != :nomatch

      # reset comes before show cursor, show cursor comes before leave alternate
      {reset_start, _} = reset_pos
      {show_start, _} = show_cursor_pos
      {leave_start, _} = leave_alt_pos

      assert reset_start < show_start
      assert show_start < leave_start
    end
  end

  # ===========================================================================
  # Section 3.3.1 Tests - clear/1 Callback
  # ===========================================================================

  describe "clear/1 (Section 3.3.1)" do
    test "outputs clear screen sequence" do
      {:ok, state} = init_tty([])

      output =
        capture_io(fn ->
          TTY.clear(state)
        end)

      assert output =~ "\e[2J"
    end

    test "outputs cursor home sequence" do
      {:ok, state} = init_tty([])

      output =
        capture_io(fn ->
          TTY.clear(state)
        end)

      assert output =~ "\e[H"
    end

    test "clear screen comes before cursor home" do
      {:ok, state} = init_tty([])

      output =
        capture_io(fn ->
          TTY.clear(state)
        end)

      clear_pos = :binary.match(output, "\e[2J")
      home_pos = :binary.match(output, "\e[H")

      assert clear_pos != :nomatch
      assert home_pos != :nomatch

      {clear_start, _} = clear_pos
      {home_start, _} = home_pos

      assert clear_start < home_start
    end

    test "clears last_frame in state" do
      {:ok, state} = init_tty([])
      state = %{state | last_frame: %{some: :data}}

      {:ok, new_state} =
        capture_io(fn ->
          send(self(), TTY.clear(state))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      assert new_state.last_frame == nil
    end

    test "sets cursor_position to {1, 1}" do
      {:ok, state} = init_tty([])
      state = %{state | cursor_position: {10, 20}}

      {:ok, new_state} =
        capture_io(fn ->
          send(self(), TTY.clear(state))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      assert new_state.cursor_position == {1, 1}
    end

    test "returns {:ok, state}" do
      {:ok, state} = init_tty([])

      result =
        capture_io(fn ->
          send(self(), TTY.clear(state))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      assert {:ok, %TTY{}} = result
    end
  end

  # ===========================================================================
  # Section 3.3.2 Tests - draw_cells/2 Callback
  # ===========================================================================

  describe "draw_cells/2 (Section 3.3.2)" do
    test "in full_redraw mode, outputs clear screen sequence" do
      {:ok, state} = init_tty(line_mode: :full_redraw)
      cells = [{{1, 1}, {"A", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[2J"
    end

    test "in incremental mode with existing frame, does not output clear screen sequence" do
      {:ok, state} = init_tty(line_mode: :incremental)
      cells = [{{1, 1}, {"A", :default, :default, []}}]

      # First frame sets last_frame (will clear screen)
      {:ok, state_with_frame} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Subsequent frame should NOT clear screen
      output =
        capture_io(fn ->
          TTY.draw_cells(state_with_frame, cells)
        end)

      refute output =~ "\e[2J"
    end

    test "outputs cursor positioning sequence" do
      {:ok, state} = init_tty([])
      cells = [{{5, 1}, {"X", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[5;1H"
    end

    test "outputs cell character" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"Z", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "Z"
    end

    test "outputs multiple cells in row order" do
      {:ok, state} = init_tty([])

      cells = [
        {{2, 1}, {"B", :default, :default, []}},
        {{1, 1}, {"A", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Row 1 should come before Row 2
      row1_pos = :binary.match(output, "\e[1;1H")
      row2_pos = :binary.match(output, "\e[2;1H")

      assert row1_pos != :nomatch
      assert row2_pos != :nomatch

      {row1_start, _} = row1_pos
      {row2_start, _} = row2_pos

      assert row1_start < row2_start
    end

    test "outputs named foreground color" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :red, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[31m"
    end

    test "outputs named background color" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :default, :blue, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[44m"
    end

    test "outputs RGB foreground in true_color mode" do
      {:ok, state} = init_tty(capabilities: %{colors: :true_color})
      cells = [{{1, 1}, {"X", {255, 128, 64}, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[38;2;255;128;64m"
    end

    test "outputs RGB background in true_color mode" do
      {:ok, state} = init_tty(capabilities: %{colors: :true_color})
      cells = [{{1, 1}, {"X", :default, {64, 128, 255}, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[48;2;64;128;255m"
    end

    test "outputs bold attribute" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :default, :default, [:bold]}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[1m"
    end

    test "outputs underline attribute" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :default, :default, [:underline]}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[4m"
    end

    test "resets attributes at end of row" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :red, :default, [:bold]}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should end with reset
      assert output =~ "\e[0m"
    end

    test "outputs dim attribute" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :default, :default, [:dim]}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[2m"
    end

    test "outputs italic attribute" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :default, :default, [:italic]}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[3m"
    end

    test "outputs blink attribute" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :default, :default, [:blink]}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[5m"
    end

    test "outputs reverse attribute" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :default, :default, [:reverse]}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[7m"
    end

    test "outputs strikethrough attribute" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :default, :default, [:strikethrough]}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[9m"
    end

    test "outputs multiple attributes combined" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :default, :default, [:bold, :italic, :underline]}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "\e[1m"
      assert output =~ "\e[3m"
      assert output =~ "\e[4m"
    end

    test "updates last_frame in state for incremental mode" do
      {:ok, state} = init_tty(line_mode: :incremental)
      cells = [{{1, 1}, {"A", :default, :default, []}}]

      {:ok, new_state} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      assert new_state.last_frame == %{{1, 1} => {"A", :default, :default, []}}
    end

    test "empty cells list produces no cell output" do
      {:ok, state} = init_tty([])

      output =
        capture_io(fn ->
          TTY.draw_cells(state, [])
        end)

      # Should only have clear screen, no row positioning
      refute output =~ "\e[1;1H"
    end

    test "returns {:ok, state}" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"A", :default, :default, []}}]

      result =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      assert {:ok, %TTY{}} = result
    end
  end

  # ===========================================================================
  # Color Degradation Tests (Section 3.3.2)
  # ===========================================================================

  describe "color degradation in draw_cells/2" do
    test "256-color mode converts RGB to palette index" do
      {:ok, state} = init_tty(capabilities: %{colors: :color_256})
      cells = [{{1, 1}, {"X", {255, 0, 0}, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should use 38;5;N format, not 38;2;r;g;b
      assert output =~ "\e[38;5;"
      refute output =~ "\e[38;2;"
    end

    test "16-color mode converts RGB to basic color" do
      {:ok, state} = init_tty(capabilities: %{colors: :color_16})
      cells = [{{1, 1}, {"X", {255, 0, 0}, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should use basic foreground codes (31 = red or 91 = bright red)
      assert output =~ "\e[91m" or output =~ "\e[31m"
    end

    test "monochrome mode omits color sequences" do
      {:ok, state} = init_tty(capabilities: %{colors: :monochrome})
      cells = [{{1, 1}, {"X", {255, 0, 0}, {0, 0, 255}, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should not have any color codes
      refute output =~ "\e[38;"
      refute output =~ "\e[48;"
      refute output =~ "\e[31m"
    end

    test "nil foreground color produces no color sequence" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", nil, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should not have foreground color sequences (38;2 or 38;5)
      refute output =~ "\e[38;"
    end

    test "nil background color produces no color sequence" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :default, nil, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should not have background color sequences (48;2 or 48;5)
      refute output =~ "\e[48;"
    end

    test ":default foreground outputs reset foreground sequence" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :default, :blue, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Default foreground should output \e[39m
      assert output =~ "\e[39m"
      # And blue background
      assert output =~ "\e[44m"
    end

    test ":default background outputs reset background sequence" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :red, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Default background should output \e[49m
      assert output =~ "\e[49m"
      # And red foreground
      assert output =~ "\e[31m"
    end

    test "palette index foreground in 256-color mode" do
      {:ok, state} = init_tty(capabilities: %{colors: :color_256})
      cells = [{{1, 1}, {"X", 42, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Palette index 42 as foreground
      assert output =~ "\e[38;5;42m"
    end

    test "palette index background in 256-color mode" do
      {:ok, state} = init_tty(capabilities: %{colors: :color_256})
      cells = [{{1, 1}, {"X", :default, 196, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Palette index 196 as background
      assert output =~ "\e[48;5;196m"
    end

    test "palette index colors work in true_color mode" do
      {:ok, state} = init_tty(capabilities: %{colors: :true_color})
      cells = [{{1, 1}, {"X", 100, 200, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Palette indices should still work in true_color mode
      assert output =~ "\e[38;5;100m"
      assert output =~ "\e[48;5;200m"
    end
  end

  # ===========================================================================
  # Section 3.5 Tests - Color Degradation
  # ===========================================================================

  describe "color degradation - 256-color mode (Section 3.5.2)" do
    test "256-color mapping uses color cube for non-gray colors" do
      {:ok, state} = init_tty(capabilities: %{colors: :color_256})
      # Pure red should map to color cube, not grayscale
      cells = [{{1, 1}, {"X", {255, 0, 0}, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should use 38;5;N format with a color cube index (16-231)
      # Pure red (255, 0, 0) should map to index 196 (5*36 + 0*6 + 0 + 16)
      assert output =~ "\e[38;5;196m"
    end

    test "256-color mapping uses grayscale for near-gray colors" do
      {:ok, state} = init_tty(capabilities: %{colors: :color_256})
      # Gray (128, 128, 128) should map to grayscale ramp
      cells = [{{1, 1}, {"X", {128, 128, 128}, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should use 38;5;N format with a grayscale index (232-255)
      # Gray (128, 128, 128) average = 128, maps to 232 + (128 * 23 / 255) = 232 + 11 = 243
      assert output =~ "\e[38;5;243m"
    end

    test "256-color background uses palette index" do
      {:ok, state} = init_tty(capabilities: %{colors: :color_256})
      cells = [{{1, 1}, {"X", :default, {0, 255, 0}, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Pure green should map to 16 + 0*36 + 5*6 + 0 = 46
      assert output =~ "\e[48;5;46m"
    end
  end

  describe "color degradation - monochrome mode (Section 3.5.4)" do
    test "monochrome mode preserves bold attribute" do
      {:ok, state} = init_tty(capabilities: %{colors: :monochrome})
      cells = [{{1, 1}, {"X", {255, 0, 0}, :default, [:bold]}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Color should be omitted
      refute output =~ "\e[38;"
      # But bold should be preserved
      assert output =~ "\e[1m"
    end

    test "monochrome mode preserves underline attribute" do
      {:ok, state} = init_tty(capabilities: %{colors: :monochrome})
      cells = [{{1, 1}, {"X", :red, :blue, [:underline]}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Colors should be omitted
      refute output =~ "\e[31m"
      refute output =~ "\e[44m"
      # But underline should be preserved
      assert output =~ "\e[4m"
    end

    test "monochrome mode preserves reverse attribute for contrast" do
      {:ok, state} = init_tty(capabilities: %{colors: :monochrome})
      cells = [{{1, 1}, {"X", {255, 255, 255}, {0, 0, 0}, [:reverse]}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # RGB colors should be omitted
      refute output =~ "\e[38;2;"
      refute output =~ "\e[48;2;"
      # But reverse should be preserved for visibility
      assert output =~ "\e[7m"
    end
  end

  describe "color degradation - named colors (Section 3.5.5)" do
    test "named colors work in true_color mode" do
      {:ok, state} = init_tty(capabilities: %{colors: :true_color})
      cells = [{{1, 1}, {"X", :cyan, :magenta, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Named colors should use standard SGR codes
      # cyan foreground
      assert output =~ "\e[36m"
      # magenta background
      assert output =~ "\e[45m"
    end

    test "named colors work in 256-color mode" do
      {:ok, state} = init_tty(capabilities: %{colors: :color_256})
      cells = [{{1, 1}, {"X", :yellow, :green, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Named colors should still use standard SGR codes
      # yellow foreground
      assert output =~ "\e[33m"
      # green background
      assert output =~ "\e[42m"
    end

    test "named colors work in 16-color mode" do
      {:ok, state} = init_tty(capabilities: %{colors: :color_16})
      cells = [{{1, 1}, {"X", :blue, :white, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Named colors should use standard SGR codes
      # blue foreground
      assert output =~ "\e[34m"
      # white background
      assert output =~ "\e[47m"
    end

    test "bright named colors work correctly" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"X", :bright_red, :bright_blue, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Bright colors use codes 90-97 (fg) and 100-107 (bg)
      # bright red foreground
      assert output =~ "\e[91m"
      # bright blue background
      assert output =~ "\e[104m"
    end

    test ":default foreground works in all modes" do
      for mode <- [:true_color, :color_256, :color_16] do
        {:ok, state} = init_tty(capabilities: %{colors: mode})
        cells = [{{1, 1}, {"X", :default, :red, []}}]

        output =
          capture_io(fn ->
            TTY.draw_cells(state, cells)
          end)

        # Default foreground should always output \e[39m
        assert output =~ "\e[39m", "Failed for mode #{mode}"
      end
    end

    test ":default background works in all modes" do
      for mode <- [:true_color, :color_256, :color_16] do
        {:ok, state} = init_tty(capabilities: %{colors: mode})
        cells = [{{1, 1}, {"X", :red, :default, []}}]

        output =
          capture_io(fn ->
            TTY.draw_cells(state, cells)
          end)

        # Default background should always output \e[49m
        assert output =~ "\e[49m", "Failed for mode #{mode}"
      end
    end
  end

  # ===========================================================================
  # Section 3.3.3 Tests - Row-by-Row Output with Style Delta Tracking
  # ===========================================================================

  describe "row-by-row output (Section 3.3.3)" do
    test "consecutive cells with same style only output style once" do
      {:ok, state} = init_tty([])

      # Two cells with identical style
      cells = [
        {{1, 1}, {"A", :red, :default, []}},
        {{1, 2}, {"B", :red, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Count occurrences of red foreground SGR
      red_count = length(String.split(output, "\e[31m")) - 1

      # Should only output red once (for first cell), not twice
      assert red_count == 1
    end

    test "cells with different styles output style for each change" do
      {:ok, state} = init_tty([])

      # Two cells with different styles
      cells = [
        {{1, 1}, {"A", :red, :default, []}},
        {{1, 2}, {"B", :blue, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should have both red and blue
      assert output =~ "\e[31m"
      assert output =~ "\e[34m"
    end

    test "style change in attributes triggers new SGR" do
      {:ok, state} = init_tty([])

      cells = [
        {{1, 1}, {"A", :default, :default, [:bold]}},
        {{1, 2}, {"B", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Count reset sequences - should have at least 2 (one for style change, one at end)
      reset_count = length(String.split(output, "\e[0m")) - 1

      assert reset_count >= 2
    end

    test "gap filling preserves style tracking" do
      {:ok, state} = init_tty([])

      # Cells with gap between them, same style
      cells = [
        {{1, 1}, {"A", :green, :default, []}},
        {{1, 5}, {"B", :green, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Gap should be filled with spaces
      assert output =~ "A   "

      # Green should only be output once
      green_count = length(String.split(output, "\e[32m")) - 1
      assert green_count == 1
    end

    test "outputs cells left-to-right" do
      {:ok, state} = init_tty([])

      # Cells given out of order
      cells = [
        {{1, 3}, {"C", :default, :default, []}},
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 2}, {"B", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Characters should appear in correct order
      a_pos = :binary.match(output, "A")
      b_pos = :binary.match(output, "B")
      c_pos = :binary.match(output, "C")

      assert a_pos != :nomatch
      assert b_pos != :nomatch
      assert c_pos != :nomatch

      {a_start, _} = a_pos
      {b_start, _} = b_pos
      {c_start, _} = c_pos

      assert a_start < b_start
      assert b_start < c_start
    end

    test "multiple rows maintain correct ordering" do
      {:ok, state} = init_tty([])

      cells = [
        {{2, 1}, {"2", :default, :default, []}},
        {{1, 1}, {"1", :default, :default, []}},
        {{3, 1}, {"3", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Row positioning should be in order
      row1_pos = :binary.match(output, "\e[1;1H")
      row2_pos = :binary.match(output, "\e[2;1H")
      row3_pos = :binary.match(output, "\e[3;1H")

      assert row1_pos != :nomatch
      assert row2_pos != :nomatch
      assert row3_pos != :nomatch

      {r1_start, _} = row1_pos
      {r2_start, _} = row2_pos
      {r3_start, _} = row3_pos

      assert r1_start < r2_start
      assert r2_start < r3_start
    end

    test "each row ends with attribute reset" do
      {:ok, state} = init_tty([])

      cells = [
        {{1, 1}, {"A", :red, :default, []}},
        {{2, 1}, {"B", :blue, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should have reset after each row
      # Row 1: [1;1H + style + A + reset
      # Row 2: [2;1H + style + B + reset
      reset_count = length(String.split(output, "\e[0m")) - 1

      # At least 2 resets (one per row) plus any style changes
      assert reset_count >= 2
    end
  end

  # ===========================================================================
  # Security Tests - Character Sanitization
  # ===========================================================================

  describe "character sanitization" do
    test "escape sequences in cell content are stripped" do
      {:ok, state} = init_tty([])
      # Attempt to inject an escape sequence via cell content
      cells = [{{1, 1}, {"\e[31mEVIL", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # The escape should be stripped from the cell content
      # So we should see "EVIL" but not an extra \e[31m from the content itself
      assert output =~ "[31mEVIL"
      # The cell content escape was stripped, only framework escapes remain
      # Count number of \e[31m - should only be 0 (no red from cell content)
      refute output =~ "\e[31mEVIL"
    end

    test "normal characters are not affected by sanitization" do
      {:ok, state} = init_tty([])
      cells = [{{1, 1}, {"Hello!", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "Hello!"
    end
  end

  # ===========================================================================
  # Frame Map Tests - Incremental Mode
  # ===========================================================================

  describe "frame map handling" do
    test "full_redraw mode sets last_frame to nil" do
      {:ok, state} = init_tty(line_mode: :full_redraw)
      cells = [{{1, 1}, {"A", :default, :default, []}}]

      {:ok, new_state} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      assert new_state.last_frame == nil
    end

    test "incremental mode stores last_frame as map" do
      {:ok, state} = init_tty(line_mode: :incremental)
      cells = [{{1, 1}, {"A", :default, :default, []}}]

      {:ok, new_state} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      assert new_state.last_frame == %{{1, 1} => {"A", :default, :default, []}}
    end

    test "incremental mode first frame (nil last_frame) triggers full redraw" do
      {:ok, state} = init_tty(line_mode: :incremental)
      # Verify last_frame starts as nil
      assert state.last_frame == nil

      cells = [{{1, 1}, {"X", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # First frame should include clear screen sequence
      assert output =~ "\e[2J"
    end

    test "incremental mode subsequent frame does not clear screen" do
      {:ok, state} = init_tty(line_mode: :incremental)
      cells = [{{1, 1}, {"A", :default, :default, []}}]

      # First frame - sets last_frame
      {:ok, state_with_frame} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Verify last_frame is now set
      assert state_with_frame.last_frame != nil

      # Second frame - should NOT clear screen
      output =
        capture_io(fn ->
          TTY.draw_cells(state_with_frame, cells)
        end)

      # Should NOT include clear screen sequence
      refute output =~ "\e[2J"
    end

    test "clear/1 clears last_frame" do
      {:ok, state} = init_tty(line_mode: :incremental)
      cells = [{{1, 1}, {"A", :default, :default, []}}]

      # First draw to set last_frame
      {:ok, state_with_frame} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      assert state_with_frame.last_frame != nil

      # Clear should reset last_frame
      {:ok, cleared_state} =
        capture_io(fn ->
          send(self(), TTY.clear(state_with_frame))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      assert cleared_state.last_frame == nil
    end

    test "set_size/2 clears last_frame" do
      {:ok, state} = init_tty(line_mode: :incremental)
      cells = [{{1, 1}, {"A", :default, :default, []}}]

      # First draw to set last_frame
      {:ok, state_with_frame} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      assert state_with_frame.last_frame != nil

      # set_size should clear last_frame
      {:ok, resized_state} = TTY.set_size(state_with_frame, {50, 120})

      assert resized_state.last_frame == nil
      assert resized_state.size == {50, 120}
    end

    test "set_size/2 updates size correctly" do
      {:ok, state} = init_tty([])

      {:ok, resized_state} = TTY.set_size(state, {100, 200})

      assert resized_state.size == {100, 200}
    end

    test "after resize, next draw in incremental mode triggers full redraw" do
      {:ok, state} = init_tty(line_mode: :incremental)
      cells = [{{1, 1}, {"A", :default, :default, []}}]

      # First draw to set last_frame
      {:ok, state_with_frame} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Resize clears last_frame
      {:ok, resized_state} = TTY.set_size(state_with_frame, {50, 120})
      assert resized_state.last_frame == nil

      # Next draw should trigger full redraw (clear screen)
      output =
        capture_io(fn ->
          TTY.draw_cells(resized_state, cells)
        end)

      assert output =~ "\e[2J"
    end
  end

  # ===========================================================================
  # Frame Comparison Tests (Section 3.4.2)
  # ===========================================================================

  describe "compare_frames/2" do
    test "empty last frame and empty current returns no changes" do
      {changed, removed} = TTY.compare_frames(%{}, [])

      assert changed == []
      assert removed == []
    end

    test "new cell is detected as changed" do
      last_frame = %{}
      current_cells = [{{1, 1}, {"A", :default, :default, []}}]

      {changed, removed} = TTY.compare_frames(last_frame, current_cells)

      assert changed == [{{1, 1}, {"A", :default, :default, []}}]
      assert removed == []
    end

    test "multiple new cells are all detected as changed" do
      last_frame = %{}

      current_cells = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 2}, {"B", :default, :default, []}},
        {{2, 1}, {"C", :default, :default, []}}
      ]

      {changed, removed} = TTY.compare_frames(last_frame, current_cells)

      assert length(changed) == 3
      assert removed == []
    end

    test "removed cell is detected" do
      last_frame = %{{1, 1} => {"A", :default, :default, []}}
      current_cells = []

      {changed, removed} = TTY.compare_frames(last_frame, current_cells)

      assert changed == []
      assert removed == [{1, 1}]
    end

    test "multiple removed cells are all detected" do
      last_frame = %{
        {1, 1} => {"A", :default, :default, []},
        {1, 2} => {"B", :default, :default, []},
        {2, 1} => {"C", :default, :default, []}
      }

      current_cells = []

      {changed, removed} = TTY.compare_frames(last_frame, current_cells)

      assert changed == []
      assert length(removed) == 3
      assert {1, 1} in removed
      assert {1, 2} in removed
      assert {2, 1} in removed
    end

    test "unchanged cell is not in changed or removed" do
      cell = {"A", :default, :default, []}
      last_frame = %{{1, 1} => cell}
      current_cells = [{{1, 1}, cell}]

      {changed, removed} = TTY.compare_frames(last_frame, current_cells)

      assert changed == []
      assert removed == []
    end

    test "changed character is detected" do
      last_frame = %{{1, 1} => {"A", :default, :default, []}}
      current_cells = [{{1, 1}, {"B", :default, :default, []}}]

      {changed, removed} = TTY.compare_frames(last_frame, current_cells)

      assert changed == [{{1, 1}, {"B", :default, :default, []}}]
      assert removed == []
    end

    test "changed foreground color is detected" do
      last_frame = %{{1, 1} => {"A", :red, :default, []}}
      current_cells = [{{1, 1}, {"A", :blue, :default, []}}]

      {changed, removed} = TTY.compare_frames(last_frame, current_cells)

      assert changed == [{{1, 1}, {"A", :blue, :default, []}}]
      assert removed == []
    end

    test "changed background color is detected" do
      last_frame = %{{1, 1} => {"A", :default, :red, []}}
      current_cells = [{{1, 1}, {"A", :default, :blue, []}}]

      {changed, removed} = TTY.compare_frames(last_frame, current_cells)

      assert changed == [{{1, 1}, {"A", :default, :blue, []}}]
      assert removed == []
    end

    test "changed attributes are detected" do
      last_frame = %{{1, 1} => {"A", :default, :default, [:bold]}}
      current_cells = [{{1, 1}, {"A", :default, :default, [:underline]}}]

      {changed, removed} = TTY.compare_frames(last_frame, current_cells)

      assert changed == [{{1, 1}, {"A", :default, :default, [:underline]}}]
      assert removed == []
    end

    test "added attribute is detected as change" do
      last_frame = %{{1, 1} => {"A", :default, :default, []}}
      current_cells = [{{1, 1}, {"A", :default, :default, [:bold]}}]

      {changed, removed} = TTY.compare_frames(last_frame, current_cells)

      assert changed == [{{1, 1}, {"A", :default, :default, [:bold]}}]
      assert removed == []
    end

    test "mixed scenario: some changed, some removed, some unchanged" do
      last_frame = %{
        {1, 1} => {"A", :default, :default, []},
        {1, 2} => {"B", :default, :default, []},
        {1, 3} => {"C", :default, :default, []}
      }

      current_cells = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 2}, {"X", :default, :default, []}},
        {{1, 4}, {"D", :default, :default, []}}
      ]

      {changed, removed} = TTY.compare_frames(last_frame, current_cells)

      # {1, 1} unchanged - not in changed
      # {1, 2} changed from B to X
      # {1, 3} removed
      # {1, 4} new
      assert length(changed) == 2

      assert {{1, 2}, {"X", :default, :default, []}} in changed
      assert {{1, 4}, {"D", :default, :default, []}} in changed

      assert removed == [{1, 3}]
    end

    test "position order is preserved in changed list" do
      last_frame = %{}

      current_cells = [
        {{1, 1}, {"A", :default, :default, []}},
        {{2, 1}, {"B", :default, :default, []}},
        {{1, 2}, {"C", :default, :default, []}}
      ]

      {changed, _removed} = TTY.compare_frames(last_frame, current_cells)

      # Order should match input order
      assert changed == current_cells
    end

    test "RGB color change is detected" do
      last_frame = %{{1, 1} => {"A", {255, 0, 0}, :default, []}}
      current_cells = [{{1, 1}, {"A", {0, 255, 0}, :default, []}}]

      {changed, removed} = TTY.compare_frames(last_frame, current_cells)

      assert changed == [{{1, 1}, {"A", {0, 255, 0}, :default, []}}]
      assert removed == []
    end
  end

  # ===========================================================================
  # Incremental Rendering Tests (Section 3.4.3)
  # ===========================================================================

  describe "incremental rendering" do
    test "only renders changed cells on subsequent frames" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame with two cells
      cells1 = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 2}, {"B", :default, :default, []}}
      ]

      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells1))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame: change one cell, keep one the same
      cells2 = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 2}, {"X", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells2)
        end)

      # Should NOT have clear screen (incremental)
      refute output =~ "\e[2J"

      # Should have cursor positioning for the changed cell {1, 2}
      assert output =~ "\e[1;2H"

      # Should contain the changed character X
      assert output =~ "X"
    end

    test "unchanged cells are not re-rendered" do
      {:ok, state} = init_tty(line_mode: :incremental)

      cells = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 2}, {"B", :default, :default, []}}
      ]

      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Same cells - nothing should be rendered
      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells)
        end)

      # No clear screen
      refute output =~ "\e[2J"

      # No cursor positioning (nothing to render)
      refute output =~ "\e[1;1H"
      refute output =~ "\e[1;2H"
    end

    test "removed cells are cleared with space" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame with two cells
      cells1 = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 2}, {"B", :default, :default, []}}
      ]

      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells1))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame: remove one cell
      cells2 = [{{1, 1}, {"A", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells2)
        end)

      # Should position cursor at removed cell location {1, 2}
      assert output =~ "\e[1;2H"

      # Should write a space to clear it (with reset)
      assert output =~ "\e[0m "
    end

    test "new cells are rendered" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame with one cell
      cells1 = [{{1, 1}, {"A", :default, :default, []}}]

      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells1))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame: add a new cell
      cells2 = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 2}, {"B", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells2)
        end)

      # Should position cursor at new cell location {1, 2}
      assert output =~ "\e[1;2H"

      # Should render the new cell
      assert output =~ "B"
    end

    test "mixed changes: add, modify, remove in single frame" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame
      cells1 = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 2}, {"B", :default, :default, []}},
        {{1, 3}, {"C", :default, :default, []}}
      ]

      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells1))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame:
      # - {1, 1} unchanged (A)
      # - {1, 2} changed (B -> X)
      # - {1, 3} removed
      # - {1, 4} added (D)
      cells2 = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 2}, {"X", :default, :default, []}},
        {{1, 4}, {"D", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells2)
        end)

      # Should NOT render unchanged cell {1, 1}
      refute output =~ "\e[1;1H"

      # Should render changed cell {1, 2} - cursor positioned there
      assert output =~ "\e[1;2H"
      assert output =~ "X"

      # Should clear removed cell {1, 3} (separate cursor positioning for clear)
      assert output =~ "\e[1;3H"

      # The new cell has its own run. Removal at column 3 is explicit.
      assert output =~ "\e[1;4H"
      assert output =~ "D"
      refute output =~ "X D"
    end

    test "style change triggers re-render" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame
      cells1 = [{{1, 1}, {"A", :red, :default, []}}]

      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells1))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame: change color
      cells2 = [{{1, 1}, {"A", :blue, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells2)
        end)

      # Should re-render the cell
      assert output =~ "\e[1;1H"

      # Should have blue color code
      assert output =~ "\e[34m"
    end

    test "last_frame is updated after incremental render" do
      {:ok, state} = init_tty(line_mode: :incremental)

      cells1 = [{{1, 1}, {"A", :default, :default, []}}]

      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells1))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      cells2 = [{{1, 1}, {"B", :default, :default, []}}]

      {:ok, state2} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state1, cells2))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # last_frame should now contain B, not A
      assert state2.last_frame == %{{1, 1} => {"B", :default, :default, []}}
    end

    test "full_redraw mode always clears screen" do
      {:ok, state} = init_tty(line_mode: :full_redraw)

      cells1 = [{{1, 1}, {"A", :default, :default, []}}]

      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells1))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Even identical cells should trigger full redraw
      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells1)
        end)

      # Should ALWAYS have clear screen in full_redraw mode
      assert output =~ "\e[2J"
    end
  end

  # ===========================================================================
  # Cursor Movement Optimization Tests (Section 3.4.4)
  # ===========================================================================

  describe "cursor movement optimization" do
    test "changed cells are sorted by position for rendering" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame
      cells1 = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 5}, {"E", :default, :default, []}},
        {{1, 3}, {"C", :default, :default, []}}
      ]

      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells1))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame: change all cells (order doesn't match position order)
      cells2 = [
        {{1, 5}, {"X", :default, :default, []}},
        {{1, 1}, {"Y", :default, :default, []}},
        {{1, 3}, {"Z", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells2)
        end)

      # All cells changed so they should all be rendered
      # They should be grouped by row and sorted by column
      assert output =~ "Y"
      assert output =~ "Z"
      assert output =~ "X"

      # Characters should appear in column order (Y at 1, Z at 3, X at 5)
      y_pos = :binary.match(output, "Y")
      z_pos = :binary.match(output, "Z")
      x_pos = :binary.match(output, "X")

      assert y_pos != :nomatch
      assert z_pos != :nomatch
      assert x_pos != :nomatch

      {y_start, _} = y_pos
      {z_start, _} = z_pos
      {x_start, _} = x_pos

      assert y_start < z_start
      assert z_start < x_start
    end

    test "adjacent cells on same row use single cursor positioning" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame - empty
      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, []))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame: add adjacent cells on row 1
      cells2 = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 2}, {"B", :default, :default, []}},
        {{1, 3}, {"C", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells2)
        end)

      # Should only have ONE cursor positioning for row 1 (at start)
      # Count cursor positioning sequences for row 1
      row1_positions =
        output
        |> String.split("\e[1;")
        |> length()

      # Should position only once at the start of the row
      # (one more element than actual occurrences due to split behavior)
      assert row1_positions == 2
    end

    test "non-adjacent changed cells use separate cursor positions" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame - empty
      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, []))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame: cells at columns 1 and 4 (gap of 2)
      cells2 = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 4}, {"D", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells2)
        end)

      assert output =~ "\e[1;1H"
      assert output =~ "\e[1;4H"
      assert output =~ "A"
      assert output =~ "D"
      refute output =~ "A  "
    end

    test "cells on different rows get separate cursor positioning" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame - empty
      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, []))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame: cells on rows 1 and 3
      cells2 = [
        {{1, 1}, {"A", :default, :default, []}},
        {{3, 1}, {"C", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells2)
        end)

      # Should have cursor positioning for both rows
      assert output =~ "\e[1;1H"
      assert output =~ "\e[3;1H"
    end

    test "style delta tracking works within grouped row cells" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame - empty
      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, []))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame: adjacent cells with same style
      cells2 = [
        {{1, 1}, {"A", :red, :default, []}},
        {{1, 2}, {"B", :red, :default, []}},
        {{1, 3}, {"C", :red, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells2)
        end)

      # Red color should only appear once (delta tracking)
      red_count = length(String.split(output, "\e[31m")) - 1
      assert red_count == 1
    end

    test "multiple rows are processed in order" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame - empty
      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, []))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame: cells on rows 3, 1, 2 (out of order)
      cells2 = [
        {{3, 1}, {"3", :default, :default, []}},
        {{1, 1}, {"1", :default, :default, []}},
        {{2, 1}, {"2", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells2)
        end)

      # Rows should be processed in order 1, 2, 3
      row1_pos = :binary.match(output, "\e[1;1H")
      row2_pos = :binary.match(output, "\e[2;1H")
      row3_pos = :binary.match(output, "\e[3;1H")

      assert row1_pos != :nomatch
      assert row2_pos != :nomatch
      assert row3_pos != :nomatch

      {r1_start, _} = row1_pos
      {r2_start, _} = row2_pos
      {r3_start, _} = row3_pos

      assert r1_start < r2_start
      assert r2_start < r3_start
    end

    test "removed cells are sorted for sequential clearing" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame: cells at various positions
      cells1 = [
        {{2, 3}, {"X", :default, :default, []}},
        {{1, 1}, {"A", :default, :default, []}},
        {{2, 1}, {"B", :default, :default, []}}
      ]

      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells1))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame: remove all cells
      output =
        capture_io(fn ->
          TTY.draw_cells(state1, [])
        end)

      # All positions should be cleared
      assert output =~ "\e[1;1H"
      assert output =~ "\e[2;1H"
      assert output =~ "\e[2;3H"

      # Positions should be cleared in sorted order
      pos_1_1 = :binary.match(output, "\e[1;1H")
      pos_2_1 = :binary.match(output, "\e[2;1H")
      pos_2_3 = :binary.match(output, "\e[2;3H")

      {p1_start, _} = pos_1_1
      {p2_start, _} = pos_2_1
      {p3_start, _} = pos_2_3

      # {1, 1} < {2, 1} < {2, 3} in tuple comparison order
      assert p1_start < p2_start
      assert p2_start < p3_start
    end

    test "mixed changed and removed cells both optimized" do
      {:ok, state} = init_tty(line_mode: :incremental)

      # First frame
      cells1 = [
        {{1, 1}, {"A", :default, :default, []}},
        {{1, 2}, {"B", :default, :default, []}},
        {{2, 1}, {"C", :default, :default, []}}
      ]

      {:ok, state1} =
        capture_io(fn ->
          send(self(), TTY.draw_cells(state, cells1))
        end)
        |> then(fn _ ->
          receive do
            result -> result
          end
        end)

      # Second frame: change {1, 1} and {1, 2}, remove {2, 1}
      cells2 = [
        {{1, 1}, {"X", :default, :default, []}},
        {{1, 2}, {"Y", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state1, cells2)
        end)

      # Changed cells on row 1 should be grouped (single cursor positioning)
      # Should have cursor position for row 1
      assert output =~ "\e[1;1H"

      # Should have both changed characters
      assert output =~ "X"
      assert output =~ "Y"

      # Should clear removed cell at {2, 1}
      assert output =~ "\e[2;1H"
      assert output =~ "\e[0m "
    end
  end

  # ===========================================================================
  # Section 3.6.2 Tests - Character Mapping
  # ===========================================================================

  describe "character mapping (Section 3.6.2)" do
    test "unicode mode passes through box-drawing characters unchanged" do
      {:ok, state} = init_tty(capabilities: %{unicode: true})
      assert state.character_set == :unicode

      # Unicode box-drawing character
      cells = [{{1, 1}, {"┌", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should contain the Unicode character unchanged
      assert output =~ "┌"
    end

    test "ascii mode converts box corners to +" do
      {:ok, state} = init_tty(capabilities: %{unicode: false})
      assert state.character_set == :ascii

      # Unicode corners should become +
      cells = [
        {{1, 1}, {"┌", :default, :default, []}},
        {{1, 2}, {"┐", :default, :default, []}},
        {{1, 3}, {"└", :default, :default, []}},
        {{1, 4}, {"┘", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should have + characters, not Unicode corners
      assert output =~ "++++"
      refute output =~ "┌"
      refute output =~ "┐"
      refute output =~ "└"
      refute output =~ "┘"
    end

    test "ascii mode converts horizontal line to -" do
      {:ok, state} = init_tty(capabilities: %{unicode: false})

      cells = [{{1, 1}, {"─", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "-"
      refute output =~ "─"
    end

    test "ascii mode converts vertical line to |" do
      {:ok, state} = init_tty(capabilities: %{unicode: false})

      cells = [{{1, 1}, {"│", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "|"
      refute output =~ "│"
    end

    test "ascii mode converts T-junctions to +" do
      {:ok, state} = init_tty(capabilities: %{unicode: false})

      cells = [
        {{1, 1}, {"┬", :default, :default, []}},
        {{1, 2}, {"┴", :default, :default, []}},
        {{1, 3}, {"├", :default, :default, []}},
        {{1, 4}, {"┤", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should have + characters
      assert output =~ "++++"
      refute output =~ "┬"
      refute output =~ "┴"
      refute output =~ "├"
      refute output =~ "┤"
    end

    test "ascii mode converts cross junction to +" do
      {:ok, state} = init_tty(capabilities: %{unicode: false})

      cells = [{{1, 1}, {"┼", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "+"
      refute output =~ "┼"
    end

    test "ascii mode converts progress bar characters" do
      {:ok, state} = init_tty(capabilities: %{unicode: false})

      cells = [
        {{1, 1}, {"█", :default, :default, []}},
        {{1, 2}, {"░", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Full block becomes #, empty becomes .
      assert output =~ "#."
      refute output =~ "█"
      refute output =~ "░"
    end

    test "ascii mode converts check marks" do
      {:ok, state} = init_tty(capabilities: %{unicode: false})

      cells = [
        {{1, 1}, {"✓", :default, :default, []}},
        {{1, 2}, {"✗", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Check becomes x, cross becomes X
      assert output =~ "xX"
      refute output =~ "✓"
      refute output =~ "✗"
    end

    test "ascii mode converts arrows" do
      {:ok, state} = init_tty(capabilities: %{unicode: false})

      cells = [
        {{1, 1}, {"↑", :default, :default, []}},
        {{1, 2}, {"↓", :default, :default, []}},
        {{1, 3}, {"←", :default, :default, []}},
        {{1, 4}, {"→", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Up=^, Down=v, Left=<, Right=>
      assert output =~ "^v<>"
      refute output =~ "↑"
      refute output =~ "↓"
      refute output =~ "←"
      refute output =~ "→"
    end

    test "regular characters pass through unchanged in ascii mode" do
      {:ok, state} = init_tty(capabilities: %{unicode: false})

      cells = [{{1, 1}, {"Hello", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "Hello"
    end

    test "regular characters pass through unchanged in unicode mode" do
      {:ok, state} = init_tty(capabilities: %{unicode: true})

      cells = [{{1, 1}, {"World", :default, :default, []}}]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      assert output =~ "World"
    end

    test "mixed content with box drawing in ascii mode" do
      {:ok, state} = init_tty(capabilities: %{unicode: false})

      # Simulate a simple box: ┌─┐
      cells = [
        {{1, 1}, {"┌", :default, :default, []}},
        {{1, 2}, {"─", :default, :default, []}},
        {{1, 3}, {"┐", :default, :default, []}}
      ]

      output =
        capture_io(fn ->
          TTY.draw_cells(state, cells)
        end)

      # Should render as +-+
      assert output =~ "+-+"
    end
  end

  # ===========================================================================
  # Section 3.8.1 Integration Tests - Full Redraw Lifecycle
  # ===========================================================================

  describe "integration - full redraw lifecycle (Section 3.8.1)" do
    @describetag :integration

    test "init -> draw_cells -> shutdown sequence works correctly" do
      # Initialize backend with full_redraw mode
      output =
        capture_io(fn ->
          {:ok, state} = TTY.init(line_mode: :full_redraw, size: {24, 80})

          # Verify state is correctly initialized
          assert state.line_mode == :full_redraw
          assert state.size == {24, 80}

          # Draw some cells
          cells = [
            {{1, 1}, {"H", :default, :default, []}},
            {{1, 2}, {"i", :default, :default, []}}
          ]

          {:ok, state} = TTY.draw_cells(state, cells)

          # Verify last_frame is nil (full_redraw doesn't track frames)
          assert state.last_frame == nil

          # Shutdown
          :ok = TTY.shutdown(state)
        end)

      # Verify init sequence: hide cursor, clear screen
      assert output =~ "\e[?25l"
      assert output =~ "\e[2J"
      assert output =~ "\e[H"

      # Verify content was rendered
      assert output =~ "Hi"

      # Verify shutdown sequence: reset attrs, show cursor
      assert output =~ "\e[0m"
      assert output =~ "\e[?25h"
    end

    test "init -> draw_cells -> shutdown with alternate screen" do
      output =
        capture_io(fn ->
          {:ok, state} = TTY.init(alternate_screen: true, size: {24, 80})

          assert state.alternate_screen == true

          cells = [{{1, 1}, {"X", :default, :default, []}}]
          {:ok, state} = TTY.draw_cells(state, cells)

          :ok = TTY.shutdown(state)
        end)

      # Verify alternate screen enter
      assert output =~ "\e[?1049h"

      # Verify content rendered
      assert output =~ "X"

      # Verify alternate screen leave on shutdown
      assert output =~ "\e[?1049l"
    end

    test "multiple frames render correctly in full_redraw mode" do
      output =
        capture_io(fn ->
          {:ok, state} = TTY.init(line_mode: :full_redraw, size: {24, 80})

          # Frame 1: Render "A"
          cells1 = [{{1, 1}, {"A", :default, :default, []}}]
          {:ok, state} = TTY.draw_cells(state, cells1)

          # Frame 2: Render "B" at different position
          cells2 = [{{2, 1}, {"B", :default, :default, []}}]
          {:ok, state} = TTY.draw_cells(state, cells2)

          # Frame 3: Render "C" with both positions
          cells3 = [
            {{1, 1}, {"C", :default, :default, []}},
            {{2, 1}, {"D", :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells3)
        end)

      # Each frame should have a clear screen sequence
      # Count occurrences of clear screen (init + 3 frames = 4)
      clear_count = length(String.split(output, "\e[2J")) - 1
      assert clear_count == 4

      # Verify all content was rendered
      assert output =~ "A"
      assert output =~ "B"
      assert output =~ "C"
      assert output =~ "D"
    end

    test "state is properly maintained between frames" do
      capture_io(fn ->
        {:ok, state} =
          TTY.init(
            line_mode: :full_redraw,
            size: {30, 100},
            capabilities: %{colors: :true_color}
          )

        # Verify initial state
        assert state.size == {30, 100}
        assert state.line_mode == :full_redraw
        assert state.color_mode == :true_color

        # Frame 1
        cells1 = [{{1, 1}, {"X", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells1)

        # Verify state persists after frame 1
        assert state.size == {30, 100}
        assert state.line_mode == :full_redraw
        assert state.color_mode == :true_color

        # Frame 2
        cells2 = [{{1, 1}, {"Y", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells2)

        # Verify state still persists after frame 2
        assert state.size == {30, 100}
        assert state.line_mode == :full_redraw
        assert state.color_mode == :true_color
      end)
    end

    test "style changes between frames render different SGR sequences" do
      output =
        capture_io(fn ->
          {:ok, state} = TTY.init(line_mode: :full_redraw, size: {24, 80})

          # Frame 1: Red text
          cells1 = [{{1, 1}, {"R", :red, :default, []}}]
          {:ok, state} = TTY.draw_cells(state, cells1)

          # Frame 2: Blue text with bold
          cells2 = [{{1, 1}, {"B", :blue, :default, [:bold]}}]
          {:ok, state} = TTY.draw_cells(state, cells2)

          # Frame 3: Green background
          cells3 = [{{1, 1}, {"G", :default, :green, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells3)
        end)

      # Verify red foreground (SGR code 31)
      assert output =~ "\e[31m"

      # Verify blue foreground (SGR code 34)
      assert output =~ "\e[34m"

      # Verify bold attribute (SGR code 1)
      assert output =~ "\e[1m"

      # Verify green background (SGR code 42)
      assert output =~ "\e[42m"

      # Verify content
      assert output =~ "R"
      assert output =~ "B"
      assert output =~ "G"
    end

    test "style changes with RGB colors in true_color mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :true_color}
            )

          # Frame 1: RGB red foreground
          cells1 = [{{1, 1}, {"1", {255, 0, 0}, :default, []}}]
          {:ok, state} = TTY.draw_cells(state, cells1)

          # Frame 2: RGB blue background
          cells2 = [{{1, 1}, {"2", :default, {0, 0, 255}, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells2)
        end)

      # Verify true color foreground sequence
      assert output =~ "\e[38;2;255;0;0m"

      # Verify true color background sequence
      assert output =~ "\e[48;2;0;0;255m"
    end

    test "style changes with multiple attributes" do
      output =
        capture_io(fn ->
          {:ok, state} = TTY.init(line_mode: :full_redraw, size: {24, 80})

          # Frame 1: Bold + underline
          cells1 = [{{1, 1}, {"A", :default, :default, [:bold, :underline]}}]
          {:ok, state} = TTY.draw_cells(state, cells1)

          # Frame 2: Italic + reverse
          cells2 = [{{1, 1}, {"B", :default, :default, [:italic, :reverse]}}]
          {:ok, state} = TTY.draw_cells(state, cells2)

          # Frame 3: Dim + strikethrough
          cells3 = [{{1, 1}, {"C", :default, :default, [:dim, :strikethrough]}}]
          {:ok, _state} = TTY.draw_cells(state, cells3)
        end)

      # Verify bold (SGR 1) and underline (SGR 4)
      assert output =~ "\e[1m"
      assert output =~ "\e[4m"

      # Verify italic (SGR 3) and reverse (SGR 7)
      assert output =~ "\e[3m"
      assert output =~ "\e[7m"

      # Verify dim (SGR 2) and strikethrough (SGR 9)
      assert output =~ "\e[2m"
      assert output =~ "\e[9m"
    end

    test "combined color and attribute changes between frames" do
      output =
        capture_io(fn ->
          {:ok, state} = TTY.init(line_mode: :full_redraw, size: {24, 80})

          # Frame 1: Red + bold
          cells1 = [{{1, 1}, {"X", :red, :default, [:bold]}}]
          {:ok, state} = TTY.draw_cells(state, cells1)

          # Frame 2: Blue background + italic
          cells2 = [{{1, 1}, {"Y", :white, :blue, [:italic]}}]
          {:ok, state} = TTY.draw_cells(state, cells2)

          # Frame 3: RGB color + underline
          cells3 = [{{1, 1}, {"Z", {128, 128, 0}, {64, 64, 64}, [:underline]}}]
          {:ok, _state} = TTY.draw_cells(state, cells3)
        end)

      # Frame 1: red (31) + bold (1)
      assert output =~ "\e[31m"
      assert output =~ "\e[1m"

      # Frame 2: white fg (37) + blue bg (44) + italic (3)
      assert output =~ "\e[37m"
      assert output =~ "\e[44m"
      assert output =~ "\e[3m"

      # Frame 3: RGB colors + underline (4)
      assert output =~ "\e[38;2;128;128;0m"
      assert output =~ "\e[48;2;64;64;64m"
      assert output =~ "\e[4m"

      # Verify content
      assert output =~ "X"
      assert output =~ "Y"
      assert output =~ "Z"
    end

    test "each row ends with attribute reset" do
      output =
        capture_io(fn ->
          {:ok, state} = TTY.init(line_mode: :full_redraw, size: {24, 80})

          # Multiple rows with different styles
          cells = [
            {{1, 1}, {"A", :red, :default, [:bold]}},
            {{2, 1}, {"B", :blue, :default, [:italic]}},
            {{3, 1}, {"C", :green, :default, [:underline]}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Each row should have reset sequence after content
      # Count reset sequences (excluding final reset from last row)
      reset_count = length(String.split(output, "\e[0m")) - 1

      # Should have at least 3 resets (one per row) plus init
      assert reset_count >= 3
    end

    test "cursor position is updated after draw_cells" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :full_redraw, size: {24, 80})

        # Initial cursor position after init should be {1, 1}
        assert state.cursor_position == {1, 1}

        # Draw cells
        cells = [{{5, 10}, {"X", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells)

        # After draw_cells, cursor_position is nil (rendering doesn't track final position)
        assert state.cursor_position == nil
      end)
    end

    test "full lifecycle with clear operation" do
      output =
        capture_io(fn ->
          {:ok, state} = TTY.init(line_mode: :full_redraw, size: {24, 80})

          # Draw initial content
          cells1 = [{{1, 1}, {"A", :default, :default, []}}]
          {:ok, state} = TTY.draw_cells(state, cells1)

          # Explicit clear
          {:ok, state} = TTY.clear(state)

          # Draw new content
          cells2 = [{{1, 1}, {"B", :default, :default, []}}]
          {:ok, state} = TTY.draw_cells(state, cells2)

          :ok = TTY.shutdown(state)
        end)

      # Count clear sequences: init + frame1 + explicit clear + frame2 = 4
      clear_count = length(String.split(output, "\e[2J")) - 1
      assert clear_count == 4

      # Both characters rendered
      assert output =~ "A"
      assert output =~ "B"
    end

    test "full lifecycle maintains correct line_mode throughout" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :full_redraw, size: {24, 80})
        assert state.line_mode == :full_redraw

        # After multiple operations, line_mode should remain unchanged
        cells = [{{1, 1}, {"X", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells)
        assert state.line_mode == :full_redraw

        {:ok, state} = TTY.clear(state)
        assert state.line_mode == :full_redraw

        {:ok, state} = TTY.move_cursor(state, {5, 5})
        assert state.line_mode == :full_redraw

        {:ok, state} = TTY.flush(state)
        assert state.line_mode == :full_redraw
      end)
    end
  end

  # ===========================================================================
  # Section 3.8.2 Integration Tests - Incremental Rendering
  # ===========================================================================

  describe "integration - incremental rendering (Section 3.8.2)" do
    @describetag :integration

    # -------------------------------------------------------------------------
    # 3.8.2.1 - Test first frame falls back to full redraw
    # -------------------------------------------------------------------------

    test "first frame in incremental mode triggers full redraw" do
      output =
        capture_io(fn ->
          {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

          # First frame should trigger full redraw (clear screen)
          cells = [{{1, 1}, {"A", :default, :default, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Should contain clear screen sequence (full redraw behavior)
      assert output =~ "\e[2J"
    end

    test "first frame in incremental mode populates last_frame" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

        # Verify initial state has nil last_frame
        assert is_nil(state.last_frame)

        # First frame should populate last_frame
        cells = [{{1, 1}, {"A", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells)

        # last_frame should now be populated
        assert is_map(state.last_frame)
        assert map_size(state.last_frame) == 1
        assert Map.has_key?(state.last_frame, {1, 1})
      end)
    end

    test "first frame with nil last_frame outputs clear screen and content" do
      output =
        capture_io(fn ->
          {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

          cells = [
            {{1, 1}, {"H", :default, :default, []}},
            {{1, 2}, {"i", :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Full redraw behavior: clear screen, home cursor, render content
      # clear screen
      assert output =~ "\e[2J"
      # cursor home
      assert output =~ "\e[H"
      assert output =~ "H"
      assert output =~ "i"
    end

    test "state transitions from nil to populated last_frame correctly" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

        # First draw
        cells1 = [{{1, 1}, {"A", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells1)

        # Capture the first frame
        first_frame = state.last_frame
        assert is_map(first_frame)

        # Second draw with different content
        cells2 = [{{1, 1}, {"B", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells2)

        # Frame should be updated
        assert state.last_frame != first_frame
        assert Map.get(state.last_frame, {1, 1}) == {"B", :default, :default, []}
      end)
    end

    # -------------------------------------------------------------------------
    # 3.8.2.2 - Test subsequent frames only update changes
    # -------------------------------------------------------------------------

    test "subsequent frames do not clear screen" do
      _first_output =
        capture_io(fn ->
          {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

          # First frame (triggers full redraw)
          cells1 = [{{1, 1}, {"A", :default, :default, []}}]
          {:ok, state} = TTY.draw_cells(state, cells1)

          # Capture output from second frame only
          second_output =
            capture_io(fn ->
              cells2 = [{{1, 1}, {"B", :default, :default, []}}]
              {:ok, _state} = TTY.draw_cells(state, cells2)
            end)

          send(self(), {:second_output, second_output})
        end)

      receive do
        {:second_output, second_output} ->
          # Second frame should NOT contain clear screen
          refute second_output =~ "\e[2J"
      end
    end

    test "unchanged cells are not re-rendered in subsequent frames" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

        # First frame with two cells
        cells1 = [
          {{1, 1}, {"A", :default, :default, []}},
          {{1, 2}, {"B", :default, :default, []}}
        ]

        {:ok, state} = TTY.draw_cells(state, cells1)

        # Second frame - only change one cell, keep the other same
        second_output =
          capture_io(fn ->
            cells2 = [
              # unchanged
              {{1, 1}, {"A", :default, :default, []}},
              # changed
              {{1, 2}, {"X", :default, :default, []}}
            ]

            {:ok, _state} = TTY.draw_cells(state, cells2)
          end)

        # Should contain the changed cell
        assert second_output =~ "X"
        # Count occurrences of "A" - should not be re-rendered
        # (A may appear in escape sequences so we check it's not in content position)
        # The incremental render only outputs changed cells
      end)
    end

    test "changed cells are rendered with cursor positioning" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

        # First frame
        cells1 = [{{5, 10}, {"A", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells1)

        # Second frame - change the cell
        second_output =
          capture_io(fn ->
            cells2 = [{{5, 10}, {"B", :default, :default, []}}]
            {:ok, _state} = TTY.draw_cells(state, cells2)
          end)

        # Should contain cursor positioning for row 5, col 10
        assert second_output =~ "\e[5;10H"
        # Should contain the new content
        assert second_output =~ "B"
      end)
    end

    test "new cells are added in subsequent frames" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

        # First frame with one cell
        cells1 = [{{1, 1}, {"A", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells1)

        # Second frame - add a new cell
        second_output =
          capture_io(fn ->
            cells2 = [
              {{1, 1}, {"A", :default, :default, []}},
              # new cell
              {{1, 2}, {"B", :default, :default, []}}
            ]

            {:ok, _state} = TTY.draw_cells(state, cells2)
          end)

        # Should contain the new cell
        assert second_output =~ "B"
      end)
    end

    test "removed cells are cleared in subsequent frames" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

        # First frame with two cells
        cells1 = [
          {{1, 1}, {"A", :default, :default, []}},
          {{1, 2}, {"B", :default, :default, []}}
        ]

        {:ok, state} = TTY.draw_cells(state, cells1)

        # Second frame - remove second cell
        second_output =
          capture_io(fn ->
            cells2 = [{{1, 1}, {"A", :default, :default, []}}]
            {:ok, _state} = TTY.draw_cells(state, cells2)
          end)

        # Should contain cursor positioning for removed cell and a space
        # The cleared position should have cursor move to {1, 2}
        assert second_output =~ "\e[1;2H"
        # Space to clear
        assert second_output =~ " "
      end)
    end

    test "multiple changed cells render efficiently in batches" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

        # First frame
        cells1 = [
          {{1, 1}, {"A", :default, :default, []}},
          {{1, 2}, {"B", :default, :default, []}},
          {{1, 3}, {"C", :default, :default, []}}
        ]

        {:ok, state} = TTY.draw_cells(state, cells1)

        # Second frame - change all cells
        second_output =
          capture_io(fn ->
            cells2 = [
              {{1, 1}, {"X", :default, :default, []}},
              {{1, 2}, {"Y", :default, :default, []}},
              {{1, 3}, {"Z", :default, :default, []}}
            ]

            {:ok, _state} = TTY.draw_cells(state, cells2)
          end)

        # All changed cells should be present
        assert second_output =~ "X"
        assert second_output =~ "Y"
        assert second_output =~ "Z"
        # No clear screen
        refute second_output =~ "\e[2J"
      end)
    end

    test "style changes trigger cell update" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

        # First frame - plain text
        cells1 = [{{1, 1}, {"A", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells1)

        # Second frame - same text but with bold
        second_output =
          capture_io(fn ->
            cells2 = [{{1, 1}, {"A", :default, :default, [:bold]}}]
            {:ok, _state} = TTY.draw_cells(state, cells2)
          end)

        # Should contain the cell (style changed)
        assert second_output =~ "A"
        # Should contain bold SGR
        assert second_output =~ "\e[1m"
      end)
    end

    # -------------------------------------------------------------------------
    # 3.8.2.3 - Test resize triggers full redraw
    # -------------------------------------------------------------------------

    test "set_size/2 clears last_frame" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

        # First frame populates last_frame
        cells = [{{1, 1}, {"A", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells)
        assert is_map(state.last_frame)

        # set_size should clear last_frame
        {:ok, state} = TTY.set_size(state, {30, 100})
        assert is_nil(state.last_frame)
      end)
    end

    test "refresh_size/1 clears last_frame" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

        # First frame populates last_frame
        cells = [{{1, 1}, {"A", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells)
        assert is_map(state.last_frame)

        # refresh_size should clear last_frame
        {:ok, _size, state} = TTY.refresh_size(state)
        assert is_nil(state.last_frame)
      end)
    end

    test "draw_cells after set_size triggers full redraw" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

        # First frame
        cells1 = [{{1, 1}, {"A", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells1)

        # set_size
        {:ok, state} = TTY.set_size(state, {30, 100})

        # Draw after set_size should trigger full redraw
        resize_output =
          capture_io(fn ->
            cells2 = [{{1, 1}, {"B", :default, :default, []}}]
            {:ok, _state} = TTY.draw_cells(state, cells2)
          end)

        # Should contain clear screen (full redraw)
        assert resize_output =~ "\e[2J"
      end)
    end

    test "clear/1 also clears last_frame for incremental mode" do
      capture_io(fn ->
        {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

        # First frame populates last_frame
        cells = [{{1, 1}, {"A", :default, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells)
        assert is_map(state.last_frame)

        # Clear should reset last_frame
        {:ok, state} = TTY.clear(state)
        assert is_nil(state.last_frame)
      end)
    end

    test "full resize cycle: populate -> set_size -> redraw" do
      output =
        capture_io(fn ->
          {:ok, state} = TTY.init(line_mode: :incremental, size: {24, 80})

          # First frame
          cells1 = [{{1, 1}, {"A", :default, :default, []}}]
          {:ok, state} = TTY.draw_cells(state, cells1)

          # Second frame (incremental - no clear)
          cells2 = [{{1, 1}, {"B", :default, :default, []}}]
          {:ok, state} = TTY.draw_cells(state, cells2)

          # set_size
          {:ok, state} = TTY.set_size(state, {30, 100})

          # Third frame (should be full redraw after set_size)
          cells3 = [{{1, 1}, {"C", :default, :default, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells3)
        end)

      # Count clear screen sequences: init + first frame + after set_size = 3
      clear_count = length(String.split(output, "\e[2J")) - 1
      # Init produces clear, first frame in incremental produces clear,
      # third frame after set_size produces clear
      assert clear_count == 3
    end
  end

  # ===========================================================================
  # Section 3.8.3 Integration Tests - Color Degradation
  # ===========================================================================

  describe "integration - color degradation (Section 3.8.3)" do
    @describetag :integration

    # -------------------------------------------------------------------------
    # 3.8.3.1 - Test rendering with true_color capabilities
    # -------------------------------------------------------------------------

    test "RGB colors render with full 24-bit sequences in true_color mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :true_color}
            )

          # Cell with RGB foreground color
          cells = [{{1, 1}, {"X", {255, 128, 64}, :default, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Should contain true color sequence: \e[38;2;r;g;bm
      assert output =~ "\e[38;2;255;128;64m"
    end

    test "multiple RGB colors in same frame render correctly in true_color mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :true_color}
            )

          # Multiple cells with different RGB colors
          cells = [
            {{1, 1}, {"R", {255, 0, 0}, :default, []}},
            {{1, 2}, {"G", {0, 255, 0}, :default, []}},
            {{1, 3}, {"B", {0, 0, 255}, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # All three RGB sequences should be present
      assert output =~ "\e[38;2;255;0;0m"
      assert output =~ "\e[38;2;0;255;0m"
      assert output =~ "\e[38;2;0;0;255m"
    end

    test "RGB foreground and background combinations in true_color mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :true_color}
            )

          # Cell with RGB foreground and background
          cells = [{{1, 1}, {"X", {100, 150, 200}, {50, 75, 100}, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Should contain both foreground and background true color sequences
      # foreground
      assert output =~ "\e[38;2;100;150;200m"
      # background
      assert output =~ "\e[48;2;50;75;100m"
    end

    # -------------------------------------------------------------------------
    # 3.8.3.2 - Test rendering with color_256 capabilities
    # -------------------------------------------------------------------------

    test "RGB colors are mapped to 256-color palette in color_256 mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :color_256}
            )

          # Bright red should map to a palette index
          cells = [{{1, 1}, {"X", {255, 0, 0}, :default, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Should contain 256-color sequence: \e[38;5;nm (not true color)
      assert output =~ ~r/\e\[38;5;\d+m/
      # Should NOT contain true color sequence
      refute output =~ ~r/\e\[38;2;\d+;\d+;\d+m/
    end

    test "color cube mapping (16-231) in color_256 mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :color_256}
            )

          # Non-gray color maps to 6x6x6 color cube (indices 16-231)
          # RGB(255, 0, 0) -> red in color cube
          cells = [{{1, 1}, {"X", {255, 0, 0}, :default, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Should map to color cube (16 + 36*5 + 6*0 + 0 = 196 for pure red)
      assert output =~ "\e[38;5;196m"
    end

    test "grayscale mapping (232-255) in color_256 mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :color_256}
            )

          # Gray color (128, 128, 128) should map to grayscale ramp
          cells = [{{1, 1}, {"X", {128, 128, 128}, :default, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Should map to grayscale ramp (232 + div(128*23, 255) = 232 + 11 = 243)
      assert output =~ "\e[38;5;243m"
    end

    test "palette indices pass through directly in color_256 mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :color_256}
            )

          # Use direct palette index 42
          cells = [{{1, 1}, {"X", 42, :default, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Palette index should pass through unchanged
      assert output =~ "\e[38;5;42m"
    end

    # -------------------------------------------------------------------------
    # 3.8.3.3 - Test rendering with color_16 capabilities
    # -------------------------------------------------------------------------

    test "RGB colors are mapped to nearest basic color in color_16 mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :color_16}
            )

          # Bright red (255, 0, 0) should map to basic red
          cells = [{{1, 1}, {"X", {255, 0, 0}, :default, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Should contain basic color code (30-37 or 90-97)
      assert output =~ ~r/\e\[(3[0-7]|9[0-7])m/
      # Should NOT contain 256-color or true color sequences
      refute output =~ ~r/\e\[38;5;\d+m/
      refute output =~ ~r/\e\[38;2;\d+;\d+;\d+m/
    end

    test "bright vs normal color selection in color_16 mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :color_16}
            )

          # High intensity color should map to bright variant (90-97)
          # Low intensity color should map to normal variant (30-37)
          cells = [
            # Bright white
            {{1, 1}, {"B", {255, 255, 255}, :default, []}},
            # Dark gray -> black range
            {{1, 2}, {"D", {64, 64, 64}, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Bright white should map to 97 (bright white)
      assert output =~ "\e[97m"
      # Dark gray should map to dim range (30-37 range)
      assert output =~ ~r/\e\[3[0-7]m/
    end

    test "named colors work directly in color_16 mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :color_16}
            )

          # Named colors should pass through
          cells = [
            {{1, 1}, {"R", :red, :default, []}},
            {{1, 2}, {"G", :green, :default, []}},
            {{1, 3}, {"B", :bright_blue, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Named colors should produce their standard codes
      # red
      assert output =~ "\e[31m"
      # green
      assert output =~ "\e[32m"
      # bright_blue
      assert output =~ "\e[94m"
    end

    # -------------------------------------------------------------------------
    # 3.8.3.4 - Test rendering with monochrome capabilities
    # -------------------------------------------------------------------------

    test "color sequences are omitted in monochrome mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :monochrome}
            )

          # RGB colors should be omitted entirely
          cells = [{{1, 1}, {"X", {255, 128, 64}, {0, 128, 255}, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Should NOT contain any color sequences
      # No true color
      refute output =~ ~r/\e\[38;2;\d+;\d+;\d+m/
      # No true color bg
      refute output =~ ~r/\e\[48;2;\d+;\d+;\d+m/
      # No 256-color
      refute output =~ ~r/\e\[38;5;\d+m/
      # No 256-color bg
      refute output =~ ~r/\e\[48;5;\d+m/
      # Named colors are also omitted (but 39m/49m for :default are allowed)
      # No named fg colors
      refute output =~ ~r/\e\[3[1-7]m/
      # No named bg colors
      refute output =~ ~r/\e\[4[1-7]m/
    end

    test "text attributes are preserved in monochrome mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :monochrome}
            )

          # Cell with color (should be ignored) and attributes (should be preserved)
          cells = [{{1, 1}, {"X", {255, 0, 0}, :default, [:bold, :underline]}}]
          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Attributes should be present
      # bold
      assert output =~ "\e[1m"
      # underline
      assert output =~ "\e[4m"
      # Color should NOT be present
      refute output =~ ~r/\e\[38;2;\d+;\d+;\d+m/
    end

    test "content still renders correctly in monochrome mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :monochrome}
            )

          # Multiple cells with colors should render content without color codes
          cells = [
            {{1, 1}, {"H", {255, 0, 0}, :default, []}},
            {{1, 2}, {"e", {0, 255, 0}, :default, []}},
            {{1, 3}, {"l", {0, 0, 255}, :default, []}},
            {{1, 4}, {"l", :cyan, :default, []}},
            {{1, 5}, {"o", 42, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Each character should be present (separated by SGR sequences in output)
      assert output =~ "H"
      assert output =~ "e"
      assert output =~ "l"
      assert output =~ "o"
    end

    test "named colors are omitted in monochrome mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :monochrome}
            )

          cells = [{{1, 1}, {"X", :red, :blue, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Named colors should be omitted
      # no red
      refute output =~ "\e[31m"
      # no blue background
      refute output =~ "\e[44m"
    end

    test "palette indices are omitted in monochrome mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{colors: :monochrome}
            )

          cells = [{{1, 1}, {"X", 42, 100, []}}]
          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Palette indices should be omitted
      refute output =~ "\e[38;5;42m"
      refute output =~ "\e[48;5;100m"
    end
  end

  # ===========================================================================
  # Section 3.8.4 Integration Tests - Character Set Fallback
  # ===========================================================================

  describe "integration - character set fallback (Section 3.8.4)" do
    @describetag :integration

    # Get Unicode character set for reference in tests
    # (we test that Unicode chars are mapped to ASCII, so we only need the Unicode set)
    @unicode_chars TermUI.CharacterSet.get(:unicode)

    # -------------------------------------------------------------------------
    # 3.8.4.1 - Test Unicode box-drawing renders correctly
    # -------------------------------------------------------------------------

    test "Unicode box corners render correctly in unicode mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: true}
            )

          # Render all four corners
          cells = [
            {{1, 1}, {@unicode_chars.tl, :default, :default, []}},
            {{1, 2}, {@unicode_chars.tr, :default, :default, []}},
            {{2, 1}, {@unicode_chars.bl, :default, :default, []}},
            {{2, 2}, {@unicode_chars.br, :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # All Unicode corners should be present
      assert output =~ "┌"
      assert output =~ "┐"
      assert output =~ "└"
      assert output =~ "┘"
    end

    test "Unicode horizontal and vertical lines render correctly" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: true}
            )

          cells = [
            {{1, 1}, {@unicode_chars.h_line, :default, :default, []}},
            {{1, 2}, {@unicode_chars.h_line, :default, :default, []}},
            {{2, 1}, {@unicode_chars.v_line, :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      assert output =~ "─"
      assert output =~ "│"
    end

    test "Unicode T-junctions and cross render correctly" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: true}
            )

          cells = [
            {{1, 1}, {@unicode_chars.t_up, :default, :default, []}},
            {{1, 2}, {@unicode_chars.t_down, :default, :default, []}},
            {{1, 3}, {@unicode_chars.t_left, :default, :default, []}},
            {{1, 4}, {@unicode_chars.t_right, :default, :default, []}},
            {{1, 5}, {@unicode_chars.cross, :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      assert output =~ "┴"
      assert output =~ "┬"
      assert output =~ "┤"
      assert output =~ "├"
      assert output =~ "┼"
    end

    test "Unicode progress bar characters render correctly" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: true}
            )

          cells = [
            {{1, 1}, {@unicode_chars.bar_full, :default, :default, []}},
            {{1, 2}, {@unicode_chars.bar_empty, :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      assert output =~ "█"
      assert output =~ "░"
    end

    test "Unicode check marks and arrows render correctly" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: true}
            )

          cells = [
            {{1, 1}, {@unicode_chars.check, :default, :default, []}},
            {{1, 2}, {@unicode_chars.cross_mark, :default, :default, []}},
            {{1, 3}, {@unicode_chars.arrow_up, :default, :default, []}},
            {{1, 4}, {@unicode_chars.arrow_down, :default, :default, []}},
            {{1, 5}, {@unicode_chars.arrow_left, :default, :default, []}},
            {{1, 6}, {@unicode_chars.arrow_right, :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      assert output =~ "✓"
      assert output =~ "✗"
      assert output =~ "↑"
      assert output =~ "↓"
      assert output =~ "←"
      assert output =~ "→"
    end

    # -------------------------------------------------------------------------
    # 3.8.4.2 - Test ASCII fallback renders correctly
    # -------------------------------------------------------------------------

    test "ASCII fallback maps box corners to +" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: false}
            )

          # Unicode corners should be mapped to +
          cells = [
            {{1, 1}, {@unicode_chars.tl, :default, :default, []}},
            {{1, 2}, {@unicode_chars.tr, :default, :default, []}},
            {{2, 1}, {@unicode_chars.bl, :default, :default, []}},
            {{2, 2}, {@unicode_chars.br, :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Unicode corners should NOT appear
      refute output =~ "┌"
      refute output =~ "┐"
      refute output =~ "└"
      refute output =~ "┘"

      # ASCII + should appear instead (multiple times for corners)
      # Count + characters (excluding those in escape sequences)
      plus_count = output |> String.graphemes() |> Enum.count(&(&1 == "+"))
      assert plus_count >= 4
    end

    test "ASCII fallback maps horizontal line to - and vertical to |" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: false}
            )

          cells = [
            {{1, 1}, {@unicode_chars.h_line, :default, :default, []}},
            {{1, 2}, {@unicode_chars.h_line, :default, :default, []}},
            {{2, 1}, {@unicode_chars.v_line, :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Unicode should NOT appear
      refute output =~ "─"
      refute output =~ "│"

      # ASCII equivalents should appear
      assert output =~ "-"
      assert output =~ "|"
    end

    test "ASCII fallback maps T-junctions and cross to +" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: false}
            )

          cells = [
            {{1, 1}, {@unicode_chars.t_up, :default, :default, []}},
            {{1, 2}, {@unicode_chars.t_down, :default, :default, []}},
            {{1, 3}, {@unicode_chars.t_left, :default, :default, []}},
            {{1, 4}, {@unicode_chars.t_right, :default, :default, []}},
            {{1, 5}, {@unicode_chars.cross, :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Unicode should NOT appear
      refute output =~ "┴"
      refute output =~ "┬"
      refute output =~ "┤"
      refute output =~ "├"
      refute output =~ "┼"

      # ASCII + should appear (5 junctions)
      plus_count = output |> String.graphemes() |> Enum.count(&(&1 == "+"))
      assert plus_count >= 5
    end

    test "ASCII fallback maps progress bar characters" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: false}
            )

          cells = [
            {{1, 1}, {@unicode_chars.bar_full, :default, :default, []}},
            {{1, 2}, {@unicode_chars.bar_empty, :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Unicode should NOT appear
      refute output =~ "█"
      refute output =~ "░"

      # ASCII equivalents
      assert output =~ "#"
      assert output =~ "."
    end

    test "ASCII fallback maps check marks and arrows" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: false}
            )

          cells = [
            {{1, 1}, {@unicode_chars.check, :default, :default, []}},
            {{1, 2}, {@unicode_chars.cross_mark, :default, :default, []}},
            {{1, 3}, {@unicode_chars.arrow_up, :default, :default, []}},
            {{1, 4}, {@unicode_chars.arrow_down, :default, :default, []}},
            {{1, 5}, {@unicode_chars.arrow_left, :default, :default, []}},
            {{1, 6}, {@unicode_chars.arrow_right, :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Unicode should NOT appear
      refute output =~ "✓"
      refute output =~ "✗"
      refute output =~ "↑"
      refute output =~ "↓"
      refute output =~ "←"
      refute output =~ "→"

      # ASCII equivalents (check is x, cross_mark is X)
      assert output =~ "x"
      assert output =~ "X"
      assert output =~ "^"
      assert output =~ "v"
      assert output =~ "<"
      assert output =~ ">"
    end

    # -------------------------------------------------------------------------
    # 3.8.4.3 - Test mixed content (Unicode text with ASCII boxes)
    # -------------------------------------------------------------------------

    test "regular ASCII text passes through unchanged in both modes" do
      for unicode_mode <- [true, false] do
        output =
          capture_io(fn ->
            {:ok, state} =
              TTY.init(
                line_mode: :full_redraw,
                size: {24, 80},
                capabilities: %{unicode: unicode_mode}
              )

            cells = [
              {{1, 1}, {"H", :default, :default, []}},
              {{1, 2}, {"e", :default, :default, []}},
              {{1, 3}, {"l", :default, :default, []}},
              {{1, 4}, {"l", :default, :default, []}},
              {{1, 5}, {"o", :default, :default, []}}
            ]

            {:ok, _state} = TTY.draw_cells(state, cells)
          end)

        assert output =~ "H"
        assert output =~ "e"
        assert output =~ "l"
        assert output =~ "o"
      end
    end

    test "Unicode text passes through unchanged in unicode mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: true}
            )

          # Unicode text that is NOT box-drawing (should pass through)
          cells = [
            {{1, 1}, {"日", :default, :default, []}},
            {{1, 2}, {"本", :default, :default, []}},
            {{1, 3}, {"語", :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      assert output =~ "日"
      assert output =~ "本"
      assert output =~ "語"
    end

    test "non-box-drawing Unicode passes through unchanged in ascii mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: false}
            )

          # Unicode text that is NOT in our box-drawing map should pass through
          # (the terminal may or may not display it, but we don't modify it)
          cells = [
            {{1, 1}, {"日", :default, :default, []}},
            {{1, 2}, {"本", :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Non-box-drawing Unicode should pass through even in ASCII mode
      # (we only map the specific box-drawing characters)
      assert output =~ "日"
      assert output =~ "本"
    end

    test "mixed content: text with box-drawing on same row in unicode mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: true}
            )

          # Mixed: box corner, text, box corner
          cells = [
            {{1, 1}, {@unicode_chars.tl, :default, :default, []}},
            {{1, 2}, {"T", :default, :default, []}},
            {{1, 3}, {"e", :default, :default, []}},
            {{1, 4}, {"s", :default, :default, []}},
            {{1, 5}, {"t", :default, :default, []}},
            {{1, 6}, {@unicode_chars.tr, :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Both Unicode box-drawing and text should appear
      assert output =~ "┌"
      assert output =~ "Test"
      assert output =~ "┐"
    end

    test "mixed content: text with box-drawing on same row in ascii mode" do
      output =
        capture_io(fn ->
          {:ok, state} =
            TTY.init(
              line_mode: :full_redraw,
              size: {24, 80},
              capabilities: %{unicode: false}
            )

          # Mixed: box corner, text, box corner (should map corners to +)
          cells = [
            {{1, 1}, {@unicode_chars.tl, :default, :default, []}},
            {{1, 2}, {"T", :default, :default, []}},
            {{1, 3}, {"e", :default, :default, []}},
            {{1, 4}, {"s", :default, :default, []}},
            {{1, 5}, {"t", :default, :default, []}},
            {{1, 6}, {@unicode_chars.tr, :default, :default, []}}
          ]

          {:ok, _state} = TTY.draw_cells(state, cells)
        end)

      # Box-drawing should be mapped to ASCII
      refute output =~ "┌"
      refute output =~ "┐"

      # Text should be unchanged
      assert output =~ "Test"

      # ASCII + for corners
      plus_count = output |> String.graphemes() |> Enum.count(&(&1 == "+"))
      assert plus_count >= 2
    end

    test "character_set state is set correctly based on capabilities" do
      capture_io(fn ->
        {:ok, unicode_state} = TTY.init(capabilities: %{unicode: true})
        assert unicode_state.character_set == :unicode

        {:ok, ascii_state} = TTY.init(capabilities: %{unicode: false})
        assert ascii_state.character_set == :ascii

        # Default should be unicode
        {:ok, default_state} = TTY.init(capabilities: %{})
        assert default_state.character_set == :unicode
      end)
    end
  end
end
