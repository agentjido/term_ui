defmodule TermUI.TermUtilsTest do
  use ExUnit.Case, async: true

  alias TermUI.TermUtils

  # Note: These tests use actual command execution, which may not work in all CI environments.
  # In CI, we may need to skip tests that require external commands.

  describe "safe_stty/2" do
    @tag :external
    test "accepts valid stty flags" do
      # These should pass argument validation even if command fails
      result = TermUtils.safe_stty(["-g"])

      # Either succeeds (has TTY) or fails with :stty_failed (no TTY)
      # But should NOT fail with :invalid_arguments
      refute match?({:error, :invalid_arguments}, result)
    end

    @tag :external
    test "returns error for invalid arguments" do
      # These should be rejected by argument validation
      assert {:error, :invalid_arguments} = TermUtils.safe_stty(["$(malicious)"])
      assert {:error, :invalid_arguments} = TermUtils.safe_stty(["; rm -rf /"])
      assert {:error, :invalid_arguments} = TermUtils.safe_stty(["|", "cat"])
    end

    @tag :external
    test "enforces timeout" do
      # If stty exists, it should respond quickly
      # This test just verifies the timeout mechanism is in place
      result = TermUtils.safe_stty(["-g"], timeout: 5000)

      # Should not hang - either succeeds or fails (but not timeout)
      refute match?({:error, :timeout}, result)
    end
  end

  describe "safe_test/2" do
    @tag :external
    test "accepts valid test flags" do
      # -t 0 checks if stdin is a TTY (valid format)
      result = TermUtils.safe_test(["-t", "0"])

      # Should pass validation even if no TTY (exit code 1)
      refute match?({:error, :invalid_arguments}, result)
    end

    @tag :external
    test "rejects invalid test arguments" do
      assert {:error, :invalid_arguments} = TermUtils.safe_test(["-t", "1000"])
      assert {:error, :invalid_arguments} = TermUtils.safe_test(["$(malicious)"])
      assert {:error, :invalid_arguments} = TermUtils.safe_test([";", "rm"])
    end

    @tag :external
    test "accepts file existence tests" do
      # These should be valid arguments
      assert {:ok, _} = TermUtils.safe_test(["-n", "test"])
      assert {:ok, _} = TermUtils.safe_test(["-z", ""])
    end
  end

  describe "safe_command/3" do
    test "blocks non-whitelisted commands" do
      assert {:error, :command_not_allowed} = TermUtils.safe_command("rm", ["-rf", "/"])
      assert {:error, :command_not_allowed} = TermUtils.safe_command("cat", ["/etc/passwd"])
    end

    test "stops the command task after a timeout" do
      owner = self()

      validate = fn _output ->
        send(owner, {:validator, self()})
        Process.sleep(:infinity)
      end

      # The deadline also includes starting an external command on CI workers.
      assert {:error, :timeout} =
               TermUtils.safe_test(["-n", "term_ui"], timeout: 5_000, validate: validate)

      assert_receive {:validator, validator}, 1_000
      refute Process.alive?(validator)
    end
  end

  describe "validate_stty_settings/1" do
    test "accepts valid stty -g output format" do
      # Valid stty -g output examples
      assert :ok = TermUtils.validate_stty_settings("speed 9600 baud; rows 24; columns 80;")
      assert :ok = TermUtils.validate_stty_settings("speed 115200 baud; rows 40; columns 120;")
      assert :ok = TermUtils.validate_stty_settings("9600:5:cbf3a3b:bf:8a3b:3d")
    end

    test "rejects invalid stty settings" do
      # Contains shell metacharacters
      assert {:error, _} = TermUtils.validate_stty_settings("$(rm -rf /)")
      assert {:error, _} = TermUtils.validate_stty_settings("settings; rm -rf /")
      assert {:error, _} = TermUtils.validate_stty_settings("settings | cat /etc/passwd")

      # Contains null byte
      assert {:error, _} = TermUtils.validate_stty_settings("settings\x00")

      # Too long
      long_settings = String.duplicate("a", 300)
      assert {:error, _} = TermUtils.validate_stty_settings(long_settings)
    end
  end

  describe "validate_stty_size/1" do
    test "accepts valid stty size output" do
      assert :ok = TermUtils.validate_stty_size("24 80")
      assert :ok = TermUtils.validate_stty_size("40 120")
      assert :ok = TermUtils.validate_stty_size("100 200")
    end

    test "rejects invalid size formats" do
      assert {:error, _} = TermUtils.validate_stty_size("abc")
      assert {:error, _} = TermUtils.validate_stty_size("24")
      assert {:error, _} = TermUtils.validate_stty_size("24 80 40")
      assert {:error, _} = TermUtils.validate_stty_size("24 abc")
      assert {:error, _} = TermUtils.validate_stty_size("-1 80")
      assert {:error, _} = TermUtils.validate_stty_size("24 100000")
    end
  end

  describe "command validation and output validation" do
    test "rejects empty terminal command arguments" do
      assert {:error, :invalid_arguments} = TermUtils.safe_stty([])
      assert {:error, :invalid_arguments} = TermUtils.safe_test([])
    end

    test "accepts bounded file descriptors and single test flags" do
      refute match?({:error, :invalid_arguments}, TermUtils.safe_test(["-t", "255"]))
      assert {:ok, _output} = TermUtils.safe_test(["-n"])
    end

    test "custom validators can reject output or fail safely" do
      assert {:error, :output_validation_failed} =
               TermUtils.safe_test(["-n", "term_ui"], validate: fn _ -> {:error, :bad} end)

      assert {:error, :execution_failed} =
               TermUtils.safe_test(["-n", "term_ui"], validate: fn _ -> raise "bad validator" end)
    end

    test "infocmp validates safe flags and rejects unsafe terminal names" do
      result = TermUtils.safe_infocmp(["-1", "xterm"])
      refute match?({:error, :invalid_arguments}, result)

      assert {:error, :invalid_arguments} = TermUtils.safe_infocmp(["xterm;rm"])
      assert {:error, :invalid_arguments} = TermUtils.safe_infocmp([String.duplicate("x", 64)])
    end
  end

  describe "security - command injection prevention" do
    test "stty argument validation blocks shell metacharacters" do
      # All of these should be rejected
      bad_inputs = [
        ["$(whoami)"],
        ["`whoami`"],
        [";rm", "-rf", "/"],
        ["|cat"],
        ["&&echo"],
        ["||echo"],
        [">/tmp/pwn"],
        ["</etc/passwd"]
      ]

      for bad_args <- bad_inputs do
        assert {:error, :invalid_arguments} = TermUtils.safe_stty(bad_args)
      end
    end

    test "test argument validation blocks dangerous inputs" do
      bad_inputs = [
        # FD too large
        ["-t", "1000"],
        ["-t", "$(whoami)"],
        [";rm"],
        ["$(echo", "pwn)"]
      ]

      for bad_args <- bad_inputs do
        assert {:error, :invalid_arguments} = TermUtils.safe_test(bad_args)
      end
    end
  end

  describe "integration - command execution" do
    @tag :external
    @tag :requires_terminal
    test "safe_stty can save and restore settings" do
      # Save current settings
      case TermUtils.safe_stty(["-g"]) do
        {:ok, settings} ->
          # Settings should be validatable
          assert :ok = TermUtils.validate_stty_settings(settings)

          # Should be able to restore (don't actually restore to avoid affecting test environment)
          # Just verify the command format is accepted
          assert {:ok, _} = TermUtils.safe_stty([settings])

        {:error, reason} when reason in [:command_not_found, :not_tty] ->
          assert reason in [:command_not_found, :not_tty]

        {:error, {:exit_code, code}} ->
          assert is_integer(code)

        {:error, reason} ->
          flunk("Unexpected error: #{inspect(reason)}")
      end
    end
  end

  test "saved Linux and BSD settings and bounded numbers pass argument validation" do
    for args <- [
          ["9600:5:cbf3a3b:bf:8a3b:3d"],
          ["gfmt1:cflag=4b00:iflag=6b02:lflag=200005cb"],
          ["min", "10"],
          ["time", "255"]
        ] do
      refute TermUtils.safe_stty(args) == {:error, :invalid_arguments}
    end

    for args <- [
          ["min", "65536"],
          ["time", "-1"],
          ["x"],
          ["10x"],
          ["gfmt1:cflag=zz"],
          ["9600:5;echo"]
        ] do
      assert TermUtils.safe_stty(args) == {:error, :invalid_arguments}
    end
  end
end
