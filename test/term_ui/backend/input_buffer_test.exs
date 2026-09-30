defmodule TermUI.Backend.InputBufferTest do
  use ExUnit.Case, async: false

  alias TermUI.Backend.InputBuffer
  alias TermUI.Terminal.EscapeParser

  setup do
    # Clear rate limits between tests
    InputBuffer.clear_rate_limits()
    :ok
  end

  describe "max_size/0" do
    test "returns 1024" do
      assert InputBuffer.max_size() == 1024
    end
  end

  describe "keep_size/0" do
    test "returns 256" do
      assert InputBuffer.keep_size() == 256
    end
  end

  describe "append/2" do
    test "appends data to buffer" do
      assert InputBuffer.append("hello", " world") == "hello world"
    end

    test "appends to empty buffer" do
      assert InputBuffer.append("", "data") == "data"
    end

    test "appends empty data" do
      assert InputBuffer.append("data", "") == "data"
    end

    test "handles binary data" do
      assert InputBuffer.append(<<1, 2, 3>>, <<4, 5, 6>>) == <<1, 2, 3, 4, 5, 6>>
    end
  end

  describe "apply_limit/2" do
    test "returns buffer unchanged if under limit" do
      buffer = String.duplicate("x", 100)
      {result, overflowed} = InputBuffer.apply_limit(buffer)
      assert result == buffer
      assert overflowed == false
    end

    test "returns buffer unchanged at exact limit" do
      buffer = String.duplicate("x", 1024)
      {result, overflowed} = InputBuffer.apply_limit(buffer)
      assert result == buffer
      assert overflowed == false
    end

    test "truncates buffer exceeding limit" do
      buffer = String.duplicate("x", 2000)
      {result, overflowed} = InputBuffer.apply_limit(buffer, log: false)
      assert byte_size(result) == 256
      assert overflowed == true
    end

    test "keeps most recent bytes when truncating" do
      # Create buffer with identifiable end
      buffer = String.duplicate("a", 1500) <> "END"
      {result, _} = InputBuffer.apply_limit(buffer, log: false)
      assert String.ends_with?(result, "END")
    end

    test "handles buffer just over limit" do
      buffer = String.duplicate("x", 1025)
      {result, overflowed} = InputBuffer.apply_limit(buffer, log: false)
      assert byte_size(result) == 256
      assert overflowed == true
    end

    test "handles very large buffers" do
      buffer = String.duplicate("x", 100_000)
      {result, overflowed} = InputBuffer.apply_limit(buffer, log: false)
      assert byte_size(result) == 256
      assert overflowed == true
    end
  end

  describe "apply_limit/2 with logging" do
    import ExUnit.CaptureLog

    test "logs warning on first overflow" do
      buffer = String.duplicate("x", 2000)

      log =
        capture_log(fn ->
          InputBuffer.apply_limit(buffer, source: :test_first)
        end)

      assert log =~ "Input buffer overflow"
      assert log =~ "2000 bytes"
      assert log =~ "truncating to 256 bytes"
    end

    test "rate limits logging for same source" do
      buffer = String.duplicate("x", 2000)

      # First call should log
      log1 =
        capture_log(fn ->
          InputBuffer.apply_limit(buffer, source: :test_rate_limit)
        end)

      assert log1 =~ "Input buffer overflow"

      # Immediate second call should NOT log
      log2 =
        capture_log(fn ->
          InputBuffer.apply_limit(buffer, source: :test_rate_limit)
        end)

      assert log2 == ""
    end

    test "different sources log independently" do
      buffer = String.duplicate("x", 2000)

      log1 =
        capture_log(fn ->
          InputBuffer.apply_limit(buffer, source: :source_a)
        end)

      log2 =
        capture_log(fn ->
          InputBuffer.apply_limit(buffer, source: :source_b)
        end)

      assert log1 =~ "Input buffer overflow"
      assert log2 =~ "Input buffer overflow"
    end

    test "suppresses logging when log: false" do
      buffer = String.duplicate("x", 2000)

      log =
        capture_log(fn ->
          InputBuffer.apply_limit(buffer, source: :test_no_log, log: false)
        end)

      assert log == ""
    end
  end

  describe "append_with_limit/4" do
    test "appends and returns state with updated buffer" do
      state = %{input_buffer: "partial"}
      new_state = InputBuffer.append_with_limit(state, "[A", :input_buffer, log: false)
      assert new_state.input_buffer == "partial[A"
    end

    test "handles struct-like maps" do
      state = %{input_buffer: "", other_field: 42}
      new_state = InputBuffer.append_with_limit(state, "data", :input_buffer, log: false)
      assert new_state.input_buffer == "data"
      assert new_state.other_field == 42
    end

    test "truncates when buffer exceeds limit" do
      state = %{input_buffer: String.duplicate("x", 1000)}

      new_state =
        InputBuffer.append_with_limit(state, String.duplicate("y", 500), :input_buffer,
          log: false
        )

      assert byte_size(new_state.input_buffer) == 256
    end

    test "handles missing field by using empty string" do
      state = %{other_field: 42}
      new_state = InputBuffer.append_with_limit(state, "data", :input_buffer, log: false)
      assert new_state.input_buffer == "data"
    end

    test "passes options to apply_limit" do
      import ExUnit.CaptureLog

      state = %{input_buffer: String.duplicate("x", 1000)}

      log =
        capture_log(fn ->
          InputBuffer.append_with_limit(
            state,
            String.duplicate("y", 500),
            :input_buffer,
            source: :append_test
          )
        end)

      assert log =~ "Input buffer overflow"
    end
  end

  describe "append_with_limit/4 with bracketed paste" do
    @paste_start "\e[200~"
    @paste_end "\e[201~"
    @max_paste_size 8 * 1024 * 1024

    test "collects a normal paste one byte at a time and keeps trailing input" do
      state = %{input_buffer: "", paste_state: nil}

      state =
        Enum.reduce(
          String.to_charlist(@paste_start <> "hello" <> @paste_end <> "x"),
          state,
          fn byte, state ->
            InputBuffer.append_with_limit(state, <<byte>>, :input_buffer,
              paste_aware: true,
              log: false
            )
          end
        )

      assert state.paste_state == nil
      assert state.input_buffer == @paste_start <> "hello" <> @paste_end <> "x"

      {events, remaining} = EscapeParser.parse(state.input_buffer)
      assert [%TermUI.Event.Paste{content: "hello"}, %TermUI.Event.Text{text: "x"}] = events
      assert remaining == ""
    end

    test "keeps a paste body at the exact maximum size" do
      body = :binary.copy("x", @max_paste_size)
      state = %{input_buffer: "", paste_state: nil}

      state =
        InputBuffer.append_with_limit(state, @paste_start <> body <> @paste_end, :input_buffer,
          paste_aware: true,
          log: false
        )

      assert state.paste_state == nil
      assert state.input_buffer == @paste_start <> body <> @paste_end
    end

    test "discards a one-byte oversized paste and recovers when the end marker is fragmented" do
      state = %{input_buffer: "", paste_state: nil}
      oversized = :binary.copy("x", @max_paste_size + 1)

      state =
        InputBuffer.append_with_limit(state, @paste_start <> oversized, :input_buffer,
          paste_aware: true,
          log: false
        )

      assert %{mode: :discarding} = state.paste_state

      state =
        Enum.reduce(String.to_charlist(@paste_end <> "z"), state, fn byte, state ->
          InputBuffer.append_with_limit(state, <<byte>>, :input_buffer,
            paste_aware: true,
            log: false
          )
        end)

      assert state.paste_state == nil
      assert state.input_buffer == "z"
    end
  end

  describe "clear_rate_limits/0" do
    import ExUnit.CaptureLog

    test "clears rate limit state" do
      buffer = String.duplicate("x", 2000)

      # First call logs
      capture_log(fn ->
        InputBuffer.apply_limit(buffer, source: :clear_test)
      end)

      # Clear limits
      InputBuffer.clear_rate_limits()

      # Should log again after clear
      log =
        capture_log(fn ->
          InputBuffer.apply_limit(buffer, source: :clear_test)
        end)

      assert log =~ "Input buffer overflow"
    end
  end

  describe "edge cases" do
    test "handles empty buffer" do
      {result, overflowed} = InputBuffer.apply_limit("")
      assert result == ""
      assert overflowed == false
    end

    test "handles single byte buffer" do
      {result, overflowed} = InputBuffer.apply_limit("x")
      assert result == "x"
      assert overflowed == false
    end

    test "handles binary with null bytes" do
      buffer = <<0, 1, 2, 0, 3, 4>>
      {result, overflowed} = InputBuffer.apply_limit(buffer)
      assert result == buffer
      assert overflowed == false
    end

    test "handles UTF-8 content" do
      # Unicode characters (varying byte sizes)
      # Using a 3-byte UTF-8 character repeated 400 times = 1200 bytes
      # Heart symbol, 3 bytes each
      buffer = String.duplicate("\u{2764}", 400)
      {result, overflowed} = InputBuffer.apply_limit(buffer, log: false)
      # 400 * 3 = 1200 bytes, exceeds 1024 limit
      assert overflowed == true
      assert byte_size(result) == 256
    end
  end

  describe "concurrent access" do
    test "handles concurrent calls from multiple processes" do
      buffer = String.duplicate("x", 2000)

      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            source = :"concurrent_test_#{i}"
            {result, overflowed} = InputBuffer.apply_limit(buffer, source: source, log: false)
            {byte_size(result), overflowed}
          end)
        end

      results = Task.await_many(tasks)

      # All should have truncated
      for {size, overflowed} <- results do
        assert size == 256
        assert overflowed == true
      end
    end
  end
end
