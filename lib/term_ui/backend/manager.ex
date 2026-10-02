defmodule TermUI.Backend.Manager do
  @moduledoc false

  use GenServer

  alias TermUI.Backend
  alias TermUI.Backend.{Raw, Selector, TTY}
  alias TermUI.Clipboard.Operation
  alias TermUI.Frame
  alias TermUI.Terminal.{RawMode, SignalHandler, SizeDetector}

  require Logger

  @input_poll_timeout 10
  @fast_size_poll_interval 200
  @fallback_size_poll_interval 1_000
  @minimum_size_poll_interval 50

  @type info :: %{
          backend: module(),
          size: Backend.size(),
          capabilities: map()
        }

  @doc "Starts the serialized owner for one backend session."
  @spec start_link(pid(), Backend.spec(), keyword()) :: GenServer.on_start()
  def start_link(owner, spec, opts) when is_pid(owner) do
    GenServer.start_link(__MODULE__, {owner, spec, opts})
  end

  @doc "Returns the selected backend, size, and capabilities."
  @spec info(pid()) :: info()
  def info(manager), do: GenServer.call(manager, :info)

  @doc "Marks successful application initialization before the first view."
  @spec complete_startup(pid()) :: :ok
  def complete_startup(manager), do: GenServer.call(manager, :complete_startup)

  @doc "Starts input and size polling after the runtime is ready."
  @spec activate(pid()) :: :ok
  def activate(manager), do: GenServer.call(manager, :activate)

  @doc "Draws one complete frame through the selected backend."
  @spec draw(pid(), Frame.t()) :: :ok | {:error, term()}
  def draw(manager, frame), do: GenServer.call(manager, {:draw, frame})

  @doc "Flushes pending backend output."
  @spec flush(pid()) :: :ok | {:error, term()}
  def flush(manager), do: GenServer.call(manager, :flush)

  @doc "Invalidates previous output through the backend owner."
  @spec invalidate(pid()) :: :ok | {:error, term()}
  def invalidate(manager), do: GenServer.call(manager, :invalidate)

  @doc "Runs one serialized clipboard operation."
  @spec clipboard(pid(), Operation.t()) :: :ok | {:error, term()}
  def clipboard(manager, %Operation{} = operation),
    do: GenServer.call(manager, {:clipboard, operation})

  @doc "Updates the backend size after a resize event."
  @spec resize(pid(), Backend.size()) :: :ok | {:error, term()}
  def resize(manager, size), do: GenServer.call(manager, {:resize, size})

  @doc "Closes the backend session and waits for cleanup."
  @spec close(pid(), term()) :: :ok | {:error, term()}
  def close(manager, reason) do
    GenServer.call(manager, {:close, reason}, :infinity)
  catch
    :exit, reason -> {:error, {:backend_manager_exit, reason}}
  end

  @doc "Releases backend state before application initialization has completed."
  @spec abort_startup(pid(), term()) :: :ok | {:error, term()}
  def abort_startup(manager, reason) do
    GenServer.call(manager, {:abort_startup, reason}, :infinity)
  catch
    :exit, reason -> {:error, {:backend_manager_exit, reason}}
  end

  @impl true
  @doc false
  def init({owner, spec, opts}) do
    Process.flag(:trap_exit, true)
    opts = Keyword.put_new(opts, :runtime, owner)

    with {:ok, requested_size_poll_interval} <- parse_size_poll_interval(opts),
         {:ok, backend, backend_state} <- open_backend(spec, opts),
         {:ok, size} <- query_size(backend, backend_state),
         {:ok, capabilities} <- query_capabilities(backend, backend_state) do
      register_resume_handler(backend)

      {:ok,
       %{
         owner: owner,
         backend: backend,
         backend_state: backend_state,
         size: size,
         capabilities: capabilities,
         size_poll_interval: resolve_size_poll_interval(backend, requested_size_poll_interval),
         active?: false,
         startup_complete?: false,
         closed?: false
       }}
    else
      {:opened_error, backend, backend_state, reason} ->
        _cleanup_result = close_backend(backend, backend_state, reason, :abort_startup)
        {:stop, reason}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  @doc false
  def handle_call(:info, _from, state) do
    {:reply, %{backend: state.backend, size: state.size, capabilities: state.capabilities}, state}
  end

  def handle_call(:complete_startup, _from, state),
    do: {:reply, :ok, %{state | startup_complete?: true}}

  def handle_call(:activate, _from, %{active?: false} = state) do
    send(self(), :poll_input)
    schedule_size_poll(state)
    {:reply, :ok, %{state | active?: true}}
  end

  def handle_call(:activate, _from, state), do: {:reply, :ok, state}

  def handle_call({:draw, %Frame{} = frame}, _from, state) do
    case invoke_state_callback(state, :draw, [frame]) do
      {:ok, backend_state} -> {:reply, :ok, %{state | backend_state: backend_state}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:flush, _from, state) do
    case invoke_state_callback(state, :flush, []) do
      {:ok, backend_state} -> {:reply, :ok, %{state | backend_state: backend_state}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:invalidate, _from, state) do
    case invoke_invalidation(state) do
      {:ok, backend_state} -> {:reply, :ok, %{state | backend_state: backend_state}}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:clipboard, %Operation{} = operation}, _from, state) do
    if function_exported?(state.backend, :clipboard, 2) do
      case invoke_state_callback(state, :clipboard, [operation]) do
        {:ok, backend_state} -> {:reply, :ok, %{state | backend_state: backend_state}}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, backend_error(state.backend, :clipboard, :unsupported)}, state}
    end
  end

  def handle_call({:resize, size}, _from, state) do
    case invoke_state_callback(state, :resize, [size]) do
      {:ok, backend_state} ->
        {:reply, :ok, %{state | backend_state: backend_state, size: size}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:close, reason}, _from, state) do
    result = close_backend(state.backend, state.backend_state, reason)
    {:stop, :normal, result, %{state | closed?: true, active?: false}}
  end

  def handle_call({:abort_startup, reason}, _from, state) do
    result = close_backend(state.backend, state.backend_state, reason, :abort_startup)
    {:stop, :normal, result, %{state | closed?: true, active?: false}}
  end

  @impl true
  @doc false
  def handle_info(:terminal_resume, %{active?: true} = state) do
    with :ok <- wait_for_otp_signal(state.backend),
         {:ok, backend_state} <- invoke_resume(state) do
      send(state.owner, :backend_resumed)
      {:noreply, %{state | backend_state: backend_state}}
    else
      {:error, reason} ->
        send(state.owner, {:backend_failed, reason})
        {:noreply, %{state | active?: false}}
    end
  end

  def handle_info(:terminal_resume, state), do: {:noreply, state}

  def handle_info({:gen_event_EXIT, {SignalHandler, _owner}, reason}, state) do
    failure = backend_error(state.backend, :resume, {:signal_handler_exit, reason})
    send(state.owner, {:backend_failed, failure})
    {:noreply, %{state | active?: false}}
  end

  def handle_info(:poll_input, %{active?: true} = state) do
    case invoke_poll(state) do
      {:ok, event, backend_state} ->
        send(state.owner, {:backend_event, event})
        send(self(), :poll_input)
        {:noreply, %{state | backend_state: backend_state}}

      {:timeout, backend_state} ->
        send(self(), :poll_input)
        {:noreply, %{state | backend_state: backend_state}}

      {:error, reason, backend_state} ->
        send(state.owner, {:backend_failed, reason})
        {:noreply, %{state | backend_state: backend_state, active?: false}}
    end
  end

  def handle_info(:poll_input, state), do: {:noreply, state}

  def handle_info(:poll_size, %{active?: true} = state) do
    state =
      case refresh_size(state) do
        {:ok, size, backend_state} ->
          if size != state.size, do: send(state.owner, {:backend_size, size})
          %{state | size: size, backend_state: backend_state}

        {:error, _reason} ->
          state
      end

    schedule_size_poll(state)
    {:noreply, state}
  end

  def handle_info(:poll_size, state), do: {:noreply, state}

  def handle_info({:EXIT, owner, reason}, %{owner: owner} = state) do
    {:stop, reason, state}
  end

  def handle_info({:EXIT, reader, reason}, state) do
    if reader == input_reader(state.backend_state) and state.active? do
      failure = backend_error(state.backend, :input, {:reader_exit, reason})
      send(state.owner, {:backend_failed, failure})
      {:noreply, %{state | active?: false}}
    else
      {:noreply, state}
    end
  end

  @impl true
  @doc false
  def terminate(reason, %{closed?: false} = state) do
    callback = if state.startup_complete?, do: :shutdown, else: :abort_startup
    _cleanup_result = close_backend(state.backend, state.backend_state, reason, callback)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  defp invoke_invalidation(state) do
    if function_exported?(state.backend, :invalidate, 1),
      do: invoke_state_callback(state, :invalidate, []),
      else: invoke_state_callback(state, :resize, [state.size])
  end

  defp invoke_resume(state) do
    if function_exported?(state.backend, :resume, 1),
      do: invoke_state_callback(state, :resume, []),
      else: invoke_invalidation(state)
  end

  defp register_resume_handler(backend) when backend in [Raw, TTY] do
    if match?({:unix, _}, :os.type()) do
      case :gen_event.add_sup_handler(:erl_signal_server, {SignalHandler, self()}, self()) do
        :ok -> :ok
        {:error, reason} -> Logger.warning("Cannot register terminal resume: #{inspect(reason)}")
      end
    end
  end

  defp register_resume_handler(_backend), do: :ok

  defp unregister_resume_handler(backend) when backend in [Raw, TTY] do
    if match?({:unix, _}, :os.type()) do
      :gen_event.delete_handler(:erl_signal_server, {SignalHandler, self()}, :normal)
    end

    :ok
  catch
    :exit, _reason -> :ok
  end

  defp unregister_resume_handler(_backend), do: :ok

  defp wait_for_otp_signal(backend) when backend in [Raw, TTY] do
    case :gen_event.call(:erl_signal_server, {SignalHandler, self()}, :sync, 1_000) do
      :ok -> :ok
      {:error, reason} -> {:error, backend_error(backend, :resume, {:signal_sync, reason})}
    end
  rescue
    exception -> {:error, backend_error(backend, :resume, {:exception, exception})}
  catch
    kind, reason -> {:error, backend_error(backend, :resume, {kind, reason})}
  end

  defp wait_for_otp_signal(_backend), do: :ok

  defp open_backend(:auto, opts) do
    case Selector.select() do
      {:raw, raw_opts} ->
        start_backend(Raw, Keyword.merge(opts, Map.to_list(raw_opts)),
          raw_mode_session: raw_opts.raw_mode_session
        )

      {:tty, capabilities} ->
        start_backend(TTY, Keyword.put(opts, :capabilities, capabilities))
    end
  end

  defp open_backend(:raw, opts) do
    case Selector.attempt_raw_mode() do
      {:raw, raw_opts} ->
        start_backend(Raw, Keyword.merge(opts, Map.to_list(raw_opts)),
          raw_mode_session: raw_opts.raw_mode_session
        )

      {:tty, capabilities} ->
        {:error,
         {:raw_mode_unavailable, Map.get(capabilities, :raw_mode_error, :already_started)}}
    end
  end

  defp open_backend(:tty, opts), do: start_backend(TTY, opts)

  defp open_backend({module, backend_opts}, opts)
       when is_atom(module) and is_list(backend_opts) do
    start_backend(module, Keyword.merge(opts, backend_opts))
  end

  defp open_backend(module, opts) when is_atom(module), do: start_backend(module, opts)

  defp start_backend(module, opts, open_opts \\ []) do
    case module.init(opts) do
      {:ok, state} ->
        {:ok, module, state}

      {:error, reason} ->
        maybe_restore_raw(open_opts)
        {:error, {:backend_init_failed, module, reason}}

      other ->
        maybe_restore_raw(open_opts)
        {:error, {:invalid_backend_init, module, other}}
    end
  rescue
    exception ->
      maybe_restore_raw(open_opts)
      {:error, {:backend_init_failed, module, exception}}
  catch
    kind, reason ->
      maybe_restore_raw(open_opts)
      {:error, {:backend_init_failed, module, {kind, reason}}}
  end

  defp query_size(backend, backend_state) do
    case backend.size(backend_state) do
      {:ok, {rows, columns} = size}
      when is_integer(rows) and rows > 0 and is_integer(columns) and columns > 0 ->
        {:ok, size}

      {:error, reason} ->
        {:opened_error, backend, backend_state, backend_error(backend, :size, reason)}

      other ->
        {:opened_error, backend, backend_state,
         backend_error(backend, :size, {:invalid_result, other})}
    end
  rescue
    exception ->
      {:opened_error, backend, backend_state, backend_error(backend, :size, exception)}
  catch
    kind, reason ->
      {:opened_error, backend, backend_state, backend_error(backend, :size, {kind, reason})}
  end

  defp query_capabilities(backend, backend_state) do
    case backend.capabilities(backend_state) do
      capabilities when is_map(capabilities) ->
        {:ok, capabilities}

      other ->
        {:opened_error, backend, backend_state,
         backend_error(backend, :capabilities, {:invalid_result, other})}
    end
  rescue
    exception ->
      {:opened_error, backend, backend_state, backend_error(backend, :capabilities, exception)}
  catch
    kind, reason ->
      {:opened_error, backend, backend_state,
       backend_error(backend, :capabilities, {kind, reason})}
  end

  defp invoke_state_callback(state, stage, args) do
    result = apply(state.backend, stage, [state.backend_state | args])

    case result do
      {:ok, backend_state} -> {:ok, backend_state}
      {:error, reason} -> {:error, backend_error(state.backend, stage, reason)}
      other -> {:error, backend_error(state.backend, stage, {:invalid_result, other})}
    end
  rescue
    exception -> {:error, backend_error(state.backend, stage, exception)}
  catch
    kind, reason -> {:error, backend_error(state.backend, stage, {kind, reason})}
  end

  defp invoke_poll(state) do
    case state.backend.poll_event(state.backend_state, @input_poll_timeout) do
      {:ok, event, backend_state} ->
        {:ok, event, backend_state}

      {:timeout, backend_state} ->
        {:timeout, backend_state}

      {:error, reason, backend_state} ->
        {:error, backend_error(state.backend, :input, reason), backend_state}

      other ->
        {:error, backend_error(state.backend, :input, {:invalid_result, other}),
         state.backend_state}
    end
  rescue
    exception ->
      {:error, backend_error(state.backend, :input, exception), state.backend_state}
  catch
    kind, reason ->
      {:error, backend_error(state.backend, :input, {kind, reason}), state.backend_state}
  end

  defp refresh_size(state) do
    state
    |> size_result()
    |> normalize_size_result(state.backend)
  rescue
    exception -> {:error, backend_error(state.backend, :size, exception)}
  catch
    kind, reason -> {:error, backend_error(state.backend, :size, {kind, reason})}
  end

  defp size_result(state) do
    if function_exported?(state.backend, :refresh_size, 1) do
      state.backend.refresh_size(state.backend_state)
    else
      state.backend.size(state.backend_state)
      |> add_backend_state(state.backend_state)
    end
  end

  defp add_backend_state({:ok, size}, backend_state), do: {:ok, size, backend_state}
  defp add_backend_state(other, _backend_state), do: other

  defp normalize_size_result(
         {:ok, {rows, columns} = size, backend_state},
         _backend
       )
       when is_integer(rows) and rows > 0 and is_integer(columns) and columns > 0,
       do: {:ok, size, backend_state}

  defp normalize_size_result({:error, reason}, backend),
    do: {:error, backend_error(backend, :size, reason)}

  defp normalize_size_result(other, backend),
    do: {:error, backend_error(backend, :size, {:invalid_result, other})}

  defp close_backend(module, state, reason, callback \\ :shutdown) do
    unregister_resume_handler(module)

    callback = if function_exported?(module, callback, 2), do: callback, else: :shutdown

    case apply(module, callback, [state, reason]) do
      :ok -> :ok
      {:error, error} -> {:error, backend_error(module, :shutdown, error)}
      other -> {:error, backend_error(module, :shutdown, {:invalid_result, other})}
    end
  rescue
    exception -> {:error, backend_error(module, :shutdown, exception)}
  catch
    kind, error -> {:error, backend_error(module, :shutdown, {kind, error})}
  end

  defp backend_error(backend, stage, reason), do: {:backend, backend, stage, reason}

  defp input_reader(%{input_reader: reader}), do: reader
  defp input_reader(_backend_state), do: nil

  defp parse_size_poll_interval(opts) do
    case Keyword.get(opts, :size_poll_interval, :auto) do
      :auto ->
        {:ok, :auto}

      :disabled ->
        {:ok, nil}

      interval when is_integer(interval) and interval >= @minimum_size_poll_interval ->
        {:ok, interval}

      invalid ->
        {:error, {:invalid_size_poll_interval, invalid}}
    end
  end

  defp resolve_size_poll_interval(_backend, nil), do: nil
  defp resolve_size_poll_interval(_backend, interval) when is_integer(interval), do: interval

  defp resolve_size_poll_interval(backend, :auto) when backend in [Raw, TTY] do
    if fast_size_detection_available?(),
      do: @fast_size_poll_interval,
      else: @fallback_size_poll_interval
  end

  defp resolve_size_poll_interval(_backend, :auto), do: @fast_size_poll_interval

  defp fast_size_detection_available? do
    match?({:ok, _size}, SizeDetector.detect_from_io()) or
      match?({:ok, _size}, SizeDetector.detect_from_env())
  end

  defp schedule_size_poll(%{size_poll_interval: nil}), do: :ok

  defp schedule_size_poll(%{size_poll_interval: interval}) do
    Process.send_after(self(), :poll_size, interval)
    :ok
  end

  defp maybe_restore_raw(opts) do
    case Keyword.get(opts, :raw_mode_session) do
      nil ->
        :ok

      session ->
        _result = RawMode.exit(session)
        :ok
    end
  rescue
    _exception -> :ok
  catch
    _kind, _reason -> :ok
  end
end
