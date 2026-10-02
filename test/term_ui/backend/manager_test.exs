defmodule TermUI.Backend.ManagerTest do
  use ExUnit.Case, async: true

  alias TermUI.Backend.Manager
  alias TermUI.{Clipboard, Event, Frame}
  alias TermUI.Terminal.SignalHandler
  alias TermUI.Test.DeterministicBackend

  defmodule NoClipboardBackend do
    @behaviour TermUI.Backend

    defdelegate init(opts), to: DeterministicBackend
    defdelegate size(state), to: DeterministicBackend
    defdelegate capabilities(state), to: DeterministicBackend
    defdelegate draw(state, frame), to: DeterministicBackend
    defdelegate flush(state), to: DeterministicBackend
    defdelegate poll_event(state, timeout), to: DeterministicBackend
    defdelegate resize(state, size), to: DeterministicBackend
    defdelegate shutdown(state, reason), to: DeterministicBackend
  end

  defmodule ExercisingBackend do
    @behaviour TermUI.Backend

    def init(opts) do
      owner = Keyword.fetch!(opts, :owner)
      mode = Keyword.get(opts, :mode, :ok)

      case mode do
        :init_error ->
          {:error, :no_terminal}

        :init_invalid ->
          :invalid

        :init_raise ->
          raise "init failed"

        :init_throw ->
          throw(:init_failed)

        _ ->
          reader = input_reader(mode)

          send(owner, {:exercising_backend, :init, self(), reader})
          {:ok, %{owner: owner, mode: mode, size: {4, 12}, input_reader: reader, draws: 0}}
      end
    end

    def size(%{mode: :size_error}), do: {:error, :unavailable}
    def size(%{mode: :size_invalid}), do: {:ok, {0, 12}}
    def size(%{mode: :size_other}), do: :invalid
    def size(%{mode: :size_raise}), do: raise("size failed")
    def size(%{mode: :size_throw}), do: throw(:size_failed)
    def size(state), do: {:ok, state.size}

    def capabilities(%{mode: :capabilities_invalid}), do: :invalid
    def capabilities(%{mode: :capabilities_raise}), do: raise("capabilities failed")
    def capabilities(%{mode: :capabilities_throw}), do: throw(:capabilities_failed)
    def capabilities(_state), do: %{colors: :color_16, unicode: true}

    def draw(state, _frame), do: state_callback(state, :draw)
    def flush(state), do: state_callback(state, :flush)
    def invalidate(state), do: state_callback(state, :invalidate)
    def resume(state), do: state_callback(state, :resume)

    def resize(state, size) do
      case state_callback(state, :resize) do
        {:ok, next} -> {:ok, %{next | size: size}}
        error -> error
      end
    end

    def poll_event(%{mode: :poll_invalid}, _timeout), do: :invalid
    def poll_event(%{mode: :poll_raise}, _timeout), do: raise("poll failed")
    def poll_event(%{mode: :poll_throw}, _timeout), do: throw(:poll_failed)
    def poll_event(state, _timeout), do: {:timeout, state}

    def refresh_size(%{mode: :refresh_changed} = state),
      do: {:ok, {8, 30}, %{state | size: {8, 30}}}

    def refresh_size(%{mode: :refresh_error}), do: {:error, :unavailable}
    def refresh_size(%{mode: :refresh_invalid}), do: :invalid
    def refresh_size(%{mode: :refresh_raise}), do: raise("refresh failed")
    def refresh_size(%{mode: :refresh_throw}), do: throw(:refresh_failed)
    def refresh_size(state), do: {:ok, state.size, state}

    def shutdown(%{owner: owner, mode: :shutdown_raise}, reason) do
      send(owner, {:exercising_backend, :shutdown, reason})
      raise "shutdown failed"
    end

    def shutdown(%{owner: owner, mode: :shutdown_throw}, reason) do
      send(owner, {:exercising_backend, :shutdown, reason})
      throw(:shutdown_failed)
    end

    def shutdown(state, reason) do
      send(state.owner, {:exercising_backend, :shutdown, reason})
      :ok
    end

    defp input_reader(:reader), do: spawn_link(fn -> Process.sleep(:infinity) end)
    defp input_reader(_mode), do: nil

    defp state_callback(%{mode: mode}, stage) when mode == {:invalid, stage}, do: :invalid
    defp state_callback(%{mode: mode}, stage) when mode == {:error, stage}, do: {:error, :failed}
    defp state_callback(%{mode: mode}, stage) when mode == {:raise, stage}, do: raise("failed")
    defp state_callback(%{mode: mode}, stage) when mode == {:throw, stage}, do: throw(:failed)

    defp state_callback(state, :draw) do
      send(state.owner, {:exercising_backend, :draw})
      {:ok, %{state | draws: state.draws + 1}}
    end

    defp state_callback(state, _stage), do: {:ok, state}
  end

  test "accepts a custom size poll interval" do
    manager = start_manager(size_poll_interval: 75)

    assert %{size_poll_interval: 75} = :sys.get_state(manager)
    assert :ok = Manager.close(manager, :normal)
  end

  test "can disable size polling" do
    manager = start_manager(size_poll_interval: :disabled)

    assert %{size_poll_interval: nil} = :sys.get_state(manager)
    assert :ok = Manager.close(manager, :normal)
  end

  test "rejects an unsafe size poll interval" do
    previous = Process.flag(:trap_exit, true)

    try do
      assert {:error, {:invalid_size_poll_interval, 20}} =
               Manager.start_link(
                 self(),
                 {DeterministicBackend, owner: self()},
                 size_poll_interval: 20
               )

      refute_receive {:backend, :init, _pid}
    after
      Process.flag(:trap_exit, previous)
    end
  end

  test "serializes frame, clipboard, resize, and cleanup callbacks" do
    manager = start_manager(size_poll_interval: :disabled)
    frame = Frame.from_rows(["ok"], 20, 6)
    operation = Clipboard.operation("copy")

    assert %{backend: DeterministicBackend, size: {6, 20}, capabilities: capabilities} =
             Manager.info(manager)

    assert capabilities.colors == :true_color
    assert :ok = Manager.draw(manager, frame)
    assert_receive {:backend, :draw, ^frame}
    assert :ok = Manager.flush(manager)
    assert_receive {:backend, :flush, 1}
    assert :ok = Manager.clipboard(manager, operation)
    assert_receive {:backend, :clipboard, ^operation}
    assert :ok = Manager.resize(manager, {12, 40})
    assert_receive {:backend, :resize, {12, 40}}
    assert %{size: {12, 40}} = Manager.info(manager)
    assert :ok = Manager.close(manager, :complete)
    assert_receive {:backend, :shutdown, :complete}
  end

  test "delivers input and stops polling after an input failure" do
    event = Event.text("x")
    manager = start_manager([], events: [event])

    assert :ok = Manager.activate(manager)
    assert_receive {:backend_event, ^event}, 100
    assert :ok = Manager.close(manager, :normal)

    manager = start_manager([], fail: :input)
    assert :ok = Manager.activate(manager)

    assert_receive {:backend_failed, {:backend, DeterministicBackend, :input, :input_failed}},
                   100

    assert :ok = Manager.close(manager, :normal)
  end

  test "returns structured callback failures" do
    manager = start_manager([], fail: :clipboard)

    assert {:error, {:backend, DeterministicBackend, :clipboard, :clipboard_failed}} =
             Manager.clipboard(manager, Clipboard.operation("copy"))

    assert :ok = Manager.close(manager, :normal)

    manager = start_manager([], fail: :resize)

    assert {:error, {:backend, DeterministicBackend, :resize, :resize_failed}} =
             Manager.resize(manager, {10, 30})

    assert :ok = Manager.close(manager, :normal)
  end

  test "reports an optional clipboard callback as unsupported" do
    assert {:ok, manager} =
             Manager.start_link(
               self(),
               {NoClipboardBackend, owner: self()},
               size_poll_interval: :disabled
             )

    assert_receive {:backend, :init, ^manager}

    assert {:error, {:backend, NoClipboardBackend, :clipboard, :unsupported}} =
             Manager.clipboard(manager, Clipboard.operation("copy"))

    assert :ok = Manager.close(manager, :normal)
  end

  test "invalidation uses the current size for an older custom backend" do
    manager = start_manager(size_poll_interval: :disabled)
    assert :ok = Manager.invalidate(manager)
    assert_receive {:backend, :resize, {6, 20}}
    assert %{size: {6, 20}} = Manager.info(manager)
    assert :ok = Manager.close(manager, :normal)
  end

  test "cleans an opened backend when later setup fails" do
    previous = Process.flag(:trap_exit, true)

    try do
      reason = {:backend, DeterministicBackend, :size, :size_failed}

      assert {:error, ^reason} =
               Manager.start_link(
                 self(),
                 {DeterministicBackend, owner: self(), fail: :size},
                 size_poll_interval: :disabled
               )

      assert_receive {:backend, :init, _manager}
      assert_receive {:backend, :shutdown, ^reason}
    after
      Process.flag(:trap_exit, previous)
    end
  end

  test "cleans the backend when its owner is killed" do
    test_process = self()

    owner =
      spawn(fn ->
        {:ok, manager} =
          Manager.start_link(
            self(),
            {DeterministicBackend, owner: test_process},
            size_poll_interval: :disabled
          )

        send(test_process, {:manager, manager})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:backend, :init, manager}
    assert_receive {:manager, ^manager}
    reference = Process.monitor(manager)

    Process.exit(owner, :kill)

    assert_receive {:backend, :shutdown, :killed}
    assert_receive {:DOWN, ^reference, :process, ^manager, :killed}, 1_000
  end

  test "activate is idempotent and inactive polling messages are ignored" do
    manager = start_exercising_manager(:ok, size_poll_interval: :disabled)
    send(manager, :poll_input)
    send(manager, :poll_size)
    send(manager, :terminal_resume)
    assert %{active?: false} = :sys.get_state(manager)
    refute_receive :backend_resumed

    assert :ok = Manager.activate(manager)
    assert :ok = Manager.activate(manager)
    assert %{active?: true} = :sys.get_state(manager)
    assert :ok = Manager.close(manager, :normal)

    assert {:error, {:backend_manager_exit, {:noproc, _}}} =
             Manager.close(manager, :already_closed)
  end

  test "resume restores through the backend owner and reports callback failures" do
    manager = start_exercising_manager(:ok, size_poll_interval: :disabled)
    assert :ok = Manager.activate(manager)
    send(manager, :terminal_resume)
    assert_receive :backend_resumed, 1_000
    assert :ok = Manager.close(manager, :normal)

    for kind <- [:invalid, :error, :raise, :throw] do
      manager = start_exercising_manager({kind, :resume}, size_poll_interval: :disabled)
      assert :ok = Manager.activate(manager)
      send(manager, :terminal_resume)
      assert_receive {:backend_failed, {:backend, ExercisingBackend, :resume, _reason}}, 1_000
      assert %{active?: false} = :sys.get_state(manager)
      refute_receive :backend_resumed
      assert :ok = Manager.close(manager, :normal)
    end
  end

  test "a backend without resume uses its invalidation contract" do
    manager = start_manager(size_poll_interval: :disabled)
    assert :ok = Manager.activate(manager)
    send(manager, :terminal_resume)
    assert_receive {:backend, :resize, {6, 20}}, 1_000
    assert_receive :backend_resumed, 1_000
    assert :ok = Manager.close(manager, :normal)
  end

  test "a failed supervised signal handler stops input with a backend reason" do
    manager = start_exercising_manager(:ok, size_poll_interval: :disabled)
    assert :ok = Manager.activate(manager)
    handler = {SignalHandler, manager}
    send(manager, {:gen_event_EXIT, handler, :failed})

    assert_receive {:backend_failed,
                    {:backend, ExercisingBackend, :resume, {:signal_handler_exit, :failed}}},
                   1_000

    assert %{active?: false} = :sys.get_state(manager)
    assert :ok = Manager.close(manager, :normal)
  end

  test "size polling reports changes and preserves state after failures" do
    changed = start_exercising_manager(:refresh_changed, size_poll_interval: 50)
    assert :ok = Manager.activate(changed)
    send(changed, :poll_size)
    assert_receive {:backend_size, {8, 30}}, 200
    assert %{size: {8, 30}} = Manager.info(changed)
    assert :ok = Manager.close(changed, :normal)

    for mode <- [:refresh_error, :refresh_invalid, :refresh_raise, :refresh_throw] do
      manager = start_exercising_manager(mode, size_poll_interval: 50)
      assert :ok = Manager.activate(manager)
      send(manager, :poll_size)
      Process.sleep(5)
      assert %{size: {4, 12}} = Manager.info(manager)
      assert :ok = Manager.close(manager, :normal)
    end
  end

  test "an active backend reports linked input reader exits" do
    manager = start_exercising_manager(:reader, size_poll_interval: :disabled)
    assert :ok = Manager.activate(manager)
    reader = :sys.get_state(manager).backend_state.input_reader
    Process.exit(reader, :input_closed)

    assert_receive {:backend_failed,
                    {:backend, ExercisingBackend, :input, {:reader_exit, :input_closed}}},
                   200

    assert %{active?: false} = :sys.get_state(manager)
    assert :ok = Manager.close(manager, :normal)
  end

  test "invalid and crashing input callbacks stop input with structured errors" do
    expectations = [
      poll_invalid: {:invalid_result, :invalid},
      poll_raise: %RuntimeError{message: "poll failed"},
      poll_throw: {:throw, :poll_failed}
    ]

    for {mode, expected} <- expectations do
      manager = start_exercising_manager(mode, size_poll_interval: :disabled)
      assert :ok = Manager.activate(manager)
      assert_receive {:backend_failed, {:backend, ExercisingBackend, :input, ^expected}}, 200
      assert %{active?: false} = :sys.get_state(manager)
      assert :ok = Manager.close(manager, :normal)
    end
  end

  test "state callbacks normalize invalid, error, raised, and thrown results" do
    frame = Frame.from_rows(["ok"], 12, 4)

    for stage <- [:draw, :flush, :resize, :invalidate],
        kind <- [:invalid, :error, :raise, :throw] do
      manager = start_exercising_manager({kind, stage}, size_poll_interval: :disabled)

      result =
        case stage do
          :draw -> Manager.draw(manager, frame)
          :flush -> Manager.flush(manager)
          :resize -> Manager.resize(manager, {5, 14})
          :invalidate -> Manager.invalidate(manager)
        end

      assert {:error, {:backend, ExercisingBackend, ^stage, _reason}} = result
      assert :ok = Manager.close(manager, :normal)
    end
  end

  test "backend startup validates init, size, and capability callbacks and cleans opened sessions" do
    init_modes = [:init_error, :init_invalid, :init_raise, :init_throw]

    opened_modes = [
      :size_error,
      :size_invalid,
      :size_other,
      :size_raise,
      :size_throw,
      :capabilities_invalid,
      :capabilities_raise,
      :capabilities_throw
    ]

    previous = Process.flag(:trap_exit, true)

    try do
      for mode <- init_modes do
        assert {:error, _reason} =
                 Manager.start_link(
                   self(),
                   {ExercisingBackend, owner: self(), mode: mode},
                   size_poll_interval: :disabled
                 )
      end

      for mode <- opened_modes do
        assert {:error, reason} =
                 Manager.start_link(
                   self(),
                   {ExercisingBackend, owner: self(), mode: mode},
                   size_poll_interval: :disabled
                 )

        assert_receive {:exercising_backend, :init, _manager, _reader}
        assert_receive {:exercising_backend, :shutdown, ^reason}
      end
    after
      Process.flag(:trap_exit, previous)
    end
  end

  test "cleanup contains raised and thrown shutdown failures" do
    for mode <- [:shutdown_raise, :shutdown_throw] do
      manager = start_exercising_manager(mode, size_poll_interval: :disabled)

      assert {:error, {:backend, ExercisingBackend, :shutdown, _reason}} =
               Manager.close(manager, :test_complete)

      assert_receive {:exercising_backend, :shutdown, :test_complete}
    end
  end

  defp start_manager(opts, backend_opts \\ []) do
    assert {:ok, manager} =
             Manager.start_link(
               self(),
               {DeterministicBackend, [owner: self()] ++ backend_opts},
               opts
             )

    assert_receive {:backend, :init, ^manager}
    manager
  end

  defp start_exercising_manager(mode, opts) do
    assert {:ok, manager} =
             Manager.start_link(
               self(),
               {ExercisingBackend, owner: self(), mode: mode},
               opts
             )

    assert_receive {:exercising_backend, :init, ^manager, _reader}
    manager
  end
end
