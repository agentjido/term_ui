defmodule TermUI.Backend.SSH do
  @moduledoc """
  A complete backend for remote SSH terminal sessions.

  Each session owns one `TermUI.Runtime`. The backend parses remote input,
  tracks PTY size, draws complete `TermUI.Frame` values, and restores the
  remote terminal when the runtime stops. It does not start an SSH daemon or
  define authentication and connection limits. The host application keeps
  control of those policies.

  ## Direct session API

  Applications that already own an SSH server can start a session directly.
  The `:output` option can be a one-argument function or a process.

      {:ok, session} =
        TermUI.Backend.SSH.start_session(MyApp,
          size: {24, 80},
          output: fn data -> MySSHTransport.send(data) end
        )

      :ok = TermUI.Backend.SSH.input(session, remote_bytes)
      :ok = TermUI.Backend.SSH.resize(session, 40, 120)
      :ok = TermUI.Backend.SSH.stop_session(session)

  A process output target receives one bounded output request at a time:

      {:term_ui_ssh_output, session, token, data}

  The owner must call `ack_output/3` after it sends that data. This form is
  useful for SSH implementations that require channel output to come from the
  channel process.

  ## OTP SSH

  `TermUI.Backend.SSH.Channel` is an `:ssh_server_channel` callback for OTP
  SSH. Configure it as the daemon's `:ssh_cli` value. The host application
  still supplies all authentication, key, and session-limit options.

      :ssh.daemon(port,
        system_dir: system_dir,
        pwdfun: password_fun,
        ssh_cli: {TermUI.Backend.SSH.Channel, [MyApp, runtime_options: []]}
      )

  Output is bounded to one in-flight frame and one waiting frame. A new frame
  replaces a stale waiting frame. The next diff is always calculated from the
  last frame that the SSH transport confirmed, so coalescing cannot corrupt
  the remote screen.
  """

  @behaviour TermUI.Backend

  alias TermUI.Frame

  @typedoc "Remote mouse tracking mode."
  @type mouse_mode :: :none | :click | :drag | :all

  @type t :: %__MODULE__{
          session: pid(),
          size: TermUI.Backend.size(),
          capabilities: map()
        }

  @enforce_keys [:session, :size, :capabilities]
  defstruct [:session, :size, :capabilities]

  @doc "Starts one SSH session and one isolated TermUI runtime."
  @spec start_session(module(), keyword()) :: GenServer.on_start()
  def start_session(root, opts \\ []) when is_atom(root) and is_list(opts) do
    GenServer.start(session_module(), {root, Keyword.put_new(opts, :owner, self())})
  end

  @doc "Sends remote terminal bytes to a session."
  @spec input(GenServer.server(), iodata()) :: :ok | {:error, term()}
  def input(session, data), do: GenServer.call(session, {:input, data})

  @doc "Sends one normalized terminal event to a session."
  @spec send_event(GenServer.server(), TermUI.Event.t()) :: :ok | {:error, term()}
  def send_event(session, event), do: GenServer.call(session, {:event, event})

  @doc "Updates a remote PTY size in rows and columns."
  @spec resize(GenServer.server(), pos_integer(), pos_integer()) :: :ok | {:error, term()}
  def resize(session, rows, columns), do: GenServer.call(session, {:resize, rows, columns})

  @doc "Confirms a process-target output request."
  @spec ack_output(GenServer.server(), reference(), :ok | {:error, term()}) :: :ok
  def ack_output(session, token, result) do
    GenServer.cast(session, {:output_result, token, result})
    :ok
  end

  @doc "Requests a final render and a clean session stop."
  @spec stop_session(GenServer.server(), term()) :: :ok
  def stop_session(session, reason \\ :normal) do
    GenServer.call(session, {:stop, reason})
  catch
    :exit, _reason -> :ok
  end

  @doc "Reports runtime, size, and bounded queue state for a session."
  @spec session_info(GenServer.server()) :: map()
  def session_info(session), do: GenServer.call(session, :info)

  @doc "Reports that the remote channel disconnected."
  @spec disconnect(GenServer.server(), term()) :: :ok
  def disconnect(session, reason \\ :disconnected) do
    GenServer.cast(session, {:disconnect, reason})
    :ok
  end

  @impl true
  @doc false
  def init(opts) do
    with {:ok, session} <- fetch_session(opts),
         {:ok, size} <- valid_size(Keyword.get(opts, :size, {24, 80})),
         true <- Process.alive?(session) do
      capabilities = Keyword.get(opts, :capabilities, default_capabilities(size, opts))
      {:ok, %__MODULE__{session: session, size: size, capabilities: capabilities}}
    else
      false -> {:error, :session_not_alive}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @doc false
  def size(%__MODULE__{size: size}), do: {:ok, size}

  @impl true
  @doc false
  def capabilities(%__MODULE__{capabilities: capabilities}), do: capabilities

  @impl true
  @doc false
  def draw(%__MODULE__{} = state, %Frame{} = frame) do
    case GenServer.call(state.session, {:frame, frame}) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @doc false
  def flush(%__MODULE__{} = state), do: {:ok, state}

  @impl true
  @doc false
  def invalidate(%__MODULE__{} = state) do
    case GenServer.call(state.session, :invalidate) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @doc false
  def poll_event(%__MODULE__{} = state, timeout) do
    case GenServer.call(state.session, {:poll_event, timeout}, timeout + 1_000) do
      {:ok, event} -> {:ok, event, state}
      :timeout -> {:timeout, state}
      {:error, reason} -> {:error, reason, state}
    end
  catch
    :exit, reason -> {:error, {:session_exit, reason}, state}
  end

  @impl true
  @doc false
  def resize(%__MODULE__{} = state, size) do
    case valid_size(size) do
      {:ok, size} -> {:ok, %{state | size: size}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @doc false
  def shutdown(%__MODULE__{} = state, reason) do
    GenServer.call(state.session, {:backend_shutdown, reason}, :infinity)
  catch
    :exit, reason -> {:error, {:session_exit, reason}}
  end

  @impl true
  @doc false
  def abort_startup(%__MODULE__{}, _reason), do: :ok

  defp fetch_session(opts) do
    case Keyword.fetch(opts, :session) do
      {:ok, session} when is_pid(session) -> {:ok, session}
      :error -> {:error, {:missing_option, :session}}
      {:ok, invalid} -> {:error, {:invalid_option, :session, invalid}}
    end
  end

  defp valid_size({rows, columns} = size)
       when is_integer(rows) and rows > 0 and is_integer(columns) and columns > 0,
       do: {:ok, size}

  defp valid_size(invalid), do: {:error, {:invalid_size, invalid}}

  defp default_capabilities(size, opts) do
    %{
      colors: :true_color,
      unicode: true,
      mouse: Keyword.get(opts, :mouse_tracking, :none) != :none,
      paste: Keyword.get(opts, :bracketed_paste, true),
      focus: Keyword.get(opts, :focus_events, true),
      dimensions: size,
      remote: :ssh
    }
  end

  defp session_module, do: Module.concat(__MODULE__, "Session")
end
