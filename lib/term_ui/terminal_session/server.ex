defmodule TermUI.TerminalSession.Server do
  @moduledoc false
  use GenServer

  alias TermUI.Event
  alias TermUI.TerminalSession.{Frame, Ghostty}

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    driver = Keyword.get(opts, :driver, Ghostty)
    owner = Keyword.fetch!(opts, :owner)
    size = Keyword.get(opts, :size, {24, 80})
    timeout = Keyword.get(opts, :output_timeout, 5_000)
    scrollback = Keyword.get(opts, :scrollback, 1_000)

    with :ok <- validate_options(owner, size, timeout, scrollback),
         :ok <- driver.available(),
         {:ok, terminal, pty} <- start_children(driver, opts, size, scrollback) do
      send(self(), :render)

      {:ok,
       %{
         driver: driver,
         owner: owner,
         owner_monitor: Process.monitor(owner),
         terminal: terminal,
         pty: pty,
         size: size,
         timeout: timeout,
         render_timer: nil,
         sequence: 0,
         in_flight: nil,
         pending: nil,
         exit_status: nil,
         reason: :normal
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp validate_options(owner, {rows, columns}, timeout, scrollback)
       when is_pid(owner) and is_integer(rows) and rows in 1..120 and is_integer(columns) and
              columns in 1..300 and is_integer(timeout) and timeout > 0 and
              is_integer(scrollback) and scrollback in 0..10_000,
       do: :ok

  defp validate_options(_owner, _size, _timeout, _scrollback),
    do: {:error, :invalid_session_options}

  defp start_children(driver, opts, {rows, columns}, scrollback) do
    case driver.start_terminal(cols: columns, rows: rows, max_scrollback: scrollback) do
      {:ok, terminal} ->
        pty_opts =
          opts
          |> Keyword.take([:cmd, :args, :reader_start_timeout])
          |> Keyword.merge(cols: columns, rows: rows)

        case driver.start_pty(pty_opts) do
          {:ok, pty} ->
            {:ok, terminal, pty}

          {:error, reason} ->
            driver.stop(terminal)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_call(:info, _from, state) do
    info = %{
      terminal: state.terminal,
      pty: state.pty,
      size: state.size,
      exit_status: state.exit_status,
      output_queue: %{
        capacity: 2,
        in_flight: if(state.in_flight, do: 1, else: 0),
        pending_frames: if(state.pending, do: 1, else: 0)
      }
    }

    {:reply, info, state}
  end

  def handle_call({:input, event}, _from, state) do
    {result, state} = input(event, state)
    {:reply, result, state}
  end

  def handle_call({:ack, sequence}, _from, state) do
    case acknowledge(sequence, state) do
      {:ok, state} -> reply(:ok, state)
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info({:terminal_input, event}, state) do
    {result, state} = input(event, state)
    if result != :ok, do: send(state.owner, {:term_ui_terminal_error, self(), result})
    {:noreply, state}
  end

  def handle_info({:terminal_ack, sequence}, state) do
    case acknowledge(sequence, state) do
      {:ok, state} ->
        noreply(state)

      {:error, reason} ->
        send(state.owner, {:term_ui_terminal_error, self(), {:error, reason}})
        {:noreply, state}
    end
  end

  def handle_info(:terminal_stop, state), do: {:stop, :normal, state}

  def handle_info({:data, bytes}, state) when is_binary(bytes) and byte_size(bytes) <= 65_536 do
    {:message_queue_len, count} = Process.info(self(), :message_queue_len)

    if count > 1_024 do
      {:stop, :normal, %{state | reason: :input_overflow}}
    else
      :ok = state.driver.write_terminal(state.terminal, bytes)
      {:noreply, schedule_render(state)}
    end
  end

  def handle_info({:data, _bytes}, state),
    do: {:stop, :normal, %{state | reason: :output_chunk_limit}}

  def handle_info({:pty_write, bytes}, state) do
    :ok = state.driver.write_pty(state.pty, bytes)
    {:noreply, state}
  end

  def handle_info(:render, state) do
    snapshot = state.driver.snapshot(state.terminal)
    frame = Frame.from_snapshot(snapshot, state.size)
    metadata = Map.take(snapshot, [:cursor, :scrollbar, :mouse, :focus_reporting])
    state = %{state | render_timer: nil}
    pair = {frame, metadata}
    state = if state.in_flight, do: %{state | pending: pair}, else: dispatch(pair, state)
    {:noreply, state}
  end

  def handle_info({:exit, status}, state) when is_integer(status) do
    {:noreply, schedule_render(%{state | exit_status: status})}
  end

  def handle_info({:output_timeout, token}, %{in_flight: {_seq, token, _timer}} = state),
    do: {:stop, :normal, %{state | reason: :output_timeout}}

  def handle_info(
        {:DOWN, ref, :process, owner, _reason},
        %{owner_monitor: ref, owner: owner} = state
      ),
      do: {:stop, :normal, %{state | reason: :owner_down}}

  def handle_info({:EXIT, child, reason}, state)
      when child == state.terminal or child == state.pty,
      do: {:stop, :normal, %{state | reason: {:child_exit, reason}}}

  def handle_info(message, state) when message in [:bell, :title_changed] do
    send(state.owner, {:term_ui_terminal_effect, self(), message})
    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(reason, state) do
    state.driver.stop(state.pty)
    state.driver.stop(state.terminal)

    reason =
      cond do
        reason != :normal -> {:session_failure, reason}
        state.reason != :normal -> state.reason
        state.exit_status != nil -> {:exit, state.exit_status}
        true -> :normal
      end

    send(state.owner, {:term_ui_terminal_closed, self(), reason})
  end

  defp input(_event, %{exit_status: status} = state) when status != nil,
    do: {{:error, :child_exited}, state}

  defp input(%Event.Resize{width: columns, height: rows}, state)
       when rows in 1..120 and columns in 1..300 do
    :ok = state.driver.resize_terminal(state.terminal, columns, rows)
    :ok = state.driver.resize_pty(state.pty, columns, rows)
    {:ok, schedule_render(%{state | size: {rows, columns}})}
  end

  defp input(%Event.Mouse{action: action}, state) when action in [:scroll_up, :scroll_down] do
    delta = if action == :scroll_up, do: -3, else: 3
    :ok = state.driver.scroll(state.terminal, delta)
    {:ok, schedule_render(state)}
  end

  defp input(%Event.Paste{content: content}, state)
       when is_binary(content) and byte_size(content) <= 65_536 do
    state.driver.paste(state.terminal, state.pty, content) |> write_input(state)
  end

  defp input(%Event.Text{text: text} = event, state)
       when is_binary(text) and byte_size(text) in 1..4_096 do
    state.driver.key(state.terminal, event) |> write_input(state)
  end

  defp input(%Event.Key{} = event, state) do
    state.driver.key(state.terminal, event) |> write_input(state)
  end

  defp input(%Event.Mouse{x: x, y: y} = event, state)
       when x < elem(state.size, 1) and y < elem(state.size, 0) do
    state.driver.mouse(state.terminal, event) |> write_input(state)
  end

  defp input(%Event.Focus{} = event, state) do
    state.driver.focus(state.terminal, event) |> write_input(state)
  end

  defp input(_event, state), do: {{:error, :invalid_input}, state}

  defp write_input({:ok, bytes}, state), do: {state.driver.write_pty(state.pty, bytes), state}
  defp write_input(:none, state), do: {:ok, state}
  defp write_input({:error, reason}, state), do: {{:error, reason}, state}

  defp schedule_render(%{render_timer: nil} = state),
    do: %{state | render_timer: Process.send_after(self(), :render, 16)}

  defp schedule_render(state), do: state

  defp dispatch({frame, metadata}, state) do
    sequence = state.sequence + 1
    token = make_ref()
    timer = Process.send_after(self(), {:output_timeout, token}, state.timeout)
    send(state.owner, {:term_ui_terminal_frame, self(), sequence, frame, metadata})
    %{state | sequence: sequence, in_flight: {sequence, token, timer}, pending: nil}
  end

  defp acknowledge(sequence, %{in_flight: {sequence, _token, timer}} = state) do
    _ = Process.cancel_timer(timer)
    state = %{state | in_flight: nil}
    state = if state.pending, do: dispatch(state.pending, state), else: state
    {:ok, state}
  end

  defp acknowledge(sequence, state) when is_integer(sequence) and sequence > 0 do
    if sequence <= state.sequence, do: {:ok, state}, else: {:error, :future_acknowledgement}
  end

  defp acknowledge(_sequence, _state), do: {:error, :invalid_acknowledgement}

  defp finished?(state),
    do: state.exit_status != nil and state.in_flight == nil and state.render_timer == nil

  defp reply(result, state) do
    if finished?(state), do: {:stop, :normal, result, state}, else: {:reply, result, state}
  end

  defp noreply(state) do
    if finished?(state), do: {:stop, :normal, state}, else: {:noreply, state}
  end
end
