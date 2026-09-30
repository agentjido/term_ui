defmodule TermUI.WebBackend.Session do
  @moduledoc false
  use GenServer

  alias TermUI.{Event, Frame, Runtime, WebBackend}
  alias TermUI.WebBackend.Protocol

  @maximum_events 1_024
  @default_output_timeout 5_000

  @impl true
  def init({root, opts}) do
    Process.flag(:trap_exit, true)

    with {:ok, limits} <- Protocol.limits(Keyword.get(opts, :limits, %{})),
         {:ok, size} <- Protocol.size(Keyword.get(opts, :size, {24, 80}), limits),
         {:ok, owner} <- process_option(opts, :owner),
         {:ok, output} <- process_option(opts, :output),
         {:ok, timeout} <- output_timeout(opts) do
      capabilities = %{
        dimensions: size,
        colors: :true_color,
        unicode: true,
        mouse: true,
        paste: true,
        focus: true,
        remote: :web
      }

      runtime_opts =
        opts
        |> Keyword.get(:runtime_options, [])
        |> Keyword.put(:root, root)
        |> Keyword.put(
          :backend,
          {WebBackend, session: self(), size: size, capabilities: capabilities, limits: limits}
        )
        |> Keyword.put(:backend_opts, size_poll_interval: :disabled)

      case Runtime.start_link(runtime_opts) do
        {:ok, runtime} ->
          {:ok,
           %{
             runtime: runtime,
             owner: owner,
             owner_monitor: Process.monitor(owner),
             output: output,
             output_timeout: timeout,
             limits: limits,
             size: size,
             capabilities: capabilities,
             status: :running,
             connected?: true,
             notify?: true,
             runtime_stopped?: false,
             reason: :normal,
             events: :queue.new(),
             event_count: 0,
             waiter: nil,
             sequence: 0,
             confirmed_sequence: nil,
             confirmed_frame: nil,
             current_frame: nil,
             in_flight: nil,
             pending_frame: nil,
             full?: true
           }}

        {:error, reason} ->
          {:stop, reason}
      end
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:info, _from, state) do
    info = %{
      runtime: state.runtime,
      size: state.size,
      capabilities: state.capabilities,
      status: state.status,
      connected?: state.connected?,
      queued_events: state.event_count,
      confirmed_sequence: state.confirmed_sequence,
      output_queue: %{
        capacity: 2,
        in_flight: if(state.in_flight, do: 1, else: 0),
        pending_frames: if(state.pending_frame, do: 1, else: 0)
      }
    }

    {:reply, info, state}
  end

  def handle_call({:input, %{"v" => 1, "type" => "ack", "seq" => sequence}}, _from, state)
      when is_integer(sequence) and sequence > 0 do
    case acknowledge(state, sequence) do
      {:ok, state} -> reply(:ok, state)
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:input, %{"v" => 1, "type" => "resync"}}, _from, %{status: :running} = state) do
    state = clear_output(state)

    state = %{
      state
      | full?: true,
        confirmed_sequence: nil,
        confirmed_frame: nil,
        pending_frame: nil
    }

    state = if state.current_frame, do: dispatch(state, state.current_frame), else: state
    {:reply, :ok, state}
  end

  def handle_call({:input, _payload}, _from, %{status: :stopping} = state),
    do: {:reply, {:error, :stopping}, state}

  def handle_call({:input, payload}, _from, state) do
    with {:ok, event} <- Protocol.event(payload, state.size, state.limits),
         {:ok, state} <- enqueue(state, event) do
      {:reply, :ok, deliver_waiter(state)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:frame, _frame}, _from, %{connected?: false} = state),
    do: {:reply, :ok, state}

  def handle_call({:frame, %Frame{} = frame}, _from, state) do
    case Protocol.size({frame.height, frame.width}, state.limits) do
      {:ok, _size} ->
        state = %{state | current_frame: frame}

        state =
          if state.in_flight, do: %{state | pending_frame: frame}, else: dispatch(state, frame)

        {:reply, :ok, state}

      {:error, _reason} ->
        {:reply, {:error, :frame_size_limit}, state}
    end
  end

  def handle_call(:invalidate, _from, state), do: {:reply, :ok, %{state | full?: true}}

  def handle_call({:poll, _timeout}, _from, %{event_count: count} = state) when count > 0 do
    {{:value, event}, events} = :queue.out(state.events)
    {:reply, {:ok, event}, %{state | events: events, event_count: count - 1}}
  end

  def handle_call({:poll, 0}, _from, state), do: {:reply, :timeout, state}

  def handle_call({:poll, timeout}, from, %{waiter: nil} = state) do
    token = make_ref()
    timer = Process.send_after(self(), {:poll_timeout, token}, timeout)
    {:noreply, %{state | waiter: {from, token, timer}}}
  end

  def handle_call({:poll, _timeout}, _from, state),
    do: {:reply, {:error, :poll_in_progress}, state}

  def handle_call(:stop, _from, state) do
    Runtime.shutdown(state.runtime)
    reply(:ok, %{state | status: :stopping})
  end

  def handle_call({:backend_shutdown, reason}, _from, state) do
    reason = if state.reason == :normal, do: reason, else: state.reason
    reply(:ok, %{state | status: :stopping, reason: reason})
  end

  @impl true
  def handle_cast({:disconnect, reason}, state), do: noreply(disconnect(state, reason))

  @impl true
  def handle_info({:output_timeout, sequence}, %{in_flight: %{sequence: sequence}} = state) do
    state = disconnect(state, :output_timeout)
    # The transport still exists. It receives a close message after runtime cleanup.
    noreply(%{state | notify?: true})
  end

  def handle_info({:output_timeout, _old_sequence}, state), do: {:noreply, state}

  def handle_info({:poll_timeout, token}, %{waiter: {from, token, _timer}} = state) do
    GenServer.reply(from, :timeout)
    {:noreply, %{state | waiter: nil}}
  end

  def handle_info({:poll_timeout, _old_token}, state), do: {:noreply, state}

  def handle_info(
        {:DOWN, monitor, :process, owner, reason},
        %{owner_monitor: monitor, owner: owner} = state
      ),
      do: noreply(disconnect(state, {:owner_exit, reason}))

  def handle_info({:EXIT, runtime, reason}, %{runtime: runtime} = state) do
    reason = if state.reason == :normal, do: reason, else: state.reason
    noreply(%{state | runtime_stopped?: true, status: :stopping, reason: reason})
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _state = clear_output(state)
    reply_waiter(state.waiter, {:error, :session_closed})
    Process.demonitor(state.owner_monitor, [:flush])
    if Process.alive?(state.runtime), do: Runtime.shutdown(state.runtime)
    :ok
  end

  defp acknowledge(%{in_flight: %{sequence: sequence} = packet} = state, sequence) do
    state = clear_output(state)

    state = %{
      state
      | confirmed_sequence: sequence,
        confirmed_frame: packet.frame
    }

    state =
      if state.pending_frame do
        dispatch(%{state | pending_frame: nil}, state.pending_frame)
      else
        state
      end

    {:ok, state}
  end

  defp acknowledge(state, sequence) when sequence <= state.sequence, do: {:ok, state}
  defp acknowledge(_state, _sequence), do: {:error, :invalid_acknowledgement}

  defp dispatch(state, frame) do
    sequence = state.sequence + 1
    previous = if state.full?, do: nil, else: state.confirmed_frame
    payload = Protocol.frame(previous, frame, sequence, state.confirmed_sequence)
    send(state.output, {:term_ui_web_output, self(), payload})
    timer = Process.send_after(self(), {:output_timeout, sequence}, state.output_timeout)
    packet = %{sequence: sequence, frame: frame, timer: timer}
    %{state | sequence: sequence, in_flight: packet, full?: false}
  end

  defp clear_output(%{in_flight: nil} = state), do: state

  defp clear_output(state) do
    _ = Process.cancel_timer(state.in_flight.timer)
    %{state | in_flight: nil}
  end

  defp enqueue(%{event_count: @maximum_events}, _event), do: {:error, :input_queue_full}

  defp enqueue(state, %Event.Resize{width: width, height: height} = event) do
    size = {height, width}
    state = %{state | size: size, capabilities: Map.put(state.capabilities, :dimensions, size)}
    enqueue_event(state, event)
  end

  defp enqueue(state, event), do: enqueue_event(state, event)

  defp enqueue_event(state, event) do
    {:ok, %{state | events: :queue.in(event, state.events), event_count: state.event_count + 1}}
  end

  defp deliver_waiter(%{waiter: nil} = state), do: state

  defp deliver_waiter(state) do
    {{:value, event}, events} = :queue.out(state.events)
    reply_waiter(state.waiter, {:ok, event})
    %{state | waiter: nil, events: events, event_count: state.event_count - 1}
  end

  defp reply_waiter(nil, _result), do: :ok

  defp reply_waiter({from, _token, timer}, result) do
    _ = Process.cancel_timer(timer)
    GenServer.reply(from, result)
  end

  defp disconnect(state, reason) do
    state = clear_output(state)
    Runtime.shutdown(state.runtime)
    reply_waiter(state.waiter, {:error, :disconnected})

    %{
      state
      | status: :stopping,
        connected?: false,
        notify?: false,
        reason: reason,
        pending_frame: nil,
        waiter: nil,
        events: :queue.new(),
        event_count: 0
    }
  end

  defp reply(result, state) do
    if finished?(state) do
      notify_closed(state)
      {:stop, :normal, result, state}
    else
      {:reply, result, state}
    end
  end

  defp noreply(state) do
    if finished?(state) do
      notify_closed(state)
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  defp finished?(state),
    do: state.runtime_stopped? and is_nil(state.in_flight) and is_nil(state.pending_frame)

  defp notify_closed(%{notify?: true} = state) do
    reason = if state.reason in [:normal, :shutdown], do: "normal", else: "error"
    payload = %{"v" => 1, "type" => "closed", "reason" => reason}
    send(state.output, {:term_ui_web_output, self(), payload})
  end

  defp notify_closed(_state), do: :ok

  defp process_option(opts, key) do
    case Keyword.get(opts, key) do
      process when is_pid(process) ->
        if Process.alive?(process), do: {:ok, process}, else: {:error, {:dead_process, key}}

      _invalid ->
        {:error, {:invalid_process, key}}
    end
  end

  defp output_timeout(opts) do
    case Keyword.get(opts, :output_timeout, @default_output_timeout) do
      timeout when is_integer(timeout) and timeout > 0 -> {:ok, timeout}
      _invalid -> {:error, :invalid_output_timeout}
    end
  end
end
