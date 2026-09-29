defmodule TermUI.Integration.SSHRuntimeIntegrationTest do
  use ExUnit.Case, async: false

  alias TermUI.Event
  alias TermUI.Runtime

  defmodule SessionRoot do
    use TermUI.Elm

    @impl true
    def init(opts), do: %{label: Keyword.fetch!(opts, :label)}

    @impl true
    def event_to_msg(_event, _state), do: :ignore

    @impl true
    def update({:label, label}, state), do: {%{state | label: label}, []}
    def update(_message, state), do: {state, []}

    @impl true
    def view(state), do: {:text, state.label}
  end

  defmodule ReleaseSessionRoot do
    use TermUI.Elm

    @impl true
    def init(opts) do
      %{label: Keyword.fetch!(opts, :label), keys: [], dimensions: nil}
    end

    @impl true
    def event_to_msg(%Event.Key{key: key}, _state), do: {:msg, {:key, key}}

    def event_to_msg(%Event.Resize{width: width, height: height}, _state),
      do: {:msg, {:resize, width, height}}

    def event_to_msg(_event, _state), do: :ignore

    @impl true
    def update({:key, key}, state), do: {%{state | keys: state.keys ++ [key]}, []}

    def update({:resize, width, height}, state),
      do: {%{state | dimensions: {width, height}}, []}

    def update(_message, state), do: {state, []}

    @impl true
    def view(state) do
      {:text, "#{state.label}|keys:#{inspect(state.keys)}|size:#{inspect(state.dimensions)}"}
    end
  end

  test "concurrent SSH sessions own independent render buffers and lifecycle" do
    {:ok, device_a} = StringIO.open("")
    {:ok, device_b} = StringIO.open("")

    runtime_a = start_ssh_runtime(device_a, "session-a")
    runtime_b = start_ssh_runtime(device_b, "session-b")

    state_a = Runtime.get_state(runtime_a)
    state_b = Runtime.get_state(runtime_b)

    assert state_a.buffer_manager != state_b.buffer_manager

    force_render_sync(runtime_a)
    force_render_sync(runtime_b)

    assert device_output(device_a) =~ "session-a"
    refute device_output(device_a) =~ "session-b"
    assert device_output(device_b) =~ "session-b"
    refute device_output(device_b) =~ "session-a"

    buffer_ref = Process.monitor(state_a.buffer_manager)
    runtime_ref = Process.monitor(runtime_a)
    Runtime.shutdown(runtime_a)

    assert_receive {:DOWN, ^runtime_ref, :process, ^runtime_a, :normal}
    assert_receive {:DOWN, ^buffer_ref, :process, _pid, :normal}
    assert Process.alive?(runtime_b)

    force_render_sync(runtime_b)
  end

  test "shrinking content erases stale SSH cells without clearing the screen" do
    {:ok, device} = StringIO.open("")
    runtime = start_ssh_runtime(device, "ABCDEFGHIJ")

    force_render_sync(runtime)
    snapshot = device_output(device)

    Runtime.send_message(runtime, :root, {:label, "AB"})
    :ok = Runtime.sync(runtime)
    render_sync(runtime)

    output = output_since(device, snapshot)
    assert output =~ "\e[1;3H        "
    refute output =~ "\e[2J"
  end

  @tag :redraw_regression
  test "forced rendering restores unchanged content after terminal output is damaged" do
    {:ok, device} = StringIO.open("")
    runtime = start_ssh_runtime(device, "same-screen")
    force_render_sync(runtime)
    snapshot = device_output(device)

    force_render_sync(runtime)

    output = output_since(device, snapshot)
    assert output =~ "\e[0m\e[2J"
    assert output =~ "same-screen"
    assert Runtime.get_state(runtime).root_state.label == "same-screen"
  end

  @tag :redraw_regression
  test "focus gain restores the screen when the application ignores the event" do
    {:ok, device} = StringIO.open("")
    runtime = start_ssh_runtime(device, "focus-screen")
    force_render_sync(runtime)
    snapshot = device_output(device)

    Runtime.send_event(runtime, Event.focus(:gained))
    :ok = Runtime.sync(runtime)

    output = output_since(device, snapshot)
    assert output =~ "\e[2J"
    assert output =~ "focus-screen"
  end

  test "renders the bottom-right cell while autowrap is disabled" do
    {:ok, device} = StringIO.open("")

    {:ok, runtime} =
      Runtime.start_link(
        root: SessionRoot,
        label: "AB\nCD",
        backend: {TermUI.Backend.SSH, device: device, size: {2, 2}},
        render_interval: 60_000
      )

    on_exit(fn ->
      if Process.alive?(runtime), do: Runtime.shutdown(runtime)
    end)

    force_render_sync(runtime)

    output = device_output(device)
    assert output =~ "\e[?7l"
    assert output =~ "D"
  end

  test "SSH session handles input, resize, and graceful disconnect cleanup" do
    {:ok, device} = StringIO.open("")

    runtime =
      start_ssh_runtime(device, "release-session", root: ReleaseSessionRoot)

    send(runtime, {:ssh_input, Event.key(:up)})
    send(runtime, {:ssh_resize, 12, 34})
    :ok = Runtime.sync(runtime)

    state = Runtime.get_state(runtime)
    assert state.root_state.keys == [:up]
    assert state.root_state.dimensions == {34, 12}
    assert state.dimensions == {34, 12}
    assert state.backend_state.size == {12, 34}

    force_render_sync(runtime)
    assert device_output(device) =~ "release-session|keys:[:up]"

    buffer_ref = Process.monitor(state.buffer_manager)
    runtime_ref = Process.monitor(runtime)
    Runtime.shutdown(runtime)

    assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, :normal}
    assert_receive {:DOWN, ^buffer_ref, :process, _pid, :normal}

    output = device_output(device)
    assert output =~ "\e[?1006l\e[?1003l\e[?1002l\e[?1000l"
    assert output =~ "\e[?25h"
    assert output =~ "\e[?7h"
    assert output =~ "\e[?1049l"
  end

  test "abrupt SSH channel close does not block runtime teardown" do
    {:ok, device} = StringIO.open("")
    runtime = start_ssh_runtime(device, "closed-session")
    state = Runtime.get_state(runtime)

    runtime_ref = Process.monitor(runtime)
    buffer_ref = Process.monitor(state.buffer_manager)
    assert {:ok, _contents} = StringIO.close(device)

    Runtime.shutdown(runtime)

    assert_receive {:DOWN, ^runtime_ref, :process, ^runtime, :normal}
    assert_receive {:DOWN, ^buffer_ref, :process, _pid, :normal}
  end

  defp start_ssh_runtime(device, label, opts \\ []) do
    {:ok, runtime} =
      Runtime.start_link(
        root: Keyword.get(opts, :root, SessionRoot),
        label: label,
        backend: {TermUI.Backend.SSH, device: device, size: {4, 20}},
        render_interval: 60_000
      )

    on_exit(fn ->
      if Process.alive?(runtime), do: Runtime.shutdown(runtime)
    end)

    runtime
  end

  defp force_render_sync(runtime) do
    Runtime.force_render(runtime)
    _state = :sys.get_state(runtime)
    :ok
  end

  defp render_sync(runtime) do
    send(runtime, :render)
    _state = :sys.get_state(runtime)
    :ok
  end

  defp device_output(device) do
    {_input, output} = StringIO.contents(device)
    output
  end

  defp output_since(device, snapshot) do
    device
    |> device_output()
    |> String.replace_prefix(snapshot, "")
  end
end
