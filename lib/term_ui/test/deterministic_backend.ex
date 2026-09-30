defmodule TermUI.Test.DeterministicBackend do
  @moduledoc """
  A deterministic backend for v2 application tests.

  The backend uses fixed terminal dimensions and explicit capabilities. It
  performs no terminal I/O and does not call the TTY NIF. Each draw captures a
  complete `TermUI.Frame` and sends it to the process in the required `:owner`
  option.

  Start an application with this backend:

      {:ok, runtime} =
        TermUI.start_link(MyApp,
          backend: {
            TermUI.Test.DeterministicBackend,
            owner: self(),
            size: {12, 40},
            capabilities: %{colors: :ansi_16, unicode: true}
          }
        )

      assert_receive {:backend, :draw, %TermUI.Frame{} = frame}
      :ok = TermUI.Test.DeterministicBackend.send_event(runtime, TermUI.Event.key(:enter))

  `:size` uses the backend order `{rows, columns}`. The default is `{6, 20}`.
  The default capabilities are `%{colors: :true_color, unicode: true}`. The
  optional `:events` list is delivered before injected events.

  The owner can receive these messages:

  - `{:backend, :init, backend_owner}` after initialization.
  - `{:backend, :draw, frame}` for each complete frame.
  - `{:backend, :flush, frame_count}` after a flush.
  - `{:backend, :resize, {rows, columns}}` after a resize.
  - `{:backend, :clipboard, operation}` for a clipboard command.
  - `{:backend, :shutdown, reason}` during cleanup.
  - `{:backend, :shutdown_snapshot, snapshot}` with all captured state.

  A shutdown snapshot contains the final size, capabilities, complete frames
  in draw order, pending events, queued-event count, clipboard operations,
  flush count, and shutdown reason.
  """

  @behaviour TermUI.Backend

  alias TermUI.{Clipboard.Operation, Event, Frame}

  @type snapshot :: %{
          size: TermUI.Backend.size(),
          capabilities: map(),
          frames: [Frame.t()],
          pending_events: [Event.t()],
          queued_events_delivered: non_neg_integer(),
          clipboard_operations: [Operation.t()],
          flushes: non_neg_integer(),
          shutdown_reason: term()
        }

  @type state :: %{
          owner: pid(),
          size: TermUI.Backend.size(),
          capabilities: map(),
          events: [Event.t()],
          queued_events_delivered: non_neg_integer(),
          frames: [Frame.t()],
          clipboard_operations: [Operation.t()],
          flushes: non_neg_integer(),
          fail: atom() | nil
        }

  @doc "Sends one normalized event to a running v2 runtime."
  @spec send_event(pid(), Event.t()) :: :ok
  def send_event(runtime, event) when is_pid(runtime) do
    event = Zoi.parse!(Event.schema(), event)
    send(runtime, {:backend_event, event})
    :ok
  end

  @doc "Sends a resize event in application order: width, then height."
  @spec resize(pid(), pos_integer(), pos_integer()) :: :ok
  def resize(runtime, width, height) when is_pid(runtime) do
    send_event(runtime, Event.resize(width, height))
  end

  @impl true
  @doc false
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    send(owner, {:backend, :init, self()})

    {:ok,
     %{
       owner: owner,
       size: Keyword.get(opts, :size, {6, 20}),
       capabilities: Keyword.get(opts, :capabilities, %{colors: :true_color, unicode: true}),
       events: Keyword.get(opts, :events, []),
       queued_events_delivered: 0,
       frames: [],
       clipboard_operations: [],
       flushes: 0,
       fail: Keyword.get(opts, :fail)
     }}
  end

  @impl true
  @doc false
  def size(%{fail: :size}), do: {:error, :size_failed}
  def size(state), do: {:ok, state.size}

  @impl true
  @doc false
  def capabilities(%{fail: :capabilities}), do: raise("capabilities failed")
  def capabilities(state), do: state.capabilities

  @impl true
  @doc false
  def draw(%{fail: :draw}, _frame), do: {:error, :draw_failed}

  def draw(state, %Frame{} = frame) do
    send(state.owner, {:backend, :draw, frame})
    {:ok, %{state | frames: [frame | state.frames]}}
  end

  @impl true
  @doc false
  def flush(%{fail: :flush}), do: {:error, :flush_failed}

  def flush(state) do
    send(state.owner, {:backend, :flush, length(state.frames)})
    {:ok, %{state | flushes: state.flushes + 1}}
  end

  @impl true
  @doc false
  def clipboard(%{fail: :clipboard}, _operation), do: {:error, :clipboard_failed}

  def clipboard(state, %Operation{} = operation) do
    send(state.owner, {:backend, :clipboard, operation})
    {:ok, %{state | clipboard_operations: [operation | state.clipboard_operations]}}
  end

  @impl true
  @doc false
  def poll_event(%{fail: :input} = state, _timeout), do: {:error, :input_failed, state}

  def poll_event(%{events: [event | rest]} = state, _timeout) do
    {:ok, event,
     %{state | events: rest, queued_events_delivered: state.queued_events_delivered + 1}}
  end

  def poll_event(state, timeout) do
    receive do
    after
      timeout -> {:timeout, state}
    end
  end

  @impl true
  @doc false
  def resize(%{fail: :resize}, _size), do: {:error, :resize_failed}

  def resize(state, size) do
    send(state.owner, {:backend, :resize, size})
    {:ok, %{state | size: size}}
  end

  @impl true
  @doc false
  def shutdown(state, reason) do
    send(state.owner, {:backend, :shutdown, reason})
    send(state.owner, {:backend, :shutdown_state, length(state.events), length(state.frames)})
    send(state.owner, {:backend, :shutdown_snapshot, snapshot(state, reason)})
    :ok
  end

  defp snapshot(state, reason) do
    %{
      size: state.size,
      capabilities: state.capabilities,
      frames: Enum.reverse(state.frames),
      pending_events: state.events,
      queued_events_delivered: state.queued_events_delivered,
      clipboard_operations: Enum.reverse(state.clipboard_operations),
      flushes: state.flushes,
      shutdown_reason: reason
    }
  end
end
