defmodule TermUI.Widget.PluralCompatibilityTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame}
  alias TermUI.Widget.Sparkline

  test "the plural sparkline facade has the same pure state, update, and frame" do
    opts = [values: [1, 5, 10], min: 0, max: 10, color_ranges: [{8, :red}]]
    direct = Sparkline.init(opts)
    facade = facade().init(opts)

    assert facade == direct

    assert facade().update(Event.focus(:lost), facade) ==
             Sparkline.update(Event.focus(:lost), direct)

    assert facade().view(facade, {8, 2}) == Sparkline.view(direct, {8, 2})
  end

  test "the source render bridges are exact v2 views" do
    opts = [values: [1, 5, 10], min: 0, max: 10, width: 6, height: 2]
    state = Sparkline.init(opts)

    assert %Frame{} = frame = facade().render(opts)
    assert frame == Sparkline.view(state, {6, 2})

    labeled_opts = [values: [1, 5, 10], label: "CPU", width: 16]
    labeled = Sparkline.init(Keyword.put(labeled_opts, :show_range, true))
    assert facade().render_labeled(labeled_opts) == Sparkline.view(labeled, {16, 1})
  end

  test "numeric helpers delegate all edge behavior" do
    assert facade().bar_characters() == Sparkline.bar_characters()
    assert facade().value_to_bar(5, 0, 10) == Sparkline.value_to_bar(5, 0, 10)
    assert facade().value_to_bar(5, 5, 5) == Sparkline.value_to_bar(5, 5, 5)
    assert facade().to_sparkline([1, 5, 10], min: 0, max: 10) == "▂▅█"
    assert facade().to_sparkline([1, "bad"]) == ""
  end

  test "each facade function names its direct singular replacement" do
    assert {:docs_v1, _, _, _, _, _, entries} = Code.fetch_docs(facade())

    deprecations =
      Map.new(entries, fn
        {{:function, name, arity}, _, _, _, metadata} -> {{name, arity}, metadata[:deprecated]}
        {_entry, _, _, _, _metadata} -> {nil, nil}
      end)

    for {{name, arity}, replacement} <- deprecations, name != nil do
      assert is_binary(replacement), "#{name}/#{arity} must be deprecated"
      assert replacement =~ "TermUI.Widget.Sparkline"
    end
  end

  test "complex plural modules are not false compatibility claims" do
    for name <- [
          "Table",
          "Menu",
          "FormBuilder",
          "SplitPane",
          "StreamWidget",
          "ProcessMonitor",
          "ClusterDashboard",
          "SupervisionTreeViewer",
          "ToastManager"
        ] do
      refute Code.ensure_loaded?(Module.concat(TermUI.Widgets, name))
    end
  end

  test "the public table classifies every v1 plural widget family" do
    guide = File.read!(Path.expand("../../../guides/widget-parity.md", __DIR__))

    for status <- ["Direct", "Reduced", "Deferred", "Application-owned", "Removed"] do
      assert guide =~ "**#{status}**"
    end

    for name <- [
          "AlertDialog",
          "BarChart",
          "Canvas",
          "ClusterDashboard",
          "CommandPalette",
          "ContextMenu",
          "ContextMenu.Behavior",
          "ContextMenu.Factory",
          "ContextMenu.Inline",
          "Dialog",
          "FormBuilder",
          "Gauge",
          "LineChart",
          "LogViewer",
          "MarkdownViewer",
          "Menu",
          "ProcessMonitor",
          "ScrollBar",
          "Sparkline",
          "SplitPane",
          "StreamWidget",
          "StreamWidget.Consumer",
          "SupervisionTreeViewer",
          "Table",
          "Table.Column",
          "Tabs",
          "TextInput",
          "TextInput.Line",
          "Toast",
          "ToastManager",
          "TreeView",
          "Viewport",
          "VisualizationHelper",
          "WidgetHelpers"
        ] do
      assert guide =~ "TermUI.Widgets.#{name}", "missing parity row for #{name}"
    end
  end

  defp facade, do: Module.concat(TermUI.Widgets, "Sparkline")
end
