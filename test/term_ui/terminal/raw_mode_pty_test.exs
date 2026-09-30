defmodule TermUI.Terminal.RawModePtyTest do
  use ExUnit.Case, async: false

  @moduletag :tty_nif

  if match?({:unix, _name}, :os.type()) do
    @control_bytes <<15, 3, 19, 17>>
    @result "__TERM_UI_RESULT__:0F031311::ok"
    @timeout 10_000

    test "raw mode receives Ctrl+O, Ctrl+C, Ctrl+S, and Ctrl+Q" do
      script = System.find_executable("script")
      elixir = System.find_executable("elixir")

      assert script, "script executable is required for the PTY regression test"
      assert elixir, "elixir executable is required for the PTY regression test"

      port = open_probe(script, elixir)

      try do
        output = receive_until(port, "__TERM_UI_READY__", "", @timeout)
        assert Port.command(port, @control_bytes)
        output = receive_until(port, @result, output, @timeout)
        assert output =~ @result
        assert_receive {^port, {:exit_status, 0}}, @timeout
      after
        if Port.info(port), do: Port.close(port)
      end
    end

    defp open_probe(script, elixir) do
      root = File.cwd!()
      ebin = Mix.Project.compile_path()
      probe = Path.join(root, "test/support/raw_mode_pty_probe.exs")
      arguments = script_arguments(elixir, ebin, probe)

      Port.open(
        {:spawn_executable, script},
        [
          :binary,
          :exit_status,
          :use_stdio,
          :stderr_to_stdout,
          args: arguments,
          env: [{~c"TERM", ~c"xterm-256color"}]
        ]
      )
    end

    defp script_arguments(elixir, ebin, probe) do
      case :os.type() do
        {:unix, :darwin} ->
          ["-q", "/dev/null", elixir, "-pa", ebin, probe]

        {:unix, _name} ->
          command = Enum.map_join([elixir, "-pa", ebin, probe], " ", &shell_quote/1)
          ["-q", "-e", "-c", command, "/dev/null"]
      end
    end

    defp shell_quote(value), do: "'" <> String.replace(value, "'", "'\\''") <> "'"

    defp receive_until(port, marker, output, timeout) do
      started_at = System.monotonic_time(:millisecond)
      receive_until(port, marker, output, timeout, started_at)
    end

    defp receive_until(port, marker, output, timeout, started_at) do
      if String.contains?(output, marker) do
        output
      else
        elapsed = System.monotonic_time(:millisecond) - started_at
        remaining = max(timeout - elapsed, 0)

        receive do
          {^port, {:data, data}} ->
            receive_until(port, marker, output <> data, timeout, started_at)

          {^port, {:exit_status, status}} ->
            flunk("PTY probe exited with status #{status}: #{inspect(output)}")
        after
          remaining ->
            flunk("PTY probe timed out while waiting for #{marker}: #{inspect(output)}")
        end
      end
    end
  end
end
