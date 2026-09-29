defmodule TermUI.PlatformTest do
  use ExUnit.Case, async: true

  alias TermUI.Platform

  describe "OTP capabilities" do
    test "reports a numeric OTP release" do
      assert Platform.otp_release() >= 1
    end

    test "native raw mode requires OTP 28 or later" do
      assert Platform.native_raw_mode_supported?() == Platform.otp_release() >= 28
    end
  end

  describe "platform/0" do
    test "returns a valid platform atom" do
      platform = Platform.platform()
      assert platform in [:linux, :macos, :windows, :freebsd, :unknown]
    end

    test "returns consistent results" do
      platform1 = Platform.platform()
      platform2 = Platform.platform()
      assert platform1 == platform2
    end
  end

  describe "os_version/0" do
    test "returns a version tuple or nil" do
      version = Platform.os_version()

      case version do
        {major, minor, patch} ->
          assert is_integer(major) and major >= 0
          assert is_integer(minor) and minor >= 0
          assert is_integer(patch) and patch >= 0

        nil ->
          assert true
      end
    end
  end

  describe "unix?/0" do
    test "returns boolean" do
      result = Platform.unix?()
      assert is_boolean(result)
    end

    test "is true for Unix platforms" do
      if Platform.platform() in [:linux, :macos, :freebsd] do
        assert Platform.unix?() == true
      end
    end

    test "is false for Windows" do
      if Platform.platform() == :windows do
        assert Platform.unix?() == false
      end
    end
  end

  describe "windows?/0" do
    test "returns boolean" do
      result = Platform.windows?()
      assert is_boolean(result)
    end

    test "is true only for Windows" do
      if Platform.platform() == :windows do
        assert Platform.windows?() == true
      else
        assert Platform.windows?() == false
      end
    end
  end

  describe "wsl?/0" do
    test "returns boolean" do
      result = Platform.wsl?()
      assert is_boolean(result)
    end

    test "is always false on non-Linux platforms" do
      if Platform.platform() != :linux do
        assert Platform.wsl?() == false
      end
    end
  end

  describe "macos?/0" do
    test "returns boolean" do
      result = Platform.macos?()
      assert is_boolean(result)
    end

    test "matches platform detection" do
      assert Platform.macos?() == (Platform.platform() == :macos)
    end
  end

  describe "linux?/0" do
    test "returns boolean" do
      result = Platform.linux?()
      assert is_boolean(result)
    end

    test "is false if WSL" do
      if Platform.wsl?() do
        assert Platform.linux?() == false
      end
    end
  end

  describe "terminal_size/0" do
    test "returns tuple of positive integers" do
      {rows, cols} = Platform.terminal_size()

      assert is_integer(rows) and rows > 0
      assert is_integer(cols) and cols > 0
    end

    test "returns reasonable default values" do
      {rows, cols} = Platform.terminal_size()

      # Should be at least default size
      assert rows >= 1
      assert cols >= 1
    end
  end

  describe "supports_feature?/1" do
    test "returns boolean for valid features" do
      features = [:signals, :pty, :terminfo, :vt_sequences]

      for feature <- features do
        result = Platform.supports_feature?(feature)
        assert is_boolean(result), "Expected boolean for #{feature}, got #{inspect(result)}"
      end
    end

    test "returns false for unknown features" do
      assert Platform.supports_feature?(:unknown_feature) == false
      assert Platform.supports_feature?(:nonexistent) == false
    end

    test "Unix platforms support all standard features" do
      if Platform.unix?() do
        assert Platform.supports_feature?(:signals) == true
        assert Platform.supports_feature?(:pty) == true
        assert Platform.supports_feature?(:terminfo) == true
        assert Platform.supports_feature?(:vt_sequences) == true
      end
    end

    test "Windows supports VT sequences" do
      if Platform.windows?() do
        assert Platform.supports_feature?(:vt_sequences) == true
        assert Platform.supports_feature?(:signals) == false
        assert Platform.supports_feature?(:pty) == false
        assert Platform.supports_feature?(:terminfo) == false
      end
    end
  end

  describe "info/0" do
    test "returns map with all expected keys" do
      info = Platform.info()

      assert is_map(info)
      assert Map.has_key?(info, :platform)
      assert Map.has_key?(info, :os_version)
      assert Map.has_key?(info, :unix)
      assert Map.has_key?(info, :windows)
      assert Map.has_key?(info, :wsl)
      assert Map.has_key?(info, :terminal_size)
    end

    test "info values are consistent with individual functions" do
      info = Platform.info()

      assert info.platform == Platform.platform()
      assert info.os_version == Platform.os_version()
      assert info.unix == Platform.unix?()
      assert info.windows == Platform.windows?()
      assert info.wsl == Platform.wsl?()
      assert info.terminal_size == Platform.terminal_size()
    end
  end
end

defmodule TermUI.Platform.UnixTest do
  use ExUnit.Case, async: true

  alias TermUI.Platform
  alias TermUI.Platform.Unix

  # Only run these tests on Unix platforms
  @moduletag :unix
  if not Platform.unix?() do
    @moduletag skip: "Unix-only tests"
  end

  describe "info/0" do
    test "returns map with expected keys" do
      info = Unix.info()

      assert is_map(info)
      assert Map.has_key?(info, :platform)
      assert Map.has_key?(info, :kernel_version)
      assert Map.has_key?(info, :terminfo_paths)
      assert Map.has_key?(info, :supports_signals)
      assert Map.has_key?(info, :supports_pty)
    end

    test "supports_signals is true" do
      info = Unix.info()
      assert info.supports_signals == true
    end

    test "supports_pty is true" do
      info = Unix.info()
      assert info.supports_pty == true
    end
  end

  describe "detect_unix_variant/0" do
    test "returns valid Unix variant" do
      variant = Unix.detect_unix_variant()
      assert variant in [:linux, :macos, :freebsd, :unknown]
    end
  end

  describe "kernel_version/0" do
    test "returns version string or nil" do
      version = Unix.kernel_version()

      case version do
        nil -> assert true
        str -> assert is_binary(str)
      end
    end
  end

  describe "terminfo_paths/0" do
    test "returns list of paths" do
      paths = Unix.terminfo_paths()

      assert is_list(paths)
      assert paths != []

      for path <- paths do
        assert is_binary(path)
      end
    end

    test "includes standard paths" do
      paths = Unix.terminfo_paths()

      # At least one standard path should be included
      standard_paths = [
        "/usr/share/terminfo",
        "/usr/lib/terminfo",
        "/lib/terminfo"
      ]

      assert Enum.any?(paths, fn path -> path in standard_paths end)
    end
  end

  describe "capability_hints/0" do
    test "returns map with capability hints" do
      hints = Unix.capability_hints()

      assert is_map(hints)
      assert Map.has_key?(hints, :supports_mouse)
      assert Map.has_key?(hints, :supports_bracketed_paste)
      assert Map.has_key?(hints, :supports_focus_events)
      assert Map.has_key?(hints, :supports_alternate_screen)
    end

    test "all capabilities are true for Unix" do
      hints = Unix.capability_hints()

      assert hints.supports_mouse == true
      assert hints.supports_bracketed_paste == true
      assert hints.supports_focus_events == true
      assert hints.supports_alternate_screen == true
    end
  end

  describe "supported_signals/0" do
    test "returns list of signal atoms" do
      signals = Unix.supported_signals()

      assert is_list(signals)
      assert :sigwinch in signals
      assert :sigterm in signals
      assert :sigint in signals
    end
  end

  describe "signal_available?/1" do
    test "returns true for supported signals" do
      assert Unix.signal_available?(:sigwinch) == true
      assert Unix.signal_available?(:sigterm) == true
      assert Unix.signal_available?(:sigint) == true
    end

    test "returns false for unsupported signals" do
      assert Unix.signal_available?(:unknown_signal) == false
    end
  end
end

defmodule TermUI.Platform.WindowsTest do
  use ExUnit.Case, async: true

  alias TermUI.Platform.Windows

  describe "info/0" do
    test "returns map with expected keys" do
      info = Windows.info()

      assert is_map(info)
      assert Map.has_key?(info, :platform)
      assert Map.has_key?(info, :implementation_status)
      assert info.platform == :windows
      assert info.implementation_status == :stub
    end

    test "indicates stub status" do
      info = Windows.info()
      assert info.notes =~ "NIF"
    end
  end

  describe "vt_support_available?/0" do
    test "returns boolean" do
      result = Windows.vt_support_available?()
      assert is_boolean(result)
    end
  end

  describe "windows_version/0" do
    test "returns version tuple or nil" do
      version = Windows.windows_version()

      case version do
        {major, minor, build} ->
          assert is_integer(major)
          assert is_integer(minor)
          assert is_integer(build)

        nil ->
          assert true
      end
    end
  end

  describe "enable_vt_processing/0" do
    test "returns ok tuple or error" do
      result = Windows.enable_vt_processing()

      case result do
        {:ok, :stub} -> assert true
        {:error, msg} -> assert is_binary(msg)
      end
    end
  end

  describe "disable_vt_processing/0" do
    test "returns :ok" do
      assert Windows.disable_vt_processing() == :ok
    end
  end

  describe "capability_hints/0" do
    test "returns map with capability hints" do
      hints = Windows.capability_hints()

      assert is_map(hints)
      assert Map.has_key?(hints, :supports_mouse)
      assert Map.has_key?(hints, :supports_bracketed_paste)
      assert Map.has_key?(hints, :requires_vt_mode)
    end
  end

  describe "terminal_size/0" do
    test "returns tuple of positive integers" do
      {rows, cols} = Windows.terminal_size()

      assert is_integer(rows) and rows > 0
      assert is_integer(cols) and cols > 0
    end
  end

  describe "minimum_version/0" do
    test "returns Windows 10 version tuple" do
      {major, minor, build} = Windows.minimum_version()

      assert major == 10
      assert minor == 0
      assert build == 10_586
    end
  end

  describe "meets_minimum_version?/0" do
    test "returns boolean" do
      result = Windows.meets_minimum_version?()
      assert is_boolean(result)
    end
  end
end
