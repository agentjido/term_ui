defmodule TermUI.Dev.HotReload do
  @moduledoc """
  Hot Reload integration for development mode.

  Watches .ex files for changes and reloads modules without restarting
  the application. State is preserved across reloads where possible.

  This server is not started by TermUI or by `DevMode.start_link/1`. A custom
  development integration must start `HotReload` before calling `start/0` or
  enabling DevMode's hot-reload toggle.

  ## Usage

      # Start hot reload
      HotReload.start()

      # Stop hot reload
      HotReload.stop()

      # Manually reload a module
      HotReload.reload_module(MyModule)

  ## How It Works

  1. File watcher monitors lib/ directory for .ex changes
  2. On change, affected modules are identified
  3. Modules are recompiled using Mix
  4. Old code is purged and new code loaded
  5. Notification sent to UI

  Note: Uses polling-based approach for compatibility.
  """

  use GenServer

  require Logger

  # 1 second
  @poll_interval 1000

  @type state :: %{
          enabled: boolean(),
          watched_dirs: [String.t()],
          file_mtimes: %{String.t() => integer()},
          on_reload: (module() -> any()) | nil
        }

  # Dialyzer: Pattern match coverage warnings
  @dialyzer {:nowarn_function,
             handle_info: 2, reload_module: 1, check_for_changes: 1, recompile_file: 1}

  # Client API

  @doc """
  Starts the hot reload watcher.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts watching for file changes.
  """
  @spec start() :: :ok
  def start do
    GenServer.call(__MODULE__, :start)
  end

  @doc """
  Stops watching for file changes.
  """
  @spec stop() :: :ok
  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Returns whether hot reload is running.
  """
  @spec running?() :: boolean()
  def running? do
    GenServer.call(__MODULE__, :running?)
  end

  @doc """
  Manually reloads a specific module.
  """
  @spec reload_module(module()) :: :ok | {:error, term()}
  def reload_module(module) do
    GenServer.call(__MODULE__, {:reload_module, module})
  end

  @doc """
  Sets callback for reload notifications.
  """
  @spec on_reload((module() -> any())) :: :ok
  def on_reload(callback) do
    GenServer.cast(__MODULE__, {:on_reload, callback})
  end

  @doc """
  Gets recently reloaded modules.
  """
  @spec get_recent_reloads() :: [{module(), DateTime.t()}]
  def get_recent_reloads do
    GenServer.call(__MODULE__, :get_recent_reloads)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    state = %{
      enabled: false,
      watched_dirs: Keyword.get(opts, :dirs, ["lib"]),
      file_mtimes: %{},
      on_reload: nil,
      recent_reloads: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:start, _from, state) do
    if state.enabled do
      {:reply, :ok, state}
    else
      # Initial file scan
      file_mtimes = scan_files(state.watched_dirs)

      # Start polling
      schedule_poll()

      Logger.info("Hot reload started, watching #{length(state.watched_dirs)} directories")
      {:reply, :ok, %{state | enabled: true, file_mtimes: file_mtimes}}
    end
  end

  def handle_call(:stop, _from, state) do
    Logger.info("Hot reload stopped")
    {:reply, :ok, %{state | enabled: false}}
  end

  def handle_call(:running?, _from, state) do
    {:reply, state.enabled, state}
  end

  def handle_call({:reload_module, module}, _from, state) do
    result = do_reload_module(module)

    state =
      case result do
        :ok ->
          notify_reload(state.on_reload, module)
          add_recent_reload(state, module)

        _ ->
          state
      end

    {:reply, result, state}
  end

  def handle_call(:get_recent_reloads, _from, state) do
    {:reply, state.recent_reloads, state}
  end

  @impl true
  def handle_cast({:on_reload, callback}, state) do
    {:noreply, %{state | on_reload: callback}}
  end

  @impl true
  def handle_info(:poll, state) do
    if state.enabled do
      state = check_for_changes(state)
      schedule_poll()
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end

  defp scan_files(dirs) do
    dirs
    |> Enum.flat_map(&find_ex_files/1)
    |> Enum.map(fn path ->
      mtime = get_file_mtime(path)
      {path, mtime}
    end)
    |> Map.new()
  end

  defp find_ex_files(dir) do
    if File.dir?(dir) do
      Path.wildcard(Path.join(dir, "**/*.ex"))
    else
      []
    end
  end

  defp get_file_mtime(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> mtime
      _ -> 0
    end
  end

  defp check_for_changes(state) do
    current_mtimes = scan_files(state.watched_dirs)

    # Find changed files
    changed_files =
      current_mtimes
      |> Enum.filter(fn {path, mtime} ->
        old_mtime = Map.get(state.file_mtimes, path, 0)
        mtime > old_mtime
      end)
      |> Enum.map(fn {path, _} -> path end)

    if changed_files != [] do
      Logger.debug("Hot reload detected changes in #{length(changed_files)} files")

      # Reload changed files
      state =
        Enum.reduce(changed_files, state, fn path, acc ->
          reload_file(path, acc)
        end)

      %{state | file_mtimes: current_mtimes}
    else
      state
    end
  end

  defp reload_file(path, state) do
    Logger.info("Hot reloading: #{path}")

    case recompile_file(path) do
      {:ok, modules} ->
        reload_modules(modules, state)

      {:error, reason} ->
        Logger.error("Failed to recompile #{path}: #{inspect(reason)}")
        state
    end
  end

  defp reload_modules(modules, state) do
    Enum.reduce(modules, state, fn module, acc ->
      reload_single_module(module, acc, state.on_reload)
    end)
  end

  defp reload_single_module(module, state, on_reload) do
    case do_reload_module(module) do
      :ok ->
        notify_reload(on_reload, module)
        add_recent_reload(state, module)

      {:error, reason} ->
        Logger.error("Failed to reload #{module}: #{inspect(reason)}")
        state
    end
  end

  defp recompile_file(path) do
    # Get modules defined in the file before recompilation
    _old_modules = get_modules_in_file(path)

    # Recompile using Code module
    case Code.compile_file(path) do
      modules when is_list(modules) ->
        module_names = Enum.map(modules, fn {name, _binary} -> name end)
        {:ok, module_names}

      _ ->
        {:error, :compilation_failed}
    end
  rescue
    e ->
      {:error, e}
  end

  defp get_modules_in_file(path) do
    # Parse file to find module definitions
    case File.read(path) do
      {:ok, content} ->
        Regex.scan(~r/defmodule\s+([\w.]+)/, content)
        |> Enum.map(fn [_, name] ->
          String.to_atom("Elixir.#{name}")
        end)

      _ ->
        []
    end
  end

  defp do_reload_module(module) do
    # Purge old code
    :code.purge(module)

    # Delete old code if still loaded
    :code.delete(module)

    # The module should already be loaded from compilation
    # Just ensure it's available
    case Code.ensure_loaded(module) do
      {:module, ^module} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, e}
  end

  defp notify_reload(nil, _module), do: :ok

  defp notify_reload(callback, module) when is_function(callback, 1) do
    callback.(module)
  rescue
    e ->
      Logger.error("Hot reload callback failed: #{inspect(e)}")
  end

  defp add_recent_reload(state, module) do
    reload = {module, DateTime.utc_now()}
    recent = [reload | state.recent_reloads] |> Enum.take(20)
    %{state | recent_reloads: recent}
  end

  # Public helpers

  @doc """
  Gets the source file path for a module.
  """
  @spec get_module_source(module()) :: String.t() | nil
  def get_module_source(module) do
    case module.__info__(:compile)[:source] do
      source when is_list(source) -> List.to_string(source)
      _ -> nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Checks if a module can be hot reloaded.

  Some modules (like those with NIFs or ports) may not reload properly.
  """
  @spec can_reload?(module()) :: boolean()
  def can_reload?(module) do
    # Check if module exists and is loaded
    # Check if it has source info (not a native module)
    Code.ensure_loaded?(module) and
      is_list(module.__info__(:compile)[:source])
  rescue
    _ -> false
  end
end
