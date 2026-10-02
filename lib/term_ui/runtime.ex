defmodule TermUI.Runtime do
  @moduledoc """
  Runs one Elm application against one terminal backend.

  The runtime is the only owner of application state. It serializes terminal
  events, application messages, command results, frame scheduling, and
  shutdown. Backend state is opaque to the runtime.
  """

  use GenServer

  alias TermUI.Backend
  alias TermUI.Backend.Manager, as: BackendManager
  alias TermUI.{Command, Elm, Event, Frame, LoggerControl}

  @default_render_interval 16
  @type option ::
          {:root, module()}
          | {:name, GenServer.name()}
          | {:backend, Backend.spec()}
          | {:backend_opts, keyword()}
          | {:suppress_logger, boolean()}
          | {:render_interval, pos_integer()}

  @type state :: %{
          app: module(),
          app_state: term(),
          backend: module(),
          backend_manager: pid(),
          logger_token: {reference(), pid()} | nil,
          capabilities: map(),
          dimensions: {pos_integer(), pos_integer()},
          render_interval: pos_integer(),
          render_timer: {reference(), reference()} | nil,
          dirty: boolean(),
          status: :running | :final_render_pending | :stopping,
          stop_reason: term(),
          async_tasks: map(),
          async_monitors: map(),
          async_links: MapSet.t(pid()),
          frames_rendered: non_neg_integer()
        }

  @doc "Starts a linked runtime process."
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    start_options = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, start_options)
  end

  @doc false
  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 5_000,
      type: :worker
    }
  end

  @doc "Runs an application until it exits."
  @spec run([option()]) :: :ok | {:error, term()}
  def run(opts) do
    {name, opts} = Keyword.pop(opts, :name)

    case start_monitor(name, opts) do
      {:ok, {runtime, reference}} ->
        receive do
          {:DOWN, ^reference, :process, ^runtime, reason} when reason in [:normal, :shutdown] ->
            :ok

          {:DOWN, ^reference, :process, ^runtime, {:shutdown, :normal}} ->
            :ok

          {:DOWN, ^reference, :process, ^runtime, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Queues an application message."
  @spec send_message(GenServer.server(), term()) :: :ok
  def send_message(runtime, message), do: GenServer.cast(runtime, {:message, message})

  @doc """
  Deprecated v1 target form for a root application message.

  The `:root` target delegates to `send_message/2`. A component identifier
  returns a migration error because v2 has no component process routing.
  """
  @deprecated "Use TermUI.Runtime.send_message/2 and route the message in the root application."
  @spec send_message(GenServer.server(), :root | term(), term()) ::
          :ok | {:error, {:component_routing_removed, term(), String.t()}}
  def send_message(runtime, :root, message), do: send_message(runtime, message)

  def send_message(_runtime, component_id, _message) do
    {:error,
     {:component_routing_removed, component_id,
      "Use TermUI.Runtime.send_message/2 and route the message in the root update/2 function."}}
  end

  @doc "Requests a final render and clean shutdown."
  @spec shutdown(GenServer.server()) :: :ok
  def shutdown(runtime), do: GenServer.cast(runtime, {:shutdown, :normal})

  @doc "Restores the complete screen from the newest state, even when it is unchanged."
  @spec force_render(GenServer.server()) :: :ok
  def force_render(runtime), do: GenServer.cast(runtime, :force_render)

  @doc "Waits until older messages from this caller are processed."
  @spec sync(GenServer.server(), timeout()) :: :ok
  def sync(runtime, timeout \\ 5_000), do: GenServer.call(runtime, :sync, timeout)

  @doc "Returns internal state for deterministic tests and diagnostics."
  @spec get_state(GenServer.server()) :: state()
  def get_state(runtime), do: GenServer.call(runtime, :get_state)

  @doc "Returns capabilities for one runtime."
  @spec capabilities(GenServer.server()) :: map()
  def capabilities(runtime), do: GenServer.call(runtime, :capabilities)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    logger_token = if suppress_logger?(opts), do: LoggerControl.suspend(), else: nil

    case initialize(opts, logger_token) do
      {:ok, state, commands} ->
        {:ok, state, {:continue, {:start, commands}}}

      {:error, reason} ->
        LoggerControl.resume(logger_token)
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue({:start, commands}, state) do
    with {:ok, state} <- render_now(state),
         {:ok, state} <- execute_commands(commands, state) do
      if state.status == :final_render_pending do
        finish(state)
      else
        :ok = BackendManager.activate(state.backend_manager)
        {:noreply, state}
      end
    else
      {:error, reason, state} -> {:stop, reason, %{state | stop_reason: reason}}
      {:error, reason} -> {:stop, reason, %{state | stop_reason: reason}}
    end
  end

  @impl true
  def handle_cast({:message, message}, state), do: process_update(message, state)

  def handle_cast({:shutdown, reason}, state) do
    finish(%{state | status: :final_render_pending, stop_reason: reason})
  end

  def handle_cast(:force_render, state) do
    force_render_now(state)
  end

  @impl true
  def handle_call(:sync, _from, state), do: {:reply, :ok, state}
  def handle_call(:get_state, _from, state), do: {:reply, state, state}
  def handle_call(:capabilities, _from, state), do: {:reply, state.capabilities, state}

  @impl true
  def handle_info({:render, token}, %{render_timer: {_reference, token}} = state) do
    state = %{state | render_timer: nil}

    case render_now(state) do
      {:ok, state} -> {:noreply, state}
      {:error, reason, state} -> {:stop, reason, %{state | stop_reason: reason}}
    end
  end

  def handle_info({:render, _old_token}, state), do: {:noreply, state}

  def handle_info({:backend_event, event}, state), do: process_event(event, state)

  def handle_info(:backend_resumed, %{status: :running} = state), do: force_render_now(state)
  def handle_info(:backend_resumed, state), do: {:noreply, state}

  def handle_info({:backend_size, {rows, columns}}, state) do
    case BackendManager.resize(state.backend_manager, {rows, columns}) do
      :ok ->
        {width, height} = Frame.clamp_dimensions({columns, rows})
        state = %{state | dimensions: {width, height}, dirty: true}
        dispatch_event(Event.resize(width, height), state)

      {:error, stop_reason} ->
        {:stop, stop_reason, %{state | stop_reason: stop_reason}}
    end
  end

  def handle_info({:backend_failed, reason}, state) do
    finish(%{state | status: :final_render_pending, stop_reason: reason})
  end

  def handle_info({:EXIT, manager, reason}, %{backend_manager: manager} = state) do
    stop_reason = {:backend, state.backend, :manager, reason}
    {:stop, stop_reason, %{state | stop_reason: stop_reason}}
  end

  def handle_info({:EXIT, pid, _reason} = message, state) do
    if MapSet.member?(state.async_links, pid) do
      {:noreply, %{state | async_links: MapSet.delete(state.async_links, pid)}}
    else
      handle_application_info(message, state)
    end
  end

  def handle_info({:app_message, message}, state), do: process_update(message, state)

  def handle_info({:async_result, token, result}, state) do
    case Map.pop(state.async_tasks, token) do
      {nil, _tasks} ->
        {:noreply, state}

      {%{mapper: mapper, monitor: monitor}, tasks} ->
        Process.demonitor(monitor, [:flush])

        state = %{
          state
          | async_tasks: tasks,
            async_monitors: Map.delete(state.async_monitors, monitor)
        }

        case safe_apply_mapper(mapper, result) do
          {:ok, message} -> process_update(message, state)
          {:error, reason} -> {:stop, reason, %{state | stop_reason: reason}}
        end
    end
  end

  def handle_info({:DOWN, reference, :process, pid, reason}, state) do
    case Map.get(state.async_monitors, reference) do
      nil ->
        handle_application_info({:DOWN, reference, :process, pid, reason}, state)

      token ->
        {task, tasks} = Map.pop(state.async_tasks, token)

        state = %{
          state
          | async_tasks: tasks,
            async_monitors: Map.delete(state.async_monitors, reference)
        }

        handle_async_exit(task, reason, state)
    end
  end

  def handle_info(message, state), do: handle_application_info(message, state)

  defp handle_application_info(message, state) do
    case app_handle_info(state.app, message, state.app_state) do
      {:ok, app_state, commands} ->
        after_application_update(app_state, commands, state)

      {:error, reason} ->
        {:stop, reason, %{state | stop_reason: reason}}
    end
  end

  defp handle_async_exit(nil, _reason, state), do: {:noreply, state}

  defp handle_async_exit(%{mapper: mapper}, reason, state) do
    case safe_apply_mapper(mapper, {:error, {:exit, reason, []}}) do
      {:ok, message} -> process_update(message, state)
      {:error, error} -> {:stop, error, %{state | stop_reason: error}}
    end
  end

  @impl true
  def terminate(reason, state) do
    _state = cancel_render(state)
    stop_async_tasks(state)
    BackendManager.close(state.backend_manager, effective_reason(reason, state))
    LoggerControl.resume(state.logger_token)
    app_terminate(state.app, effective_reason(reason, state), state.app_state)
    :ok
  end

  defp initialize(opts, logger_token) do
    with {:ok, app} <- fetch_app(opts),
         {:ok, backend_manager} <-
           BackendManager.start_link(
             self(),
             Keyword.get(opts, :backend, :auto),
             Keyword.get(opts, :backend_opts, [])
           ) do
      backend_info = BackendManager.info(backend_manager)

      case build_state(app, backend_manager, backend_info, opts) do
        {:ok, state, commands} ->
          {:ok, Map.put(state, :logger_token, logger_token), commands}

        {:error, reason} ->
          BackendManager.close(backend_manager, reason)
          {:error, reason}
      end
    end
  end

  defp fetch_app(opts) do
    case Keyword.fetch(opts, :root) do
      {:ok, app} when is_atom(app) -> validate_app(app)
      :error -> {:error, {:invalid_option, :root, :missing}}
      {:ok, value} -> {:error, {:invalid_option, :root, value}}
    end
  end

  defp validate_app(app) do
    required_callbacks = [event_to_msg: 2, update: 2, view: 1]

    with {:module, ^app} <- Code.ensure_loaded(app),
         [] <-
           Enum.reject(required_callbacks, fn {name, arity} ->
             function_exported?(app, name, arity)
           end) do
      {:ok, app}
    else
      {:error, reason} -> {:error, {:application, :load, {app, reason}}}
      missing when is_list(missing) -> {:error, {:application, :callbacks, {app, missing}}}
    end
  end

  defp build_state(app, backend_manager, backend_info, opts) do
    dimensions = backend_info.size |> size_to_dimensions() |> Frame.clamp_dimensions()
    app_opts = Keyword.put(opts, :dimensions, dimensions)

    with {:ok, app_state, commands} <- app_init(app, app_opts) do
      {:ok,
       %{
         app: app,
         app_state: app_state,
         backend: backend_info.backend,
         backend_manager: backend_manager,
         capabilities: backend_info.capabilities,
         dimensions: dimensions,
         render_interval: render_interval(opts),
         render_timer: nil,
         dirty: true,
         status: :running,
         stop_reason: :normal,
         async_tasks: %{},
         async_monitors: %{},
         async_links: MapSet.new(),
         frames_rendered: 0
       }, commands}
    end
  end

  defp app_init(app, opts) do
    result = if function_exported?(app, :init, 1), do: app.init(opts), else: %{}
    {app_state, commands} = Elm.normalize_init_result(result)
    validate_commands(commands, app_state)
  rescue
    exception -> {:error, application_error(:init, :error, exception, __STACKTRACE__)}
  catch
    kind, reason -> {:error, application_error(:init, kind, reason, __STACKTRACE__)}
  end

  defp app_handle_info(app, message, app_state) do
    result =
      if function_exported?(app, :handle_info, 2),
        do: app.handle_info(message, app_state),
        else: :noreply

    {new_state, commands} = Elm.normalize_update_result(result, app_state)
    validate_commands(commands, new_state)
  rescue
    exception -> {:error, application_error(:handle_info, :error, exception, __STACKTRACE__)}
  catch
    kind, reason -> {:error, application_error(:handle_info, kind, reason, __STACKTRACE__)}
  end

  defp app_update(app, message, app_state) do
    {new_state, commands} =
      app.update(message, app_state)
      |> Elm.normalize_update_result(app_state)

    validate_commands(commands, new_state)
  rescue
    exception -> {:error, application_error(:update, :error, exception, __STACKTRACE__)}
  catch
    kind, reason -> {:error, application_error(:update, kind, reason, __STACKTRACE__)}
  end

  defp validate_commands(commands, app_state) do
    if Enum.all?(commands, &valid_command?/1) do
      {:ok, app_state, commands}
    else
      {:error, {:application, :commands, {:invalid_commands, commands}}}
    end
  end

  defp valid_command?(%Command{kind: :message}), do: true
  defp valid_command?(%Command{kind: :send, value: {pid, _message}}), do: is_pid(pid)

  defp valid_command?(%Command{kind: :timer, value: {milliseconds, _message}}),
    do: is_integer(milliseconds) and milliseconds >= 0

  defp valid_command?(%Command{kind: :async, value: {function, mapper}}),
    do: is_function(function, 0) and is_function(mapper, 1)

  defp valid_command?(%Command{
         kind: :clipboard,
         value: {%TermUI.Clipboard.Operation{}, mapper}
       }),
       do: is_function(mapper, 1)

  defp valid_command?(%Command{kind: :shutdown}), do: true
  defp valid_command?(_command), do: false

  defp process_event(%Event.Resize{width: width, height: height} = event, state) do
    case BackendManager.resize(state.backend_manager, {height, width}) do
      :ok ->
        {width, height} = Frame.clamp_dimensions({width, height})
        state = %{state | dimensions: {width, height}, dirty: true}
        dispatch_event(%{event | width: width, height: height}, state)

      {:error, stop_reason} ->
        {:stop, stop_reason, %{state | stop_reason: stop_reason}}
    end
  end

  defp process_event(%Event.Focus{action: :gained} = event, state) do
    case dispatch_event(event, state) do
      {:noreply, state} -> force_render_now(state)
      stop -> stop
    end
  end

  defp process_event(event, state), do: dispatch_event(event, state)

  defp dispatch_event(event, state) do
    case app_event_to_message(state.app, event, state.app_state) do
      {:ok, :ignore} -> {:noreply, state}
      {:ok, {:msg, message}} -> process_update(message, state)
      {:error, reason} -> {:stop, reason, %{state | stop_reason: reason}}
    end
  end

  defp app_event_to_message(app, event, app_state) do
    case app.event_to_msg(event, app_state) do
      :ignore = result -> {:ok, result}
      {:msg, _message} = result -> {:ok, result}
      other -> {:error, {:application, :event_to_msg, {:invalid_result, other}}}
    end
  rescue
    exception -> {:error, application_error(:event_to_msg, :error, exception, __STACKTRACE__)}
  catch
    kind, reason -> {:error, application_error(:event_to_msg, kind, reason, __STACKTRACE__)}
  end

  defp process_update(message, state) do
    case app_update(state.app, message, state.app_state) do
      {:ok, app_state, commands} ->
        after_application_update(app_state, commands, state)

      {:error, reason} ->
        {:stop, reason, %{state | stop_reason: reason}}
    end
  end

  defp after_application_update(app_state, commands, state) do
    state = %{state | app_state: app_state, dirty: true}

    case execute_commands(commands, state) do
      {:ok, %{status: :final_render_pending} = state} -> finish(state)
      {:ok, state} -> {:noreply, schedule_render(state)}
      {:error, reason, state} -> {:stop, reason, %{state | stop_reason: reason}}
    end
  end

  defp execute_commands(commands, state) do
    Enum.reduce_while(commands, {:ok, state}, fn
      %Command{kind: :message, value: message}, {:ok, state} ->
        send(self(), {:app_message, message})
        {:cont, {:ok, state}}

      %Command{kind: :send, value: {pid, message}}, {:ok, state} ->
        send(pid, message)
        {:cont, {:ok, state}}

      %Command{kind: :timer, value: {milliseconds, message}}, {:ok, state} ->
        Process.send_after(self(), {:app_message, message}, milliseconds)
        {:cont, {:ok, state}}

      %Command{kind: :async, value: {function, mapper}}, {:ok, state} ->
        {:cont, {:ok, start_async_task(state, function, mapper)}}

      %Command{kind: :clipboard, value: {operation, mapper}}, {:ok, state} ->
        result = BackendManager.clipboard(state.backend_manager, operation)

        case safe_apply_mapper(mapper, result) do
          {:ok, message} ->
            send(self(), {:app_message, message})
            {:cont, {:ok, state}}

          {:error, reason} ->
            {:halt, {:error, reason, state}}
        end

      %Command{kind: :shutdown, value: reason}, {:ok, state} ->
        {:halt, {:ok, %{state | status: :final_render_pending, stop_reason: reason}}}
    end)
  end

  defp schedule_render(%{dirty: false} = state), do: state
  defp schedule_render(%{render_timer: {_reference, _token}} = state), do: state

  defp schedule_render(state) do
    token = make_ref()
    reference = Process.send_after(self(), {:render, token}, state.render_interval)
    %{state | render_timer: {reference, token}}
  end

  defp cancel_render(%{render_timer: nil} = state), do: state

  defp cancel_render(%{render_timer: {reference, _token}} = state) do
    _cancelled = Process.cancel_timer(reference)
    %{state | render_timer: nil}
  end

  defp force_render_now(state) do
    state = cancel_render(state)

    with :ok <- BackendManager.invalidate(state.backend_manager),
         {:ok, state} <- render_now(%{state | dirty: true}) do
      {:noreply, state}
    else
      {:error, reason} -> {:stop, reason, %{state | stop_reason: reason}}
      {:error, reason, state} -> {:stop, reason, %{state | stop_reason: reason}}
    end
  end

  defp render_now(%{dirty: false} = state), do: {:ok, state}

  defp render_now(state) do
    with {:ok, %Frame{} = frame} <- app_view(state.app, state.app_state),
         :ok <- BackendManager.draw(state.backend_manager, frame) do
      case BackendManager.flush(state.backend_manager) do
        :ok ->
          {:ok,
           %{
             state
             | dirty: false,
               frames_rendered: state.frames_rendered + 1
           }}

        {:error, reason} ->
          {:error, reason, state}
      end
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp app_view(app, app_state) do
    case app.view(app_state) do
      %Frame{} = frame -> {:ok, frame}
      other -> {:error, {:application, :view, {:expected_frame, other}}}
    end
  rescue
    exception -> {:error, application_error(:view, :error, exception, __STACKTRACE__)}
  catch
    kind, reason -> {:error, application_error(:view, kind, reason, __STACKTRACE__)}
  end

  defp finish(state) do
    state = state |> cancel_render() |> Map.put(:status, :final_render_pending)

    case render_now(state) do
      {:ok, state} ->
        reason = normalize_stop_reason(state.stop_reason)
        {:stop, reason, %{state | status: :stopping}}

      {:error, reason, state} ->
        {:stop, reason, %{state | status: :stopping, stop_reason: reason}}
    end
  end

  defp normalize_stop_reason(:normal), do: :normal
  defp normalize_stop_reason(:shutdown), do: :shutdown
  defp normalize_stop_reason({:backend, _, _, _} = reason), do: reason
  defp normalize_stop_reason({:application, _, _} = reason), do: reason
  defp normalize_stop_reason(reason), do: {:shutdown, reason}

  defp start_async_task(state, function, mapper) do
    parent = self()
    token = make_ref()

    {pid, monitor} =
      :erlang.spawn_opt(
        fn ->
          result =
            try do
              {:ok, function.()}
            rescue
              exception -> {:error, {:error, exception, __STACKTRACE__}}
            catch
              kind, reason -> {:error, {kind, reason, __STACKTRACE__}}
            end

          send(parent, {:async_result, token, result})
        end,
        [:link, :monitor]
      )

    task = %{pid: pid, monitor: monitor, mapper: mapper}

    %{
      state
      | async_tasks: Map.put(state.async_tasks, token, task),
        async_monitors: Map.put(state.async_monitors, monitor, token),
        async_links: MapSet.put(state.async_links, pid)
    }
  end

  defp safe_apply_mapper(mapper, result) do
    {:ok, mapper.(result)}
  rescue
    exception -> {:error, application_error(:command_result, :error, exception, __STACKTRACE__)}
  catch
    kind, reason -> {:error, application_error(:command_result, kind, reason, __STACKTRACE__)}
  end

  defp stop_async_tasks(state) do
    Enum.each(state.async_tasks, fn {_token, %{pid: pid, monitor: monitor}} ->
      Process.demonitor(monitor, [:flush])
      Process.exit(pid, :kill)
    end)
  end

  defp app_terminate(app, reason, app_state) do
    if function_exported?(app, :terminate, 2), do: app.terminate(reason, app_state), else: :ok
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp effective_reason(:normal, state), do: state.stop_reason
  defp effective_reason(reason, %{stop_reason: :normal}), do: reason
  defp effective_reason(_reason, state), do: state.stop_reason

  defp application_error(stage, kind, reason, stacktrace) do
    {:application, stage, {kind, reason, stacktrace}}
  end

  defp size_to_dimensions({rows, columns}), do: {columns, rows}

  defp render_interval(opts) do
    case Keyword.get(opts, :render_interval, @default_render_interval) do
      interval when is_integer(interval) and interval > 0 -> interval
      _other -> @default_render_interval
    end
  end

  defp suppress_logger?(opts) do
    case Keyword.fetch(opts, :suppress_logger) do
      {:ok, value} when is_boolean(value) -> value
      {:ok, _invalid} -> false
      :error -> full_screen_backend?(Keyword.get(opts, :backend, :auto))
    end
  end

  defp full_screen_backend?(backend)
       when backend in [:auto, :raw, :tty, TermUI.Backend.Raw, TermUI.Backend.TTY],
       do: true

  defp full_screen_backend?({backend, _opts}), do: full_screen_backend?(backend)
  defp full_screen_backend?(_backend), do: false

  defp start_monitor(nil, opts), do: :gen_server.start_monitor(__MODULE__, opts, [])

  defp start_monitor(name, opts) do
    :gen_server.start_monitor(normalize_server_name(name), __MODULE__, opts, [])
  end

  defp normalize_server_name(name) when is_atom(name), do: {:local, name}
  defp normalize_server_name({:global, _term} = name), do: name
  defp normalize_server_name({:via, module, _term} = name) when is_atom(module), do: name
end
