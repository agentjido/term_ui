defmodule TermUI.Terminal.SignalHandler do
  @moduledoc false
  @behaviour :gen_event

  @impl true
  def init(owner) do
    :os.set_signal(:sigcont, :handle)
    {:ok, owner}
  end

  @impl true
  def handle_event(:sigcont, owner) do
    send(owner, :terminal_resume)
    {:ok, owner}
  end

  def handle_event(_event, owner), do: {:ok, owner}

  @impl true
  def handle_call(:sync, owner) do
    # OTP's handler sent SIGCONT from this same event-manager process. Wait
    # for that earlier message without starting another shell or input group.
    if Process.whereis(:user_drv), do: :sys.get_state(:user_drv, 1_000)
    {:ok, :ok, owner}
  end

  def handle_call(_request, owner), do: {:ok, :ok, owner}

  @impl true
  def handle_info(_message, owner), do: {:ok, owner}

  @impl true
  def terminate(_reason, _owner), do: :ok

  @impl true
  def code_change(_old_version, owner, _extra), do: {:ok, owner}
end
