defmodule TermUI.Widget.TextInput.Line do
  @moduledoc "Compatibility name for `TermUI.Widget.LineInput`."

  @behaviour TermUI.Widget

  defdelegate init(opts), to: TermUI.Widget.LineInput
  defdelegate update(event, state), to: TermUI.Widget.LineInput
  defdelegate mouse(event, state, dimensions), to: TermUI.Widget.LineInput
  defdelegate view(state, dimensions), to: TermUI.Widget.LineInput
  defdelegate validate(state), to: TermUI.Widget.LineInput
end
