defmodule TermUI.Backend do
  @moduledoc """
  The terminal backend contract.

  A backend owns input, output, size, capabilities, cursor state, terminal
  setup, and cleanup. The runtime treats backend state as opaque data.
  """

  @type position :: {row :: pos_integer(), column :: pos_integer()}
  @type size :: {rows :: pos_integer(), columns :: pos_integer()}
  @type color :: :default | atom() | 0..255 | {0..255, 0..255, 0..255}
  @type cell :: {String.t(), color(), color(), [atom()]}
  @type event :: TermUI.Event.t()
  @type state :: term()
  @type spec :: :auto | :raw | :tty | module() | {module(), keyword()}

  @callback init(keyword()) :: {:ok, state()} | {:error, term()}
  @callback size(state()) :: {:ok, size()} | {:error, term()}
  @callback capabilities(state()) :: map()
  @callback draw(state(), TermUI.Frame.t()) :: {:ok, state()} | {:error, term()}
  @callback flush(state()) :: {:ok, state()} | {:error, term()}
  @doc """
  Invalidates previous output so the next draw restores the complete screen.

  Backends that cache output must implement this callback. A backend without
  this callback must invalidate output when `resize/2` receives its current
  size. The backend owner serializes invalidation and the next complete frame.
  """
  @callback invalidate(state()) :: {:ok, state()} | {:error, term()}
  @doc "Restores owned terminal modes after resume, keeping the original settings for shutdown."
  @callback resume(state()) :: {:ok, state()} | {:error, term()}
  @callback clipboard(state(), TermUI.Clipboard.Operation.t()) ::
              {:ok, state()} | {:error, term()}
  @callback poll_event(state(), non_neg_integer()) ::
              {:ok, event(), state()}
              | {:timeout, state()}
              | {:error, term(), state()}
  @callback resize(state(), size()) :: {:ok, state()} | {:error, term()}
  @callback shutdown(state(), term()) :: :ok

  @optional_callbacks clipboard: 2, invalidate: 1, resume: 1
end
