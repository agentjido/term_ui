defmodule TermUI.Widget.StreamWidget do
  @moduledoc "Compatibility name for the pure `TermUI.Widget.Stream` view."

  @behaviour TermUI.Widget

  defdelegate init(opts), to: TermUI.Widget.Stream
  defdelegate update(event, state), to: TermUI.Widget.Stream
  defdelegate view(state, dimensions), to: TermUI.Widget.Stream
  defdelegate push(state, item), to: TermUI.Widget.Stream
  defdelegate push_many(state, items), to: TermUI.Widget.Stream
  defdelegate offer_many(state, items), to: TermUI.Widget.Stream
  defdelegate clear(state), to: TermUI.Widget.Stream
  defdelegate reset_stats(state), to: TermUI.Widget.Stream
  defdelegate set_overflow(state, overflow), to: TermUI.Widget.Stream
  defdelegate stats(state), to: TermUI.Widget.Stream
end
