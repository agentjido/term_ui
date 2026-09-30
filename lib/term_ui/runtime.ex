defmodule TermUI.Runtime do
  @moduledoc """
  The central runtime orchestrator for TermUI applications.

  The runtime implements The Elm Architecture dispatch loop:
  1. Receive event from terminal
  2. Deliver it to the single root Elm module
  3. Call the root's event_to_msg
  4. Call the root's update with the resulting message
  5. Collect commands from update
  6. Mark component dirty
  7. On render timer, call view and render

  The `components` field in runtime state currently contains only the reserved
  `:root` entry. `TermUI.ComponentServer`, `TermUI.EventRouter`, and the other
  process-oriented component services are separate lower-level APIs; they are
  not mounted or consulted by this runtime loop.

  ## Usage

      # Start with a root component
      {:ok, runtime} = Runtime.start_link(root: MyApp.Root)

      # Send events (usually from terminal input)
      Runtime.send_event(runtime, Event.key(:enter))

      # Shutdown gracefully
      Runtime.shutdown(runtime)
  """

  use GenServer
  require Logger

  alias TermUI.Backend.{Selector, TTY}
  alias TermUI.Command
  alias TermUI.Command.Executor
  alias TermUI.Config
  alias TermUI.Elm
  alias TermUI.Event
  alias TermUI.EventQueue
  alias TermUI.Input.Selector, as: InputSelector
  alias TermUI.MessageQueue
  alias TermUI.PersistentTerms
  alias TermUI.Renderer.Buffer
  alias TermUI.Renderer.BufferManager
  alias TermUI.Renderer.Cell
  alias TermUI.Runtime.NodeRenderer
  alias TermUI.Runtime.State
  alias TermUI.Terminal
  alias TermUI.Terminal.InputReader
  alias TermUI.Terminal.SignalHandler
  alias TermUI.TerminalOutput

  # Dialyzer: Functions with unmatched return values in side-effect calls
  @dialyzer {:nowarn_function,
             init: 1,
             handle_call: 3,
             handle_info: 2,
             terminate: 2,
             process_render_tick: 1,
             cleanup_input_reader: 1,
             cleanup_input_handler: 1,
             cleanup_buffer_manager: 1,
             cleanup_resize_callback: 1,
             cleanup_backend: 1,
             cleanup_shutdown: 1,
             cleanup_terminal_restore: 1,
             cleanup_persistent_terms: 0,
             ensure_echo_enabled: 1,
             render_with_buffer_manager: 2,
             render_to_tty_backend: 2,
             extract_all_cells: 1}

  @type option ::
          {:root, module()}
          | {:name, GenServer.name()}
          | {:render_interval, pos_integer()}
          | {:backend, :auto | :raw | :tty | module() | {module(), keyword()}}
          | {:skip_terminal, boolean()}
          | {:use_input_handler, boolean()}
          | {:iex_mode, boolean()}

  # Default render interval in milliseconds (~60 FPS)
  @default_render_interval 16

  # Timeout for input handler poll calls in the async reader process.
  # For Raw handler: controls how long each poll waits before returning :timeout.
  # For TTY handler: ignored (TTY.poll blocks regardless of timeout).
  @input_poll_interval 16

  # --- Public API ---

  @doc """
  Starts the runtime with the given options.

  ## Options

  - `:root` - The root component module (required)
  - `:name` - GenServer name (optional)
  - `:render_interval` - Milliseconds between renders (default: 16)
  - `:backend` - `:auto` (default), `:raw`, `:tty`, a backend module, or
    `{backend_module, backend_opts}`
  - `:skip_terminal` - Skip terminal initialization (default: false, for testing)
  - `:use_input_handler` - Use the `TermUI.Input` handler path instead of the
    legacy local input reader (default: false)

  ## Backend Selection

  The `:backend` option controls which terminal backend is used:

  - `:auto` (default) - Attempts raw mode first, falls back to TTY if unavailable
  - `:raw` - Forces raw mode (requires OTP 28+, errors if unavailable)
  - `:tty` - Forces TTY mode (line-based input, no raw mode attempt)

  When the caller is an IEx evaluator, `:auto` resolves directly to `:tty` so
  the existing shell keeps ownership of the terminal. An explicit `:raw` or
  custom backend selection is preserved.

  ## Examples

      # Auto-detect backend (default behavior)
      {:ok, runtime} = Runtime.start_link(root: MyApp.Root)

      # Force TTY mode
      {:ok, runtime} = Runtime.start_link(root: MyApp.Root, backend: :tty)

      # Query backend mode at runtime
      :raw = Runtime.backend_mode()

      # Query capabilities (useful for TTY mode)
      %{colors: :true_color, unicode: true} = Runtime.capabilities()
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    opts = inherit_iex_mode(opts)
    {name, opts} = Keyword.pop(opts, :name)

    if name do
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      GenServer.start_link(__MODULE__, opts)
    end
  end

  @doc """
  Returns a child specification for starting the runtime in a supervisor.

  ## Options

  Same as `start_link/1`:
  - `:root` - The root component module (required)
  - `:name` - GenServer name (optional)
  - `:render_interval` - Milliseconds between renders (default: 16)
  - `:backend` - `:auto`, `:raw`, `:tty`, a backend module, or
    `{backend_module, backend_opts}`
  - `:skip_terminal` - Skip terminal initialization (default: false)
  - `:use_input_handler` - Use the `TermUI.Input` handler path (default: false)

  ## Examples

      children = [
        {TermUI.Runtime, root: MyApp.Root, name: :my_runtime}
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
  """
  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts = inherit_iex_mode(opts)

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @doc """
  Sends an event to the runtime for processing.
  """
  @spec send_event(GenServer.server(), Event.t()) :: :ok
  def send_event(runtime, event) do
    GenServer.cast(runtime, {:event, event})
  end

  @doc """
  Sends a message to a runtime component ID.

  In the 1.0 runtime, only `:root` is registered. Messages sent to any other ID
  are ignored.
  """
  @spec send_message(GenServer.server(), term(), term()) :: :ok
  def send_message(runtime, component_id, message) do
    GenServer.cast(runtime, {:message, component_id, message})
  end

  @doc """
  Delivers a command result back to the runtime.
  """
  @spec command_result(GenServer.server(), term(), term(), term()) :: :ok
  def command_result(runtime, component_id, command_id, result) do
    GenServer.cast(runtime, {:command_result, component_id, command_id, result})
  end

  @doc """
  Initiates graceful shutdown of the runtime.
  """
  @spec shutdown(GenServer.server()) :: :ok
  def shutdown(runtime) do
    GenServer.cast(runtime, :shutdown)
  end

  @doc """
  Gets the current runtime state (for testing/debugging).
  """
  @spec get_state(GenServer.server()) :: State.t()
  def get_state(runtime) do
    GenServer.call(runtime, :get_state)
  end

  @doc """
  Synchronously waits for all pending events and messages to be processed.

  This is primarily useful for testing to avoid race conditions from
  Process.sleep. It processes all queued messages and returns when complete.

  ## Example

      Runtime.send_event(runtime, Event.key(:up))
      Runtime.send_event(runtime, Event.key(:up))
      Runtime.sync(runtime)  # Wait for both events to be processed
      state = Runtime.get_state(runtime)
      assert state.root_state.count == 2
  """
  @spec sync(GenServer.server(), timeout()) :: :ok
  def sync(runtime, timeout \\ 5000) do
    GenServer.call(runtime, :sync, timeout)
  end

  @doc """
  Gets the current backend mode.

  Returns the node-global local backend context: `:raw`, `:tty`, `:skip`, or
  `nil`. Explicit custom/SSH runtimes do not publish a mode here; query their
  host/session state instead.

  ## Examples

      :raw = Runtime.backend_mode()
      :tty = Runtime.backend_mode()
  """
  @spec backend_mode() :: State.backend_mode()
  def backend_mode, do: PersistentTerms.backend_mode()

  @doc """
  Gets the detected terminal capabilities.

  Returns a map with keys:
  - `:colors` - Color depth (`:true_color`, `:color_256`, `:color_16`, `:monochrome`)
  - `:unicode` - Boolean indicating Unicode support
  - `:dimensions` - `{rows, cols}` tuple or `nil`
  - `:terminal` - Boolean indicating terminal presence

  Returns the node-global local Raw/TTY capability map, or `nil` when no local
  context is published. Explicit custom/SSH runtimes keep capabilities in
  their session/backend state and do not publish them here.

  ## Examples

      %{colors: :true_color, unicode: true} = Runtime.capabilities()
  """
  @spec capabilities() :: State.capabilities() | nil
  def capabilities, do: PersistentTerms.capabilities()

  @doc """
  Restores the complete screen from the current state, even when it is unchanged.
  """
  @spec force_render(GenServer.server()) :: :ok
  def force_render(runtime) do
    GenServer.cast(runtime, :force_render)
  end

  @doc """
  Starts the runtime and blocks until it shuts down.

  This is the main entry point for running a TUI application. It starts the
  runtime, takes over the terminal, and blocks the calling process until
  the application exits (e.g., user presses quit key).

  ## Options

  Same as `start_link/1`.

  ## Example

      # In your application entry point:
      TermUI.Runtime.run(root: MyApp.Root)
      # This blocks until the app exits
  """
  @spec run([option()]) :: :ok | {:error, term()}
  def run(opts) do
    case start_link(opts) do
      {:ok, runtime} ->
        # Monitor the runtime process and block until it exits
        ref = Process.monitor(runtime)

        receive do
          {:DOWN, ^ref, :process, ^runtime, _reason} ->
            :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    # Trap exits to ensure terminate/2 is called even on crashes
    Process.flag(:trap_exit, true)

    # Merge runtime options with application configuration
    # Runtime options take precedence over config
    opts = Config.merge_options(opts)

    # Component callbacks run in this process rather than in the IEx evaluator
    # that started us. Preserve the caller's mode for TermUI.iex_mode?/0.
    Process.put({TermUI, :iex_mode}, Keyword.get(opts, :iex_mode, false))

    root_module = Keyword.fetch!(opts, :root)
    render_interval = Keyword.get(opts, :render_interval, @default_render_interval)

    {backend_mode, backend, backend_state, capabilities, terminal_started, buffer_manager,
     dimensions} =
      init_backend(opts, unique_buffer_manager_name())

    # Suppress the local Logger handler only when this runtime owns the local
    # terminal. Custom backends such as SSH must not mutate node-global logger
    # state shared by other sessions.
    logger_handler_config =
      if local_backend_mode?(backend_mode) and not Keyword.get(opts, :skip_terminal, false) do
        suppress_logger()
      else
        nil
      end

    # The public global context describes the local terminal runtime. An SSH
    # session must not overwrite it for every connected client.
    if local_backend_mode?(backend_mode) do
      PersistentTerms.store_backend_context(backend_mode, capabilities)
    end

    # Initialize async command execution before the root module boots.
    {:ok, command_executor} = Executor.start_link()

    # Initialize root component state and any startup commands.
    {root_state, init_commands} =
      opts
      |> root_module.init()
      |> Elm.normalize_init_result()

    # Initialize input handling
    {use_input_handler, input_handler, input_state, input_reader} =
      init_input_handling(opts, backend_mode, terminal_started)

    # Register for resize callbacks if using new input handler
    register_resize_callback(use_input_handler, backend_mode)

    state =
      build_initial_state(%{
        root_module: root_module,
        root_state: root_state,
        render_interval: render_interval,
        terminal_started: terminal_started,
        buffer_manager: buffer_manager,
        dimensions: dimensions,
        input_reader: input_reader,
        backend_mode: backend_mode,
        backend: backend,
        backend_state: backend_state,
        capabilities: capabilities,
        command_executor: command_executor,
        input_handler: input_handler,
        input_state: input_state,
        logger_handler_config: logger_handler_config
      })

    register_runtime_signal_handler(backend_mode)

    if terminal_backend_mode?(backend_mode), do: schedule_size_check()

    # Schedule first render
    schedule_render(render_interval)

    # Spawn async reader process for input handler (runs poll loop in separate process)
    state =
      if state.input_handler do
        reader_pid =
          spawn_input_handler_reader(state.input_handler, state.input_state, self())

        %{state | input_handler_reader: reader_pid}
      else
        state
      end

    state =
      init_commands
      |> Enum.map(&{:root, &1})
      |> then(&execute_commands(&1, state))

    {:ok, state}
  end

  defp init_backend(opts, buffer_manager_name) do
    skip_terminal = Keyword.get(opts, :skip_terminal, false)
    backend_opt = Keyword.get(opts, :backend, :auto)

    if skip_terminal do
      {:skip, nil, nil, nil, false, nil, nil}
    else
      select_backend(backend_opt, buffer_manager_name)
    end
  end

  defp inherit_iex_mode(opts) do
    iex_mode = Keyword.get_lazy(opts, :iex_mode, &TermUI.iex_mode?/0)
    configured_backend = Keyword.get(opts, :backend, Config.get(:backend))

    opts = Keyword.put(opts, :iex_mode, iex_mode)

    if iex_mode and configured_backend == :auto do
      Keyword.put(opts, :backend, :tty)
    else
      opts
    end
  end

  defp init_input_handling(opts, backend_mode, terminal_started) do
    use_input_handler_opt = Keyword.get(opts, :use_input_handler, false)

    # TTY mode requires the new input handler (IEx compatible)
    # Raw mode can use either InputReader (legacy) or Input.Raw (new)
    use_input_handler = use_input_handler_opt or backend_mode == :tty

    {input_handler, input_state} =
      if use_input_handler and backend_mode in [:raw, :tty] do
        handler = InputSelector.select(backend_mode)
        {handler, handler.new()}
      else
        {nil, nil}
      end

    # Start input reader and register for resize callbacks if using legacy InputReader
    input_reader =
      if not use_input_handler and terminal_started do
        {:ok, reader_pid} = InputReader.start_link(target: self())
        Terminal.register_resize_callback(self())
        reader_pid
      else
        nil
      end

    {use_input_handler, input_handler, input_state, input_reader}
  end

  defp register_resize_callback(use_input_handler, backend_mode) do
    if use_input_handler and backend_mode in [:raw, :tty] do
      # Only register if Terminal GenServer is running
      if Process.whereis(Terminal) do
        Terminal.register_resize_callback(self())
      end
    end
  end

  # Raw mode installs this handler through Terminal. TTY does not start the
  # Terminal singleton, so give it its own supervised subscriber to restore
  # the cursor and alternate screen before the VM continues SIGTERM shutdown.
  defp register_runtime_signal_handler(:tty) do
    case :os.type() do
      {:unix, _} ->
        handler = {SignalHandler, self()}
        args = {self(), :restore_terminal, nil}

        case :gen_event.add_sup_handler(:erl_signal_server, handler, args) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("Unable to register TTY signal handler: #{inspect(reason)}")
        end

      _ ->
        :ok
    end
  rescue
    error -> Logger.warning("Unable to register TTY signal handler: #{Exception.message(error)}")
  catch
    kind, reason ->
      Logger.warning("Unable to register TTY signal handler: #{inspect({kind, reason})}")
  end

  defp register_runtime_signal_handler(_backend_mode), do: :ok

  defp build_initial_state(params) do
    %{
      root_module: params.root_module,
      root_state: params.root_state,
      message_queue: MessageQueue.new(),
      event_queue: EventQueue.new(),
      render_interval: params.render_interval,
      # Initial render needed
      dirty: true,
      focused_component: :root,
      components: %{root: %{module: params.root_module, state: params.root_state}},
      pending_commands: %{},
      shutting_down: false,
      terminal_started: params.terminal_started,
      buffer_manager: params.buffer_manager,
      dimensions: params.dimensions,
      input_reader: params.input_reader,
      input_handler_reader: nil,
      backend_mode: params.backend_mode,
      backend: params.backend,
      backend_state: params.backend_state,
      capabilities: params.capabilities,
      command_executor: params.command_executor,
      input_handler: params.input_handler,
      input_state: params.input_state,
      logger_handler_config: params[:logger_handler_config]
    }
  end

  defp select_backend(backend_opt, buffer_manager_name) do
    case Selector.select(backend_opt) do
      {:raw, _raw_state} ->
        attempt_raw_backend(fallback_to_tty: true, buffer_manager_name: buffer_manager_name)

      {:tty, capabilities} ->
        init_tty_backend(capabilities)

      {:explicit, :raw, _opts} ->
        attempt_raw_backend(fallback_to_tty: false, buffer_manager_name: buffer_manager_name)

      {:explicit, :tty, _opts} ->
        init_tty_backend(Selector.detect_capabilities())

      {:explicit, module, opts} ->
        init_explicit_backend(module, opts, buffer_manager_name)
    end
  end

  defp attempt_raw_backend(opts) do
    case setup_terminal_and_buffers(Keyword.fetch!(opts, :buffer_manager_name)) do
      {true, buffer_manager, dimensions} ->
        init_raw_backend(buffer_manager, dimensions)

      {false, nil, nil} ->
        if Keyword.get(opts, :fallback_to_tty, false) do
          init_tty_backend(Selector.detect_capabilities())
        else
          raise "Raw backend requested but unavailable"
        end
    end
  end

  defp init_raw_backend(buffer_manager, {cols, rows}) do
    backend = TermUI.Backend.Raw

    # Enable ONLCR translation (bare \n → \r\n) since raw mode disables OPOST
    TerminalOutput.enable_onlcr()

    # Terminal GenServer already entered alternate screen and hid cursor in
    # setup_terminal_and_buffers, so skip those here to avoid double entry.
    # Mouse tracking is also already configured.
    {:ok, backend_state} =
      backend.init(
        alternate_screen: false,
        hide_cursor: false,
        mouse_tracking: :none,
        size: {cols, rows}
      )

    {:raw, backend, backend_state, nil, true, buffer_manager, {cols, rows}}
  end

  defp init_tty_backend(capabilities) do
    backend = TermUI.Backend.TTY
    {:ok, backend_state} = backend.init(capabilities: capabilities, alternate_screen: true)
    {:ok, {rows, cols}} = backend.size(backend_state)
    {:tty, backend, backend_state, capabilities, false, nil, {cols, rows}}
  end

  defp init_explicit_backend(TermUI.Backend.Raw, _opts, buffer_manager_name) do
    attempt_raw_backend(fallback_to_tty: false, buffer_manager_name: buffer_manager_name)
  end

  defp init_explicit_backend(TermUI.Backend.TTY, _opts, _buffer_manager_name) do
    init_tty_backend(Selector.detect_capabilities())
  end

  defp init_explicit_backend(module, opts, buffer_manager_name) when is_atom(module) do
    {:ok, backend_state} = module.init(opts)
    {:ok, {rows, cols}} = module.size(backend_state)

    # Start BufferManager for the custom backend
    buffer_pid =
      case BufferManager.start_link(rows: rows, cols: cols, name: buffer_manager_name) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    {:custom, module, backend_state, nil, false, buffer_pid, {cols, rows}}
  end

  defp setup_terminal_and_buffers(buffer_manager_name) do
    # Start Terminal GenServer (or reuse if already running)
    case Terminal.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> throw({:terminal_failed, reason})
    end

    case Terminal.enable_raw_mode() do
      {:ok, _state} -> :ok
      {:error, reason} -> throw({:terminal_failed, reason})
    end

    # Configure terminal for TUI mode
    :ok = Terminal.enter_alternate_screen()
    :ok = Terminal.hide_cursor()
    :ok = Terminal.enable_mouse_tracking(:all)

    {rows, cols} = get_terminal_dimensions_safe()

    # Start BufferManager (or reuse if already running)
    buffer_pid =
      case BufferManager.start_link(rows: rows, cols: cols, name: buffer_manager_name) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    {true, buffer_pid, {cols, rows}}
  rescue
    _ -> {false, nil, nil}
  catch
    {:terminal_failed, _} -> {false, nil, nil}
  end

  @spec unique_buffer_manager_name() :: {:global, {:term_ui_buffer_manager, pid(), integer()}}
  defp unique_buffer_manager_name do
    {:global, {:term_ui_buffer_manager, self(), System.unique_integer([:positive])}}
  end

  defp local_backend_mode?(mode), do: mode in [:raw, :tty, :skip]
  defp terminal_backend_mode?(mode), do: mode in [:raw, :tty]

  defp get_terminal_dimensions_safe do
    case Terminal.get_terminal_size() do
      {:ok, {rows, cols}} -> {rows, cols}
      {:error, _reason} -> {24, 80}
    end
  end

  @impl true
  def handle_cast({:event, event}, state) do
    if state.shutting_down do
      {:noreply, state}
    else
      # Add to bounded event queue (may drop oldest if full)
      {result, new_queue} = EventQueue.push(state.event_queue, event)
      state = %{state | event_queue: new_queue}
      # Log if event was dropped
      case result do
        # EventQueue already logged
        {:dropped, _} -> :ok
        :ok -> :ok
      end

      # Process queued events
      state = process_event_queue(state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:message, component_id, message}, state) do
    if state.shutting_down do
      {:noreply, state}
    else
      state = enqueue_message(component_id, message, state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:command_result, component_id, command_id, result}, state) do
    state = handle_command_result(component_id, command_id, result, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:shutdown, state) do
    state = initiate_shutdown(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:force_render, state) do
    state = state |> process_messages() |> do_full_render()
    {:noreply, state}
  end

  @impl true
  def handle_info(:render, state) do
    state = process_render_tick(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:terminal_resume, %{shutting_down: true} = state), do: {:noreply, state}

  def handle_info(:terminal_resume, %{backend_mode: mode} = state) when mode in [:raw, :tty] do
    state =
      if mode == :tty do
        {:ok, backend_state} = TTY.resume(state.backend_state)
        %{state | backend_state: backend_state}
      else
        state
      end

    {:noreply, state |> process_messages() |> do_full_render()}
  end

  def handle_info({:terminal_resume_failed, reason}, state) do
    {:stop, {:terminal_resume_failed, reason}, state}
  end

  @impl true
  def handle_info(:input_eof, state) do
    # EOF from async input handler reader - initiate shutdown
    if state.shutting_down do
      {:noreply, state}
    else
      state = initiate_shutdown(%{state | input_handler_reader: nil})
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:input, event}, state) do
    # Keyboard/mouse input from InputReader or async input handler reader
    if state.shutting_down do
      {:noreply, state}
    else
      # Add to bounded event queue (may drop oldest if full)
      {result, new_queue} = EventQueue.push(state.event_queue, event)
      state = %{state | event_queue: new_queue}
      # Process queued events
      state = process_event_queue(state)
      # Log if event was dropped (EventQueue handles rate limiting)
      case result do
        {:dropped, _} -> :ok
        :ok -> :ok
      end

      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:terminal_resize, {rows, cols}}, state) do
    # Terminal window was resized
    if state.shutting_down do
      {:noreply, state}
    else
      state = handle_resize(rows, cols, state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ssh_input, event}, state) do
    # SSH input delivered externally from the host process
    if state.shutting_down do
      {:noreply, state}
    else
      {result, new_queue} = EventQueue.push(state.event_queue, event)
      state = %{state | event_queue: new_queue}
      state = process_event_queue(state)

      case result do
        {:dropped, _} -> :ok
        :ok -> :ok
      end

      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:ssh_resize, rows, cols}, state)
      when is_integer(rows) and rows > 0 and is_integer(cols) and cols > 0 do
    # SSH window_change event from the host process
    if state.shutting_down do
      {:noreply, state}
    else
      state = handle_resize(rows, cols, state)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Command task completed (handled via command_result)
    {:noreply, state}
  end

  @impl true
  def handle_info({:command_result, component_id, command_id, result}, state) do
    state = handle_command_result(component_id, command_id, result, state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:stop_runtime, state) do
    # Stop the GenServer after shutdown cleanup
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:check_terminal_size, %{shutting_down: false, backend_mode: mode} = state)
      when mode in [:raw, :tty] do
    state = refresh_local_size(state)
    unless state.shutting_down, do: schedule_size_check()
    {:noreply, state}
  end

  def handle_info(:check_terminal_size, state), do: {:noreply, state}

  # Handle linked process exits (input handler reader, etc.)
  @impl true
  def handle_info({:EXIT, pid, reason}, state) do
    if pid == state[:input_handler_reader] do
      Logger.warning("Input handler reader exited: #{inspect(reason)}")
      {:noreply, %{state | input_handler_reader: nil}}
    else
      # Forward to root module or ignore
      if function_exported?(state.root_module, :handle_info, 2) do
        handle_root_info({:EXIT, pid, reason}, state)
      else
        {:noreply, state}
      end
    end
  end

  # Catch-all for unknown messages - forward to root module's handle_info if it exists
  @impl true
  def handle_info(msg, state) do
    if function_exported?(state.root_module, :handle_info, 2) do
      handle_root_info(msg, state)
    else
      # Ignore unknown messages if root module doesn't handle them
      {:noreply, state}
    end
  end

  defp handle_root_info(msg, state) do
    case state.root_module.handle_info(msg, state.root_state) do
      {new_root_state, commands} ->
        state = update_root_state(state, new_root_state)
        tagged_commands = Enum.map(commands, fn cmd -> {:root, cmd} end)
        state = execute_commands(tagged_commands, state)
        {:noreply, state}

      new_root_state ->
        state = update_root_state(state, new_root_state)
        {:noreply, state}
    end
  end

  defp update_root_state(state, new_root_state) do
    components =
      Map.update!(state.components, :root, fn comp ->
        %{comp | state: new_root_state}
      end)

    %{state | root_state: new_root_state, components: components, dirty: true}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:restore_terminal, _from, state) do
    # TTY input may have a blocking IO.getn request queued on standard_io.
    # Bypass that IO server so signal cleanup cannot stall behind the read.
    TerminalOutput.write_to_tty(TerminalOutput.cleanup_sequence())
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:sync, _from, state) do
    # Process all pending messages synchronously
    state = process_messages(state)
    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Step 1: Restore logger FIRST (before any other cleanup that might log)
    terminate_logger_restore(state)

    # Step 2: Stop input reader BEFORE backend (prevents stdin contention during drain)
    cleanup_input_reader(state)
    cleanup_input_handler(state)

    # Step 3: Backend shutdown (drain pending input, cooked mode)
    cleanup_backend(state)
    cleanup_buffer_manager(state)

    # Step 4: Terminal restore and resize callback cleanup
    cleanup_resize_callback(state)
    cleanup_shutdown(state)
    cleanup_command_executor(state)
    cleanup_terminal_restore(state)

    # Only runtimes that initialized a physical terminal should attempt escape
    # sequence, stty, or echo restoration. `:skip` still owns the runtime's
    # persistent backend context, but deliberately has no terminal to restore.
    if terminal_backend_mode?(state.backend_mode) do
      terminate_defensive_cleanup()
      ensure_echo_enabled(state)
    end

    if local_backend_mode?(state.backend_mode), do: cleanup_persistent_terms()

    :ok
  end

  defp cleanup_input_reader(state) do
    if state.input_reader do
      InputReader.stop(state.input_reader)
    end
  rescue
    _ -> :ok
  end

  defp cleanup_input_handler(state) do
    # Kill the async reader process first
    if is_pid(state[:input_handler_reader]) and Process.alive?(state[:input_handler_reader]) do
      Process.unlink(state[:input_handler_reader])
      Process.exit(state[:input_handler_reader], :shutdown)
    end

    # Then stop the handler (restores IO opts for TTY, etc.)
    if state.input_handler != nil and state.input_state != nil do
      state.input_handler.stop(state.input_state)
    end
  rescue
    _ -> :ok
  end

  defp cleanup_resize_callback(state) do
    if state.terminal_started do
      Terminal.unregister_resize_callback(self())
    end
  rescue
    _ -> :ok
  end

  defp cleanup_backend(state) do
    if state.backend != nil and state.backend_state != nil do
      state.backend.shutdown(state.backend_state)
    end
  rescue
    _ -> :ok
  end

  defp cleanup_buffer_manager(%{buffer_manager: pid}) when is_pid(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid, :normal)
  rescue
    _ -> :ok
  end

  defp cleanup_buffer_manager(_state), do: :ok

  defp cleanup_shutdown(state) do
    if not state.shutting_down do
      do_shutdown(state)
    end
  rescue
    _ -> :ok
  end

  defp cleanup_command_executor(%{command_executor: executor}) when is_pid(executor) do
    if Process.alive?(executor), do: GenServer.stop(executor, :normal)
    :ok
  catch
    :exit, _reason -> :ok
  end

  defp cleanup_command_executor(_state), do: :ok

  defp cleanup_terminal_restore(state) do
    # Only restore Terminal singleton for local backends (Raw/TTY).
    # Custom backends (SSH) handle their own cleanup in cleanup_backend/1.
    if state.terminal_started and state.backend_mode in [:raw, :tty] do
      Terminal.restore()
    end
  rescue
    _ -> :ok
  end

  defp cleanup_persistent_terms do
    PersistentTerms.cleanup()
  rescue
    _ -> :ok
  end

  defp ensure_echo_enabled(state) do
    # Only restore echo on local terminals, not custom backends (SSH)
    if terminal_backend_mode?(state.backend_mode) do
      :io.setopts(echo: true)
    end
  rescue
    _ -> :ok
  end

  defp terminate_logger_restore(state) do
    restore_logger(state.logger_handler_config)
  rescue
    _ -> :ok
  end

  defp terminate_defensive_cleanup do
    # Crash-safe logger restore from persistent_term
    restore_logger_from_persistent_term()

    # Direct-to-TTY cleanup (bypasses Erlang IO)
    TerminalOutput.write_to_tty(TerminalOutput.cleanup_sequence())

    # Cleanup ONLCR persistent_term
    TerminalOutput.disable_onlcr()

    # Safety net stty restore (skip on WSL where stty always fails)
    unless TerminalOutput.needs_hard_reset?() do
      TermUI.TermUtils.safe_stty(["sane"])
    end
  rescue
    _ -> :ok
  end

  defp suppress_logger do
    case :logger.get_handler_config(:default) do
      {:ok, config} ->
        _ = :logger.remove_handler(:default)
        :persistent_term.put(:term_ui_logger_handler_config, config)
        config

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp restore_logger(nil), do: :ok

  defp restore_logger(%{module: module} = config) do
    # Only add if not already present (idempotent)
    case :logger.get_handler_config(:default) do
      {:ok, _} ->
        :ok

      _ ->
        _ = :logger.add_handler(:default, module, config)
        :ok
    end

    :persistent_term.erase(:term_ui_logger_handler_config)
    :ok
  rescue
    _ -> :ok
  end

  defp restore_logger(_), do: :ok

  defp restore_logger_from_persistent_term do
    case :persistent_term.get(:term_ui_logger_handler_config, nil) do
      nil -> :ok
      config -> restore_logger(config)
    end
  rescue
    _ -> :ok
  end

  # --- Event Dispatch ---

  # Processes events from the bounded event queue.
  #
  # Processes one event per call to prevent event loop starvation.
  # Multiple events will be processed across multiple GenServer handle_info/call cycles.
  defp process_event_queue(state) do
    case EventQueue.pop(state.event_queue) do
      {{:value, event}, new_queue} ->
        state = %{state | event_queue: new_queue}
        dispatch_event(event, state)

      {:empty, _} ->
        state
    end
  end

  defp dispatch_event(%Event.Key{} = event, state) do
    # Keyboard events go to focused component
    dispatch_to_component(state.focused_component, event, state)
  end

  defp dispatch_event(%Event.Mouse{} = event, state) do
    # The integrated 1.0 runtime has one root and does not use SpatialIndex.
    dispatch_to_component(:root, event, state)
  end

  defp dispatch_event(%Event.Resize{} = event, state) do
    # Resize broadcasts to all components
    broadcast_event(event, state)
  end

  defp dispatch_event(%Event.Focus{action: :gained} = event, state) do
    event |> broadcast_event(state) |> process_messages() |> do_full_render()
  end

  defp dispatch_event(%Event.Focus{} = event, state) do
    # Focus broadcasts to all components
    broadcast_event(event, state)
  end

  defp dispatch_event(%Event.Paste{} = event, state) do
    # Paste goes to focused component
    dispatch_to_component(state.focused_component, event, state)
  end

  defp dispatch_event(%Event.Tick{} = event, state) do
    # Tick broadcasts to all components
    broadcast_event(event, state)
  end

  defp dispatch_event(_event, state) do
    # Unknown event type, ignore
    state
  end

  defp dispatch_to_component(component_id, event, state) do
    case Map.get(state.components, component_id) do
      nil ->
        state

      %{module: module, state: component_state} ->
        # Transform event to message, with error handling
        try do
          case module.event_to_msg(event, component_state) do
            {:msg, message} ->
              enqueue_message(component_id, message, state)

            :ignore ->
              state

            :propagate ->
              # The single-root runtime has no parent target.
              state
          end
        rescue
          error ->
            require Logger
            Logger.error("Component #{component_id} crashed in event_to_msg: #{inspect(error)}")
            state
        end
    end
  end

  defp broadcast_event(event, state) do
    Enum.reduce(state.components, state, fn {component_id, _}, acc ->
      dispatch_to_component(component_id, event, acc)
    end)
  end

  # --- Message Processing ---

  defp enqueue_message(component_id, message, state) do
    queue = MessageQueue.enqueue(state.message_queue, {component_id, message})
    %{state | message_queue: queue}
  end

  defp process_messages(state) do
    {messages, queue} = MessageQueue.flush(state.message_queue)

    {state, commands} =
      Enum.reduce(messages, {%{state | message_queue: queue}, []}, fn {component_id, message},
                                                                      {acc_state, acc_cmds} ->
        {new_state, cmds} = process_message(component_id, message, acc_state)
        {new_state, acc_cmds ++ cmds}
      end)

    # Execute collected commands
    state = execute_commands(commands, state)

    state
  end

  defp process_message(component_id, message, state) do
    case Map.get(state.components, component_id) do
      nil ->
        {state, []}

      %{module: module, state: component_state} ->
        # Call update function with error handling
        try do
          result = module.update(message, component_state)
          {new_component_state, commands} = Elm.normalize_update_result(result, component_state)

          # Update component state
          components =
            Map.update!(state.components, component_id, fn comp ->
              %{comp | state: new_component_state}
            end)

          # Mark dirty if state changed
          dirty = state.dirty or new_component_state != component_state

          # Update root_state if this is root
          state =
            if component_id == :root do
              %{state | root_state: new_component_state, components: components, dirty: dirty}
            else
              %{state | components: components, dirty: dirty}
            end

          # Tag commands with component_id
          tagged_commands = Enum.map(commands, fn cmd -> {component_id, cmd} end)

          {state, tagged_commands}
        rescue
          error ->
            require Logger
            Logger.error("Component #{component_id} crashed in update: #{inspect(error)}")
            # Return unchanged state and no commands
            {state, []}
        end
    end
  end

  # --- Command Execution ---

  defp execute_commands([], state), do: state

  defp execute_commands(commands, state) do
    # Check for quit command first
    # Handle both Command struct and legacy atom :quit
    quit_cmd =
      Enum.find(commands, fn {_component_id, cmd} ->
        case cmd do
          %{type: :quit} -> true
          :quit -> true
          _ -> false
        end
      end)

    if quit_cmd do
      # Quit command takes precedence - initiate shutdown
      # Stop the GenServer after cleanup
      GenServer.cast(self(), :shutdown)
      %{state | shutting_down: true}
    else
      Enum.reduce(commands, state, fn {component_id, cmd}, acc ->
        execute_command(component_id, cmd, acc)
      end)
    end
  end

  defp execute_command(_component_id, %Command{type: :none}, state), do: state

  defp execute_command(component_id, %Command{} = command, state) do
    case Executor.execute(state.command_executor, command, self(), component_id) do
      {:ok, command_id} ->
        pending =
          Map.put(state.pending_commands, command_id, %{
            component_id: component_id,
            command: command
          })

        %{state | pending_commands: pending}

      {:error, reason} ->
        enqueue_message(component_id, {:error, reason}, state)
    end
  end

  defp execute_command(component_id, {:timer, ms, message}, state)
       when is_integer(ms) and ms >= 0 do
    execute_command(component_id, Command.timer(ms, message), state)
  end

  defp execute_command(_component_id, {:send, pid, message}, state) when is_pid(pid) do
    send(pid, message)
    state
  end

  defp execute_command(component_id, other, state) do
    Logger.warning("Unknown command for #{inspect(component_id)}: #{inspect(other)}")
    state
  end

  defp handle_command_result(component_id, command_id, result, state) do
    # Remove from pending
    pending = Map.delete(state.pending_commands, command_id)
    state = %{state | pending_commands: pending}

    if state.shutting_down do
      state
    else
      case result do
        {:send_to, target_component, message} ->
          enqueue_message(target_component, message, state)

        _ ->
          enqueue_message(component_id, result, state)
      end
    end
  end

  # --- Rendering ---

  defp schedule_render(interval) do
    Process.send_after(self(), :render, interval)
  end

  # Spawns a linked process that runs the input handler's poll loop.
  # Events are sent as {:input, event} messages (same format as InputReader).
  # This prevents blocking handlers (like Input.TTY) from freezing the GenServer.
  defp spawn_input_handler_reader(handler, input_state, target) do
    spawn_link(fn ->
      input_handler_loop(handler, input_state, target)
    end)
  end

  defp input_handler_loop(handler, input_state, target) do
    case handler.poll(input_state, @input_poll_interval) do
      {{:ok, event}, new_input_state} ->
        send(target, {:input, event})
        input_handler_loop(handler, new_input_state, target)

      {:timeout, new_input_state} ->
        input_handler_loop(handler, new_input_state, target)

      {:eof, _new_input_state} ->
        send(target, :input_eof)
    end
  end

  defp process_render_tick(state) do
    # Process any pending messages
    state = process_messages(state)

    # Render if dirty
    state =
      if state.dirty and not state.shutting_down do
        do_render(state)
      else
        state
      end

    # Schedule next render unless shutting down
    unless state.shutting_down do
      schedule_render(state.render_interval)
    end

    state
  end

  defp do_render(state) do
    # Render if backend is available (TTY backend works even without terminal_started)
    if state.backend do
      # Call view on root component with error handling
      %{module: module, state: component_state} = Map.get(state.components, :root)

      render_tree =
        try do
          module.view(component_state)
        rescue
          error ->
            require Logger
            Logger.error("Component :root crashed in view: #{inspect(error)}")
            # Return a simple error indicator
            {:text, "[Render Error]"}
        end

      # Different rendering paths for Raw vs TTY backends
      {cells, new_backend_state} =
        if state.buffer_manager do
          # Raw backend: use double buffering with diffing
          render_with_buffer_manager(render_tree, state)
        else
          # TTY backend: create temporary buffer, render all cells
          render_to_tty_backend(render_tree, state)
        end

      # Delegate rendering to backend
      {:ok, new_backend_state} = state.backend.draw_cells(new_backend_state, cells)

      # Flush any pending output
      {:ok, ^new_backend_state} = state.backend.flush(new_backend_state)

      %{state | dirty: false, backend_state: new_backend_state}
    else
      %{state | dirty: false}
    end
  end

  defp do_full_render(%{shutting_down: true} = state), do: state
  defp do_full_render(%{backend: nil} = state), do: %{state | dirty: false}

  defp do_full_render(state) do
    {:ok, backend_state} = state.backend.clear(state.backend_state)

    if state.buffer_manager do
      state.buffer_manager |> BufferManager.get_previous_buffer() |> Buffer.clear()
    end

    do_render(%{state | backend_state: backend_state, dirty: true})
  end

  # Renders using BufferManager with double buffering and diffing (Raw backend)
  defp render_with_buffer_manager(render_tree, state) do
    # Clear current buffer
    BufferManager.clear_current(state.buffer_manager)

    # Render tree to buffer
    NodeRenderer.render_to_buffer(render_tree, state.buffer_manager)

    # Get buffers for diffing
    current = BufferManager.get_current_buffer(state.buffer_manager)
    previous = BufferManager.get_previous_buffer(state.buffer_manager)

    # Get changed cells and convert to backend format
    cells = get_changed_cells(current, previous)

    # Swap buffers
    BufferManager.swap_buffers(state.buffer_manager)

    {cells, state.backend_state}
  end

  # Renders to TTY backend without double buffering
  defp render_to_tty_backend(render_tree, state) do
    # Get terminal size from backend state or capabilities
    {rows, cols} =
      case state.backend_state do
        %{size: {r, c}} -> {r, c}
        _ -> {24, 80}
      end

    # Create temporary buffer for this frame
    case Buffer.new(rows, cols) do
      {:ok, temp_buffer} ->
        # Render tree directly to temporary buffer (bypassing BufferManager)
        NodeRenderer.render_to_buffer_direct(render_tree, temp_buffer)

        # Extract all non-empty cells for TTY backend
        cells = extract_all_cells(temp_buffer)

        # Clean up temporary buffer
        Buffer.destroy(temp_buffer)

        {cells, state.backend_state}

      {:error, _reason} ->
        # If buffer creation fails, render nothing
        {[], state.backend_state}
    end
  end

  # Extracts all non-empty cells from buffer for TTY backend
  defp extract_all_cells(buffer) do
    {rows, _cols} = Buffer.dimensions(buffer)

    for row <- 1..rows, reduce: [] do
      acc ->
        buffer_row = Buffer.get_row(buffer, row)

        cells_in_row =
          buffer_row
          |> Enum.with_index(1)
          |> Enum.filter(fn {%TermUI.Renderer.Cell{} = cell, _col} ->
            # Include non-space characters OR spaces with non-default background
            cell.char != " " or (cell.bg != nil and cell.bg != :default)
          end)
          |> Enum.flat_map(fn {cell, col} -> cell_to_backend_tuple(cell, row, col) end)

        cells_in_row ++ acc
    end
  end

  # Gets changed cells by comparing current and previous buffers.
  # Returns cells in the format expected by Backend.draw_cells/2: [{position, cell_data}]
  # where position is {row, col} and cell_data is {char, fg, bg, attrs}
  defp get_changed_cells(current, previous) do
    {rows, _cols} = Buffer.dimensions(current)

    for row <- 1..rows, reduce: [] do
      acc ->
        current_row = Buffer.get_row(current, row)
        previous_row = Buffer.get_row(previous, row)

        # Single O(n) zip pass instead of two O(n^2) passes with Enum.at
        diff_row_cells(current_row, previous_row, row, 1, acc)
    end
  end

  # Zips current and previous rows in a single pass, emitting:
  # - Changed displayable cells (new content to draw)
  # - Clear cells (previous content that needs erasing)
  defp diff_row_cells([], [], _row, _col, acc), do: acc

  defp diff_row_cells([cur | cur_rest], [prev | prev_rest], row, col, acc) do
    acc = diff_cell(cur, prev, row, col, acc)

    diff_row_cells(cur_rest, prev_rest, row, col + 1, acc)
  end

  # Handle rows of different lengths (shouldn't happen normally, but be safe)
  defp diff_row_cells([cur | cur_rest], [], row, col, acc) do
    acc =
      if displayable_cell?(cur) do
        cell_to_backend_tuple(cur, row, col) ++ acc
      else
        acc
      end

    diff_row_cells(cur_rest, [], row, col + 1, acc)
  end

  defp diff_row_cells([], [prev | prev_rest], row, col, acc) do
    acc =
      if displayable_cell?(prev) do
        [{{row, col}, {" ", :default, :default, []}} | acc]
      else
        acc
      end

    diff_row_cells([], prev_rest, row, col + 1, acc)
  end

  defp diff_cell(cur, prev, row, col, acc) do
    if Cell.equal?(cur, prev) do
      acc
    else
      cur_displayable = displayable_cell?(cur)
      prev_displayable = displayable_cell?(prev)

      acc
      |> add_current_cell(cur, row, col, cur_displayable)
      |> clear_previous_cell(prev, cur, row, col, prev_displayable, cur_displayable)
    end
  end

  defp add_current_cell(acc, cur, row, col, true) do
    cell_to_backend_tuple(cur, row, col) ++ acc
  end

  defp add_current_cell(acc, _cur, _row, _col, false), do: acc

  defp clear_previous_cell(acc, prev, cur, row, col, prev_displayable, cur_displayable) do
    if clear_previous_cell?(prev, cur, prev_displayable, cur_displayable) do
      [{{row, col}, {" ", :default, :default, []}} | acc]
    else
      acc
    end
  end

  defp clear_previous_cell?(_prev, _cur, true, false), do: true

  defp clear_previous_cell?(prev, cur, true, true) do
    prev.bg != nil and prev.bg != :default and cur.char == " "
  end

  defp clear_previous_cell?(_prev, _cur, _prev_displayable, _cur_displayable), do: false

  defp displayable_cell?(%Cell{} = cell) do
    cell.char != " " or (cell.bg != nil and cell.bg != :default)
  end

  # Converts a Cell struct to the backend format: {{row, col}, {char, fg, bg, attrs}}
  # Skips wide placeholder cells (they're part of wide characters)
  # Returns [] for skipped cells to filter them out
  defp cell_to_backend_tuple(%Cell{wide_placeholder: true}, _row, _col), do: []

  defp cell_to_backend_tuple(%Cell{char: char, fg: fg, bg: bg, attrs: attrs}, row, col) do
    # Convert MapSet attrs to list for backend format
    attrs_list = MapSet.to_list(attrs)
    [{{row, col}, {char, normalize_color(fg), normalize_color(bg), attrs_list}}]
  end

  # Normalizes colors to ensure :default instead of nil
  defp normalize_color(nil), do: :default
  defp normalize_color(color), do: color

  # --- Resize Handling ---

  # Windows does not send SIGWINCH. TTY can also run without the Terminal
  # singleton. Query the active local backend without changing custom sessions.
  defp schedule_size_check, do: Process.send_after(self(), :check_terminal_size, 250)

  defp refresh_local_size(%{backend_mode: mode} = state) when mode in [:raw, :tty] do
    case state.backend.refresh_size(state.backend_state) do
      {:ok, {rows, cols} = size, backend_state} ->
        state =
          if size != state.backend_state.size,
            do: %{state | backend_state: backend_state},
            else: state

        if {cols, rows} != state.dimensions,
          do: handle_resize(rows, cols, state),
          else: state

      {:error, _reason} ->
        state
    end
  end

  defp refresh_local_size(state), do: state

  defp handle_resize(rows, cols, state) do
    cond do
      state.terminal_started ->
        # Local terminal (Raw/TTY) with Terminal singleton
        new_dimensions = {cols, rows}

        if state.buffer_manager do
          BufferManager.resize(state.buffer_manager, rows, cols)
        end

        resize_event = Event.Resize.new(cols, rows)
        state = broadcast_event(resize_event, %{state | dimensions: new_dimensions})

        # broadcast_event only enqueues; drain the queue so the upcoming
        # render uses the new dimensions instead of the previous frame's.
        # Without this the first frame after a resize draws stale content
        # into the resized buffer -- visible as blanks (on grow) or
        # clipping (on shrink) during drag-resize.
        #
        # We intentionally do not call backend.clear here: the diff
        # already emits both content cells and erase cells for positions
        # that went from content to empty, so the terminal repaints
        # cleanly without a flicker-inducing full screen wipe.
        state = process_messages(state)
        finish_resize(state)

      state.backend != nil ->
        # Custom backend (SSH, etc.) — no Terminal singleton
        new_dimensions = {cols, rows}

        if state.buffer_manager do
          BufferManager.resize(state.buffer_manager, rows, cols)
        end

        # Update backend size (no clear -- see terminal_started branch).
        backend_state =
          if function_exported?(state.backend, :update_size, 3) do
            {:ok, bs} = state.backend.update_size(state.backend_state, rows, cols)
            bs
          else
            state.backend_state
          end

        # The diff renderer only emits erase cells when a buffer_manager is
        # in play. Backends without one (TTY path) need a real clear so
        # stale pre-resize content isn't left on screen.
        backend_state =
          if state.buffer_manager == nil do
            {:ok, cleared} = state.backend.clear(backend_state)
            cleared
          else
            backend_state
          end

        state = %{state | backend_state: backend_state}

        resize_event = Event.Resize.new(cols, rows)
        state = broadcast_event(resize_event, %{state | dimensions: new_dimensions})

        # See note on the terminal_started branch above -- drain the queue
        # so the render uses the new dimensions, not the previous frame's.
        state = process_messages(state)
        finish_resize(state)

      true ->
        state
    end
  end

  # process_messages can run a component's :quit command and flip
  # shutting_down. Match process_render_tick's guard so we don't paint
  # into a backend that's about to be torn down.
  defp finish_resize(%{shutting_down: true} = state), do: state
  defp finish_resize(state), do: do_render(%{state | dirty: true})

  # --- Shutdown ---

  defp initiate_shutdown(state) do
    state = %{state | shutting_down: true}
    state = do_shutdown(state)

    # Schedule the GenServer to stop after returning from this callback
    # This allows terminate/2 to run and clean up properly
    Process.send_after(self(), :stop_runtime, 0)

    state
  end

  defp do_shutdown(state) do
    if state.command_executor do
      Enum.each(Map.keys(state.pending_commands), fn command_id ->
        _ = Executor.cancel(state.command_executor, command_id)
      end)
    end

    state = %{state | pending_commands: %{}}

    # Terminate components (leaf to root)
    # For now, just clear components
    state = %{state | components: %{}}

    state
  end
end
