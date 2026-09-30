defmodule TermUI.Runtime.ResizeTest do
  use ExUnit.Case, async: false

  alias TermUI.Event
  alias TermUI.Runtime

  defmodule GeometryDevice do
    def run(size) do
      receive do
        {:resize, size, owner} ->
          send(owner, {:size_changed, self()})
          run(size)

        {:io_request, from, reference, {:get_geometry, axis}} ->
          value = if axis == :rows, do: elem(size, 0), else: elem(size, 1)
          send(from, {:io_reply, reference, value})
          run(size)

        {:io_request, _from, _reference, {:get_chars, _, _, _}} ->
          run(size)

        {:io_request, from, reference, request} ->
          reply =
            if request == :getopts, do: [echo: true, binary: true, terminal: true], else: :ok

          send(from, {:io_reply, reference, reply})
          run(size)

        :stop ->
          :ok
      end
    end
  end

  # Simple test component
  defmodule TestComponent do
    use TermUI.Elm

    def init(opts), do: %{resizes: [], owner: Keyword.get(opts, :owner)}

    def update({:resize, width, height}, state) do
      commands = if state.owner, do: [{:send, state.owner, {:resized, width, height}}], else: []
      {%{state | resizes: [{width, height} | state.resizes]}, commands}
    end

    def update(_msg, state), do: {state, []}

    def view(_state), do: text("test")

    def event_to_msg(%Event.Resize{width: w, height: h}, _state) do
      {:msg, {:resize, w, h}}
    end

    def event_to_msg(_event, _state), do: :ignore
  end

  describe "resize handling" do
    test "TTY detects size changes without a Terminal process or resize signal" do
      owner = self()
      device = spawn_link(fn -> GeometryDevice.run({24, 80}) end)

      host =
        spawn_link(fn ->
          Process.group_leader(self(), device)
          {:ok, runtime} = Runtime.start_link(root: TestComponent, backend: :tty, owner: owner)
          send(owner, {:runtime_started, runtime})

          receive do
            :stop -> :ok
          end
        end)

      on_exit(fn ->
        send(host, :stop)
        send(device, :stop)
      end)

      assert_receive {:runtime_started, runtime}, 1000
      reference = Process.monitor(runtime)
      state = Runtime.get_state(runtime)
      assert state.dimensions == {80, 24}
      refute state.terminal_started

      send(device, {:resize, {30, 100}, self()})
      assert_receive {:size_changed, ^device}
      assert_receive {:resized, 100, 30}, 1000
      state = Runtime.get_state(runtime)
      assert state.dimensions == {100, 30}
      assert state.backend_state.size == {30, 100}
      assert state.root_state.resizes == [{100, 30}]
      refute_receive {:resized, _, _}, 300

      Runtime.shutdown(runtime)
      assert_receive {:DOWN, ^reference, :process, ^runtime, :normal}, 1000
    end

    test "Runtime handles terminal_resize message" do
      {:ok, runtime} = Runtime.start_link(root: TestComponent, skip_terminal: true)

      # Send resize message
      send(runtime, {:terminal_resize, {50, 100}})

      # Give it time to process
      Process.sleep(50)

      state = Runtime.get_state(runtime)

      # With skip_terminal: true, dimensions won't be updated
      # because handle_resize checks terminal_started
      # This tests that the message is handled without crashing
      assert state != nil

      Runtime.shutdown(runtime)
    end

    test "resize event is created with correct dimensions" do
      resize_event = Event.Resize.new(120, 40)

      assert resize_event.width == 120
      assert resize_event.height == 40
      assert is_integer(resize_event.timestamp)
    end
  end

  describe "Event.Resize struct" do
    test "has default values" do
      resize = %Event.Resize{}
      assert resize.width == 80
      assert resize.height == 24
    end

    test "new/2 creates event with dimensions" do
      resize = Event.Resize.new(200, 50)
      assert resize.width == 200
      assert resize.height == 50
    end

    test "new/3 accepts timestamp option" do
      resize = Event.Resize.new(100, 50, timestamp: 12_345)
      assert resize.timestamp == 12_345
    end
  end
end
