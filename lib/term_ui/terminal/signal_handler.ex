defmodule TermUI.Terminal.SignalHandler do
  @moduledoc false

  @behaviour :gen_event

  @impl true
  def init(terminal) when is_pid(terminal) do
    enable_resize_signal()
    {:ok, terminal}
  end

  def init({terminal, restore_request, resize_message}) when is_pid(terminal) do
    enable_resize_signal()
    {:ok, {terminal, restore_request, resize_message}}
  end

  @impl true
  def handle_event(:sigwinch, terminal) when is_pid(terminal) do
    send(terminal, :sigwinch)
    {:ok, terminal}
  end

  def handle_event(:sigwinch, {terminal, _restore_request, resize_message} = state) do
    if resize_message, do: send(terminal, resize_message)
    {:ok, state}
  end

  def handle_event(:sigterm, terminal) when is_pid(terminal) do
    restore_terminal(terminal)
    {:ok, terminal}
  end

  def handle_event(:sigterm, {terminal, restore_request, _resize_message} = state) do
    restore_terminal(terminal, restore_request)
    {:ok, state}
  end

  def handle_event(:sigcont, terminal) when is_pid(terminal) do
    send(terminal, :sigcont)
    {:ok, terminal}
  end

  def handle_event(:sigcont, {terminal, _restore_request, _resize_message} = state) do
    send(terminal, :terminal_resume)
    {:ok, state}
  end

  def handle_event(_signal, terminal), do: {:ok, terminal}

  @impl true
  def handle_call(:sync, terminal) do
    # OTP's signal handler sent its message from this same event-manager
    # process. This call therefore follows it in user_drv's mailbox.
    if Process.whereis(:user_drv), do: :sys.get_state(:user_drv, 1_000)
    {:ok, :ok, terminal}
  end

  def handle_call(_request, terminal), do: {:ok, :ok, terminal}

  @impl true
  def handle_info(_message, terminal), do: {:ok, terminal}

  @impl true
  def terminate(_reason, _terminal), do: :ok

  @impl true
  def code_change(_old_version, terminal, _extra), do: {:ok, terminal}

  defp restore_terminal(terminal, request \\ :restore) do
    GenServer.call(terminal, request, 2000)
  catch
    :exit, _reason -> :ok
  end

  # OTP 26 exposes os:set_signal/2 but rejects SIGWINCH and SIGCONT. Keep the event
  # subscriber installed there so VM-handled signals such as SIGTERM remain
  # available; resize signals activate automatically on supporting versions.
  defp enable_resize_signal do
    Enum.each([:sigwinch, :sigcont], &enable_signal/1)
  end

  defp enable_signal(signal) do
    :os.set_signal(signal, :handle)
  rescue
    ArgumentError -> :ok
  end
end
