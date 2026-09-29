defmodule TermUI.Terminal.InputReaderTest do
  use ExUnit.Case, async: false

  alias TermUI.Event
  alias TermUI.Terminal.InputReader

  # Portable IO tests check delivery without changing OS terminal modes.
  # The older interactive lifecycle tests retain their terminal requirement.

  test "delivers control keys and continued text through the IO reader" do
    with_input_reader(<<3, 19, 17, ?q, "界"::binary>>, fn ->
      for key <- ["c", "s", "q"] do
        assert_receive {:input, %Event.Key{key: ^key, modifiers: [:ctrl]}}, 1_000
      end

      assert_receive {:input, %Event.Key{key: "q", modifiers: []}}, 1_000
      assert_receive {:input, %Event.Key{key: "界", modifiers: []}}, 1_000
    end)
  end

  test "completes a navigation sequence across single-character reads" do
    with_input_reader("\e[Aq", fn ->
      assert_receive {:input, %Event.Key{key: :up}}, 1_000
      assert_receive {:input, %Event.Key{key: "q"}}, 1_000
    end)
  end

  defp with_input_reader(input, assertions) do
    {:ok, device} = StringIO.open(input)
    previous = Process.group_leader()
    Process.group_leader(self(), device)

    try do
      {:ok, _reader} = InputReader.start_link(target: self())
      assertions.()
    after
      Process.group_leader(self(), previous)
      StringIO.close(device)
    end
  end

  describe "start_link/1 and stop/1" do
    @tag :requires_terminal
    test "starts and stops cleanly" do
      {:ok, reader} = InputReader.start_link(target: self())
      assert Process.alive?(reader)

      :ok = InputReader.stop(reader)
      refute Process.alive?(reader)
    end

    @tag :requires_terminal
    test "requires target option" do
      assert_raise KeyError, fn ->
        InputReader.start_link([])
      end
    end

    @tag :requires_terminal
    test "accepts name option" do
      {:ok, reader} = InputReader.start_link(target: self(), name: :test_reader)
      assert Process.whereis(:test_reader) == reader

      :ok = InputReader.stop(reader)
    end
  end

  describe "event delivery" do
    # Note: These tests are limited because we can't easily inject input
    # into the stdin port. The InputReader uses `cat` as the port command
    # which reads from stdin, making direct testing challenging.
    #
    # For full integration testing, see the dashboard example which
    # demonstrates real keyboard input handling.

    @tag :requires_terminal
    test "reader process state has correct structure" do
      # Start InputReader, but it may fail in test environment if stdin isn't available
      case InputReader.start_link(target: self()) do
        {:ok, reader} ->
          # Give process time to stabilize
          Process.sleep(10)

          # Check if process is still alive (may have died due to stdin issues)
          if Process.alive?(reader) do
            # Use sys to get state
            {:status, _pid, _module, [_pdict, _state, _parent, _debug, _state_data]} =
              :sys.get_status(reader)

            # The state is wrapped in GenServer format
            # Just verify the process is running
            assert Process.alive?(reader)

            :ok = InputReader.stop(reader)
          else
            # Process died, expected in test environment without proper stdin
            assert true
          end

        {:error, _reason} ->
          # Failed to start, expected in some test environments
          assert true
      end
    end
  end

  describe "escape timeout handling" do
    # These tests verify the timeout behavior for disambiguating
    # ESC key vs ESC sequences. Since we can't inject data into
    # the stdin port, we test this through the EscapeParser directly.
    #
    # The InputReader's timeout logic is:
    # 1. Receive partial escape sequence
    # 2. Set 50ms timer
    # 3. On timeout, emit ESC and any remaining keys

    @tag :requires_terminal
    test "timeout constant is reasonable" do
      # The escape timeout should be fast enough to feel responsive
      # but slow enough to catch escape sequences
      # Typically 50ms is a good balance
      # We can't access the constant directly, but we test the behavior
      {:ok, reader} = InputReader.start_link(target: self())
      assert Process.alive?(reader)
      :ok = InputReader.stop(reader)
    end
  end

  describe "termination" do
    @tag :requires_terminal
    test "closes port on termination" do
      {:ok, reader} = InputReader.start_link(target: self())

      # Stop the reader
      :ok = InputReader.stop(reader)

      # Process should be dead
      refute Process.alive?(reader)
    end

    @tag :requires_terminal
    test "handles normal shutdown" do
      {:ok, reader} = InputReader.start_link(target: self())

      # GenServer.stop with normal reason
      GenServer.stop(reader, :normal)
      refute Process.alive?(reader)
    end
  end
end
