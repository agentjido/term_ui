defmodule Showcase.Page do
  @moduledoc false

  @type dimensions :: {pos_integer(), pos_integer()}
  @type state :: term()
  @type message :: term()
  @type theme :: :dark | :light

  @callback init() :: state()
  @callback update(term(), state()) :: {state(), [message()]}
  @callback view(state(), dimensions(), theme()) :: TermUI.Frame.t()
  @callback help() :: String.t()
end
