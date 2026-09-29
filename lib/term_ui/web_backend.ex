defmodule TermUI.WebBackend do
  @moduledoc """
  A browser display and input backend with no required web framework.

  The host starts one session for one authenticated browser connection:

      {:ok, session} = TermUI.WebBackend.start_session(MyApp, size: {24, 80})

  The output process receives `{:term_ui_web_output, session, payload}`.
  Encode the payload as JSON and send it through the connection. After the
  browser applies a frame, pass its acknowledgement to `input/2`:

      TermUI.WebBackend.input(session, %{"v" => 1, "type" => "ack", "seq" => 1})

  Browser input uses the same versioned maps. See `TermUI.WebBackend.Protocol`.
  Output has one frame in flight and one current waiting frame. A changed-row
  frame always uses the last browser-confirmed frame as its base.

  The connection owner supplies authentication, origin policy, message byte
  limits, input rate limits, and allowed application modules. The browser must
  never select an arbitrary BEAM module. Disconnect stops the session and its
  runtime. A reconnect starts with a complete frame.
  """

  @behaviour TermUI.Backend

  alias TermUI.Frame
  alias TermUI.WebBackend.Protocol

  @type t :: %__MODULE__{session: pid(), size: TermUI.Backend.size(), capabilities: map()}
  @enforce_keys [:session, :size, :capabilities]
  defstruct [:session, :size, :capabilities]

  @doc "Starts one browser session and one isolated application runtime."
  @spec start_session(module(), keyword()) :: GenServer.on_start()
  def start_session(root, opts \\ []) when is_atom(root) and is_list(opts) do
    opts = opts |> Keyword.put_new(:owner, self()) |> Keyword.put_new(:output, self())
    GenServer.start(Module.concat(__MODULE__, "Session"), {root, opts})
  end

  @doc "Accepts a decoded browser input, acknowledgement, or resync message."
  @spec input(GenServer.server(), term()) :: :ok | {:error, term()}
  def input(session, payload), do: GenServer.call(session, {:input, payload})

  @doc "Reports runtime, dimensions, connection state, and queue sizes."
  @spec session_info(GenServer.server()) :: map()
  def session_info(session), do: GenServer.call(session, :info)

  @doc "Requests a final frame and normal runtime shutdown."
  @spec stop_session(GenServer.server()) :: :ok
  def stop_session(session) do
    GenServer.call(session, :stop)
  catch
    :exit, _reason -> :ok
  end

  @doc "Reports a connection close and releases the runtime without waiting for output."
  @spec disconnect(GenServer.server(), term()) :: :ok
  def disconnect(session, reason \\ :disconnected) do
    GenServer.cast(session, {:disconnect, reason})
    :ok
  end

  @impl true
  @doc false
  def init(opts) do
    with session when is_pid(session) <- Keyword.get(opts, :session),
         true <- Process.alive?(session),
         {:ok, limits} <- Protocol.limits(Keyword.get(opts, :limits, %{})),
         {:ok, size} <- Protocol.size(Keyword.get(opts, :size), limits),
         capabilities when is_map(capabilities) <- Keyword.get(opts, :capabilities) do
      {:ok,
       %__MODULE__{
         session: session,
         size: size,
         capabilities: capabilities
       }}
    else
      _invalid -> {:error, :invalid_web_session}
    end
  end

  @impl true
  @doc false
  def size(state), do: {:ok, state.size}

  @impl true
  @doc false
  def capabilities(state), do: state.capabilities

  @impl true
  @doc false
  def draw(state, %Frame{} = frame) do
    case GenServer.call(state.session, {:frame, frame}) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  @doc false
  def flush(state), do: {:ok, state}

  @impl true
  @doc false
  def invalidate(state) do
    :ok = GenServer.call(state.session, :invalidate)
    {:ok, state}
  end

  @impl true
  @doc false
  def poll_event(state, timeout) do
    case GenServer.call(state.session, {:poll, timeout}, timeout + 1_000) do
      {:ok, event} -> {:ok, event, state}
      :timeout -> {:timeout, state}
      {:error, reason} -> {:error, reason, state}
    end
  catch
    :exit, reason -> {:error, {:web_session_exit, reason}, state}
  end

  @impl true
  @doc false
  def resize(state, size), do: {:ok, %{state | size: size}}

  @impl true
  @doc false
  def shutdown(state, reason) do
    GenServer.call(state.session, {:backend_shutdown, reason})
  catch
    :exit, _reason -> :ok
  end
end
