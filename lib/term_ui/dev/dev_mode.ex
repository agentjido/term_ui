defmodule TermUI.Dev.DevMode do
  @moduledoc """
  Central coordinator for development mode features.

  DevMode manages the lifecycle and state of all development tools:
  - UI Inspector - Shows component boundaries
  - State Inspector - Displays component state tree
  - Hot Reload - Updates code without restart
  - Performance Monitor - Shows FPS, memory, frame times

  DevMode is a standalone coordinator in 1.0. It is not supervised or fed
  component/render metrics by `TermUI.Runtime`, and its keyboard shortcuts are
  not registered automatically. A custom integration must start it, submit
  component data and metrics, route shortcuts, and compose its overlays.

  ## Usage

      # Enable development mode
      DevMode.enable()

      # Toggle individual features
      DevMode.toggle_ui_inspector()
      DevMode.toggle_state_inspector()
      DevMode.toggle_perf_monitor()

      # Check status
      DevMode.enabled?()
      DevMode.ui_inspector_enabled?()

  ## Keyboard Shortcuts (when enabled)

  - Ctrl+Shift+I: Toggle UI Inspector
  - Ctrl+Shift+S: Toggle State Inspector
  - Ctrl+Shift+P: Toggle Performance Monitor
  """

  use GenServer

  alias TermUI.Dev.HotReload
  alias TermUI.Dev.PerfMonitor
  alias TermUI.Dev.StateInspector
  alias TermUI.Dev.UIInspector

  @type state :: %{
          enabled: boolean(),
          ui_inspector: boolean(),
          state_inspector: boolean(),
          perf_monitor: boolean(),
          hot_reload: boolean(),
          selected_component: term() | nil,
          components: %{term() => component_info()},
          metrics: metrics()
        }

  @type component_info :: %{
          module: module(),
          state: term(),
          render_time: integer(),
          bounds: bounds()
        }

  @type bounds :: %{x: integer(), y: integer(), width: integer(), height: integer()}

  @type metrics :: %{
          fps: float(),
          frame_times: [integer()],
          memory: integer(),
          process_count: integer()
        }

  # Client API

  @doc """
  Starts the DevMode server.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Enables development mode.
  """
  @spec enable() :: :ok
  def enable do
    GenServer.call(__MODULE__, :enable)
  end

  @doc """
  Disables development mode.
  """
  @spec disable() :: :ok
  def disable do
    GenServer.call(__MODULE__, :disable)
  end

  @doc """
  Returns whether development mode is enabled.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    GenServer.call(__MODULE__, :enabled?)
  end

  @doc """
  Toggles UI inspector overlay.
  """
  @spec toggle_ui_inspector() :: boolean()
  def toggle_ui_inspector do
    GenServer.call(__MODULE__, :toggle_ui_inspector)
  end

  @doc """
  Returns whether UI inspector is enabled.
  """
  @spec ui_inspector_enabled?() :: boolean()
  def ui_inspector_enabled? do
    GenServer.call(__MODULE__, :ui_inspector_enabled?)
  end

  @doc """
  Toggles state inspector panel.
  """
  @spec toggle_state_inspector() :: boolean()
  def toggle_state_inspector do
    GenServer.call(__MODULE__, :toggle_state_inspector)
  end

  @doc """
  Returns whether state inspector is enabled.
  """
  @spec state_inspector_enabled?() :: boolean()
  def state_inspector_enabled? do
    GenServer.call(__MODULE__, :state_inspector_enabled?)
  end

  @doc """
  Toggles performance monitor.
  """
  @spec toggle_perf_monitor() :: boolean()
  def toggle_perf_monitor do
    GenServer.call(__MODULE__, :toggle_perf_monitor)
  end

  @doc """
  Returns whether performance monitor is enabled.
  """
  @spec perf_monitor_enabled?() :: boolean()
  def perf_monitor_enabled? do
    GenServer.call(__MODULE__, :perf_monitor_enabled?)
  end

  @doc """
  Toggles hot reload.
  """
  @spec toggle_hot_reload() :: boolean()
  def toggle_hot_reload do
    GenServer.call(__MODULE__, :toggle_hot_reload)
  end

  @doc """
  Registers a component for inspection.
  """
  @spec register_component(term(), module(), term(), bounds()) :: :ok
  def register_component(id, module, state, bounds) do
    GenServer.cast(__MODULE__, {:register_component, id, module, state, bounds})
  end

  @doc """
  Unregisters a component.
  """
  @spec unregister_component(term()) :: :ok
  def unregister_component(id) do
    GenServer.cast(__MODULE__, {:unregister_component, id})
  end

  @doc """
  Updates component state for inspection.
  """
  @spec update_component_state(term(), term()) :: :ok
  def update_component_state(id, state) do
    GenServer.cast(__MODULE__, {:update_component_state, id, state})
  end

  @doc """
  Records component render time.
  """
  @spec record_render_time(term(), integer()) :: :ok
  def record_render_time(id, time_us) do
    GenServer.cast(__MODULE__, {:record_render_time, id, time_us})
  end

  @doc """
  Selects a component for detailed inspection.
  """
  @spec select_component(term()) :: :ok
  def select_component(id) do
    GenServer.cast(__MODULE__, {:select_component, id})
  end

  @doc """
  Gets the currently selected component.
  """
  @spec get_selected_component() :: term() | nil
  def get_selected_component do
    GenServer.call(__MODULE__, :get_selected_component)
  end

  @doc """
  Gets all registered components.
  """
  @spec get_components() :: %{term() => component_info()}
  def get_components do
    GenServer.call(__MODULE__, :get_components)
  end

  @doc """
  Gets current performance metrics.
  """
  @spec get_metrics() :: metrics()
  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  @doc """
  Records a frame for FPS calculation.
  """
  @spec record_frame(integer()) :: :ok
  def record_frame(frame_time_us) do
    GenServer.cast(__MODULE__, {:record_frame, frame_time_us})
  end

  @doc """
  Handles keyboard shortcut for development mode.
  """
  @spec handle_shortcut(atom(), [atom()]) :: :handled | :not_handled
  def handle_shortcut(key, modifiers) do
    GenServer.call(__MODULE__, {:handle_shortcut, key, modifiers})
  end

  @doc """
  Gets the current state for rendering overlays.
  """
  @spec get_state() :: state()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    state = %{
      enabled: false,
      ui_inspector: false,
      state_inspector: false,
      perf_monitor: false,
      hot_reload: false,
      selected_component: nil,
      components: %{},
      metrics: %{
        fps: 0.0,
        frame_times: [],
        memory: 0,
        process_count: 0
      }
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:enable, _from, state) do
    {:reply, :ok, %{state | enabled: true}}
  end

  def handle_call(:disable, _from, state) do
    {:reply, :ok, %{state | enabled: false}}
  end

  def handle_call(:enabled?, _from, state) do
    {:reply, state.enabled, state}
  end

  def handle_call(:toggle_ui_inspector, _from, state) do
    new_value = not state.ui_inspector
    {:reply, new_value, %{state | ui_inspector: new_value}}
  end

  def handle_call(:ui_inspector_enabled?, _from, state) do
    {:reply, state.ui_inspector, state}
  end

  def handle_call(:toggle_state_inspector, _from, state) do
    new_value = not state.state_inspector
    {:reply, new_value, %{state | state_inspector: new_value}}
  end

  def handle_call(:state_inspector_enabled?, _from, state) do
    {:reply, state.state_inspector, state}
  end

  def handle_call(:toggle_perf_monitor, _from, state) do
    new_value = not state.perf_monitor
    {:reply, new_value, %{state | perf_monitor: new_value}}
  end

  def handle_call(:perf_monitor_enabled?, _from, state) do
    {:reply, state.perf_monitor, state}
  end

  def handle_call(:toggle_hot_reload, _from, state) do
    new_value = not state.hot_reload

    if new_value do
      HotReload.start()
    else
      HotReload.stop()
    end

    {:reply, new_value, %{state | hot_reload: new_value}}
  end

  def handle_call(:get_selected_component, _from, state) do
    {:reply, state.selected_component, state}
  end

  def handle_call(:get_components, _from, state) do
    {:reply, state.components, state}
  end

  def handle_call(:get_metrics, _from, state) do
    {:reply, state.metrics, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:handle_shortcut, key, modifiers}, _from, state) do
    if state.enabled and :ctrl in modifiers and :shift in modifiers do
      case key do
        :i ->
          new_value = not state.ui_inspector
          {:reply, :handled, %{state | ui_inspector: new_value}}

        :s ->
          new_value = not state.state_inspector
          {:reply, :handled, %{state | state_inspector: new_value}}

        :p ->
          new_value = not state.perf_monitor
          {:reply, :handled, %{state | perf_monitor: new_value}}

        _ ->
          {:reply, :not_handled, state}
      end
    else
      {:reply, :not_handled, state}
    end
  end

  @impl true
  def handle_cast({:register_component, id, module, comp_state, bounds}, state) do
    component_info = %{
      module: module,
      state: comp_state,
      render_time: 0,
      bounds: bounds
    }

    components = Map.put(state.components, id, component_info)
    {:noreply, %{state | components: components}}
  end

  def handle_cast({:unregister_component, id}, state) do
    components = Map.delete(state.components, id)
    selected = if state.selected_component == id, do: nil, else: state.selected_component
    {:noreply, %{state | components: components, selected_component: selected}}
  end

  def handle_cast({:update_component_state, id, comp_state}, state) do
    components =
      update_in(state.components, [id], fn
        nil -> nil
        info -> %{info | state: comp_state}
      end)

    {:noreply, %{state | components: components}}
  end

  def handle_cast({:record_render_time, id, time_us}, state) do
    components =
      update_in(state.components, [id], fn
        nil -> nil
        info -> %{info | render_time: time_us}
      end)

    {:noreply, %{state | components: components}}
  end

  def handle_cast({:select_component, id}, state) do
    {:noreply, %{state | selected_component: id}}
  end

  def handle_cast({:record_frame, frame_time_us}, state) do
    # Keep last 60 frame times for rolling average
    frame_times = [frame_time_us | state.metrics.frame_times] |> Enum.take(60)

    # Calculate FPS from average frame time
    avg_time =
      if frame_times != [] do
        Enum.sum(frame_times) / length(frame_times)
      else
        # Default to ~60 FPS
        16_666
      end

    fps = if avg_time > 0, do: 1_000_000 / avg_time, else: 0.0

    # Get memory and process count
    memory = :erlang.memory(:total)
    process_count = length(Process.list())

    metrics = %{
      fps: fps,
      frame_times: frame_times,
      memory: memory,
      process_count: process_count
    }

    {:noreply, %{state | metrics: metrics}}
  end

  # Rendering helpers

  @doc """
  Renders development mode overlays.

  Returns render nodes for UI inspector, state inspector, and performance monitor.
  """
  @spec render_overlays(state(), bounds()) :: term()
  def render_overlays(state, area) do
    overlays = []

    overlays =
      if state.ui_inspector do
        [UIInspector.render(state.components, state.selected_component, area) | overlays]
      else
        overlays
      end

    overlays =
      if state.state_inspector do
        selected = state.components[state.selected_component]
        [StateInspector.render(selected, area) | overlays]
      else
        overlays
      end

    overlays =
      if state.perf_monitor do
        [PerfMonitor.render(state.metrics, area) | overlays]
      else
        overlays
      end

    overlays
  end
end
