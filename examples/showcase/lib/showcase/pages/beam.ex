defmodule Showcase.Pages.Beam do
  @moduledoc false

  @behaviour Showcase.Page

  alias Showcase.Layout
  alias TermUI.Event
  alias TermUI.Frame
  alias TermUI.Widget.{ClusterDashboard, ProcessMonitor, SupervisionTree}

  @views [:processes, :runtime, :cluster]

  @impl true
  def init do
    %{
      active: :processes,
      processes: ProcessMonitor.init(snapshots: []),
      runtime: SupervisionTree.init(nodes: [], expanded: [:runtime]),
      cluster: ClusterDashboard.init(nodes: [])
    }
  end

  @impl true
  def update(%Event.Key{key: :tab, modifiers: modifiers}, state) do
    delta = if :shift in modifiers, do: -1, else: 1
    {move_view(state, delta), []}
  end

  def update(event, %{active: :processes} = state) do
    {widget, messages} = ProcessMonitor.update(event, state.processes)
    {%{state | processes: widget}, messages}
  end

  def update(event, %{active: :runtime} = state) do
    {widget, messages} = SupervisionTree.update(event, state.runtime)
    {%{state | runtime: widget}, messages}
  end

  def update(event, %{active: :cluster} = state) do
    {widget, messages} = ClusterDashboard.update(event, state.cluster)
    {%{state | cluster: widget}, messages}
  end

  @impl true
  def view(state, {width, height}, theme) do
    selector =
      Layout.selector(
        [processes: "Processes", runtime: "Runtime links", cluster: "Cluster"],
        state.active,
        width
      )

    panel_height = max(height - 1, 1)
    inner = {max(width - 2, 1), max(panel_height - 2, 1)}

    {title, content} =
      case state.active do
        :processes ->
          {"Parent-supplied process snapshot", ProcessMonitor.view(state.processes, inner)}

        :runtime ->
          {"Live runtime process links", SupervisionTree.view(state.runtime, inner)}

        :cluster ->
          {"Parent-supplied cluster snapshot", ClusterDashboard.view(state.cluster, inner)}
      end

    panel = Layout.panel(content, title, {width, panel_height}, active: true, theme: theme)

    Frame.new(width, height)
    |> Frame.overlay(selector, 1, 1)
    |> Frame.overlay(panel, 1, 2)
  end

  @impl true
  def help, do: "Tab changes live snapshots. Collection stays outside the widgets."

  @doc false
  def set_snapshot(state, snapshot) do
    %{
      state
      | processes: ProcessMonitor.set_snapshots(state.processes, snapshot.processes),
        runtime: SupervisionTree.set_nodes(state.runtime, snapshot.runtime_tree),
        cluster: ClusterDashboard.set_nodes(state.cluster, snapshot.cluster)
    }
  end

  defp move_view(state, delta) do
    index = Enum.find_index(@views, &(&1 == state.active)) || 0
    next = rem(index + delta + length(@views), length(@views))
    %{state | active: Enum.at(@views, next)}
  end
end
