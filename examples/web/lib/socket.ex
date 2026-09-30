defmodule TermUIWebExample.Socket do
  @moduledoc false
  @behaviour WebSock

  alias TermUI.WebBackend

  @impl true
  def init(opts) do
    root = Map.get(opts, :root, TermUIWebExample.App)
    runtime_options = Map.get(opts, :runtime_options, [])
    {:ok, session} = WebBackend.start_session(root, runtime_options: runtime_options)
    {:ok, %{session: session, window: System.monotonic_time(:millisecond), messages: 0}}
  end

  @impl true
  def handle_in({bytes, [opcode: :text]}, state) when byte_size(bytes) <= 70_000 do
    now = System.monotonic_time(:millisecond)
    state = if now - state.window >= 1_000, do: %{state | window: now, messages: 0}, else: state
    state = %{state | messages: state.messages + 1}

    if state.messages > 300 do
      {:stop, :normal, {1008, "Input rate limit"}, state}
    else
      case Jason.decode(bytes) do
        {:ok, payload} -> apply_input(payload, state)
        {:error, _reason} -> {:stop, :normal, {1008, "Invalid input"}, state}
      end
    end
  end

  def handle_in(_frame, state), do: {:stop, :normal, {1008, "Input size or type limit"}, state}

  defp apply_input(payload, state) do
    case WebBackend.input(state.session, payload) do
      :ok -> {:ok, state}
      {:error, :stopping} -> {:ok, state}
      {:error, _reason} -> {:stop, :normal, {1008, "Invalid input"}, state}
    end
  catch
    :exit, _reason -> {:stop, :normal, {1011, "Session closed"}, state}
  end

  @impl true
  def handle_info(
        {:term_ui_web_output, session, %{"type" => "closed"} = payload},
        %{session: session} = state
      ) do
    code = if payload["reason"] == "normal", do: 1000, else: 1011
    {:stop, :normal, {code, "Session closed"}, {:text, Jason.encode!(payload)}, state}
  end

  def handle_info({:term_ui_web_output, session, payload}, %{session: session} = state),
    do: {:push, {:text, Jason.encode!(payload)}, state}

  def handle_info(_message, state), do: {:ok, state}

  @impl true
  def terminate(_reason, %{session: session}), do: WebBackend.disconnect(session)
end
