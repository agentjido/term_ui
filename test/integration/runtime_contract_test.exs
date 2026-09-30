defmodule TermUI.RuntimeContractTest do
  use ExUnit.Case, async: false

  alias TermUI.{Clipboard, Command, Event, Frame, Runtime}
  alias TermUI.Test.DeterministicBackend

  setup do
    previous = Process.flag(:trap_exit, true)
    on_exit(fn -> Process.flag(:trap_exit, previous) end)
    :ok
  end

  defmodule Counter do
    use TermUI.Elm

    def init(opts), do: %{count: 0, owner: Keyword.fetch!(opts, :owner)}

    def event_to_msg(%Event.Key{key: :up}, _state), do: {:msg, :increment}
    def event_to_msg(%Event.Text{text: "q"}, _state), do: {:msg, :quit}
    def event_to_msg(_event, _state), do: :ignore

    def update(:increment, state), do: {%{state | count: state.count + 1}, []}
    def update(:quit, state), do: {%{state | count: state.count + 1}, [Command.shutdown()]}
    def update({:set, count}, state), do: {%{state | count: count}, []}

    def view(state), do: Frame.from_rows(["count=#{state.count}"], 20, 2, cursor: {1, 2})

    def terminate(reason, state) do
      send(state.owner, {:app_terminated, reason, state.count})
      :ok
    end
  end

  defmodule CrashingApp do
    use TermUI.Elm

    def init(opts), do: %{owner: Keyword.fetch!(opts, :owner)}
    def event_to_msg(_event, _state), do: {:msg, :crash}
    def update(:crash, _state), do: raise("application failed")
    def view(_state), do: Frame.from_rows(["ready"], 20, 2)
  end

  defmodule InitCrashingApp do
    use TermUI.Elm

    def init(_opts), do: raise("init failed")
    def event_to_msg(_event, _state), do: :ignore
    def update(_message, state), do: state
    def view(_state), do: Frame.from_rows(["unused"], 10, 1)
  end

  defmodule InfoApp do
    use TermUI.Elm

    def init(opts), do: %{owner: Keyword.fetch!(opts, :owner), info: nil}
    def event_to_msg(_event, _state), do: :ignore
    def update(_message, state), do: state

    def handle_info(message, state) do
      {%{state | info: message}, [Command.send(state.owner, {:application_info, message})]}
    end

    def view(state), do: Frame.from_rows([inspect(state.info)], 40, 2)
  end

  defmodule AsyncApp do
    use TermUI.Elm

    def init(opts) do
      state = %{owner: Keyword.fetch!(opts, :owner)}
      command = Command.async(Keyword.fetch!(opts, :async_function), &{:async_complete, &1})
      {state, [command]}
    end

    def event_to_msg(_event, _state), do: :ignore

    def update({:async_complete, result}, state) do
      {state, [Command.send(state.owner, {:async_complete, result})]}
    end

    def view(_state), do: Frame.from_rows(["async"], 20, 2)
  end

  defmodule EffectsApp do
    use TermUI.Elm

    def init(opts) do
      owner = Keyword.fetch!(opts, :owner)

      commands = [
        Command.send(owner, :direct_send),
        Command.message(:message),
        Command.timer(0, :timer),
        Clipboard.copy("copy", on_result: &{:clipboard, &1})
      ]

      {%{owner: owner}, commands}
    end

    def event_to_msg(_event, _state), do: :ignore

    def update(message, state) do
      {state, [Command.send(state.owner, {:effect, message})]}
    end

    def view(_state), do: Frame.from_rows(["effects"], 20, 2)
  end

  defmodule InvalidViewApp do
    use TermUI.Elm

    def event_to_msg(_event, _state), do: :ignore
    def update(_message, state), do: state
    def view(_state), do: :not_a_frame
  end

  defmodule InvalidEventApp do
    use TermUI.Elm

    def event_to_msg(_event, _state), do: :not_a_message
    def update(_message, state), do: state
    def view(_state), do: Frame.from_rows(["ready"], 20, 2)
  end

  defmodule InvalidCommandApp do
    use TermUI.Elm

    def init(_opts), do: {%{}, [:not_a_command]}
    def event_to_msg(_event, _state), do: :ignore
    def update(_message, state), do: state
    def view(_state), do: Frame.from_rows(["unused"], 20, 2)
  end

  defmodule InvalidCommandValueApp do
    use TermUI.Elm

    def init(_opts), do: {%{}, [%Command{kind: :send, value: :invalid}]}
    def event_to_msg(_event, _state), do: :ignore
    def update(_message, state), do: state
    def view(_state), do: Frame.from_rows(["unused"], 20, 2)
  end

  defmodule MapperCrashApp do
    use TermUI.Elm

    def init(_opts) do
      command = Clipboard.copy("copy", on_result: fn _result -> raise "mapper failed" end)
      {%{}, [command]}
    end

    def event_to_msg(_event, _state), do: :ignore
    def update(_message, state), do: state
    def view(_state), do: Frame.from_rows(["mapper"], 20, 2)
  end

  defmodule BlockingAsyncApp do
    use TermUI.Elm

    def init(opts) do
      owner = Keyword.fetch!(opts, :owner)

      command =
        Command.async(fn ->
          send(owner, {:async_worker, self()})

          await_finish(owner)
        end)

      {%{}, [command]}
    end

    def event_to_msg(_event, _state), do: :ignore
    def update(_message, state), do: state
    def view(_state), do: Frame.from_rows(["async"], 20, 2)

    defp await_finish(owner) do
      receive do
        {:monitor_ready, reference} ->
          send(owner, {:async_monitor_ready, self(), reference})
          await_finish(owner)

        :finish ->
          :finished
      end
    end
  end

  defmodule BlockingTerminateApp do
    use TermUI.Elm

    def init(opts), do: %{owner: Keyword.fetch!(opts, :owner)}
    def event_to_msg(_event, _state), do: :ignore
    def update(_message, state), do: state
    def view(_state), do: Frame.from_rows(["terminate"], 20, 2)

    def terminate(_reason, state) do
      send(state.owner, {:terminate_started, self()})

      receive do
        :release_terminate -> :ok
      end
    end
  end

  defmodule ResizableApp do
    use TermUI.Elm

    def init(opts), do: %{dimensions: Keyword.fetch!(opts, :dimensions)}

    def event_to_msg(%Event.Resize{width: width, height: height}, _state),
      do: {:msg, {:resize, width, height}}

    def event_to_msg(%Event.Text{text: "q"}, _state), do: {:msg, :quit}
    def event_to_msg(_event, _state), do: :ignore
    def update({:resize, width, height}, state), do: %{state | dimensions: {width, height}}
    def update(:quit, state), do: {state, [Command.shutdown()]}

    def view(%{dimensions: {width, height}}),
      do: Frame.from_rows(["#{width}x#{height}"], width, height)
  end

  defmodule LifecycleApp do
    @behaviour TermUI.Elm

    def init(opts) do
      mode = Keyword.get(opts, :mode, :ok)
      owner = Keyword.get(opts, :owner)

      case mode do
        :init_throw -> throw(:init_failed)
        :init_exit -> exit(:init_failed)
        {:init_shutdown, reason} -> {%{mode: mode, owner: owner}, [Command.shutdown(reason)]}
        {:init_command, command} -> {%{mode: mode, owner: owner}, [command]}
        _ -> %{mode: mode, owner: owner}
      end
    end

    def event_to_msg(_event, %{mode: :event_ignore}), do: :ignore
    def event_to_msg(_event, %{mode: :event_raise}), do: raise("event failed")
    def event_to_msg(_event, %{mode: :event_throw}), do: throw(:event_failed)
    def event_to_msg(_event, _state), do: {:msg, :event}

    def update(_message, %{mode: :update_throw}), do: throw(:update_failed)
    def update(_message, %{mode: :update_exit}), do: exit(:update_failed)
    def update(:shutdown, state), do: {state, [Command.shutdown(state.mode)]}
    def update(_message, state), do: state

    def handle_info(_message, %{mode: :info_raise}), do: raise("info failed")
    def handle_info(_message, %{mode: :info_throw}), do: throw(:info_failed)
    def handle_info(_message, %{mode: :info_exit}), do: exit(:info_failed)
    def handle_info(_message, state), do: state

    def view(%{mode: :view_raise}), do: raise("view failed")
    def view(%{mode: :view_throw}), do: throw(:view_failed)
    def view(%{mode: :view_exit}), do: exit(:view_failed)
    def view(_state), do: Frame.from_rows(["lifecycle"], 20, 2)

    def terminate(reason, %{owner: owner, mode: mode}) do
      if owner, do: send(owner, {:lifecycle_terminated, reason})

      case mode do
        :terminate_raise -> raise "terminate failed"
        :terminate_throw -> throw(:terminate_failed)
        _ -> :ok
      end
    end
  end

  defmodule BareApp do
    @behaviour TermUI.Elm

    def event_to_msg(_event, _state), do: :ignore
    def update(_message, state), do: state
    def view(_state), do: Frame.from_rows(["bare"], 20, 2)
  end

  test "an injected backend receives normalized input and the final meaningful frame" do
    events = [Event.key(:up), Event.text("q")]

    assert {:ok, runtime} =
             Runtime.start_link(
               root: Counter,
               owner: self(),
               backend: {DeterministicBackend, owner: self(), events: events},
               render_interval: 50
             )

    runtime_ref = Process.monitor(runtime)

    assert_receive {:backend, :draw, first}, 500
    assert Frame.row_text(first, 1) == "count=0             "

    assert_receive {:backend, :draw, final}, 500
    assert Frame.row_text(final, 1) == "count=2             "
    assert final.cursor == {1, 2}
    assert_receive {:backend, :shutdown, :normal}, 500
    assert_receive {:backend, :shutdown_state, 0, 2}, 500
    assert_receive {:app_terminated, :normal, 2}, 500
    assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, :normal}, 500
  end

  test "many updates coalesce into bounded output and external shutdown draws the newest state" do
    {:ok, runtime} = start_counter(render_interval: 100)
    assert_receive {:backend, :draw, _initial}, 500

    Enum.each(1..200, &Runtime.send_message(runtime, {:set, &1}))
    Runtime.shutdown(runtime)

    assert_receive {:backend, :draw, final}, 500
    assert Frame.row_text(final, 1) == "count=200           "
    assert_receive {:backend, :shutdown, :normal}, 500
    refute_receive {:backend, :draw, _extra}, 150
  end

  test "draw and flush failures are useful and still clean the backend" do
    for {stage, reason} <- [draw: :draw_failed, flush: :flush_failed] do
      assert {:error, {:backend, DeterministicBackend, ^stage, ^reason}} =
               Runtime.run(
                 root: Counter,
                 owner: self(),
                 backend: {DeterministicBackend, owner: self(), fail: stage}
               )

      assert_receive {:backend, :shutdown, {:backend, DeterministicBackend, ^stage, ^reason}}, 500
    end
  end

  test "size, capability, and application init failures clean an opened backend" do
    assert {:error, {:backend, DeterministicBackend, :size, :size_failed} = size_reason} =
             Runtime.run(
               root: Counter,
               owner: self(),
               backend: {DeterministicBackend, owner: self(), fail: :size}
             )

    assert_receive {:backend, :shutdown, ^size_reason}, 500

    assert {:error,
            {:backend, DeterministicBackend, :capabilities,
             %RuntimeError{message: "capabilities failed"}} = capabilities_reason} =
             Runtime.run(
               root: Counter,
               owner: self(),
               backend: {DeterministicBackend, owner: self(), fail: :capabilities}
             )

    assert_receive {:backend, :shutdown, ^capabilities_reason}, 500

    assert {:error,
            {:application, :init, {:error, %RuntimeError{message: "init failed"}, _stacktrace}} =
              init_reason} =
             Runtime.run(
               root: InitCrashingApp,
               owner: self(),
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :shutdown, ^init_reason}, 500
  end

  test "an application failure still cleans the backend" do
    assert {:ok, runtime} =
             Runtime.start_link(
               root: CrashingApp,
               owner: self(),
               backend: {DeterministicBackend, owner: self(), events: [Event.key(:enter)]}
             )

    ref = Process.monitor(runtime)
    assert_receive {:backend, :draw, _frame}, 500

    assert_receive {:DOWN, ^ref, :process, ^runtime, {:application, :update, _failure}}, 500
    assert_receive {:backend, :shutdown, {:application, :update, _failure}}, 500
  end

  test "unknown monitor messages reach the application" do
    assert {:ok, runtime} =
             Runtime.start_link(
               root: InfoApp,
               owner: self(),
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :draw, _frame}, 500
    down = {:DOWN, make_ref(), :process, self(), :test_reason}
    send(runtime, down)
    assert_receive {:application_info, ^down}, 500
    Runtime.shutdown(runtime)
  end

  test "resize updates the backend and the final frame dimensions" do
    events = [Event.resize(7, 3), Event.text("q")]

    assert {:ok, _runtime} =
             Runtime.start_link(
               root: ResizableApp,
               backend: {DeterministicBackend, owner: self(), events: events}
             )

    assert_receive {:backend, :draw, %Frame{width: 20, height: 6}}, 500
    assert_receive {:backend, :draw, %Frame{width: 7, height: 3} = final}, 500
    assert Frame.row_text(final, 1) == "7x3    "
    assert_receive {:backend, :shutdown, :normal}, 500
  end

  test "runtime dimensions stay within complete frame limits" do
    events = [Event.resize(1_001, 501)]

    assert {:ok, runtime} =
             Runtime.start_link(
               root: ResizableApp,
               backend: {DeterministicBackend, owner: self(), size: {501, 1_001}, events: events}
             )

    reference = Process.monitor(runtime)

    # This checks frame limits and cleanup, not a half-second performance limit.
    assert_receive {:backend, :draw, %Frame{width: 1_000, height: 500}}, 2_000
    assert_receive {:backend, :resize, {501, 1_001}}, 2_000
    assert_receive {:backend, :draw, %Frame{width: 1_000, height: 500}}, 2_000
    :ok = DeterministicBackend.send_event(runtime, Event.text("q"))
    assert_receive {:backend, :draw, %Frame{width: 1_000, height: 500}}, 2_000
    assert_receive {:backend, :shutdown, :normal}, 2_000
    assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}, 2_000
  end

  test "detected resize keeps the real backend size and clamps the application event" do
    assert {:ok, runtime} =
             Runtime.start_link(
               root: ResizableApp,
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :draw, %Frame{width: 20, height: 6}}, 500
    send(runtime, {:backend_size, {501, 1_001}})
    assert_receive {:backend, :resize, {501, 1_001}}, 500
    assert_receive {:backend, :draw, %Frame{width: 1_000, height: 500}}, 500
    Runtime.shutdown(runtime)
  end

  test "async commands tag a bare return value as successful" do
    runtime = start_async_app(fn -> :completed end)

    assert_receive {:async_complete, {:ok, :completed}}, 500
    Runtime.shutdown(runtime)
  end

  test "async commands preserve a tagged return value inside the success result" do
    runtime = start_async_app(fn -> {:ok, :inner} end)

    assert_receive {:async_complete, {:ok, {:ok, :inner}}}, 500
    Runtime.shutdown(runtime)
  end

  test "async commands tag raised failures as errors" do
    runtime = start_async_app(fn -> raise "async failed" end)

    assert_receive {:async_complete,
                    {:error, {:error, %RuntimeError{message: "async failed"}, _stacktrace}}},
                   500

    Runtime.shutdown(runtime)
  end

  test "async commands map abnormal worker exits" do
    runtime = start_async_app(fn -> Process.exit(self(), :kill) end)

    assert_receive {:async_complete, {:error, {:exit, :killed, []}}}, 500
    Runtime.shutdown(runtime)
  end

  test "message, send, timer, and clipboard commands stay serialized" do
    assert {:ok, runtime} =
             Runtime.start_link(
               root: EffectsApp,
               owner: self(),
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :draw, _frame}, 500
    assert_receive :direct_send, 500
    assert_receive {:backend, :clipboard, %Clipboard.Operation{content: "copy"}}, 500
    assert_receive {:effect, :message}, 500
    assert_receive {:effect, :timer}, 500
    assert_receive {:effect, {:clipboard, :ok}}, 500
    Runtime.shutdown(runtime)
  end

  test "diagnostic calls and forced rendering expose the current runtime contract" do
    assert {:ok, runtime} =
             TermUI.start_link(Counter,
               owner: self(),
               backend: {DeterministicBackend, owner: self()},
               render_interval: 1_000
             )

    assert_receive {:backend, :draw, _initial}, 500
    assert :ok = Runtime.sync(runtime)
    assert %{colors: :true_color, unicode: true} = Runtime.capabilities(runtime)
    assert %{frames_rendered: 1, dimensions: {20, 6}} = Runtime.get_state(runtime)

    Runtime.send_message(runtime, {:set, 9})
    Runtime.force_render(runtime)
    assert_receive {:backend, :draw, frame}, 500
    assert Frame.row_text(frame, 1) == "count=9             "
    Runtime.shutdown(runtime)
  end

  test "top-level run supports all GenServer name forms and preserves fast clean shutdown" do
    registry = Module.concat(__MODULE__, NameRegistry)
    start_supervised!({Registry, keys: :unique, name: registry})

    names = [
      :term_ui_named_contract_test,
      {:global, {:term_ui_named_contract_test, make_ref()}},
      {:via, Registry, {registry, :runtime}}
    ]

    for name <- names do
      assert :ok =
               TermUI.run(Counter,
                 name: name,
                 owner: self(),
                 backend: {DeterministicBackend, owner: self(), events: [Event.text("q")]}
               )

      refute GenServer.whereis(name)
    end
  end

  test "invalid applications fail before a backend is opened" do
    assert {:error, {:invalid_option, :root, :missing}} = Runtime.run([])
    assert {:error, {:application, :callbacks, {String, missing}}} = Runtime.run(root: String)
    assert {:event_to_msg, 2} in missing
    refute_receive {:backend, :init, _manager}
  end

  test "invalid application outputs fail with structured errors and cleanup" do
    assert {:error, {:application, :commands, {:invalid_commands, [:not_a_command]}} = reason} =
             Runtime.run(
               root: InvalidCommandApp,
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :shutdown, ^reason}, 500

    malformed = %Command{kind: :send, value: :invalid}

    assert {:error, {:application, :commands, {:invalid_commands, [^malformed]}} = reason} =
             Runtime.run(
               root: InvalidCommandValueApp,
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :shutdown, ^reason}, 500

    assert {:error, {:application, :view, {:expected_frame, :not_a_frame}} = reason} =
             Runtime.run(
               root: InvalidViewApp,
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :shutdown, ^reason}, 500

    assert {:error, {:application, :event_to_msg, {:invalid_result, :not_a_message}} = reason} =
             Runtime.run(
               root: InvalidEventApp,
               backend: {DeterministicBackend, owner: self(), events: [Event.key(:enter)]}
             )

    assert_receive {:backend, :shutdown, ^reason}, 500
  end

  test "a command result mapper failure is structured and cleans the backend" do
    assert {:error,
            {:application, :command_result,
             {:error, %RuntimeError{message: "mapper failed"}, _stacktrace}} = reason} =
             Runtime.run(
               root: MapperCrashApp,
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :shutdown, ^reason}, 500
  end

  test "shutdown terminates outstanding asynchronous work" do
    assert {:ok, runtime} =
             Runtime.start_link(
               root: BlockingAsyncApp,
               owner: self(),
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:async_worker, worker}, 500
    assert Process.alive?(worker)
    worker_ref = monitor_async_worker(worker)
    Runtime.shutdown(runtime)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 500
  end

  test "a forced runtime stop also terminates asynchronous work" do
    assert {:ok, runtime} =
             Runtime.start_link(
               root: BlockingAsyncApp,
               owner: self(),
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:async_worker, worker}, 500
    assert Process.alive?(worker)
    worker_ref = monitor_async_worker(worker)
    Process.exit(runtime, :kill)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 500
  end

  defp monitor_async_worker(worker) do
    reference = Process.monitor(worker)
    send(worker, {:monitor_ready, reference})
    assert_receive {:async_monitor_ready, ^worker, ^reference}, 1_000
    reference
  end

  test "backend cleanup completes before application termination can block" do
    assert {:ok, runtime} =
             Runtime.start_link(
               root: BlockingTerminateApp,
               owner: self(),
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :draw, _frame}, 500
    runtime_ref = Process.monitor(runtime)

    try do
      Runtime.shutdown(runtime)
      assert_receive {:backend, :shutdown, :normal}, 500
      assert_receive {:terminate_started, ^runtime}, 500
    after
      send(runtime, :release_terminate)
    end

    assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, :normal}, 500
  end

  test "child spec, invalid root values, missing modules, and fallback options are validated" do
    assert %{id: :named_runtime, restart: :transient, shutdown: 5_000} =
             Runtime.child_spec(name: :named_runtime, root: Counter)

    assert {:error, {:invalid_option, :root, "not a module"}} =
             Runtime.run(root: "not a module")

    missing = Module.concat(__MODULE__, MissingApplication)
    assert {:error, {:application, :load, {^missing, :nofile}}} = Runtime.run(root: missing)

    assert {:ok, runtime} =
             Runtime.start_link(
               root: BareApp,
               render_interval: 0,
               suppress_logger: :invalid,
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :draw, _frame}, 500
    assert Runtime.get_state(runtime).render_interval == 16
    Runtime.shutdown(runtime)
  end

  test "init shutdown commands render once and normalize public stop reasons" do
    reasons = [
      :shutdown,
      :custom,
      {:backend, :test, :stage, :failed},
      {:application, :test, :failed}
    ]

    for reason <- reasons do
      result =
        Runtime.run(
          root: LifecycleApp,
          mode: {:init_shutdown, reason},
          owner: self(),
          backend: {DeterministicBackend, owner: self()}
        )

      expected =
        case reason do
          :shutdown -> :ok
          {:backend, _, _, _} -> {:error, reason}
          {:application, _, _} -> {:error, reason}
          other -> {:error, {:shutdown, other}}
        end

      assert result == expected
      assert_receive {:backend, :draw, _frame}, 500
      assert_receive {:backend, :shutdown, _shutdown_reason}, 500
    end
  end

  test "thrown and exited initialization failures retain their failure kind" do
    for {mode, kind} <- [init_throw: :throw, init_exit: :exit] do
      assert {:error, {:application, :init, {^kind, :init_failed, _stacktrace}} = reason} =
               Runtime.run(
                 root: LifecycleApp,
                 mode: mode,
                 backend: {DeterministicBackend, owner: self()}
               )

      assert_receive {:backend, :shutdown, ^reason}, 500
    end
  end

  test "event, update, info, and view callback failures retain raised, thrown, and exit forms" do
    callback_modes = [
      {:event_raise, :event_to_msg, :error},
      {:event_throw, :event_to_msg, :throw},
      {:update_throw, :update, :throw},
      {:update_exit, :update, :exit},
      {:info_raise, :handle_info, :error},
      {:info_throw, :handle_info, :throw},
      {:info_exit, :handle_info, :exit},
      {:view_raise, :view, :error},
      {:view_throw, :view, :throw},
      {:view_exit, :view, :exit}
    ]

    for {mode, stage, kind} <- callback_modes do
      events = if stage in [:event_to_msg, :update], do: [Event.key(:enter)], else: []

      assert {:ok, runtime} =
               Runtime.start_link(
                 root: LifecycleApp,
                 mode: mode,
                 backend: {DeterministicBackend, owner: self(), events: events}
               )

      if stage == :handle_info do
        assert_receive {:backend, :draw, _frame}, 500
        send(runtime, :application_info)
      end

      # start_link establishes this link before the first view can fail.
      # A monitor installed after start_link can report :noproc instead.
      assert_receive {:EXIT, ^runtime, {:application, ^stage, {^kind, _reason, _stacktrace}}},
                     500
    end
  end

  test "ignored events and applications without handle_info stay alive" do
    assert {:ok, ignored} =
             Runtime.start_link(
               root: LifecycleApp,
               mode: :event_ignore,
               backend: {DeterministicBackend, owner: self(), events: [Event.key(:enter)]}
             )

    assert_receive {:backend, :draw, _frame}, 500
    assert :ok = Runtime.sync(ignored)
    Runtime.shutdown(ignored)

    assert {:ok, bare} =
             Runtime.start_link(
               root: BareApp,
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :draw, _frame}, 500
    send(bare, :unknown_info)
    assert :ok = Runtime.sync(bare)
    Runtime.shutdown(bare)
  end

  test "invalid command values are rejected for every command kind" do
    invalid_commands = [
      %Command{kind: :timer, value: {-1, :message}},
      %Command{kind: :async, value: {:not_a_function, &Function.identity/1}},
      %Command{kind: :clipboard, value: {Clipboard.operation("x"), :not_a_function}},
      %Command{kind: :unknown, value: nil}
    ]

    for command <- invalid_commands do
      assert {:error, {:application, :commands, {:invalid_commands, [^command]}} = reason} =
               Runtime.run(
                 root: LifecycleApp,
                 mode: {:init_command, command},
                 backend: {DeterministicBackend, owner: self()}
               )

      assert_receive {:backend, :shutdown, ^reason}, 500
    end
  end

  test "stale render and async messages do not change application state" do
    {:ok, runtime} = start_counter(render_interval: 1_000)
    assert_receive {:backend, :draw, _frame}, 500
    before = Runtime.get_state(runtime)
    send(runtime, {:render, make_ref()})
    send(runtime, {:async_result, make_ref(), {:ok, :stale}})
    assert :ok = Runtime.sync(runtime)
    after_state = Runtime.get_state(runtime)
    assert after_state.app_state == before.app_state
    assert after_state.frames_rendered == before.frames_rendered
    Runtime.shutdown(runtime)
  end

  test "detected resize failures stop the runtime with the backend reason" do
    assert {:ok, runtime} =
             Runtime.start_link(
               root: ResizableApp,
               backend: {DeterministicBackend, owner: self(), fail: :resize}
             )

    assert_receive {:backend, :draw, _frame}, 500
    reference = Process.monitor(runtime)
    send(runtime, {:backend_size, {8, 30}})

    assert_receive {:DOWN, ^reference, :process, ^runtime,
                    {:backend, DeterministicBackend, :resize, :resize_failed}},
                   500
  end

  test "render and final-render failures after startup stop and clean the runtime" do
    for trigger <- [:force, :shutdown] do
      {:ok, runtime} = start_counter(render_interval: 1_000)
      assert_receive {:backend, :draw, _frame}, 500
      manager = Runtime.get_state(runtime).backend_manager

      :sys.replace_state(manager, fn state ->
        put_in(state, [:backend_state, :fail], :draw)
      end)

      reference = Process.monitor(runtime)
      Runtime.send_message(runtime, {:set, 2})

      case trigger do
        :force -> Runtime.force_render(runtime)
        :shutdown -> Runtime.shutdown(runtime)
      end

      assert_receive {:DOWN, ^reference, :process, ^runtime,
                      {:backend, DeterministicBackend, :draw, :draw_failed}},
                     500
    end
  end

  test "a failed screen invalidation stops and cleans the runtime" do
    assert {:ok, runtime} =
             Runtime.start_link(
               root: Counter,
               owner: self(),
               backend: {DeterministicBackend, owner: self(), fail: :resize}
             )

    assert_receive {:backend, :draw, _frame}, 1_000
    reference = Process.monitor(runtime)
    reason = {:backend, DeterministicBackend, :resize, :resize_failed}
    Runtime.force_render(runtime)

    assert_receive {:DOWN, ^reference, :process, ^runtime, ^reason}, 1_000
    assert_receive {:backend, :shutdown, ^reason}, 1_000
  end

  test "a failed resume stops and cleans the runtime" do
    assert {:ok, runtime} =
             Runtime.start_link(
               root: Counter,
               owner: self(),
               backend: {DeterministicBackend, owner: self(), fail: :resize}
             )

    assert_receive {:backend, :draw, _frame}, 1_000
    reference = Process.monitor(runtime)
    reason = {:backend, DeterministicBackend, :resize, :resize_failed}
    manager = Runtime.get_state(runtime).backend_manager
    send(manager, :terminal_resume)

    assert_receive {:DOWN, ^reference, :process, ^runtime, ^reason}, 1_000
    assert_receive {:backend, :shutdown, ^reason}, 1_000
  end

  test "a stopping runtime does not render on resume" do
    state = %{status: :stopping}
    assert {:noreply, ^state} = Runtime.handle_info(:backend_resumed, state)
  end

  test "backend failures and manager exits stop the runtime" do
    {:ok, runtime} = start_counter(render_interval: 1_000)
    assert_receive {:backend, :draw, _frame}, 500
    reference = Process.monitor(runtime)
    send(runtime, {:backend_failed, :input_closed})
    assert_receive {:DOWN, ^reference, :process, ^runtime, {:shutdown, :input_closed}}, 500

    {:ok, runtime} = start_counter(render_interval: 1_000)
    assert_receive {:backend, :draw, _frame}, 500
    manager = Runtime.get_state(runtime).backend_manager
    reference = Process.monitor(runtime)
    Process.exit(manager, :kill)

    assert_receive {:DOWN, ^reference, :process, ^runtime,
                    {:backend, DeterministicBackend, :manager, :killed}},
                   500
  end

  test "thrown async work and mapper failures are delivered or structured" do
    runtime = start_async_app(fn -> throw(:async_failed) end)
    assert_receive {:async_complete, {:error, {:throw, :async_failed, _stacktrace}}}, 500
    Runtime.shutdown(runtime)

    command = Command.async(fn -> :ok end, fn _result -> throw(:mapper_failed) end)

    assert {:error,
            {:application, :command_result, {:throw, :mapper_failed, _stacktrace}} = reason} =
             Runtime.run(
               root: LifecycleApp,
               mode: {:init_command, command},
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :shutdown, ^reason}, 500
  end

  test "application terminate failures do not prevent backend cleanup" do
    for mode <- [:terminate_raise, :terminate_throw] do
      {:ok, runtime} =
        Runtime.start_link(
          root: LifecycleApp,
          mode: mode,
          owner: self(),
          backend: {DeterministicBackend, owner: self()}
        )

      assert_receive {:backend, :draw, _frame}, 500
      reference = Process.monitor(runtime)
      Runtime.shutdown(runtime)
      assert_receive {:backend, :shutdown, :normal}, 500
      assert_receive {:lifecycle_terminated, :normal}, 500
      assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}, 500
    end
  end

  defp start_counter(opts) do
    Runtime.start_link(
      [
        root: Counter,
        owner: self(),
        backend: {DeterministicBackend, owner: self()}
      ] ++ opts
    )
  end

  defp start_async_app(async_function) do
    assert {:ok, runtime} =
             Runtime.start_link(
               root: AsyncApp,
               owner: self(),
               async_function: async_function,
               backend: {DeterministicBackend, owner: self()}
             )

    assert_receive {:backend, :draw, _frame}, 500
    runtime
  end
end
