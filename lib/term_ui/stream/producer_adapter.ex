defmodule TermUI.Stream.ProducerAdapter do
  @moduledoc """
  A bounded producer bridge for an Elm application.

  Producers call `push/2` or `push_many/2`. The adapter sends at most one batch
  to the consumer at a time. The consumer must call `ack/2` before the next
  batch can enter its mailbox. The adapter owns only delivery state. The
  application still owns its `TermUI.Widget.Stream` state.

  Delivered messages have this form:

      {:term_ui_stream, adapter, reference, items}

  Set `:tag` to replace `:term_ui_stream`. A monitored producer failure is
  reported as `{tag, adapter, {:producer_down, producer, reason}}`.
  """

  use GenServer

  @type overflow :: :drop_oldest | :drop_newest | :reject
  @type t :: pid() | atom() | {:global, term()} | {:via, module(), term()}

  @overflows [:drop_oldest, :drop_newest, :reject]

  @enforce_keys [:consumer, :consumer_monitor]
  defstruct [
    :consumer,
    :consumer_monitor,
    tag: :term_ui_stream,
    limit: 1_000,
    batch_size: 25,
    overflow: :drop_oldest,
    buffer: [],
    in_flight: nil,
    in_flight_count: 0,
    paused: false,
    received_count: 0,
    dropped_count: 0,
    rejected_count: 0,
    producers: %{}
  ]

  @doc "Starts a producer adapter linked to the caller."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    _limit = positive!(Keyword.get(opts, :limit, 1_000), :limit)
    _batch_size = positive!(Keyword.get(opts, :batch_size, 25), :batch_size)
    _overflow = overflow!(Keyword.get(opts, :overflow, :drop_oldest))
    _consumer = consumer!(Keyword.get(opts, :consumer, self()))
    _tag = tag!(Keyword.get(opts, :tag, :term_ui_stream))

    {server_opts, init_opts} =
      Keyword.split(opts, [:name, :timeout, :debug, :spawn_opt, :hibernate_after])

    GenServer.start_link(__MODULE__, Keyword.put_new(init_opts, :consumer, self()), server_opts)
  end

  @doc "Offers one item with bounded backpressure at the adapter call boundary."
  @spec push(t(), term(), timeout()) :: :ok | {:error, :buffer_full}
  def push(adapter, item, timeout \\ 5_000), do: push_many(adapter, [item], timeout)

  @doc "Offers a batch with bounded backpressure at the adapter call boundary."
  @spec push_many(t(), Enumerable.t(), timeout()) :: :ok | {:error, :buffer_full}
  def push_many(adapter, items, timeout \\ 5_000),
    do: GenServer.call(adapter, {:push, Enum.to_list(items)}, timeout)

  @doc "Acknowledges the current batch and permits delivery of the next batch."
  @spec ack(t(), reference()) :: :ok | {:error, :unknown_batch}
  def ack(adapter, reference), do: GenServer.call(adapter, {:ack, reference})

  @doc "Pauses delivery while producers continue to use the bounded buffer."
  @spec pause(t()) :: :ok
  def pause(adapter), do: GenServer.call(adapter, :pause)

  @doc "Resumes delivery."
  @spec resume(t()) :: :ok
  def resume(adapter), do: GenServer.call(adapter, :resume)

  @doc "Monitors a producer and reports its termination to the consumer."
  @spec monitor_producer(t(), pid()) :: :ok
  def monitor_producer(adapter, producer) when is_pid(producer),
    do: GenServer.call(adapter, {:monitor_producer, producer})

  @doc "Returns buffer and delivery counters."
  @spec stats(t()) :: map()
  def stats(adapter), do: GenServer.call(adapter, :stats)

  @doc "Stops the adapter normally."
  @spec stop(t()) :: :ok
  def stop(adapter), do: GenServer.stop(adapter, :normal)

  @impl true
  def init(opts) do
    consumer = Keyword.get(opts, :consumer, self())
    limit = positive!(Keyword.get(opts, :limit, 1_000), :limit)
    batch_size = positive!(Keyword.get(opts, :batch_size, 25), :batch_size)
    overflow = overflow!(Keyword.get(opts, :overflow, :drop_oldest))

    {:ok,
     %__MODULE__{
       consumer: consumer,
       consumer_monitor: Process.monitor(consumer),
       tag: Keyword.get(opts, :tag, :term_ui_stream),
       limit: limit,
       batch_size: min(batch_size, limit),
       overflow: overflow
     }}
  end

  @impl true
  def handle_call({:push, items}, _from, state) do
    {state, result} = enqueue(state, items)
    {:reply, result, dispatch(state)}
  end

  def handle_call({:ack, reference}, _from, %{in_flight: reference} = state)
      when is_reference(reference) do
    state = %{state | in_flight: nil, in_flight_count: 0}
    {:reply, :ok, dispatch(state)}
  end

  def handle_call({:ack, _reference}, _from, state),
    do: {:reply, {:error, :unknown_batch}, state}

  def handle_call(:pause, _from, state), do: {:reply, :ok, %{state | paused: true}}

  def handle_call(:resume, _from, state) do
    state = %{state | paused: false}
    {:reply, :ok, dispatch(state)}
  end

  def handle_call({:monitor_producer, producer}, _from, state) do
    reference = Process.monitor(producer)
    {:reply, :ok, %{state | producers: Map.put(state.producers, reference, producer)}}
  end

  def handle_call(:stats, _from, state), do: {:reply, stats_map(state), state}

  @impl true
  def handle_info(
        {:DOWN, reference, :process, _pid, reason},
        %{consumer_monitor: reference} = state
      ),
      do: {:stop, {:shutdown, {:consumer_down, reason}}, state}

  def handle_info({:DOWN, reference, :process, producer, reason}, state) do
    case Map.pop(state.producers, reference) do
      {nil, _producers} ->
        {:noreply, state}

      {_producer, producers} ->
        send(state.consumer, {state.tag, self(), {:producer_down, producer, reason}})
        {:noreply, %{state | producers: producers}}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp enqueue(state, items) do
    offered = length(items)
    capacity = max(state.limit - state.in_flight_count, 0)

    {buffer, dropped, rejected, result} =
      case state.overflow do
        :drop_oldest ->
          combined = state.buffer ++ items
          dropped = max(length(combined) - capacity, 0)
          {Enum.take(combined, -capacity), dropped, 0, :ok}

        :drop_newest ->
          accepted = Enum.take(items, max(capacity - length(state.buffer), 0))
          dropped = offered - length(accepted)
          {state.buffer ++ accepted, dropped, 0, :ok}

        :reject ->
          if length(state.buffer) + offered <= capacity,
            do: {state.buffer ++ items, 0, 0, :ok},
            else: {state.buffer, 0, offered, {:error, :buffer_full}}
      end

    next = %{
      state
      | buffer: buffer,
        received_count: state.received_count + offered,
        dropped_count: state.dropped_count + dropped,
        rejected_count: state.rejected_count + rejected
    }

    {next, result}
  end

  defp dispatch(%{paused: true} = state), do: state
  defp dispatch(%{in_flight: reference} = state) when is_reference(reference), do: state
  defp dispatch(%{buffer: []} = state), do: state

  defp dispatch(state) do
    {batch, rest} = Enum.split(state.buffer, state.batch_size)
    reference = make_ref()
    send(state.consumer, {state.tag, self(), reference, batch})
    %{state | buffer: rest, in_flight: reference, in_flight_count: length(batch)}
  end

  defp stats_map(state) do
    %{
      buffered: length(state.buffer),
      in_flight: state.in_flight_count,
      limit: state.limit,
      batch_size: state.batch_size,
      overflow: state.overflow,
      paused: state.paused,
      received: state.received_count,
      dropped: state.dropped_count,
      rejected: state.rejected_count
    }
  end

  defp positive!(value, _name) when is_integer(value) and value > 0, do: value

  defp positive!(value, name),
    do: raise(ArgumentError, "#{name} must be a positive integer, got: #{inspect(value)}")

  defp overflow!(overflow) when overflow in @overflows, do: overflow

  defp overflow!(overflow),
    do:
      raise(
        ArgumentError,
        "overflow must be :drop_oldest, :drop_newest, or :reject, got: #{inspect(overflow)}"
      )

  defp consumer!(consumer) when is_pid(consumer), do: consumer

  defp consumer!(consumer),
    do: raise(ArgumentError, "consumer must be a pid, got: #{inspect(consumer)}")

  defp tag!(tag) when is_atom(tag), do: tag
  defp tag!(tag), do: raise(ArgumentError, "tag must be an atom, got: #{inspect(tag)}")
end
