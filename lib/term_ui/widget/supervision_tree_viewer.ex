defmodule TermUI.Widget.SupervisionTreeViewer do
  @moduledoc "Compatibility name for the pure `TermUI.Widget.SupervisionTree` view."

  @behaviour TermUI.Widget

  defdelegate init(opts), to: TermUI.Widget.SupervisionTree
  defdelegate update(event, state), to: TermUI.Widget.SupervisionTree
  defdelegate mouse(event, state, dimensions), to: TermUI.Widget.SupervisionTree
  defdelegate view(state, dimensions), to: TermUI.Widget.SupervisionTree
  defdelegate set_nodes(state, nodes), to: TermUI.Widget.SupervisionTree
end
