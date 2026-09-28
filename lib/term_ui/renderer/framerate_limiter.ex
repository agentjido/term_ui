defmodule TermUI.Renderer.FramerateLimiter do
  @moduledoc """
  Caps rendering to a maximum FPS with dirty flag coalescing.

  The FramerateLimiter schedules render cycles at regular intervals (default 60 FPS)
  and only renders when the buffer is dirty. Multiple buffer writes between frames
  coalesce into a single render, creating smooth animation while being efficient.

  This is an opt-in limiter. `TermUI.Runtime` implements its own
  `render_interval` timer and dirty-state check and does not start or call this
  module.

  ## Features

    * **Frame timing** - Configurable FPS (30, 60, 120)
    * **Drift compensation** - Adjusts intervals based on actual elapsed time
    * **Dirty coalescing** - Multiple writes become single render
    * **Immediate mode** - Bypass frame timing for urgent updates
    * **Performance metrics** - Tracks FPS, render time, skip ratio

  ## Usage

      # Start with default 60 FPS
      {:ok, pid} = FramerateLimiter.start_link(render_callback: fn -> :ok end)

      # Start with custom FPS
      {:ok, pid} = FramerateLimiter.start_link(fps: 120, render_callback: fn -> :ok end)

      # Mark buffer as dirty (triggers render on next tick)
      FramerateLimiter.mark_dirty()

      # Force immediate render
      FramerateLimiter.render_immediate()

      # Get performance metrics
      FramerateLimiter.stats()

  ## Render Callback

  The render callback is invoked on each frame tick when the buffer is dirty.
  It should perform the actual rendering work (diff, cursor optimization, etc.).
  """

  use GenServer

  @type fps :: 30 | 60 | 120

  @type stats :: %{
          rendered_frames: non_neg_integer(),
          skipped_frames: non_neg_integer(),
          total_frames: non_neg_integer(),
          actual_fps: float(),
          avg_render_time_us: float(),
          slow_frames: non_neg_integer()
        }

  @type t :: %__MODULE__{
          fps: fps(),
          interval_ms: float(),
          render_callback: (-> any()),
          dirty_check: (-> boolean()),
          dirty_clear: (-> :ok),
          paused: boolean(),
          timer_ref: reference() | nil,
          last_tick: integer(),
          rendered_frames: non_neg_integer(),
          skipped_frames: non_neg_integer(),
          render_times: [non_neg_integer()],
          slow_frames: non_neg_integer(),
          frame_timestamps: [integer()],
          internal_dirty: :atomics.atomics_ref() | nil
        }

  defstruct fps: 60,
            interval_ms: 16.67,
            render_callback: nil,
            dirty_check: nil,
            dirty_clear: nil,
            paused: false,
            timer_ref: nil,
            last_tick: 0,
            rendered_frames: 0,
            skipped_frames: 0,
            render_times: [],
            slow_frames: 0,
            frame_timestamps: [],
            internal_dirty: nil

  # Dialyzer: Functions with unmatched return values
  @dialyzer {:nowarn_function, schedule_tick: 1, calculate_stats: 1, handle_call: 3}

  # Client API

  @doc """
  Starts the FramerateLimiter.

  ## Options

    * `:fps` - Target FPS: 30, 60, or 120 (default: 60)
    * `:render_callback` - Function to call for rendering (required)
    * `:dirty_check` - Function returning true if render needed (optional)
    * `:dirty_clear` - Function to clear dirty flag after render (optional)
    * `:name` - GenServer name (default: `__MODULE__`)

  If `:dirty_check` and `:dirty_clear` are not provided, an internal dirty flag
  is created. For integration with BufferManager, pass its dirty functions:

  ## Examples

      # Standalone with internal dirty flag
      {:ok, pid} = FramerateLimiter.start_link(
        fps: 60,
        render_callback: fn -> render_frame() end
      )

      # With BufferManager integration
      {:ok, pid} = FramerateLimiter.start_link(
        fps: 60,
        render_callback: fn -> render_frame() end,
        dirty_check: fn -> BufferManager.dirty?(manager) end,
        dirty_clear: fn -> BufferManager.clear_dirty(manager) end
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Marks the internal dirty flag (for standalone use without BufferManager).

  When using BufferManager integration, call `BufferManager.mark_dirty/1` instead.
  """
  @spec mark_dirty(GenServer.server()) :: :ok
  def mark_dirty(server \\ __MODULE__) do
    GenServer.call(server, :mark_dirty)
  end

  @doc """
  Clears the internal dirty flag (for standalone use without BufferManager).

  When using BufferManager integration, this is called automatically via the
  `dirty_clear` callback after each render.
  """
  @spec clear_dirty(GenServer.server()) :: :ok
  def clear_dirty(server \\ __MODULE__) do
    GenServer.call(server, :clear_dirty)
  end

  @doc """
  Returns whether the internal dirty flag is set (for standalone use).

  When using BufferManager integration, call `BufferManager.dirty?/1` instead.
  """
  @spec dirty?(GenServer.server()) :: boolean()
  def dirty?(server \\ __MODULE__) do
    GenServer.call(server, :dirty?)
  end

  @doc """
  Forces an immediate render, bypassing frame timing.

  Use for urgent updates that can't wait for the next tick.
  """
  @spec render_immediate(GenServer.server()) :: :ok
  def render_immediate(server \\ __MODULE__) do
    GenServer.call(server, :render_immediate)
  end

  @doc """
  Pauses frame timing (stops render ticks).
  """
  @spec pause(GenServer.server()) :: :ok
  def pause(server \\ __MODULE__) do
    GenServer.call(server, :pause)
  end

  @doc """
  Resumes frame timing after pause.
  """
  @spec resume(GenServer.server()) :: :ok
  def resume(server \\ __MODULE__) do
    GenServer.call(server, :resume)
  end

  @doc """
  Returns whether frame timing is paused.
  """
  @spec paused?(GenServer.server()) :: boolean()
  def paused?(server \\ __MODULE__) do
    GenServer.call(server, :paused?)
  end

  @doc """
  Changes the target FPS.
  """
  @spec set_fps(GenServer.server(), fps()) :: :ok
  def set_fps(server \\ __MODULE__, fps) do
    GenServer.call(server, {:set_fps, fps})
  end

  @doc """
  Returns the current target FPS.
  """
  @spec get_fps(GenServer.server()) :: fps()
  def get_fps(server \\ __MODULE__) do
    GenServer.call(server, :get_fps)
  end

  @doc """
  Returns performance statistics.

  Returns a map with:
    * `:rendered_frames` - Number of frames rendered
    * `:skipped_frames` - Number of clean frames skipped
    * `:total_frames` - Total frame ticks
    * `:actual_fps` - Calculated FPS from recent frames
    * `:avg_render_time_us` - Average render time in microseconds
    * `:slow_frames` - Frames that exceeded target interval
  """
  @spec stats(GenServer.server()) :: stats()
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  @doc """
  Resets performance statistics.
  """
  @spec reset_stats(GenServer.server()) :: :ok
  def reset_stats(server \\ __MODULE__) do
    GenServer.call(server, :reset_stats)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    fps = Keyword.get(opts, :fps, 60)
    render_callback = Keyword.fetch!(opts, :render_callback)

    interval_ms = fps_to_interval(fps)

    # Set up dirty callbacks - use provided ones or create internal atomics
    {dirty_check, dirty_clear, internal_dirty} =
      case {Keyword.get(opts, :dirty_check), Keyword.get(opts, :dirty_clear)} do
        {check, clear} when is_function(check, 0) and is_function(clear, 0) ->
          {check, clear, nil}

        _ ->
          # Create internal atomic for standalone use (stored in state, not process dict)
          dirty = :atomics.new(1, signed: false)
          check = fn -> :atomics.get(dirty, 1) == 1 end

          clear = fn ->
            :atomics.put(dirty, 1, 0)
            :ok
          end

          {check, clear, dirty}
      end

    state = %__MODULE__{
      fps: fps,
      interval_ms: interval_ms,
      render_callback: render_callback,
      dirty_check: dirty_check,
      dirty_clear: dirty_clear,
      last_tick: System.monotonic_time(:microsecond),
      internal_dirty: internal_dirty
    }

    # Schedule first tick
    timer_ref = schedule_tick(state)
    state = %{state | timer_ref: timer_ref}

    {:ok, state}
  end

  @impl true
  def handle_call(:mark_dirty, _from, state) do
    # Use internal dirty flag if available (standalone mode)
    if state.internal_dirty do
      :atomics.put(state.internal_dirty, 1, 1)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:clear_dirty, _from, state) do
    # Use internal dirty flag if available (standalone mode)
    if state.internal_dirty do
      :atomics.put(state.internal_dirty, 1, 0)
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:dirty?, _from, state) do
    # Use internal dirty flag if available (standalone mode)
    result =
      if state.internal_dirty do
        :atomics.get(state.internal_dirty, 1) == 1
      else
        false
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:render_immediate, _from, state) do
    state = do_render(state)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    # Cancel pending timer
    state =
      if state.timer_ref do
        Process.cancel_timer(state.timer_ref)
        %{state | timer_ref: nil, paused: true}
      else
        %{state | paused: true}
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    state =
      if state.paused do
        timer_ref = schedule_tick(state)

        %{
          state
          | timer_ref: timer_ref,
            paused: false,
            last_tick: System.monotonic_time(:microsecond)
        }
      else
        state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:paused?, _from, state) do
    {:reply, state.paused, state}
  end

  @impl true
  def handle_call({:set_fps, fps}, _from, state) do
    interval_ms = fps_to_interval(fps)
    {:reply, :ok, %{state | fps: fps, interval_ms: interval_ms}}
  end

  @impl true
  def handle_call(:get_fps, _from, state) do
    {:reply, state.fps, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = calculate_stats(state)
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset_stats, _from, state) do
    state = %{
      state
      | rendered_frames: 0,
        skipped_frames: 0,
        render_times: [],
        slow_frames: 0,
        frame_timestamps: []
    }

    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    now = System.monotonic_time(:microsecond)

    # Check if dirty using callback
    is_dirty = state.dirty_check.()

    state =
      if is_dirty do
        do_render(state)
      else
        %{state | skipped_frames: state.skipped_frames + 1}
      end

    # Record timestamp for FPS calculation
    state = record_frame_timestamp(state, now)

    # Schedule next tick with drift compensation
    elapsed_us = now - state.last_tick
    target_us = trunc(state.interval_ms * 1000)
    drift = elapsed_us - target_us
    next_interval = max(0, target_us - drift)

    timer_ref = Process.send_after(self(), :tick, div(next_interval, 1000))

    state = %{state | timer_ref: timer_ref, last_tick: now}

    {:noreply, state}
  end

  # Private functions

  defp fps_to_interval(30), do: 33.33
  defp fps_to_interval(60), do: 16.67
  defp fps_to_interval(120), do: 8.33

  defp schedule_tick(state) do
    Process.send_after(self(), :tick, trunc(state.interval_ms))
  end

  defp do_render(state) do
    start_time = System.monotonic_time(:microsecond)

    # Call render callback
    state.render_callback.()

    # Clear dirty flag using callback
    state.dirty_clear.()

    end_time = System.monotonic_time(:microsecond)
    render_time = end_time - start_time

    # Check for slow frame
    target_us = trunc(state.interval_ms * 1000)
    slow_frames = if render_time > target_us, do: state.slow_frames + 1, else: state.slow_frames

    # Keep last 60 render times for average
    render_times = Enum.take([render_time | state.render_times], 60)

    %{
      state
      | rendered_frames: state.rendered_frames + 1,
        render_times: render_times,
        slow_frames: slow_frames
    }
  end

  defp record_frame_timestamp(state, timestamp) do
    # Keep last 60 timestamps for FPS calculation
    timestamps = Enum.take([timestamp | state.frame_timestamps], 60)
    %{state | frame_timestamps: timestamps}
  end

  defp calculate_stats(state) do
    total_frames = state.rendered_frames + state.skipped_frames

    # Calculate actual FPS from timestamps
    actual_fps =
      case state.frame_timestamps do
        [latest | rest] when rest != [] ->
          oldest = List.last(rest)
          duration_s = (latest - oldest) / 1_000_000
          count = length(rest)

          if duration_s > 0 do
            count / duration_s
          else
            0.0
          end

        _ ->
          0.0
      end

    # Calculate average render time
    avg_render_time_us =
      case state.render_times do
        [] ->
          0.0

        times ->
          Enum.sum(times) / length(times)
      end

    %{
      rendered_frames: state.rendered_frames,
      skipped_frames: state.skipped_frames,
      total_frames: total_frames,
      actual_fps: Float.round(actual_fps, 2),
      avg_render_time_us: Float.round(avg_render_time_us, 2),
      slow_frames: state.slow_frames
    }
  end
end
