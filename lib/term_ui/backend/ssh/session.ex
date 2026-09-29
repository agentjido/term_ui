defmodule TermUI.Backend.SSH.Session do
  @moduledoc false

  use GenServer

  alias TermUI.Backend.{CapabilityFilter, InputBuffer}
  alias TermUI.Backend.SSH
  alias TermUI.Backend.SSH.Renderer
  alias TermUI.Event
  alias TermUI.Frame
  alias TermUI.Runtime
  alias TermUI.Terminal.EscapeParser

  @escape_timeout 50
  @default_output_timeout 5_000
  @maximum_events 1_024

  @type output_target :: pid() | (binary() -> :ok | {:error, term()})

  @impl true
  def init({root, opts}) do
    Process.flag(:trap_exit, true)

    with {:ok, output} <- fetch_output(opts),
         {:ok, owner} <- fetch_owner(opts),
         {:ok, size} <- valid_size(Keyword.get(opts, :size, {24, 80})),
         {:ok, output_timeout} <- output_timeout(opts) do
      capabilities = capabilities(size, opts)
      owner_monitor = Process.monitor(owner)

      case start_runtime(root, opts, size, capabilities) do
        {:ok, runtime} ->
          state = %{
            owner: owner,
            owner_monitor: owner_monitor,
            runtime: runtime,
            output: output,
            output_timeout: output_timeout,
            options: opts,
            capabilities: capabilities,
            size: size,
            status: :running,
            stop_reason: :normal,
            runtime_stopped?: false,
            notified?: false,
            connected?: true,
            input_buffer: "",
            paste_state: nil,
            events: [],
            poll_waiter: nil,
            escape_timer: nil,
            in_flight: nil,
            pending_frame: nil,
            cleanup: nil,
            last_frame: nil,
            redraw?: false
          }

          {:ok, start_output(state, :setup, Renderer.setup_sequence(opts, capabilities), nil)}

        {:error, reason} ->
          Process.demonitor(owner_monitor, [:flush])
          {:stop, reason}
      end
    end
  end

  @impl true
  def handle_call({:input, _data}, _from, %{connected?: false} = state) do
    {:reply, {:error, :disconnected}, state}
  end

  def handle_call({:input, data}, _from, state) do
    case to_binary(data) do
      {:ok, binary} ->
        state = parse_input(state, binary)
        {:reply, :ok, deliver_waiter(state)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:event, event}, _from, state) do
    if valid_event?(event) do
      state = state |> enqueue_events([event]) |> deliver_waiter()
      {:reply, :ok, state}
    else
      {:reply, {:error, {:invalid_event, event}}, state}
    end
  end

  def handle_call({:resize, rows, columns}, _from, state) do
    case valid_size({rows, columns}) do
      {:ok, size} ->
        event = Event.resize(columns, rows)

        state =
          state
          |> Map.put(:size, size)
          |> Map.update!(:capabilities, &Map.put(&1, :dimensions, size))
          |> enqueue_events([event])
          |> deliver_waiter()

        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:frame, _frame}, _from, %{connected?: false} = state) do
    {:reply, :ok, state}
  end

  def handle_call({:frame, %Frame{} = frame}, _from, state) do
    state = queue_frame(state, frame)
    {:reply, :ok, state}
  end

  def handle_call(:invalidate, _from, state) do
    {:reply, :ok, %{state | redraw?: true}}
  end

  def handle_call({:poll_event, _timeout}, _from, %{events: [event | rest]} = state) do
    {:reply, {:ok, event}, %{state | events: rest}}
  end

  def handle_call({:poll_event, _timeout}, _from, %{connected?: false} = state) do
    {:reply, :timeout, state}
  end

  def handle_call({:poll_event, 0}, _from, state), do: {:reply, :timeout, state}

  def handle_call({:poll_event, timeout}, from, %{poll_waiter: nil} = state) do
    token = make_ref()
    timer = Process.send_after(self(), {:poll_timeout, token}, timeout)
    {:noreply, %{state | poll_waiter: {from, token, timer}}}
  end

  def handle_call({:poll_event, _timeout}, _from, state) do
    {:reply, {:error, :poll_in_progress}, state}
  end

  def handle_call({:stop, reason}, _from, %{status: :running} = state) do
    Runtime.shutdown(state.runtime)
    {:reply, :ok, %{state | status: :stopping, stop_reason: reason}}
  end

  def handle_call({:stop, _reason}, _from, state), do: {:reply, :ok, state}

  def handle_call({:backend_shutdown, reason}, _from, state) do
    state =
      state
      |> Map.put(:status, :stopping)
      |> Map.put(:stop_reason, reason)
      |> queue_cleanup()

    {:reply, :ok, state}
  end

  def handle_call(:info, _from, state) do
    info = %{
      runtime: state.runtime,
      size: state.size,
      capabilities: state.capabilities,
      connected?: state.connected?,
      status: state.status,
      queued_events: length(state.events),
      output_queue: %{
        capacity: 2,
        in_flight: if(is_nil(state.in_flight), do: 0, else: 1),
        pending_frames: if(is_nil(state.pending_frame), do: 0, else: 1)
      }
    }

    {:reply, info, state}
  end

  @impl true
  def handle_cast({:output_result, token, result}, state) do
    state |> complete_output(token, normalize_output_result(result)) |> session_reply()
  end

  def handle_cast({:disconnect, reason}, state) do
    disconnect_state(state, reason)
  end

  @impl true
  def handle_info({:output_result, worker, token, result}, state) do
    case state.in_flight do
      %{worker: ^worker, token: ^token} ->
        state |> complete_output(token, normalize_output_result(result)) |> session_reply()

      _other ->
        {:noreply, state}
    end
  end

  def handle_info({:DOWN, reference, :process, pid, reason}, state) do
    cond do
      reference == state.owner_monitor ->
        disconnect_state(state, {:owner_exit, reason})

      match?(%{worker_monitor: ^reference, worker: ^pid}, state.in_flight) ->
        case reason do
          :normal -> {:noreply, state}
          _other -> {:noreply, fail_output(state, {:writer_exit, reason})}
        end

      true ->
        {:noreply, state}
    end
  end

  def handle_info({:poll_timeout, token}, %{poll_waiter: {from, token, _timer}} = state) do
    GenServer.reply(from, :timeout)
    {:noreply, %{state | poll_waiter: nil}}
  end

  def handle_info({:poll_timeout, _old_token}, state), do: {:noreply, state}

  def handle_info({:escape_timeout, token}, %{escape_timer: {_timer, token}} = state) do
    state =
      case state.input_buffer do
        "\e" -> state |> Map.put(:input_buffer, "") |> enqueue_events([Event.key(:escape)])
        "\e" <> _partial -> %{state | input_buffer: ""}
        _other -> state
      end

    {:noreply, state |> Map.put(:escape_timer, nil) |> deliver_waiter()}
  end

  def handle_info({:escape_timeout, _old_token}, state), do: {:noreply, state}

  def handle_info({:output_timeout, token}, state) do
    case state.in_flight do
      %{token: ^token} -> state |> fail_output(:output_timeout) |> session_reply()
      _other -> {:noreply, state}
    end
  end

  def handle_info({:EXIT, runtime, reason}, %{runtime: runtime} = state) do
    state =
      state
      |> release_poll_waiter()
      |> Map.put(:runtime_stopped?, true)
      |> Map.put(:status, :stopping)
      |> Map.update!(:stop_reason, fn current ->
        if current == :normal, do: reason, else: current
      end)
      |> ensure_cleanup_after_runtime_exit()
      |> maybe_finish()

    session_reply(state)
  end

  def handle_info({:EXIT, owner, reason}, %{owner: owner} = state) do
    disconnect_state(state, {:owner_exit, reason})
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    cancel_timer(state.escape_timer)
    cancel_poll_waiter(state.poll_waiter)
    stop_in_flight(state.in_flight)
    Process.demonitor(state.owner_monitor, [:flush])

    if Process.alive?(state.runtime) do
      Process.unlink(state.runtime)
      Process.exit(state.runtime, :shutdown)
    end

    :ok
  end

  defp start_runtime(root, opts, size, capabilities) do
    runtime_options = Keyword.get(opts, :runtime_options, [])
    backend_options = [session: self(), size: size, capabilities: capabilities]

    runtime_options =
      runtime_options
      |> Keyword.put(:backend, {SSH, backend_options})
      |> Keyword.update(:backend_opts, [size_poll_interval: :disabled], fn backend_opts ->
        Keyword.put(backend_opts, :size_poll_interval, :disabled)
      end)

    TermUI.start_link(root, runtime_options)
  end

  defp fetch_output(opts) do
    case Keyword.fetch(opts, :output) do
      {:ok, output} when is_pid(output) or is_function(output, 1) -> {:ok, output}
      :error -> {:error, {:missing_option, :output}}
      {:ok, invalid} -> {:error, {:invalid_option, :output, invalid}}
    end
  end

  defp fetch_owner(opts) do
    case Keyword.fetch(opts, :owner) do
      {:ok, owner} when is_pid(owner) -> {:ok, owner}
      :error -> {:error, {:missing_option, :owner}}
      {:ok, invalid} -> {:error, {:invalid_option, :owner, invalid}}
    end
  end

  defp valid_size({rows, columns} = size)
       when is_integer(rows) and rows > 0 and is_integer(columns) and columns > 0,
       do: {:ok, size}

  defp valid_size(invalid), do: {:error, {:invalid_size, invalid}}

  defp output_timeout(opts) do
    case Keyword.get(opts, :output_timeout, @default_output_timeout) do
      timeout when is_integer(timeout) and timeout > 0 -> {:ok, timeout}
      invalid -> {:error, {:invalid_output_timeout, invalid}}
    end
  end

  defp capabilities(size, opts) do
    defaults = %{
      colors: :true_color,
      unicode: true,
      mouse: Keyword.get(opts, :mouse_tracking, :none) != :none,
      paste: Keyword.get(opts, :bracketed_paste, true),
      focus: Keyword.get(opts, :focus_events, true),
      dimensions: size,
      remote: :ssh
    }

    preferences =
      opts
      |> Keyword.get(:runtime_options, [])
      |> Keyword.get(:backend_opts, [])
      |> Keyword.merge(Keyword.take(opts, [:color_mode, :character_set]))

    defaults
    |> Map.merge(Keyword.get(opts, :capabilities, %{}))
    |> Map.put(:dimensions, size)
    |> CapabilityFilter.filter(preferences)
  end

  defp to_binary(data) do
    {:ok, IO.iodata_to_binary(data)}
  rescue
    _exception -> {:error, {:invalid_input, data}}
  end

  defp parse_input(state, data) do
    state = cancel_escape_timer(state)

    state =
      InputBuffer.append_with_limit(state, data, :input_buffer,
        source: __MODULE__,
        paste_aware: true
      )

    {events, remaining} = EscapeParser.parse(state.input_buffer)

    state
    |> Map.put(:input_buffer, remaining)
    |> enqueue_events(events)
    |> schedule_escape_timeout()
  end

  defp enqueue_events(state, []), do: state

  defp enqueue_events(state, events) do
    %{state | events: Enum.take(state.events ++ events, -@maximum_events)}
  end

  defp deliver_waiter(%{poll_waiter: {from, _token, timer}, events: [event | rest]} = state) do
    _cancelled = Process.cancel_timer(timer)
    GenServer.reply(from, {:ok, event})
    %{state | events: rest, poll_waiter: nil}
  end

  defp deliver_waiter(state), do: state

  defp schedule_escape_timeout(%{paste_state: paste_state} = state)
       when not is_nil(paste_state),
       do: state

  defp schedule_escape_timeout(%{input_buffer: "\e" <> _partial} = state) do
    token = make_ref()
    timer = Process.send_after(self(), {:escape_timeout, token}, @escape_timeout)
    %{state | escape_timer: {timer, token}}
  end

  defp schedule_escape_timeout(state), do: state

  defp cancel_escape_timer(%{escape_timer: nil} = state), do: state

  defp cancel_escape_timer(%{escape_timer: {timer, _token}} = state) do
    _cancelled = Process.cancel_timer(timer)
    %{state | escape_timer: nil}
  end

  defp valid_event?(%Event.Key{}), do: true
  defp valid_event?(%Event.Text{}), do: true
  defp valid_event?(%Event.Paste{}), do: true
  defp valid_event?(%Event.Mouse{}), do: true
  defp valid_event?(%Event.Resize{}), do: true
  defp valid_event?(%Event.Focus{}), do: true
  defp valid_event?(_event), do: false

  defp queue_frame(%{in_flight: nil} = state, frame) do
    start_frame_output(state, frame)
  end

  defp queue_frame(state, frame), do: %{state | pending_frame: frame}

  defp queue_cleanup(%{connected?: false} = state), do: state
  defp queue_cleanup(%{cleanup: cleanup} = state) when not is_nil(cleanup), do: state

  defp queue_cleanup(state) do
    state = %{state | cleanup: Renderer.cleanup_sequence(state.options, state.capabilities)}
    if is_nil(state.in_flight), do: dispatch_next(state), else: state
  end

  defp start_frame_output(state, frame) do
    previous = if state.redraw?, do: nil, else: state.last_frame
    data = Renderer.frame_sequence(previous, frame, state.capabilities)
    start_output(%{state | redraw?: false}, :frame, data, frame)
  end

  defp start_output(state, kind, data, frame) do
    token = make_ref()
    timer = Process.send_after(self(), {:output_timeout, token}, state.output_timeout)

    packet = %{
      token: token,
      timer: timer,
      kind: kind,
      frame: frame,
      worker: nil,
      worker_monitor: nil
    }

    case state.output do
      output when is_pid(output) ->
        send(output, {:term_ui_ssh_output, self(), token, data})
        %{state | in_flight: packet}

      output when is_function(output, 1) ->
        parent = self()

        {worker, worker_monitor} =
          spawn_monitor(fn ->
            result = invoke_output(output, data)
            send(parent, {:output_result, self(), token, result})
          end)

        %{state | in_flight: %{packet | worker: worker, worker_monitor: worker_monitor}}
    end
  end

  defp complete_output(%{in_flight: %{token: token} = packet} = state, token, :ok) do
    state = clear_in_flight(state, packet)
    state = if packet.kind == :frame, do: %{state | last_frame: packet.frame}, else: state
    dispatch_next(state)
  end

  defp complete_output(%{in_flight: %{token: token} = packet} = state, token, {:error, reason}) do
    state |> clear_in_flight(packet) |> fail_output(reason)
  end

  defp complete_output(state, _token, _result), do: state

  defp clear_in_flight(state, packet) do
    _cancelled = Process.cancel_timer(packet.timer)

    if packet.worker_monitor do
      Process.demonitor(packet.worker_monitor, [:flush])
    end

    %{state | in_flight: nil}
  end

  defp dispatch_next(%{pending_frame: %Frame{} = frame} = state) do
    state |> Map.put(:pending_frame, nil) |> start_frame_output(frame)
  end

  defp dispatch_next(%{cleanup: cleanup} = state) when is_binary(cleanup) do
    state |> Map.put(:cleanup, nil) |> start_output(:cleanup, cleanup, nil)
  end

  defp dispatch_next(state), do: maybe_finish(state)

  defp fail_output(state, reason) do
    stop_in_flight(state.in_flight)

    state = %{
      state
      | connected?: false,
        status: :stopping,
        stop_reason: {:output_failed, reason},
        in_flight: nil,
        pending_frame: nil,
        cleanup: nil
    }

    state = fail_poll_waiter(state, {:output_failed, reason})
    send_backend_failure(state, {:output_failed, reason})
    maybe_finish(state)
  end

  defp disconnect_state(state, reason) do
    stop_in_flight(state.in_flight)

    state = %{
      state
      | connected?: false,
        status: :stopping,
        stop_reason: reason,
        in_flight: nil,
        pending_frame: nil,
        cleanup: nil
    }

    state = release_poll_waiter(state)
    if not state.runtime_stopped?, do: Runtime.shutdown(state.runtime)
    state = maybe_finish(state)
    session_reply(state)
  end

  defp send_backend_failure(%{runtime_stopped?: false, runtime: runtime}, reason) do
    send(runtime, {:backend_failed, {:backend, SSH, :input, reason}})
    :ok
  end

  defp send_backend_failure(_state, _reason), do: :ok

  defp fail_poll_waiter(%{poll_waiter: {from, _token, timer}} = state, reason) do
    _cancelled = Process.cancel_timer(timer)
    GenServer.reply(from, {:error, reason})
    %{state | poll_waiter: nil}
  end

  defp fail_poll_waiter(state, _reason), do: state

  defp release_poll_waiter(%{poll_waiter: {from, _token, timer}} = state) do
    _cancelled = Process.cancel_timer(timer)
    GenServer.reply(from, :timeout)
    %{state | poll_waiter: nil}
  end

  defp release_poll_waiter(state), do: state

  defp ensure_cleanup_after_runtime_exit(%{connected?: true, cleanup: nil} = state),
    do: queue_cleanup(state)

  defp ensure_cleanup_after_runtime_exit(state), do: state

  defp maybe_finish(
         %{
           status: :stopping,
           runtime_stopped?: true,
           in_flight: nil,
           pending_frame: nil,
           cleanup: nil
         } = state
       ) do
    unless state.notified? do
      send(state.owner, {:term_ui_ssh_closed, self(), state.stop_reason})
    end

    %{state | notified?: true}
  end

  defp maybe_finish(state), do: state

  defp session_reply(%{notified?: true} = state), do: {:stop, :normal, state}
  defp session_reply(state), do: {:noreply, state}

  defp invoke_output(output, data) do
    output.(data)
    |> normalize_output_result()
  rescue
    exception -> {:error, exception}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp normalize_output_result(:ok), do: :ok
  defp normalize_output_result({:error, _reason} = error), do: error
  defp normalize_output_result(other), do: {:error, {:invalid_output_result, other}}

  defp stop_in_flight(nil), do: :ok

  defp stop_in_flight(packet) do
    _cancelled = Process.cancel_timer(packet.timer)

    if is_pid(packet.worker) and Process.alive?(packet.worker) do
      Process.exit(packet.worker, :kill)
    end

    if packet.worker_monitor do
      Process.demonitor(packet.worker_monitor, [:flush])
    end

    :ok
  end

  defp cancel_poll_waiter(nil), do: :ok

  defp cancel_poll_waiter({from, _token, timer}) do
    _cancelled = Process.cancel_timer(timer)
    GenServer.reply(from, :timeout)
    :ok
  end

  defp cancel_timer(nil), do: :ok

  defp cancel_timer({timer, _token}) do
    _cancelled = Process.cancel_timer(timer)
    :ok
  end
end
