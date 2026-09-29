defmodule TermUI.Integration.CrossPlatformTest do
  @moduledoc """
  Integration tests for cross-platform behavior.

  Verifies consistent behavior across operating systems and validates
  that platform-specific code works correctly on each platform.
  """

  use ExUnit.Case, async: false

  alias TermUI.IntegrationHelpers
  alias TermUI.Parser.Events.KeyEvent
  alias TermUI.Platform
  alias TermUI.Platform.Unix
  alias TermUI.Platform.Windows

  import IntegrationHelpers, only: [parse: 1]

  # These tests validate platform behavior
  @moduletag :integration

  setup do
    IntegrationHelpers.stop_terminal()

    on_exit(fn ->
      IntegrationHelpers.cleanup_terminal()
    end)

    :ok
  end

  describe "1.6.4.1 terminal initialization on all platforms" do
    test "terminal genserver starts successfully" do
      assert {:ok, pid} = IntegrationHelpers.start_terminal()
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "platform detection returns valid platform" do
      platform = Platform.platform()

      assert platform in [:linux, :macos, :windows, :freebsd, :unknown],
             "Got unexpected platform: #{platform}"
    end

    test "os version is parseable" do
      version = Platform.os_version()

      case version do
        {major, minor, patch} ->
          assert is_integer(major) and major >= 0
          assert is_integer(minor) and minor >= 0
          assert is_integer(patch) and patch >= 0

        nil ->
          # Some platforms may not provide version
          assert true
      end
    end

    test "unix?/windows? are mutually exclusive" do
      is_unix = Platform.unix?()
      is_windows = Platform.windows?()

      # Can't be both (or should be exactly one)
      refute is_unix and is_windows, "Platform cannot be both Unix and Windows"

      # At least one should be true for known platforms
      if Platform.platform() in [:linux, :macos, :freebsd] do
        assert is_unix
        refute is_windows
      end

      if Platform.platform() == :windows do
        assert is_windows
        refute is_unix
      end
    end

    test "platform info aggregates correctly" do
      info = Platform.info()

      assert is_map(info)
      assert info.platform == Platform.platform()
      assert info.unix == Platform.unix?()
      assert info.windows == Platform.windows?()
      assert info.wsl == Platform.wsl?()
    end
  end

  describe "1.6.4.2 input parsing consistency" do
    test "basic key sequences are platform-agnostic" do
      # ASCII characters work the same everywhere
      {events, ""} = parse("abc")

      assert [
               %KeyEvent{key: "a", modifiers: []},
               %KeyEvent{key: "b", modifiers: []},
               %KeyEvent{key: "c", modifiers: []}
             ] = events
    end

    test "control characters are platform-agnostic" do
      # Ctrl+C is ASCII 3 everywhere
      {events, ""} = parse(<<3>>)
      assert [%KeyEvent{key: "c", modifiers: [:ctrl]}] = events
    end

    test "escape sequences follow VT100 standard" do
      # Arrow keys use same sequences on all platforms
      {events, ""} = parse("\e[A")
      assert [%KeyEvent{key: :up, modifiers: []}] = events

      {events, ""} = parse("\e[B")
      assert [%KeyEvent{key: :down, modifiers: []}] = events
    end

    test "enter key is consistent" do
      # Enter is carriage return (13) on all platforms
      {events, ""} = parse(<<13>>)
      assert [%KeyEvent{key: :enter, modifiers: []}] = events
    end

    test "tab key is consistent" do
      {events, ""} = parse(<<9>>)
      assert [%KeyEvent{key: :tab, modifiers: []}] = events
    end

    test "backspace handling" do
      # Backspace can be 8 (BS) or 127 (DEL)
      {events1, ""} = parse(<<8>>)
      {events2, ""} = parse(<<127>>)

      # Both should parse to some form of backspace
      assert length(events1) == 1
      assert length(events2) == 1
    end
  end

  describe "1.6.4.3 terminal size detection" do
    test "returns valid dimensions" do
      {:ok, _pid} = IntegrationHelpers.start_terminal()

      case TermUI.Terminal.get_terminal_size() do
        {:ok, {rows, cols}} ->
          assert is_integer(rows) and rows > 0, "Rows should be positive integer"
          assert is_integer(cols) and cols > 0, "Cols should be positive integer"

        {:error, _reason} ->
          # In non-terminal environment, this is expected
          assert true
      end
    end

    test "platform terminal_size returns reasonable defaults" do
      {rows, cols} = Platform.terminal_size()

      # Should always return positive integers
      assert is_integer(rows) and rows > 0
      assert is_integer(cols) and cols > 0

      # Reasonable bounds (at least 1x1, at most something reasonable)
      assert rows >= 1 and rows <= 1000
      assert cols >= 1 and cols <= 1000
    end

    test "terminal size is consistent with platform" do
      # Get size from both sources
      platform_size = Platform.terminal_size()

      {:ok, _pid} = IntegrationHelpers.start_terminal()
      genserver_result = TermUI.Terminal.get_terminal_size()

      case genserver_result do
        {:ok, genserver_size} ->
          # Sizes should match (or be close if there's a race)
          {p_rows, p_cols} = platform_size
          {g_rows, g_cols} = genserver_size

          # Allow small differences due to timing
          assert abs(p_rows - g_rows) <= 1
          assert abs(p_cols - g_cols) <= 1

        {:error, _} ->
          # GenServer couldn't get size, but platform should still have defaults
          assert is_tuple(platform_size)
      end
    end
  end

  describe "1.6.4.4 cleanup on all platforms" do
    test "restore resets all state" do
      {:ok, _pid} = IntegrationHelpers.start_terminal()

      # Call restore
      assert :ok = TermUI.Terminal.restore()

      # State should be clean
      IntegrationHelpers.assert_terminal_clean()
    end

    test "genserver stop cleans up" do
      {:ok, pid} = IntegrationHelpers.start_terminal()

      # Stop normally
      GenServer.stop(pid, :normal)

      # Process should be gone
      assert Process.whereis(TermUI.Terminal) == nil
    end

    test "multiple cleanup calls are safe" do
      {:ok, _pid} = IntegrationHelpers.start_terminal()

      # Multiple restores should be safe
      :ok = TermUI.Terminal.restore()
      :ok = TermUI.Terminal.restore()
      :ok = TermUI.Terminal.restore()

      IntegrationHelpers.assert_terminal_clean()
    end
  end

  describe "platform-specific functionality" do
    @tag :unix
    test "Unix platforms support all standard features" do
      if Platform.unix?() do
        assert Platform.supports_feature?(:signals) == true
        assert Platform.supports_feature?(:pty) == true
        assert Platform.supports_feature?(:terminfo) == true
        assert Platform.supports_feature?(:vt_sequences) == true
      end
    end

    @tag :unix
    test "Unix module provides correct info" do
      if Platform.unix?() do
        info = Unix.info()

        assert is_map(info)
        assert info.supports_signals == true
        assert info.supports_pty == true
        assert is_list(info.terminfo_paths)
      end
    end

    @tag :unix
    test "Unix terminfo paths exist" do
      if Platform.unix?() do
        paths = Unix.terminfo_paths()

        # At least one path should exist
        existing =
          Enum.filter(paths, fn path ->
            File.dir?(path)
          end)

        assert existing != [], "Some terminfo paths should exist"
      end
    end

    @tag :unix
    test "Unix signals are listed" do
      if Platform.unix?() do
        signals = Unix.supported_signals()

        assert is_list(signals)
        assert :sigwinch in signals
        assert :sigterm in signals
        assert :sigint in signals
      end
    end

    test "Windows module provides stub info" do
      info = Windows.info()

      assert is_map(info)
      assert info.platform == :windows
      assert info.implementation_status == :stub
    end

    test "Windows version requirements are specified" do
      {major, minor, build} = Windows.minimum_version()

      assert major == 10
      assert minor == 0
      assert build == 10_586
    end

    test "Windows VT support check" do
      result = Windows.vt_support_available?()
      assert is_boolean(result)
    end
  end

  describe "feature support matrix" do
    @features [:signals, :pty, :terminfo, :vt_sequences]

    for feature <- @features do
      @feature feature

      test "supports_feature?(#{feature}) returns boolean" do
        result = Platform.supports_feature?(@feature)
        assert is_boolean(result)
      end
    end

    test "unknown features return false" do
      assert Platform.supports_feature?(:nonexistent) == false
      assert Platform.supports_feature?(:made_up_feature) == false
    end

    test "vt_sequences supported on all platforms" do
      # VT sequences should be supported everywhere (for modern terminals)
      assert Platform.supports_feature?(:vt_sequences) == true
    end
  end

  describe "WSL detection" do
    test "wsl? returns boolean" do
      result = Platform.wsl?()
      assert is_boolean(result)
    end

    test "wsl? is false on non-Linux" do
      if Platform.platform() != :linux do
        assert Platform.wsl?() == false
      end
    end

    test "linux? excludes WSL" do
      # If we're in WSL, linux? should be false
      if Platform.wsl?() do
        assert Platform.linux?() == false
      end
    end
  end

  describe "platform consistency" do
    test "platform detection is consistent" do
      # Multiple calls should return the same result
      p1 = Platform.platform()
      p2 = Platform.platform()
      p3 = Platform.platform()

      assert p1 == p2
      assert p2 == p3
    end

    test "helper functions match platform detection" do
      platform = Platform.platform()

      case platform do
        :linux ->
          if not Platform.wsl?() do
            assert Platform.linux?() == true
          end

          assert Platform.unix?() == true

        :macos ->
          assert Platform.macos?() == true
          assert Platform.unix?() == true

        :freebsd ->
          assert Platform.unix?() == true

        :windows ->
          assert Platform.windows?() == true
          assert Platform.unix?() == false

        :unknown ->
          # Unknown platform - just ensure no crashes
          assert true
      end
    end
  end

  describe "ANSI sequence compatibility" do
    test "cursor sequences are platform-agnostic" do
      # These should work on all platforms with VT support
      seqs = [
        TermUI.ANSI.cursor_position(1, 1),
        TermUI.ANSI.cursor_up(),
        TermUI.ANSI.cursor_down(),
        TermUI.ANSI.cursor_show(),
        TermUI.ANSI.cursor_hide()
      ]

      for seq <- seqs do
        binary = IO.iodata_to_binary(seq)
        assert String.starts_with?(binary, "\e[")
      end
    end

    test "color sequences use standard codes" do
      # SGR sequences should be standard
      red = TermUI.ANSI.foreground(:red) |> IO.iodata_to_binary()
      assert red == "\e[31m"

      bold = TermUI.ANSI.bold() |> IO.iodata_to_binary()
      assert bold == "\e[1m"

      reset = TermUI.ANSI.reset() |> IO.iodata_to_binary()
      assert reset == "\e[0m"
    end
  end
end
