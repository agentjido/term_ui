defmodule TermUI.TerminalOutputTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias TermUI.TerminalOutput

  setup do
    original_suppression = Application.get_env(:term_ui, :suppress_terminal_output)
    original_wsl_distro = System.get_env("WSL_DISTRO_NAME")
    original_wsl_interop = System.get_env("WSL_INTEROP")

    TerminalOutput.disable_onlcr()

    on_exit(fn ->
      restore_application_env(:suppress_terminal_output, original_suppression)
      restore_system_env("WSL_DISTRO_NAME", original_wsl_distro)
      restore_system_env("WSL_INTEROP", original_wsl_interop)
      TerminalOutput.disable_onlcr()
      TerminalOutput.disallow_current_process()
    end)

    :ok
  end

  test "writes iodata and translates newlines only while ONLCR is active" do
    Application.put_env(:term_ui, :suppress_terminal_output, false)

    assert capture_io(fn -> assert :ok = TerminalOutput.write(["one", "\n", "two"]) end) ==
             "one\ntwo"

    assert :ok = TerminalOutput.enable_onlcr()
    assert TerminalOutput.onlcr?()

    assert capture_io(fn -> assert :ok = TerminalOutput.write(["one", "\n", "two\r\n"]) end) ==
             "one\r\ntwo\r\n"

    assert :ok = TerminalOutput.disable_onlcr()
    refute TerminalOutput.onlcr?()
  end

  test "translates binary and character input without changing other content" do
    Application.put_env(:term_ui, :suppress_terminal_output, false)
    assert :ok = TerminalOutput.enable_onlcr()

    assert capture_io(fn ->
             assert :ok = TerminalOutput.write("plain")
             assert :ok = TerminalOutput.write(?x)
             assert :ok = TerminalOutput.write(?\n)
           end) == "plain120\r\n"
  end

  test "suppression blocks the standard terminal owner unless it opts in" do
    Application.put_env(:term_ui, :suppress_terminal_output, true)
    owner = self()
    standard_io = Process.whereis(:standard_io) || Process.whereis(:user)

    process =
      spawn(fn ->
        receive do
          :check ->
            send(
              owner,
              {:suppressed, TerminalOutput.enabled?(), TerminalOutput.write_to_tty("x")}
            )

            TerminalOutput.allow_current_process()
            send(owner, {:allowed, TerminalOutput.enabled?()})
        end
      end)

    assert Process.group_leader(process, standard_io)
    send(process, :check)

    assert_receive {:suppressed, false, :ok}
    assert_receive {:allowed, true}
  end

  test "builds cleanup output only for modes that were enabled" do
    minimal = TerminalOutput.cleanup_sequence() |> IO.iodata_to_binary()
    refute minimal =~ "\e[?1000l"
    refute minimal =~ "\e[?2004l"
    refute minimal =~ "\e[?1004l"
    refute minimal =~ "\e[?1049l"
    assert minimal == "\e[?25h\e[0m"

    complete =
      TerminalOutput.cleanup_sequence(
        mouse: true,
        bracketed_paste: true,
        focus_events: true,
        alternate_screen: true
      )
      |> IO.iodata_to_binary()

    for sequence <- ["\e[?1006l", "\e[?1000l", "\e[?2004l", "\e[?1004l", "\e[?1049l"] do
      assert complete =~ sequence
    end
  end

  test "detects and resets the cached hard-reset environment" do
    System.delete_env("WSL_DISTRO_NAME")
    System.delete_env("WSL_INTEROP")
    TerminalOutput.disable_onlcr()
    refute TerminalOutput.needs_hard_reset?()

    System.put_env("WSL_INTEROP", "/run/WSL/1_interop")
    refute TerminalOutput.needs_hard_reset?()

    TerminalOutput.disable_onlcr()
    assert TerminalOutput.needs_hard_reset?()
  end

  test "allows and removes an explicit per-process output override" do
    assert TerminalOutput.allow_current_process()
    assert TerminalOutput.disallow_current_process()
  end

  defp restore_application_env(key, nil), do: Application.delete_env(:term_ui, key)
  defp restore_application_env(key, value), do: Application.put_env(:term_ui, key, value)
  defp restore_system_env(key, nil), do: System.delete_env(key)
  defp restore_system_env(key, value), do: System.put_env(key, value)
end
