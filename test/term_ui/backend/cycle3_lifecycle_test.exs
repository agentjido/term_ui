defmodule TermUI.Backend.Cycle3LifecycleTest do
  use ExUnit.Case, async: false

  alias TermUI.Backend.{Manager, SSH}
  alias TermUI.{Command, Frame, Runtime, WebBackend}

  defmodule App do
    use TermUI.Elm

    def init(opts) do
      owner = Keyword.fetch!(opts, :test_owner)
      send(owner, {:init, self(), elem(Process.info(self(), :links), 1)})

      case Keyword.get(opts, :mode, :ok) do
        :raise -> raise "original init error"
        :throw -> throw(:original_init_error)
        :exit -> exit(:original_init_error)
        :invalid -> {%{owner: owner}, [:invalid]}
        :hold -> receive do: (:release_init -> %{owner: owner})
        mode -> {%{owner: owner, mode: mode}, Keyword.get(opts, :commands, [])}
      end
    end

    def event_to_msg(_, _), do: :ignore
    def update(:fail, _), do: raise("original update error")
    def update(_, state), do: state
    def view(%{mode: :view_error}), do: raise("original view error")
    def view(_), do: Frame.new(4, 2)
    def terminate(reason, state), do: send(state.owner, {:terminate, self(), reason})
  end

  defmodule NoTerminate do
    @behaviour TermUI.Elm
    defdelegate init(opts), to: App
    defdelegate event_to_msg(event, state), to: App
    defdelegate update(msg, state), to: App
    defdelegate view(state), to: App
  end

  defmodule CleanupBackend do
    @behaviour TermUI.Backend
    def init(opts),
      do: {:ok, %{owner: Keyword.fetch!(opts, :owner), result: Keyword.fetch!(opts, :result)}}

    def size(_), do: {:ok, {2, 4}}
    def capabilities(_), do: %{colors: :monochrome, unicode: false}
    def draw(state, _), do: {:ok, state}
    def flush(state), do: {:ok, state}
    def resize(state, _), do: {:ok, state}
    def poll_event(state, _), do: {:timeout, state}

    def shutdown(state, reason) do
      send(state.owner, {:cleanup, reason})
      state.result
    end
  end

  @tag capture_log: true
  test "both public remote APIs return every original init failure and release resources" do
    for backend <- [SSH, WebBackend], mode <- [:raise, :throw, :exit, :invalid] do
      started = System.monotonic_time(:millisecond)

      assert {:error, reason} =
               backend.start_session(App,
                 output: self(),
                 owner: self(),
                 runtime_options: [test_owner: self(), mode: mode, suppress_logger: false]
               )

      assert System.monotonic_time(:millisecond) - started < 1000
      assert_receive {:init, runtime, links}

      if mode == :invalid do
        assert reason == {:application, :commands, {:invalid_commands, [:invalid]}}
      else
        assert {:application, :init, {kind, error, [_ | _]}} = reason
        assert kind == %{raise: :error, throw: :throw, exit: :exit}[mode]

        if mode == :raise,
          do: assert(error.message == "original init error"),
          else: assert(error == :original_init_error)
      end

      assert_released([runtime | links])
      refute_receive {:term_ui_ssh_output, _, _, _}, 10
      refute_receive {:term_ui_web_output, _, _}, 10
      refute_receive {:terminate, _, _}, 10
    end
  end

  @tag capture_log: true
  test "runtime death during app init releases the startup manager without parent calls" do
    for backend <- [SSH, WebBackend] do
      owner = self()

      starter =
        spawn(fn ->
          send(
            owner,
            {:start_result,
             backend.start_session(App,
               output: owner,
               runtime_options: [test_owner: owner, mode: :hold, suppress_logger: false]
             )}
          )
        end)

      assert_receive {:init, runtime, links}, 1000

      assert Enum.any?(links, fn pid ->
               :proc_lib.translate_initial_call(pid) == {Manager, :init, 1}
             end)

      Process.exit(runtime, :kill)
      assert_receive {:start_result, {:error, :killed}}, 1000
      assert_released([starter, runtime | links])
      refute_receive {:term_ui_ssh_output, _, _, _}, 10
      refute_receive {:term_ui_web_output, _, _}, 10
    end
  end

  @tag capture_log: true
  test "connection owner death during held init closes the successful startup" do
    for backend <- [SSH, WebBackend] do
      parent = self()
      owner = spawn(fn -> receive do: (:stop -> :ok) end)

      spawn(fn ->
        send(
          parent,
          {:started,
           backend.start_session(App,
             owner: owner,
             output: parent,
             runtime_options: [test_owner: parent, mode: :hold, suppress_logger: false]
           )}
        )
      end)

      assert_receive {:init, runtime, links}, 1000
      Process.exit(owner, :kill)
      send(runtime, :release_init)
      assert_receive {:started, {:ok, session}}, 1000
      assert_released([session, runtime | links])
      flush_output()
    end
  end

  @tag capture_log: true
  test "first view failure keeps established cleanup and original runtime error" do
    {:ok, session} =
      SSH.start_session(App,
        output: self(),
        runtime_options: [test_owner: self(), mode: :view_error, suppress_logger: false]
      )

    assert_receive {:init, runtime, _}, 1000
    assert_receive {:term_ui_ssh_output, ^session, setup, _}, 1000
    refute_receive {:terminate, ^runtime, _}, 20
    SSH.ack_output(session, setup, :ok)
    assert_receive {:term_ui_ssh_output, ^session, cleanup, bytes}, 1000
    assert bytes =~ "\e[?1049l"

    assert_receive {:terminate, ^runtime, {:application, :view, {:error, %RuntimeError{}, _}}},
                   1000

    SSH.ack_output(session, setup, {:error, :stale})
    SSH.ack_output(session, cleanup, :ok)
    assert_released([session, runtime])

    {:ok, session} =
      WebBackend.start_session(App,
        output: self(),
        runtime_options: [test_owner: self(), mode: :view_error, suppress_logger: false]
      )

    assert_receive {:init, runtime, _}, 1000

    assert_receive {:terminate, ^runtime, {:application, :view, {:error, %RuntimeError{}, _}}},
                   1000

    assert_released([session, runtime])
    flush_output()
  end

  test "run reports cleanup results with and without app terminate after one cleanup" do
    for app <- [App, NoTerminate], result <- [:ok, {:error, :cleanup_failed}] do
      expected = if result == :ok, do: :ok, else: {:error, cleanup_error()}

      assert TermUI.run(app,
               test_owner: self(),
               commands: [Command.shutdown()],
               backend: {CleanupBackend, owner: self(), result: result},
               suppress_logger: false
             ) == expected

      assert_receive {:init, runtime, _}
      assert_receive {:cleanup, :normal}

      if app == App do
        reason = if result == :ok, do: :normal, else: cleanup_error()
        assert_receive {:terminate, ^runtime, ^reason}
      else
        refute_receive {:terminate, _, _}, 10
      end

      refute_receive {:cleanup, _}, 10
      refute_receive {:term_ui_run_result, _, _}, 10
    end
  end

  @tag capture_log: true
  test "run keeps prior app failure and explicit shutdown result semantics" do
    assert {:error,
            {:application, :view, {:error, %RuntimeError{message: "original view error"}, _}}} =
             TermUI.run(App,
               test_owner: self(),
               mode: :view_error,
               backend: {CleanupBackend, owner: self(), result: {:error, :cleanup_failed}},
               suppress_logger: false
             )

    assert_receive {:init, runtime, _}
    assert_receive {:cleanup, {:application, :view, _}}
    assert_receive {:terminate, ^runtime, reason}
    assert reason == cleanup_error()

    for reason <- [:normal, :shutdown, {:shutdown, :normal}, :requested, {:shutdown, :requested}],
        result <- [:ok, {:error, :cleanup_failed}] do
      expected =
        if reason in [:normal, :shutdown] do
          if result == :ok, do: :ok, else: {:error, cleanup_error()}
        else
          {:error, {:shutdown, reason}}
        end

      assert TermUI.run(NoTerminate,
               test_owner: self(),
               commands: [Command.shutdown(reason)],
               backend: {CleanupBackend, owner: self(), result: result},
               suppress_logger: false
             ) == expected

      assert_receive {:init, _, _}
      assert_receive {:cleanup, ^reason}
    end
  end

  test "linked runtime normal exit and transient supervision remain unchanged on cleanup error" do
    for reason <- [:normal, :requested] do
      opts = [
        root: App,
        test_owner: self(),
        backend: {CleanupBackend, owner: self(), result: {:error, :cleanup_failed}},
        suppress_logger: false
      ]

      {:ok, supervisor} =
        Supervisor.start_link([Runtime.child_spec(opts)], strategy: :one_for_one)

      assert_receive {:init, runtime, _}
      monitor = Process.monitor(runtime)
      Runtime.sync(runtime)
      GenServer.cast(runtime, {:shutdown, reason})
      down = if reason == :normal, do: :normal, else: {:shutdown, reason}
      assert_receive {:DOWN, ^monitor, :process, ^runtime, ^down}, 1000
      assert_receive {:cleanup, ^reason}
      assert_receive {:terminate, ^runtime, error}
      assert error == cleanup_error()
      assert Supervisor.which_children(supervisor) == [{Runtime, :undefined, :worker, [Runtime]}]
      refute_receive {:init, _, _}, 20
      Supervisor.stop(supervisor)
    end
  end

  @tag capture_log: true
  test "transient supervisor still restarts an abnormal runtime" do
    opts = [
      root: App,
      test_owner: self(),
      backend: {CleanupBackend, owner: self(), result: :ok},
      suppress_logger: false
    ]

    {:ok, supervisor} = Supervisor.start_link([Runtime.child_spec(opts)], strategy: :one_for_one)
    assert_receive {:init, runtime, _}
    Runtime.sync(runtime)
    Runtime.send_message(runtime, :fail)
    assert_receive {:cleanup, {:application, :update, _}}, 1000
    assert_receive {:terminate, ^runtime, {:application, :update, _}}, 1000
    assert_receive {:init, replacement, _}, 1000
    assert replacement != runtime
    Runtime.shutdown(replacement)
    assert_receive {:cleanup, :normal}, 1000
    assert_receive {:terminate, ^replacement, :normal}, 1000
    Supervisor.stop(supervisor)
  end

  defp cleanup_error, do: {:backend, CleanupBackend, :shutdown, :cleanup_failed}

  defp assert_released(pids) do
    for pid <- Enum.uniq(pids) do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
      refute Process.alive?(pid)
    end
  end

  defp flush_output do
    receive do
      {:term_ui_ssh_output, _, _, _} -> flush_output()
      {:term_ui_web_output, _, _} -> flush_output()
    after
      0 -> :ok
    end
  end
end
