defmodule TermUI.Widget.ClusterDashboard do
  @moduledoc "A pure cluster snapshot dashboard. It performs no RPC or node monitoring."

  @behaviour TermUI.Widget

  alias TermUI.Event
  alias TermUI.Widget.{Table, Tabs}
  alias TermUI.Widget.Table.Column

  @type snapshot :: %{
          required(:node) => term(),
          optional(:status) => term(),
          optional(:processes) => non_neg_integer(),
          optional(:memory) => non_neg_integer() | String.t(),
          optional(:uptime) => term()
        }
  @type t :: %__MODULE__{nodes: [snapshot()], tabs: Tabs.t(), table: Table.t()}
  defstruct nodes: [],
            tabs: %Tabs{},
            table: %Table{}

  @impl true
  def init(opts) do
    nodes = Keyword.get(opts, :nodes, [])

    %__MODULE__{
      nodes: nodes,
      tabs: Tabs.init(tabs: [{:nodes, "Nodes"}, {:help, "Help"}], selected: :nodes),
      table: table(nodes)
    }
  end

  @impl true
  def update(%Event.Text{text: "r"}, state), do: {state, [:refresh_requested]}

  def update(%Event.Key{key: key} = event, state) when key in [:left, :right],
    do: update_tabs(event, state)

  def update(%Event.Key{key: key} = event, state) when key in [:enter, :space] do
    if state.tabs.focused == state.tabs.selected,
      do: update_active(event, state),
      else: update_tabs(event, state)
  end

  def update(%Event.Text{text: " "} = event, state) do
    if state.tabs.focused == state.tabs.selected,
      do: update_active(event, state),
      else: update_tabs(event, state)
  end

  def update(event, state), do: update_active(event, state)

  @impl true
  def mouse(%Event.Mouse{y: 0} = event, state, dimensions) do
    {tabs, messages} = Tabs.mouse(event, state.tabs, dimensions)
    {%{state | tabs: tabs}, messages}
  end

  def mouse(%Event.Mouse{y: y} = event, state, {width, height}) when y > 0 do
    case Tabs.selected(state.tabs) do
      %{id: :nodes} ->
        {table, messages} =
          Table.mouse(%{event | y: y - 1}, state.table, {width, max(height - 1, 1)})

        {%{state | table: table}, messages}

      _tab ->
        {state, []}
    end
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(state, {width, height}) do
    frame = TermUI.Frame.new(width, height)
    tabs = Tabs.view(state.tabs, {width, 1})
    frame = TermUI.Frame.overlay(frame, tabs, 1, 1)

    if height > 1 do
      content = active_view(state, {width, height - 1})
      TermUI.Frame.overlay(frame, content, 1, 2)
    else
      frame
    end
  end

  defp update_tabs(event, state) do
    {tabs, tab_messages} = Tabs.update(event, state.tabs)
    {%{state | tabs: tabs}, tab_messages}
  end

  defp update_active(event, state) do
    case Tabs.selected(state.tabs) do
      %{id: :nodes} ->
        {table, messages} = Table.update(event, state.table)
        {%{state | table: table}, messages}

      _tab ->
        {state, []}
    end
  end

  defp active_view(state, dimensions) do
    case Tabs.selected(state.tabs) do
      %{id: :help} ->
        {width, height} = dimensions

        TermUI.Frame.from_rows(
          ["R: request refresh", "Arrows: move", "Enter: select node"],
          width,
          height
        )

      _tab ->
        Table.view(state.table, dimensions)
    end
  end

  @doc "Replaces cluster snapshots supplied by the parent."
  @spec set_nodes(t(), [snapshot()]) :: t()
  def set_nodes(state, nodes),
    do: %{state | nodes: nodes, table: Table.set_rows(state.table, nodes)}

  defp table(nodes),
    do:
      Table.init(
        columns: [
          Column.new(:node, "Node"),
          Column.new(:status, "Status", width: 10),
          Column.new(:processes, "Processes", align: :right),
          Column.new(:memory, "Memory", align: :right),
          Column.new(:uptime, "Uptime", align: :right)
        ],
        rows: nodes
      )
end
