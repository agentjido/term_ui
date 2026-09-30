defmodule TermUI.Backend.EventStream do
  @moduledoc false

  alias TermUI.Backend.{InputBuffer, InputReader}
  alias TermUI.Event
  alias TermUI.Terminal.EscapeParser

  @escape_timeout 50
  @max_reads_per_poll 256
  @max_event_queue 100

  @doc "Polls one backend input source and returns one parsed event or timeout result."
  @spec poll(map(), non_neg_integer(), (-> InputReader.result()), module()) ::
          {:ok, TermUI.Backend.event(), map()}
          | {:timeout, map()}
          | {:error, term(), map()}
  def poll(state, timeout, read_fun, source) do
    case parse_buffer(state) do
      {:ok, event, state} ->
        {:ok, event, state}

      {:need_more, state} ->
        state = ensure_reader(state, read_fun)
        read_and_parse(state, timeout, source, 0)
    end
  end

  @doc "Stops the input reader stored in backend state, when one exists."
  @spec stop(map()) :: :ok
  def stop(state), do: InputReader.stop(Map.get(state, :input_reader))

  defp read_and_parse(state, timeout, source, reads) do
    case InputReader.take(state.input_reader, timeout) do
      {:ok, data} ->
        state =
          InputBuffer.append_with_limit(state, data, :input_buffer,
            source: source,
            paste_aware: true
          )

        case parse_buffer(state) do
          {:ok, event, state} ->
            {:ok, event, state}

          {:need_more, state} when reads + 1 < @max_reads_per_poll ->
            read_and_parse(state, partial_timeout(state), source, reads + 1)

          {:need_more, state} ->
            {:timeout, state}
        end

      :timeout ->
        resolve_timeout(state)

      :eof ->
        resolve_end_of_input(state)

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  defp parse_buffer(%{event_queue: [event | rest]} = state) do
    {:ok, event, %{state | event_queue: rest}}
  end

  defp parse_buffer(%{input_buffer: ""} = state), do: {:need_more, state}

  defp parse_buffer(state) do
    case EscapeParser.parse(state.input_buffer) do
      {[event | rest], remaining} ->
        {:ok, event, queue_events(%{state | input_buffer: remaining}, rest)}

      {[], remaining} ->
        {:need_more, %{state | input_buffer: remaining}}
    end
  end

  defp resolve_timeout(%{input_buffer: <<0x1B>>} = state) do
    {:ok, Event.key(:escape), %{state | input_buffer: ""}}
  end

  defp resolve_timeout(%{input_buffer: "\e[200~" <> _paste} = state) do
    {:timeout, state}
  end

  defp resolve_timeout(%{input_buffer: ""} = state), do: {:timeout, state}
  defp resolve_timeout(state), do: {:timeout, %{state | input_buffer: ""}}

  defp resolve_end_of_input(%{input_buffer: <<0x1B>>} = state) do
    {:ok, Event.key(:escape), %{state | input_buffer: ""}}
  end

  defp resolve_end_of_input(%{input_buffer: ""} = state), do: {:error, :eof, state}
  defp resolve_end_of_input(state), do: {:error, :eof, %{state | input_buffer: ""}}

  defp partial_timeout(%{input_buffer: ""}), do: 0
  defp partial_timeout(_state), do: @escape_timeout

  defp ensure_reader(%{input_reader: nil} = state, read_fun) do
    {:ok, reader} = InputReader.start_link(read_fun)
    %{state | input_reader: reader}
  end

  defp ensure_reader(state, _read_fun), do: state

  defp queue_events(state, []), do: state

  defp queue_events(state, events) do
    queue = Enum.take(state.event_queue ++ events, -@max_event_queue)
    %{state | event_queue: queue}
  end
end
