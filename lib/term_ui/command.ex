defmodule TermUI.Command do
  @moduledoc """
  Data that asks the runtime to do work outside an Elm update.

  Commands do not contain component identifiers. A runtime delivers command
  results to its one application state.
  """

  @type kind :: :message | :send | :timer | :async | :clipboard | :shutdown
  @type message_command :: %__MODULE__{kind: :message, value: term()}
  @type send_command :: %__MODULE__{kind: :send, value: {pid(), term()}}
  @type timer_command :: %__MODULE__{kind: :timer, value: {non_neg_integer(), term()}}
  @type async_result :: {:ok, term()} | {:error, term()}
  @type async_command :: %__MODULE__{
          kind: :async,
          value: {(-> term()), (async_result() -> term())}
        }
  @type clipboard_command :: %__MODULE__{
          kind: :clipboard,
          value: {TermUI.Clipboard.Operation.t(), (term() -> term())}
        }
  @type shutdown_command :: %__MODULE__{kind: :shutdown, value: term()}

  @type t ::
          message_command()
          | send_command()
          | timer_command()
          | async_command()
          | clipboard_command()
          | shutdown_command()

  @struct_schema Zoi.struct(__MODULE__, %{
                   kind: Zoi.enum([:message, :send, :timer, :async, :clipboard, :shutdown]),
                   value: Zoi.any()
                 })

  @enforce_keys Zoi.Struct.enforce_keys(@struct_schema)
  defstruct Zoi.Struct.struct_fields(@struct_schema)

  @schema Zoi.union([
            Zoi.struct(__MODULE__, %{
              kind: Zoi.literal(:message),
              value: Zoi.any()
            }),
            Zoi.struct(__MODULE__, %{
              kind: Zoi.literal(:send),
              value: Zoi.tuple({Zoi.pid(), Zoi.any()})
            }),
            Zoi.struct(__MODULE__, %{
              kind: Zoi.literal(:timer),
              value: Zoi.tuple({Zoi.integer() |> Zoi.non_negative(), Zoi.any()})
            }),
            Zoi.struct(__MODULE__, %{
              kind: Zoi.literal(:async),
              value: Zoi.tuple({Zoi.function(arity: 0), Zoi.function(arity: 1)})
            }),
            Zoi.struct(__MODULE__, %{
              kind: Zoi.literal(:clipboard),
              value: Zoi.tuple({TermUI.Clipboard.Operation.schema(), Zoi.function(arity: 1)})
            }),
            Zoi.struct(__MODULE__, %{
              kind: Zoi.literal(:shutdown),
              value: Zoi.any()
            })
          ])

  @doc "Returns the Zoi schema for runtime commands."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc "Delivers a message to the application on the next runtime turn."
  @spec message(term()) :: message_command()
  def message(message), do: %__MODULE__{kind: :message, value: message}

  @doc "Sends a message to another process."
  @spec send(pid(), term()) :: send_command()
  def send(pid, message) when is_pid(pid),
    do: %__MODULE__{kind: :send, value: {pid, message}}

  @doc "Delivers a message to the application after a delay."
  @spec timer(non_neg_integer(), term()) :: timer_command()
  def timer(milliseconds, message) when is_integer(milliseconds) and milliseconds >= 0,
    do: %__MODULE__{kind: :timer, value: {milliseconds, message}}

  @doc """
  Runs a function and maps one runtime-produced result to an application message.

  The function can return any term. The runtime wraps a normal return value as
  `{:ok, value}` and wraps a raised, thrown, or exited function as
  `{:error, reason}`. The mapper always receives this one outer result tag. A
  function return such as `{:ok, value}` therefore reaches the mapper as
  `{:ok, {:ok, value}}`.
  """
  @spec async((-> term()), (async_result() -> term())) :: async_command()
  def async(function, on_result \\ &{:async_result, &1})
      when is_function(function, 0) and is_function(on_result, 1),
      do: %__MODULE__{kind: :async, value: {function, on_result}}

  @doc "Requests a serialized clipboard operation and maps its `:ok` or error result to a message."
  @spec clipboard(TermUI.Clipboard.Operation.t(), (term() -> term())) :: clipboard_command()
  def clipboard(%TermUI.Clipboard.Operation{} = operation, on_result \\ &{:clipboard_result, &1})
      when is_function(on_result, 1),
      do: %__MODULE__{kind: :clipboard, value: {operation, on_result}}

  @doc "Requests a final render and runtime shutdown."
  @spec shutdown(term()) :: shutdown_command()
  def shutdown(reason \\ :normal), do: %__MODULE__{kind: :shutdown, value: reason}

  @doc "Deprecated alias for `shutdown/0`."
  @deprecated "Use TermUI.Command.shutdown/0 instead."
  @spec quit() :: shutdown_command()
  def quit, do: shutdown()

  @doc "Deprecated alias for `shutdown/1`."
  @deprecated "Use TermUI.Command.shutdown/1 instead."
  @spec quit(term()) :: shutdown_command()
  def quit(reason), do: shutdown(reason)
end
