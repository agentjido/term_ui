defmodule TermUI.Backend.InputLifecycleTest do
  use ExUnit.Case, async: true

  alias TermUI.Backend.{EventStream, InputReader}
  alias TermUI.Event

  test "event stream returns queued and newly parsed events in order" do
    queued = Event.key(:enter)
    state = stream_state(event_queue: [queued])

    assert {:ok, ^queued, state} = EventStream.poll(state, 0, fn -> :eof end, __MODULE__)
    assert state.event_queue == []
    assert state.input_reader == nil

    {read_fun, agent} = queued_reader([{:ok, "ab"}])

    assert {:ok, %Event.Text{text: "a"}, state} =
             EventStream.poll(stream_state(), 20, read_fun, __MODULE__)

    assert {:ok, %Event.Text{text: "b"}, state} =
             EventStream.poll(state, 20, read_fun, __MODULE__)

    assert :ok = EventStream.stop(state)
    Agent.stop(agent)
  end

  test "event stream resolves escape, eof, errors, and partial input" do
    {escape_fun, escape_agent} = queued_reader([{:ok, "\e"}, :eof])

    assert {:ok, %Event.Key{key: :escape}, escaped} =
             EventStream.poll(stream_state(), 20, escape_fun, __MODULE__)

    assert escaped.input_buffer == ""
    EventStream.stop(escaped)
    Agent.stop(escape_agent)

    {eof_fun, eof_agent} = queued_reader([:eof])
    assert {:error, :eof, eof_state} = EventStream.poll(stream_state(), 20, eof_fun, __MODULE__)
    EventStream.stop(eof_state)
    Agent.stop(eof_agent)

    {partial_fun, partial_agent} = queued_reader([{:ok, "\e["}, :eof])

    assert {:error, :eof, partial_state} =
             EventStream.poll(stream_state(), 20, partial_fun, __MODULE__)

    assert partial_state.input_buffer == ""
    EventStream.stop(partial_state)
    Agent.stop(partial_agent)

    {error_fun, error_agent} = queued_reader([{:error, :closed}])

    assert {:error, :closed, error_state} =
             EventStream.poll(stream_state(), 20, error_fun, __MODULE__)

    EventStream.stop(error_state)
    Agent.stop(error_agent)
  end

  test "event stream timeouts retain paste input and discard other fragments" do
    owner = self()

    blocking = fn ->
      send(owner, {:reader_waiting, self()})

      receive do
        {:reader_result, result} -> result
      end
    end

    assert {:timeout, empty} = EventStream.poll(stream_state(), 0, blocking, __MODULE__)
    assert empty.input_buffer == ""
    EventStream.stop(empty)

    assert {:timeout, partial} =
             EventStream.poll(stream_state(input_buffer: "\e["), 0, blocking, __MODULE__)

    assert partial.input_buffer == ""
    EventStream.stop(partial)

    paste = "\e[200~unfinished"

    assert {:timeout, retained} =
             EventStream.poll(stream_state(input_buffer: paste), 0, blocking, __MODULE__)

    assert retained.input_buffer == paste
    EventStream.stop(retained)
    assert :ok = EventStream.stop(stream_state())
  end

  test "input reader delivers cached and waiting results and handles timeout safely" do
    owner = self()

    assert {:ok, cached_reader} =
             InputReader.start_link(fn ->
               send(owner, :cached_read)
               {:ok, "x"}
             end)

    assert_receive :cached_read
    Process.sleep(5)
    assert {:ok, "x"} = InputReader.take(cached_reader, 10)
    assert :ok = InputReader.stop(cached_reader)

    assert {:ok, waiting_reader} =
             InputReader.start_link(fn ->
               send(owner, {:waiting_read, self()})

               receive do
                 {:result, result} -> result
               end
             end)

    assert_receive {:waiting_read, worker}
    assert :timeout = InputReader.take(waiting_reader, 0)

    task = Task.async(fn -> InputReader.take(waiting_reader, 100) end)
    send(worker, {:result, :eof})
    assert :eof = Task.await(task)
    assert :ok = InputReader.stop(waiting_reader)
    assert :ok = InputReader.stop(waiting_reader)
    assert :ok = InputReader.stop(nil)
  end

  test "input reader replies after a finite waiter timeout" do
    assert {:ok, reader} = InputReader.start_link(fn -> Process.sleep(:infinity) end)
    assert :timeout = InputReader.take(reader, 10)
    assert :ok = InputReader.stop(reader)
  end

  defp stream_state(overrides \\ []) do
    Map.merge(
      %{input_buffer: "", event_queue: [], paste_state: nil, input_reader: nil},
      Map.new(overrides)
    )
  end

  defp queued_reader(results) do
    {:ok, agent} = Agent.start_link(fn -> results end)

    read_fun = fn ->
      Agent.get_and_update(agent, fn
        [result | rest] -> {result, rest}
        [] -> {:eof, []}
      end)
    end

    {read_fun, agent}
  end
end
