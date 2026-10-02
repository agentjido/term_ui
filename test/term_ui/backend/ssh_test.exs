defmodule TermUI.Backend.SSHTest do
  use ExUnit.Case, async: true

  alias TermUI.Backend.SSH
  alias TermUI.{Command, Event, Frame, Runtime}

  defmodule SessionApp do
    use TermUI.Elm

    @impl true
    def init(opts) do
      %{
        dimensions: Keyword.fetch!(opts, :dimensions),
        events: [],
        label: Keyword.get(opts, :label, "ready")
      }
    end

    @impl true
    def event_to_msg(event, _state), do: {:msg, {:event, event}}

    @impl true
    def update({:label, label}, state), do: %{state | label: label}

    def update({:event, %Event.Resize{width: width, height: height} = event}, state) do
      {%{state | dimensions: {width, height}, events: state.events ++ [event]}, []}
    end

    def update({:event, %Event.Text{text: "q"} = event}, state) do
      {%{state | events: state.events ++ [event]}, [Command.shutdown(:normal)]}
    end

    def update({:event, event}, state) do
      %{state | events: state.events ++ [event]}
    end

    @impl true
    def view(state) do
      {width, height} = state.dimensions
      Frame.from_rows([state.label, "events:#{length(state.events)}"], width, height)
    end
  end

  defmodule BlockingTerminateApp do
    use TermUI.Elm
    @impl true
    def init(opts), do: %{owner: Keyword.fetch!(opts, :test_owner)}
    @impl true
    def event_to_msg(_event, _state), do: :ignore
    @impl true
    def update(_message, state), do: state
    @impl true
    def view(_state), do: Frame.from_rows(["cleanup"], 20, 3)
    @impl true
    def terminate(_reason, state) do
      send(state.owner, {:terminate_waiting, self()})
      receive do: (:finish_terminate -> :ok)
    end
  end

  test "direct sessions parse remote terminal input and resize the v2 runtime" do
    session = start_session(label: "remote", mouse_tracking: :all)
    runtime = session |> SSH.session_info() |> Map.fetch!(:runtime)

    {setup_token, setup} = receive_output(session)
    assert setup =~ "\e[?1049h"
    assert setup =~ "\e[?1003h"
    assert setup =~ "\e[?2004h"
    assert setup =~ "\e[?1004h"
    SSH.ack_output(session, setup_token, :ok)

    {frame_token, frame} = receive_output(session)
    assert frame =~ "remote"
    SSH.ack_output(session, frame_token, :ok)

    assert :ok =
             SSH.input(
               session,
               "é\e[200~pasted text\e[201~\e[I\e[<0;3;2M"
             )

    assert :ok = SSH.resize(session, 40, 120)

    eventually(fn ->
      state = Runtime.get_state(runtime).app_state

      assert state.dimensions == {120, 40}
      assert Enum.any?(state.events, &match?(%Event.Text{text: "é"}, &1))
      assert Enum.any?(state.events, &match?(%Event.Paste{content: "pasted text"}, &1))
      assert Enum.any?(state.events, &match?(%Event.Focus{action: :gained}, &1))
      assert Enum.any?(state.events, &match?(%Event.Mouse{action: :press, x: 2, y: 1}, &1))
    end)
  end

  test "concurrent sessions isolate application state and failure" do
    session_a = start_session(label: "session-a")
    session_b = start_session(label: "session-b")
    runtime_a = SSH.session_info(session_a).runtime
    runtime_b = SSH.session_info(session_b).runtime

    acknowledge_initial_output(session_a, "session-a")
    acknowledge_initial_output(session_b, "session-b")

    assert :ok = SSH.input(session_a, "α")

    eventually(fn ->
      assert [%Event.Text{text: "α"}] = Runtime.get_state(runtime_a).app_state.events
      assert [] = Runtime.get_state(runtime_b).app_state.events
    end)

    reference = Process.monitor(session_a)
    assert :ok = SSH.disconnect(session_a, :test_disconnect)
    assert_receive {:DOWN, ^reference, :process, ^session_a, :normal}, 1_000

    assert Process.alive?(session_b)
    assert Process.alive?(runtime_b)
  end

  test "a slow output target retains only one in-flight and one current frame" do
    session = start_session(label: "frame-0", output_timeout: 60_000)
    runtime = SSH.session_info(session).runtime

    {setup_token, _setup} = receive_output(session)

    for index <- 1..100 do
      Runtime.send_message(runtime, {:label, "frame-#{index}"})
      Runtime.force_render(runtime)
      assert :ok = Runtime.sync(runtime)
    end

    assert %{
             output_queue: %{capacity: 2, in_flight: 1, pending_frames: 1}
           } = SSH.session_info(session)

    SSH.ack_output(session, setup_token, :ok)
    {frame_token, frame} = receive_output(session)

    assert frame =~ "frame-100"
    refute frame =~ "frame-99"
    SSH.ack_output(session, frame_token, :ok)

    eventually(fn ->
      assert %{output_queue: %{in_flight: 0, pending_frames: 0}} =
               SSH.session_info(session)
    end)
  end

  test "a forced redraw survives a delayed acknowledgement and replaced waiting frame" do
    session = start_session(label: "initial", output_timeout: 60_000)
    runtime = SSH.session_info(session).runtime
    acknowledge_initial_output(session, "initial")

    Runtime.send_message(runtime, {:label, "in-flight"})
    Runtime.force_render(runtime)
    :ok = Runtime.sync(runtime)
    {in_flight_token, _frame} = receive_output(session)

    Runtime.force_render(runtime)
    :ok = Runtime.sync(runtime)
    Runtime.send_message(runtime, {:label, "latest"})
    Runtime.force_render(runtime)
    :ok = Runtime.sync(runtime)
    assert SSH.session_info(session).output_queue.pending_frames == 1

    SSH.ack_output(session, in_flight_token, :ok)
    {redraw_token, redraw} = receive_output(session)
    assert redraw =~ "\e[0m\e[2J"
    assert redraw =~ "latest"
    refute redraw =~ "in-flight"
    SSH.ack_output(session, redraw_token, :ok)

    eventually(fn -> assert SSH.session_info(session).output_queue.in_flight == 0 end)
  end

  test "a function output target is serialized outside the session process" do
    owner = self()

    output = fn data ->
      send(owner, {:function_output, self(), data})
      :ok
    end

    {:ok, session} =
      SSH.start_session(SessionApp,
        output: output,
        size: {6, 20},
        runtime_options: [label: "function"]
      )

    on_exit(fn -> disconnect_session(session) end)

    assert_receive {:function_output, writer_a, setup}, 500
    assert setup =~ "\e[2J"
    refute writer_a == session

    assert_receive {:function_output, writer_b, frame}, 500
    assert frame =~ "function"
    refute writer_b == session
  end

  test "disconnect stops a session without waiting for a blocked client" do
    session = start_session(output_timeout: 60_000)
    runtime = SSH.session_info(session).runtime
    assert_receive {:term_ui_ssh_output, ^session, _token, _data}

    session_reference = Process.monitor(session)
    runtime_reference = Process.monitor(runtime)

    assert :ok = SSH.disconnect(session, :closed)

    assert_receive {:DOWN, ^runtime_reference, :process, ^runtime, _reason}, 1_000
    assert_receive {:DOWN, ^session_reference, :process, ^session, :normal}, 1_000
  end

  @tag capture_log: true
  test "unconfirmed output stops the runtime and session at the configured timeout" do
    session = start_session(output_timeout: 1_000)
    runtime = SSH.session_info(session).runtime
    session_reference = Process.monitor(session)
    runtime_reference = Process.monitor(runtime)
    {_token, _setup} = receive_output(session)

    assert_receive {:DOWN, ^runtime_reference, :process, ^runtime,
                    {:backend, SSH, :input, {:output_failed, :output_timeout}}},
                   2_500

    assert_receive {:DOWN, ^session_reference, :process, ^session, :normal}, 1_000
  end

  test "SSH backend state never selects the local raw terminal backend" do
    session = start_session()
    state = Runtime.get_state(SSH.session_info(session).runtime)

    assert state.backend == SSH
    assert state.capabilities.remote == :ssh
    refute state.backend == TermUI.Backend.Raw
  end

  defp start_session(opts \\ []) do
    runtime_options = Keyword.get(opts, :runtime_options, [])
    label = Keyword.get(opts, :label, "ready")

    opts =
      opts
      |> Keyword.delete(:label)
      |> Keyword.put_new(:output, self())
      |> Keyword.put_new(:size, {6, 20})
      |> Keyword.put(:runtime_options, Keyword.put(runtime_options, :label, label))

    assert {:ok, session} = SSH.start_session(SessionApp, opts)
    on_exit(fn -> disconnect_session(session) end)
    session
  end

  defp acknowledge_initial_output(session, label) do
    {setup_token, _setup} = receive_output(session)
    SSH.ack_output(session, setup_token, :ok)
    {frame_token, frame} = receive_output(session)
    assert frame =~ label
    SSH.ack_output(session, frame_token, :ok)
  end

  defp receive_output(session) do
    assert_receive {:term_ui_ssh_output, ^session, token, data}, 500
    {token, data}
  end

  defp disconnect_session(session) do
    if Process.alive?(session) do
      Process.unlink(session)
      reference = Process.monitor(session)
      SSH.disconnect(session, :test_cleanup)
      assert_receive {:DOWN, ^reference, :process, ^session, _reason}, 1_000
    end
  end

  defp eventually(assertion, attempts \\ 100)

  defp eventually(assertion, 0), do: assertion.()

  defp eventually(assertion, attempts) do
    assertion.()
  rescue
    ExUnit.AssertionError ->
      Process.sleep(10)
      eventually(assertion, attempts - 1)
  end

  test "SSH accepts prefixed and consecutive large pastes without turning CR into Enter" do
    session = start_session(label: "paste")
    runtime = SSH.session_info(session).runtime
    acknowledge_initial_output(session, "paste")
    body = String.duplicate("p", 2_000)
    SSH.input(session, "x\e[200~" <> body <> "\e[201~\e[200~second\r\e[201~")

    eventually(fn ->
      events = Runtime.get_state(runtime).app_state.events

      assert [
               %Event.Text{text: "x"},
               %Event.Paste{content: ^body},
               %Event.Paste{content: "second\r"}
             ] = events
    end)
  end

  test "cleanup is sent once when runtime exit comes before its acknowledgement" do
    session = start_session(label: "cleanup", output_timeout: 1_000)
    runtime = SSH.session_info(session).runtime
    ref = Process.monitor(runtime)
    acknowledge_initial_output(session, "cleanup")
    SSH.stop_session(session)
    {token, cleanup} = receive_output(session)
    assert cleanup =~ "\e[?1049l"
    assert_receive {:DOWN, ^ref, :process, ^runtime, :normal}, 500
    :sys.get_state(session)
    SSH.ack_output(session, token, :ok)
    assert_receive {:term_ui_ssh_closed, ^session, :normal}, 500
    refute_receive {:term_ui_ssh_output, ^session, _, ^cleanup}, 20
  end

  test "cleanup is not repeated after an early acknowledgement and follows unexpected exit" do
    for unexpected? <- [false, true] do
      session = start_session(label: "cleanup", output_timeout: 1_000)
      runtime = SSH.session_info(session).runtime
      acknowledge_initial_output(session, "cleanup")
      if unexpected?, do: Process.exit(runtime, :kill), else: SSH.stop_session(session)
      {token, cleanup} = receive_output(session)
      assert cleanup =~ "\e[?1049l"
      SSH.ack_output(session, token, :ok)
      assert_receive {:term_ui_ssh_closed, ^session, reason}, 500
      assert reason == if(unexpected?, do: :killed, else: :normal)
      refute_receive {:term_ui_ssh_output, ^session, _, ^cleanup}, 20
    end
  end

  test "cleanup acknowledgement before runtime exit does not send another cleanup" do
    assert {:ok, session} =
             SSH.start_session(BlockingTerminateApp,
               output: self(),
               output_timeout: 1_000,
               runtime_options: [test_owner: self()]
             )

    runtime = SSH.session_info(session).runtime

    on_exit(fn ->
      send(runtime, :finish_terminate)
      disconnect_session(session)
    end)

    acknowledge_initial_output(session, "cleanup")
    SSH.stop_session(session)
    {token, cleanup} = receive_output(session)
    assert_receive {:terminate_waiting, ^runtime}, 500
    SSH.ack_output(session, token, :ok)
    assert :sys.get_state(session).in_flight == nil
    assert Process.alive?(runtime)
    send(runtime, :finish_terminate)
    assert_receive {:term_ui_ssh_closed, ^session, :normal}, 500
    refute_receive {:term_ui_ssh_output, ^session, _, ^cleanup}, 20
  end
end
