defmodule TermUI.Backend.Cycle1LifecycleTest do
  use ExUnit.Case, async: false

  alias TermUI.Backend.{Manager, Raw, SSH, TTY}
  alias TermUI.{Command, Event, Frame, Runtime}

  defmodule App do
    use TermUI.Elm

    def init(opts),
      do: %{owner: Keyword.fetch!(opts, :test_owner), mode: Keyword.get(opts, :mode, :ignore)}

    def event_to_msg(%Event.Resize{}, %{mode: :ignore}), do: :ignore
    def event_to_msg(%Event.Resize{}, _state), do: {:msg, :resize}
    def event_to_msg(_, _), do: :ignore
    def update(:resize, %{mode: :stop} = state), do: {state, [Command.shutdown()]}
    def update(_, state), do: state
    def view(_), do: Frame.from_rows(["VISIBLE"], 8, 3)
    def terminate(reason, state), do: send(state.owner, {:app_terminated, self(), reason})
  end

  defmodule HeldBackend do
    @behaviour TermUI.Backend
    def init(opts), do: {:ok, %{owner: Keyword.fetch!(opts, :owner)}}
    def size(_), do: {:ok, {3, 8}}
    def capabilities(_), do: %{}
    def draw(state, _), do: {:ok, state}
    def flush(state), do: {:ok, state}
    def resize(state, _), do: {:ok, state}

    def poll_event(state, timeout) do
      receive do
      after
        timeout -> {:timeout, state}
      end
    end

    def shutdown(state, _) do
      send(state.owner, {:cleanup_entered, self()})

      receive do
        :release_cleanup -> :ok
      after
        10_000 -> raise "cleanup release missing"
      end

      send(state.owner, {:cleanup_completed, self()})
      :ok
    end
  end

  defmodule OutputBackend do
    @behaviour TermUI.Backend
    def init(opts) do
      backend = Keyword.fetch!(opts, :implementation)
      {:ok, state} = backend.init(opts)

      {:ok,
       %{backend: backend, state: state, fail_resize: Keyword.get(opts, :fail_resize, false)}}
    end

    def size(s), do: s.backend.size(s.state)
    def capabilities(s), do: s.backend.capabilities(s.state)
    def draw(s, f), do: invoke(s, :draw, [f])
    def flush(s), do: invoke(s, :flush, [])
    def resize(%{fail_resize: true}, _size), do: {:error, :resize_failed}
    def resize(s, size), do: invoke(s, :resize, [size])
    def shutdown(s, reason), do: s.backend.shutdown(s.state, reason)

    def poll_event(s, timeout) do
      receive do
      after
        timeout -> {:timeout, s}
      end
    end

    defp invoke(s, function, args) do
      case apply(s.backend, function, [s.state | args]) do
        {:ok, next} -> {:ok, %{s | state: next}}
        error -> error
      end
    end
  end

  setup do
    old = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, old) end)
    :ok
  end

  test "a finite cleanup beyond five seconds finishes before application termination" do
    {:ok, runtime} =
      TermUI.start_link(App,
        test_owner: self(),
        backend: {HeldBackend, owner: self()},
        backend_opts: [size_poll_interval: :disabled],
        suppress_logger: false
      )

    Runtime.sync(runtime)
    reference = Process.monitor(runtime)
    Runtime.shutdown(runtime)
    assert_receive {:cleanup_entered, manager}, 1000
    refute_receive {:app_terminated, ^runtime, _}, 5100
    assert Process.alive?(manager)
    send(manager, :release_cleanup)
    assert_receive {:cleanup_completed, ^manager}, 1000
    assert_receive {:app_terminated, ^runtime, :normal}, 1000
    assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}, 1000
    refute_receive {:cleanup_entered, _}, 20
  end

  test "close reports manager death as failure rather than successful cleanup" do
    {:ok, manager} =
      Manager.start_link(self(), {HeldBackend, owner: self()}, size_poll_interval: :disabled)

    reference = Process.monitor(manager)
    parent = self()
    spawn(fn -> send(parent, {:close_result, Manager.close(manager, :normal)}) end)
    assert_receive {:cleanup_entered, ^manager}
    Process.exit(manager, :kill)
    assert_receive {:DOWN, ^reference, :process, ^manager, :killed}
    assert_receive {:close_result, {:error, {:backend_manager_exit, _}}}, 1000
  end

  test "SSH queued setup and frame cleanup dispatch precedes terminate while acknowledgement can follow" do
    for held <- [:setup, :frame] do
      {session, runtime} = start_ssh(output_timeout: 10_000)
      {setup_token, _} = output(session)

      token =
        if held == :setup do
          setup_token
        else
          SSH.ack_output(session, setup_token, :ok)
          {frame_token, _} = output(session)
          frame_token
        end

      Runtime.send_message(runtime, :refresh)
      Runtime.sync(runtime)
      reference = Process.monitor(runtime)
      SSH.stop_session(session)
      refute_receive {:app_terminated, ^runtime, _}, 30
      state = wait_for_shutdown(session)
      assert state.in_flight.kind == held
      assert is_binary(state.cleanup)
      refute state.cleanup_sent?
      assert state.shutdown_waiter != nil
      SSH.ack_output(session, token, :ok)
      {frame_token, frame} = output(session)
      refute frame =~ "\e[?1049l"
      assert :sys.get_state(session).in_flight.kind == :frame
      refute_receive {:app_terminated, ^runtime, _}, 30
      SSH.ack_output(session, frame_token, :ok)
      {cleanup_token, cleanup} = output(session)
      assert cleanup =~ "\e[?1049l"
      assert_receive {:app_terminated, ^runtime, :normal}, 1000
      assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}, 1000
      state = :sys.get_state(session)
      assert state.cleanup_sent?
      assert state.in_flight.kind == :cleanup
      assert state.shutdown_waiter == nil
      SSH.ack_output(session, cleanup_token, :ok)
      assert_receive {:term_ui_ssh_closed, ^session, :normal}, 1000
      refute_receive {:term_ui_ssh_output, ^session, _, ^cleanup}, 20
    end
  end

  test "SSH timeout writer error disconnect and owner death release a queued shutdown caller" do
    for failure <- [:timeout, :writer_error, :disconnect, :owner_death] do
      owner =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      {session, runtime} = start_ssh(owner: owner, output_timeout: 1000)
      {token, _} = output(session)
      Runtime.sync(runtime)
      reference = Process.monitor(runtime)
      session_reference = Process.monitor(session)
      SSH.stop_session(session)
      refute_receive {:app_terminated, ^runtime, _}, 20
      assert wait_for_shutdown(session).shutdown_waiter != nil

      case failure do
        :timeout -> :ok
        :writer_error -> SSH.ack_output(session, token, {:error, :writer_failed})
        :disconnect -> SSH.disconnect(session, :gone)
        :owner_death -> Process.exit(owner, :kill)
      end

      assert_receive {:app_terminated, ^runtime, {:backend, SSH, :shutdown, _}}, 2000
      assert_receive {:DOWN, ^reference, :process, ^runtime, _}, 1000
      assert_receive {:DOWN, ^session_reference, :process, ^session, :normal}, 1000
      refute_receive {:term_ui_ssh_output, ^session, _, _}, 20
      send(owner, :stop)
    end
  end

  test "Raw and TTY redraw ignored and mapped resize output and stop once on resize" do
    for backend <- [Raw, TTY], detected <- [false, true], mode <- [:ignore, :map, :stop] do
      {:ok, device} = StringIO.open("")
      old = Process.group_leader()
      Process.group_leader(self(), device)

      try do
        {:ok, runtime} =
          TermUI.start_link(App,
            test_owner: self(),
            mode: mode,
            backend:
              {OutputBackend,
               implementation: backend,
               size: {3, 8},
               line_mode: :incremental,
               alternate_screen: false,
               bracketed_paste: false,
               focus_events: false},
            backend_opts: [size_poll_interval: :disabled],
            suppress_logger: false
          )

        reference = Process.monitor(runtime)
        Runtime.sync(runtime)
        {_, before} = StringIO.contents(device)
        assert before =~ "VISIBLE"

        send(
          runtime,
          if(detected, do: {:backend_size, {4, 10}}, else: {:backend_event, Event.resize(10, 4)})
        )

        if mode == :stop do
          assert_receive {:app_terminated, ^runtime, :normal}, 1000
          assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}, 1000
        else
          Runtime.sync(runtime)
          state = Runtime.get_state(runtime)
          assert state.frames_rendered == 2
          refute state.dirty
          assert state.render_timer == nil
          Runtime.shutdown(runtime)
          assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}, 1000
        end

        {_, after_output} = StringIO.contents(device)
        delta = String.replace_prefix(after_output, before, "")
        assert delta =~ "\e[2J"
        assert delta =~ "VISIBLE"
        assert length(Regex.scan(~r/VISIBLE/, delta)) == 1
      after
        Process.group_leader(self(), old)
        StringIO.close(device)
      end
    end
  end

  test "resize failure stops without an extra frame" do
    {:ok, runtime} =
      TermUI.start_link(App,
        test_owner: self(),
        backend: {OutputBackend, implementation: TTY, fail_resize: true, size: {3, 8}},
        backend_opts: [size_poll_interval: :disabled],
        suppress_logger: false
      )

    Runtime.sync(runtime)
    reference = Process.monitor(runtime)
    send(runtime, {:backend_event, Event.resize(10, 4)})

    assert_receive {:app_terminated, ^runtime,
                    {:backend, OutputBackend, :resize, :resize_failed}},
                   1000

    assert_receive {:DOWN, ^reference, :process, ^runtime, _}, 1000
  end

  defp start_ssh(opts) do
    {:ok, session} =
      SSH.start_session(
        App,
        Keyword.merge(
          [
            output: self(),
            owner: self(),
            runtime_options: [test_owner: self(), suppress_logger: false]
          ],
          opts
        )
      )

    on_exit(fn -> if Process.alive?(session), do: SSH.disconnect(session, :test_end) end)
    {session, SSH.session_info(session).runtime}
  end

  defp wait_for_shutdown(session, attempts \\ 100) do
    state = :sys.get_state(session)

    cond do
      state.shutdown_waiter != nil ->
        state

      attempts == 0 ->
        flunk("backend shutdown was not queued")

      true ->
        Process.sleep(10)
        wait_for_shutdown(session, attempts - 1)
    end
  end

  defp output(session) do
    assert_receive {:term_ui_ssh_output, ^session, token, data}, 1000
    {token, data}
  end
end
