defmodule TermUI.Widget.SupervisionTree do
  @moduledoc "A pure supervision-tree view built from parent-supplied snapshots."

  @behaviour TermUI.Widget

  alias TermUI.Widget.TreeView

  @type t :: %__MODULE__{tree: TreeView.t()}
  defstruct tree: %TreeView{}

  @impl true
  def init(opts),
    do: %__MODULE__{
      tree:
        TreeView.init(
          nodes: Keyword.get(opts, :nodes, []),
          expanded: Keyword.get(opts, :expanded, [])
        )
    }

  @impl true
  def update(event, state) do
    {tree, messages} = TreeView.update(event, state.tree)
    {%{state | tree: tree}, messages}
  end

  @impl true
  def mouse(event, state, dimensions) do
    {tree, messages} = TreeView.mouse(event, state.tree, dimensions)
    {%{state | tree: tree}, messages}
  end

  @impl true
  def view(state, dimensions), do: TreeView.view(state.tree, dimensions)

  @doc "Replaces the parent-supplied supervision snapshot."
  @spec set_nodes(t(), [TreeView.tree_node()]) :: t()
  def set_nodes(state, nodes), do: %{state | tree: %{state.tree | nodes: nodes}}
end
