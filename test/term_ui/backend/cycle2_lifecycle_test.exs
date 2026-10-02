defmodule TermUI.Backend.Cycle2LifecycleTest do
  use ExUnit.Case, async: false

  alias TermUI.Backend.{Raw, SSH, TTY}
  alias TermUI.{Frame, Runtime, TerminalOutput}

  defmodule App do
    use TermUI.Elm

    def init(opts),
      do: %{owner: Keyword.fetch!(opts, :test_owner), hold: Keyword.get(opts, :hold, false)}

    def event_to_msg(_, _), do: :ignore
    def update(_, state), do: state
    def view(_), do: Frame.from_rows(["ready"], 8, 2)

    def terminate(reason, state) do
      send(state.owner, {:app_terminate, self(), reason})

      if state.hold do
        receive do
          :finish_terminate -> :ok
        after
          2000 -> raise "terminate release missing"
        end
      end
    end
  end

  test "SSH cleanup writer death closes once before or after runtime exit" do
    for hold <- [false, true] do
      owner = self()

      output = fn bytes ->
        send(owner, {:writer, self(), bytes})

        receive do
          :complete -> :ok
        after
          3000 -> {:error, :release_missing}
        end
      end

      {:ok, session} =
        SSH.start_session(App,
          output: output,
          output_timeout: 4000,
          runtime_options: [test_owner: owner, hold: hold, suppress_logger: false]
        )

      runtime = SSH.session_info(session).runtime
      session_ref = Process.monitor(session)
      runtime_ref = Process.monitor(runtime)
      complete_writer()
      complete_writer()
      Runtime.sync(runtime)
      SSH.stop_session(session)
      assert_receive {:writer, cleanup, bytes}, 1000
      assert bytes =~ "\e[?1049l"
      assert_receive {:app_terminate, ^runtime, :normal}, 1000

      if not hold do
        assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, :normal}, 1000
        assert :sys.get_state(session).runtime_stopped?
      end

      Process.exit(cleanup, :kill)

      if hold do
        wait_for_failure(session)
        assert Process.alive?(session)
        refute_receive {:term_ui_ssh_closed, ^session, _}, 20
        send(runtime, :finish_terminate)
        assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, :normal}, 1000
      end

      assert_receive {:term_ui_ssh_closed, ^session, {:output_failed, {:writer_exit, :killed}}},
                     1000

      assert_receive {:DOWN, ^session_ref, :process, ^session, :normal}, 1000
      refute_receive {:term_ui_ssh_closed, ^session, _}, 20
      refute_receive {:writer, _, _}, 20
    end
  end

  test "local cleanup reports all-failed output" do
    case :file.open(~c"/dev/tty", [:write, :raw]) do
      {:ok, fd} ->
        :file.close(fd)
        # The separate PTY probe covers the real TTY fallback on this path.
        :ok

      {:error, _} ->
        leader = Process.group_leader()
        stderr = Process.whereis(:standard_error)
        rejecting = spawn(fn -> reject_io() end)

        results =
          try do
            Process.group_leader(self(), rejecting)
            if stderr, do: Process.unregister(:standard_error)
            Process.register(rejecting, :standard_error)
            helper = TerminalOutput.write_to_tty("cleanup")
            tty = TTY.shutdown(%TTY{}, :normal)

            raw =
              Raw.shutdown(
                %Raw{},
                :normal
              )

            {helper, tty, raw}
          after
            Process.group_leader(self(), leader)

            if Process.whereis(:standard_error) == rejecting,
              do: Process.unregister(:standard_error)

            if stderr, do: Process.register(stderr, :standard_error)
            Process.exit(rejecting, :kill)
          end

        assert {{:error, _}, {:error, {:terminal_write_failed, _}},
                {:error, {:cleanup_failed, failures}}} = results

        assert Keyword.has_key?(failures, :output)
    end
  end

  test "cleanup succeeds when its primary output succeeds" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = TerminalOutput.write_to_tty("cleanup")
        assert :ok = Raw.shutdown(%Raw{}, :normal)
        assert :ok = TTY.shutdown(%TTY{}, :normal)
      end)

    assert output =~ "cleanup"
    assert output =~ "\e[?25h"
  end

  defp reject_io do
    receive do
      {:io_request, from, ref, _} ->
        send(from, {:io_reply, ref, {:error, :closed}})
        reject_io()
    end
  end

  defp wait_for_failure(session, attempts \\ 100)
  defp wait_for_failure(_session, 0), do: flunk("writer failure not handled")

  defp wait_for_failure(session, attempts) do
    if :sys.get_state(session).connected? do
      Process.sleep(5)
      wait_for_failure(session, attempts - 1)
    else
      :ok
    end
  end

  defp complete_writer do
    assert_receive {:writer, worker, _bytes}, 1000
    send(worker, :complete)
  end
end
