defmodule TermUI.Widget.ContextMenu do
  @moduledoc "A pure positioned context menu built on `TermUI.Widget.Menu`."

  @behaviour TermUI.Widget

  alias TermUI.Widget.Menu

  @type t :: %__MODULE__{menu: Menu.t(), position: {integer(), integer()}}
  defstruct menu: %Menu{},
            position: {0, 0}

  defdelegate action(id, label, opts \\ []), to: Menu
  defdelegate submenu(id, label, children, opts \\ []), to: Menu
  defdelegate separator(), to: Menu

  @impl true
  def init(opts) do
    %__MODULE__{menu: Menu.init(opts), position: Keyword.get(opts, :position, {0, 0})}
  end

  @impl true
  def update(event, state) do
    {menu, messages} = Menu.update(event, state.menu)
    {%{state | menu: menu}, messages}
  end

  @impl true
  def mouse(event, state, dimensions) do
    {menu, messages} = Menu.mouse(event, state.menu, dimensions)
    {%{state | menu: menu}, messages}
  end

  @impl true
  def view(state, dimensions), do: Menu.view(state.menu, dimensions)

  @doc "Returns the requested zero-based overlay position."
  @spec position(t()) :: {integer(), integer()}
  def position(state), do: state.position

  @doc "Returns a clipped and repositioned overlay rectangle for terminal dimensions."
  @spec placement(
          t(),
          {non_neg_integer(), non_neg_integer()},
          {non_neg_integer(), non_neg_integer()}
        ) :: TermUI.Layout.rect()
  def placement(state, menu_dimensions, terminal_dimensions),
    do: Menu.fit_overlay(state.position, menu_dimensions, terminal_dimensions)

  @doc "Moves the context menu."
  @spec move_to(t(), {integer(), integer()}) :: t()
  def move_to(state, position), do: %{state | position: position}
end
