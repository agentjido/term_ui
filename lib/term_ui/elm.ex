defmodule TermUI.Elm do
  @moduledoc """
  The application contract for TermUI.

  One runtime owns one application state. `event_to_msg/2`, `update/2`, and
  `view/1` are pure. Effects are returned as `TermUI.Command` data.
  """

  alias TermUI.{Command, Event, Frame}

  @type state :: term()
  @type message :: term()
  @type update_result :: state() | {state(), [Command.t()]} | :noreply

  @callback init(keyword()) :: state() | {state(), [Command.t()]}
  @callback event_to_msg(Event.t(), state()) :: {:msg, message()} | :ignore
  @callback update(message(), state()) :: update_result()
  @callback view(state()) :: Frame.t()
  @callback handle_info(term(), state()) :: update_result()
  @callback terminate(term(), state()) :: term()

  @optional_callbacks init: 1, handle_info: 2, terminate: 2

  defmacro __using__(_opts) do
    quote do
      @behaviour TermUI.Elm

      @impl TermUI.Elm
      def init(_opts), do: %{}

      @impl TermUI.Elm
      def handle_info(_message, _state), do: :noreply

      @impl TermUI.Elm
      def terminate(_reason, _state), do: :ok

      defoverridable init: 1, handle_info: 2, terminate: 2
    end
  end

  @doc false
  @spec normalize_init_result(term()) :: {state(), [Command.t()]}
  def normalize_init_result({state, commands}) when is_list(commands), do: {state, commands}
  def normalize_init_result(state), do: {state, []}

  @doc false
  @spec normalize_update_result(term(), state()) :: {state(), [Command.t()]}
  def normalize_update_result({state, commands}, _old_state) when is_list(commands),
    do: {state, commands}

  def normalize_update_result(:noreply, old_state), do: {old_state, []}
  def normalize_update_result(state, _old_state), do: {state, []}
end
