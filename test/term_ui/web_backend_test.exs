defmodule TermUI.WebBackendTest do
  use ExUnit.Case, async: true

  alias TermUI.{Command, Event, Frame, Runtime, WebBackend}

  defmodule App do
    use TermUI.Elm

    @impl true
    def init(opts) do
      %{
        owner: Keyword.fetch!(opts, :test_owner),
        dimensions: Keyword.fetch!(opts, :dimensions),
        value: "ready",
        events: []
      }
    end

    @impl true
    def event_to_msg(event, _state), do: {:msg, {:event, event}}

    @impl true
    def update({:value, value}, state), do: %{state | value: value}
    def update({:event, %Event.Text{text: "q"}}, state), do: {state, [Command.shutdown(:normal)]}

    def update({:event, %Event.Resize{width: width, height: height} = event}, state),
      do: %{state | dimensions: {width, height}, events: state.events ++ [event]}

    def update({:event, event}, state), do: %{state | events: state.events ++ [event]}

    @impl true
    def view(state) do
      {width, height} = state.dimensions
      Frame.from_rows([state.value, "events:#{length(state.events)}"], width, height)
    end

    @impl true
    def terminate(reason, state) do
      send(state.owner, {:web_app_stopped, self(), reason, state})
      :ok
    end
  end

  test "a normal Elm application receives browser events and complete resized frames" do
    {session, runtime} = start_session()
    initial = receive_frame(session)
    assert initial["full"] and initial["base"] == nil
    assert row_text(initial, 1) == "ready               "
    acknowledge(session, initial)

    assert :ok = input(session, %{"type" => "text", "text" => "é界"})
    assert :ok = input(session, %{"type" => "key", "key" => "ArrowUp"})
    assert :ok = input(session, %{"type" => "paste", "text" => "one\ntwo"})

    assert :ok =
             input(session, %{
               "type" => "mouse",
               "action" => "press",
               "button" => "left",
               "x" => 3,
               "y" => 2
             })

    assert :ok = input(session, %{"type" => "resize", "width" => 30, "height" => 8})

    eventually(fn ->
      state = Runtime.get_state(runtime)
      assert state.backend == WebBackend
      assert state.dimensions == {30, 8}

      assert [
               %Event.Text{},
               %Event.Key{key: :up},
               %Event.Paste{},
               %Event.Mouse{},
               %Event.Resize{}
             ] = state.app_state.events
    end)

    acknowledge_until(session, fn frame -> frame["width"] == 30 and frame["height"] == 8 end)
    assert WebBackend.session_info(session).capabilities.remote == :web
  end

  test "a slow browser receives only the latest waiting frame based on its last confirmed output" do
    {session, runtime} = start_session(output_timeout: 60_000)
    initial = receive_frame(session)
    acknowledge(session, initial)
    render_value(runtime, "in-flight")
    in_flight = receive_frame(session)
    assert in_flight["base"] == initial["seq"]

    for index <- 1..100 do
      render_value(runtime, "value-#{index}")

      assert %{capacity: 2, in_flight: 1, pending_frames: 1} =
               WebBackend.session_info(session).output_queue
    end

    acknowledge(session, in_flight)
    latest = receive_frame(session)
    assert latest["base"] == in_flight["seq"]
    assert latest["seq"] == in_flight["seq"] + 1
    assert row_text(latest, 1) == "value-100           "
    assert length(latest["rows"]) == 1
    acknowledge(session, latest)
    assert %{in_flight: 0, pending_frames: 0} = WebBackend.session_info(session).output_queue
  end

  test "resync replaces an unknown baseline and ignores stale acknowledgements" do
    {session, runtime} = start_session()
    original = receive_frame(session)
    render_value(runtime, "current")
    assert :ok = input(session, %{"type" => "resync"})
    full = receive_frame(session)
    assert full["full"] and full["base"] == nil
    assert full["seq"] > original["seq"]
    assert row_text(full, 1) == "current             "
    assert :ok = acknowledge(session, original)
    assert WebBackend.session_info(session).confirmed_sequence == nil
    assert {:error, :invalid_acknowledgement} = input(session, %{"type" => "ack", "seq" => 999})
    acknowledge(session, full)
    render_value(runtime, "next")
    next = receive_frame(session)
    assert next["base"] == full["seq"]
    refute next["full"]
    acknowledge(session, next)
    refute_receive {:term_ui_web_output, ^session, %{"type" => "frame"}}, 20
  end

  test "forced redraw survives delayed acknowledgement and replaced waiting frames" do
    {session, runtime} = start_session()
    initial = receive_frame(session)
    acknowledge(session, initial)
    render_value(runtime, "in-flight")
    in_flight = receive_frame(session)
    Runtime.force_render(runtime)
    :ok = Runtime.sync(runtime)
    render_value(runtime, "latest")
    acknowledge(session, in_flight)
    redraw = receive_frame(session)
    assert redraw["full"] and redraw["base"] == nil
    assert row_text(redraw, 1) == "latest              "
    acknowledge(session, redraw)
  end

  test "shutdown accepts final acknowledgements and stops both owners" do
    {session, runtime} = start_session()
    manager = Runtime.get_state(runtime).backend_manager
    session_monitor = Process.monitor(session)
    runtime_monitor = Process.monitor(runtime)
    manager_monitor = Process.monitor(manager)
    initial = receive_frame(session)
    assert :ok = input(session, %{"type" => "text", "text" => "q"})
    assert_receive {:web_app_stopped, ^runtime, :normal, _state}, 1_000
    assert_receive {:DOWN, ^runtime_monitor, :process, ^runtime, :normal}, 1_000
    assert_receive {:DOWN, ^manager_monitor, :process, ^manager, :normal}, 1_000
    assert {:error, :stopping} = input(session, %{"type" => "text", "text" => "late"})
    acknowledge(session, initial)
    final = receive_frame(session)
    acknowledge(session, final)

    assert_receive {:term_ui_web_output, ^session, %{"type" => "closed", "reason" => "normal"}},
                   1_000

    assert_receive {:DOWN, ^session_monitor, :process, ^session, :normal}, 1_000
    assert :ok = WebBackend.stop_session(session)
  end

  test "disconnect stops the runtime and manager without waiting for output" do
    {session, runtime} = start_session(output_timeout: 60_000)
    manager = Runtime.get_state(runtime).backend_manager
    monitors = monitor_owners(session, runtime, manager)
    _initial = receive_frame(session)
    render_value(runtime, "waiting")
    assert %{in_flight: 1, pending_frames: 1} = WebBackend.session_info(session).output_queue
    assert :ok = WebBackend.disconnect(session)
    assert_receive {:web_app_stopped, ^runtime, :normal, _state}, 1_000
    assert_owners_stopped(monitors)
    refute_receive {:term_ui_web_output, ^session, _payload}, 20
  end

  test "an output timeout stops all owners and reports a close after cleanup" do
    {session, runtime} = start_session(output_timeout: 100)
    manager = Runtime.get_state(runtime).backend_manager
    monitors = monitor_owners(session, runtime, manager)
    _initial = receive_frame(session)
    assert_receive {:web_app_stopped, ^runtime, :normal, _state}, 1_000

    assert_receive {:term_ui_web_output, ^session, %{"type" => "closed", "reason" => "error"}},
                   1_000

    assert_owners_stopped(monitors)
  end

  test "connection owner exit cleans up the runtime while the output process remains alive" do
    owner = spawn(fn -> receive do: (:stop -> :ok) end)
    {session, runtime} = start_session(owner: owner)
    manager = Runtime.get_state(runtime).backend_manager
    monitors = monitor_owners(session, runtime, manager)
    _initial = receive_frame(session)
    send(owner, :stop)
    assert_receive {:web_app_stopped, ^runtime, :normal, _state}, 1_000
    assert_owners_stopped(monitors)
    refute_receive {:term_ui_web_output, ^session, _payload}, 20
  end

  @tag capture_log: true
  test "forced session exit releases its runtime and manager" do
    {session, runtime} = start_session()
    manager = Runtime.get_state(runtime).backend_manager
    monitors = monitor_owners(session, runtime, manager)
    _initial = receive_frame(session)
    Process.exit(session, :kill)
    assert_owners_stopped(monitors, false)
  end

  test "sessions keep state, input, dimensions, and shutdown separate" do
    {first, first_runtime} = start_session()
    {second, second_runtime} = start_session(size: {5, 15})
    acknowledge(first, receive_frame(first))
    acknowledge(second, receive_frame(second))
    assert :ok = input(first, %{"type" => "text", "text" => "first"})
    assert :ok = input(second, %{"type" => "text", "text" => "second"})
    assert :ok = input(first, %{"type" => "resize", "width" => 25, "height" => 7})

    eventually(fn ->
      assert [%Event.Text{text: "first"}, %Event.Resize{}] =
               Runtime.get_state(first_runtime).app_state.events

      assert [%Event.Text{text: "second"}] = Runtime.get_state(second_runtime).app_state.events
      assert Runtime.get_state(second_runtime).dimensions == {15, 5}
    end)

    assert :ok = WebBackend.disconnect(first)
    assert_receive {:web_app_stopped, ^first_runtime, :normal, _state}, 1_000
    assert Process.alive?(second_runtime)
    assert :ok = input(second, %{"type" => "text", "text" => "still-alive"})
    eventually(fn -> assert length(Runtime.get_state(second_runtime).app_state.events) == 2 end)
  end

  test "the input queue is bounded and keeps accepted events in order" do
    {session, runtime} = start_session(output_timeout: 60_000)
    acknowledge(session, receive_frame(session))
    manager = Runtime.get_state(runtime).backend_manager
    :ok = :sys.suspend(manager)

    try do
      for index <- 1..1_024 do
        assert :ok = input(session, %{"type" => "text", "text" => Integer.to_string(index)})
      end

      assert WebBackend.session_info(session).queued_events == 1_024

      assert {:error, :input_queue_full} =
               input(session, %{"type" => "resize", "width" => 25, "height" => 7})

      assert WebBackend.session_info(session).size == {6, 20}
    after
      :ok = :sys.resume(manager)
    end

    eventually(fn ->
      events = Runtime.get_state(runtime).app_state.events
      assert Enum.map(events, & &1.text) == Enum.map(1..1_024, &Integer.to_string/1)
    end)
  end

  test "host limits apply to initial size, resize, and text without changing session state" do
    {session, runtime} = start_session(limits: %{width: 20, height: 6, text_bytes: 3})
    acknowledge(session, receive_frame(session))
    assert {:error, :invalid_input} = input(session, %{"type" => "text", "text" => "four"})

    assert {:error, :invalid_input} =
             input(session, %{"type" => "resize", "width" => 21, "height" => 6})

    assert {:error, :unsupported_version} =
             WebBackend.input(session, %{"v" => 2, "type" => "text", "text" => "x"})

    assert :ok = input(session, %{"type" => "text", "text" => "é"})

    eventually(fn ->
      assert [%Event.Text{text: "é"}] = Runtime.get_state(runtime).app_state.events
    end)

    assert WebBackend.session_info(session).size == {6, 20}

    assert {:error, :invalid_size} =
             WebBackend.start_session(App, size: {7, 20}, limits: %{height: 6})

    assert {:error, :invalid_output_timeout} = WebBackend.start_session(App, output_timeout: 0)
    assert {:error, {:invalid_process, :owner}} = WebBackend.start_session(App, owner: :invalid)
  end

  defp monitor_owners(session, runtime, manager) do
    Enum.map([session, runtime, manager], fn pid -> {Process.monitor(pid), pid} end)
  end

  defp assert_owners_stopped(monitors, normal? \\ true) do
    for {monitor, pid} <- monitors do
      assert_receive {:DOWN, ^monitor, :process, ^pid, reason}, 1_000
      if normal?, do: assert(reason == :normal)
      refute Process.alive?(pid)
    end
  end

  defp start_session(opts \\ []) do
    opts =
      opts |> Keyword.put_new(:size, {6, 20}) |> Keyword.put(:runtime_options, test_owner: self())

    assert {:ok, session} = WebBackend.start_session(App, opts)
    on_exit(fn -> WebBackend.disconnect(session, :test_cleanup) end)
    {session, WebBackend.session_info(session).runtime}
  end

  defp input(session, payload), do: WebBackend.input(session, Map.put(payload, "v", 1))
  defp acknowledge(session, frame), do: input(session, %{"type" => "ack", "seq" => frame["seq"]})

  defp receive_frame(session) do
    assert_receive {:term_ui_web_output, ^session, %{"type" => "frame"} = payload}, 1_000
    payload
  end

  defp acknowledge_until(session, predicate) do
    frame = receive_frame(session)
    acknowledge(session, frame)
    if predicate.(frame), do: frame, else: acknowledge_until(session, predicate)
  end

  defp row_text(frame, row) do
    {_row, cells} =
      frame["rows"] |> Enum.find(fn [number, _cells] -> number == row end) |> List.to_tuple()

    Enum.map_join(cells, fn [text | _style] -> text end)
  end

  defp render_value(runtime, value) do
    Runtime.send_message(runtime, {:value, value})
    :ok = Runtime.sync(runtime)

    case Runtime.get_state(runtime).render_timer do
      {_reference, token} -> send(runtime, {:render, token})
      nil -> :ok
    end

    :ok = Runtime.sync(runtime)
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
end
