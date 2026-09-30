defmodule TermUI.Widget.CatalogTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame}
  alias TermUI.Widget

  alias TermUI.Widget.{
    AlertDialog,
    BarChart,
    Block,
    Breadcrumb,
    Button,
    Canvas,
    Checkbox,
    ClusterDashboard,
    CommandPalette,
    ContextMenu,
    Dialog,
    FormBuilder,
    Gauge,
    Label,
    LineChart,
    LineInput,
    List,
    LogViewer,
    Menu,
    PickList,
    ProcessMonitor,
    Progress,
    RadioGroup,
    ScrollBar,
    Select,
    Sparkline,
    Spinner,
    SplitPane,
    Stream,
    StreamWidget,
    SupervisionTree,
    SupervisionTreeViewer,
    Table,
    Tabs,
    TextArea,
    Toast,
    Toggle,
    TreeView,
    Viewport
  }

  alias TermUI.Widget.Table.Column
  alias TermUI.Widget.TextInput.Line

  test "the restored widget catalog renders only canonical frames" do
    modules_and_states = [
      {Label, Label.init(text: "label")},
      {Block, Block.init(title: "Block", content: "body")},
      {Breadcrumb, Breadcrumb.init(items: ["Home", "Docs"])},
      {Button, Button.init(id: :save, label: "Save")},
      {Checkbox, Checkbox.init(id: :enabled, label: "Enabled")},
      {List, List.init(items: ["one", "two"])},
      {PickList, PickList.init(items: ["one", "two"])},
      {Progress, Progress.init(value: 50)},
      {RadioGroup, RadioGroup.init(options: [{:one, "One"}, {:two, "Two"}])},
      {Select, Select.init(options: [{:one, "One"}, {:two, "Two"}])},
      {Spinner, Spinner.init(label: "Loading")},
      {Toggle, Toggle.init(id: :enabled, label: "Enabled")},
      {TextArea, TextArea.init(value: "one\ntwo")},
      {LineInput, LineInput.init(label: "Name")},
      {Viewport, Viewport.init(content: "one\ntwo")},
      {ScrollBar, ScrollBar.init(content_size: 100, viewport_size: 10)},
      {Tabs, Tabs.init(tabs: [{:one, "One"}, {:two, "Two"}])},
      {Table, Table.init(columns: [Column.new(:name, "Name")], rows: [%{name: "one"}])},
      {TreeView, TreeView.init(nodes: [TreeView.leaf(:one, "One")])},
      {Menu, Menu.init(items: [Menu.action(:open, "Open")])},
      {ContextMenu, ContextMenu.init(items: [Menu.action(:open, "Open")])},
      {Dialog, Dialog.init(title: "Title", content: "Body", buttons: [{:ok, "OK"}])},
      {AlertDialog, AlertDialog.init(type: :warning, message: "Careful")},
      {CommandPalette, CommandPalette.init(commands: ["Open"])},
      {FormBuilder, FormBuilder.init(fields: [%{id: :name, label: "Name", type: :text}])},
      {SplitPane, SplitPane.init(first: "left", second: "right")},
      {Toast, Toast.init(message: "Saved", type: :success)},
      {Gauge, Gauge.init(value: 60)},
      {Sparkline, Sparkline.init(values: [1, 3, 2])},
      {BarChart, BarChart.init(data: [{"A", 3}, {"B", 5}])},
      {LineChart, LineChart.init(series: [[1, 3, 2]])},
      {Canvas, Canvas.init(width: 10, height: 4) |> Canvas.draw_text(0, 0, "canvas")},
      {LogViewer, LogViewer.init(entries: ["log"])},
      {Stream, Stream.init(items: ["stream"])},
      {ProcessMonitor, ProcessMonitor.init(snapshots: [%{pid: "<0.1.0>", memory: 10}])},
      {SupervisionTree, SupervisionTree.init(nodes: [TreeView.leaf(:root, "Root")])},
      {ClusterDashboard, ClusterDashboard.init(nodes: [%{node: :local, status: :up}])}
    ]

    for {module, state} <- modules_and_states do
      assert %Frame{width: 40, height: 8} = Widget.view(module, state, {40, 8})
    end
  end

  test "buttons, lists, menus, forms, tabs, and trees return parent messages" do
    button = Button.init(id: :save, label: "Save")
    assert {_button, [{:pressed, :save}]} = Button.update(Event.key(:enter), button)

    list = List.init(items: ["one", "two"])
    {list, []} = List.update(Event.key(:down), list)
    assert {_list, [{:selected, "two"}]} = List.update(Event.key(:enter), list)

    menu = Menu.init(items: [Menu.separator(), Menu.action(:open, "Open")])
    assert {_menu, [{:selected, :open}]} = Menu.update(Event.key(:enter), menu)

    form = FormBuilder.init(fields: [%{id: :name, label: "Name", type: :text, required: true}])
    {form, [{:changed, :name, "Ada"}]} = FormBuilder.update(Event.text("Ada"), form)
    assert {_form, [{:submit, %{name: "Ada"}}]} = FormBuilder.update(Event.key(:enter), form)

    tabs = Tabs.init(tabs: [{:one, "One"}, {:two, "Two"}])
    {tabs, _messages} = Tabs.update(Event.key(:right), tabs)
    assert {tabs, [{:selected, :two}]} = Tabs.update(Event.key(:enter), tabs)
    assert Tabs.selected(tabs).id == :two

    branch = TreeView.branch(:root, "Root", [TreeView.leaf(:child, "Child")])
    tree = TreeView.init(nodes: [branch])
    assert {tree, [{:expanded, :root}]} = TreeView.update(Event.key(:right), tree)
    assert length(TreeView.visible(tree)) == 2
  end

  test "space text activates keyboard widgets and keeps text and mode guards" do
    button = Button.init(id: :save, label: "Save")
    assert {_button, [{:pressed, :save}]} = Button.update(Event.text(" "), button)

    dialog = Dialog.init(buttons: [{:ok, "OK"}])
    assert {_dialog, [{:selected, :ok}]} = Dialog.update(Event.text(" "), dialog)

    tabs = Tabs.init(tabs: [{:one, "One"}, {:two, "Two"}])
    {tabs, _messages} = Tabs.update(Event.key(:right), tabs)
    assert {tabs, [{:selected, :two}]} = Tabs.update(Event.text(" "), tabs)
    assert Tabs.selected(tabs).id == :two

    menu = Menu.init(items: [Menu.action(:open, "Open")])
    assert {_menu, [{:selected, :open}]} = Menu.update(Event.text(" "), menu)

    checkbox = FormBuilder.init(fields: [%{id: :enabled, label: "Enabled", type: :checkbox}])

    assert {_checkbox, [{:changed, :enabled, true}]} =
             FormBuilder.update(Event.text(" "), checkbox)

    text = FormBuilder.init(fields: [%{id: :name, label: "Name", type: :text}])
    assert {_text, [{:changed, :name, " "}]} = FormBuilder.update(Event.text(" "), text)

    multiple = List.init(items: ["one"], mode: :multiple)
    assert {_multiple, [{:toggled, "one"}]} = List.update(Event.text(" "), multiple)

    single = List.init(items: ["one"], mode: :single)
    assert {^single, []} = List.update(Event.text(" "), single)

    tree = TreeView.init(nodes: [TreeView.leaf(:one, "One")])
    assert {_tree, [{:selected, :one}]} = TreeView.update(Event.text(" "), tree)

    stream = Stream.init(items: ["event"])
    assert {_stream, [{:paused, true}]} = Stream.update(Event.text(" "), stream)
  end

  test "multiline input places an exact-width cursor on the next row" do
    state = TextArea.init(value: "abcd")
    frame = TextArea.view(state, {4, 2})

    assert Frame.row_text(frame, 1) == "abcd"
    assert frame.cursor == {1, 2}

    assert {state, [{:changed, "abcd\n"}]} = TextArea.update(Event.key(:enter), state)
    assert TextArea.view(state, {4, 3}).cursor == {1, 2}
  end

  test "canvas retains character and braille drawing features" do
    canvas =
      Canvas.init(width: 8, height: 3) |> Canvas.draw_rect(0, 0, 4, 3) |> Canvas.set_dot(10, 0)

    frame = Canvas.view(canvas, {8, 3})

    assert Frame.cell(frame, 1, 1).char == "┌"
    assert String.starts_with?(Frame.cell(frame, 1, 6).char, "⠁")
    assert Canvas.braille_resolution(canvas) == {16, 12}
  end

  test "canvas text advances by terminal columns" do
    canvas = Canvas.init(width: 4, height: 1) |> Canvas.draw_text(0, 0, "界a")
    frame = Canvas.view(canvas, {4, 1})

    assert Frame.cell(frame, 1, 1).char == "界"
    assert Frame.cell(frame, 1, 2).wide_placeholder
    assert Frame.cell(frame, 1, 3).char == "a"

    clipped = Canvas.init(width: 2, height: 1) |> Canvas.draw_text(0, 0, "界a")
    assert Frame.row_text(Canvas.view(clipped, {2, 1}), 1) == "界"
  end

  test "bounded log, stream, and toast data stays pure" do
    logs =
      LogViewer.init(limit: 2)
      |> LogViewer.append("one")
      |> LogViewer.append("two")
      |> LogViewer.append("three")

    assert Enum.map(logs.entries, & &1.message) == ["two", "three"]

    stream = Stream.init(limit: 2) |> Stream.push(1) |> Stream.push(2) |> Stream.push(3)
    assert stream.items == [2, 3]

    manager =
      Toast.Manager.new(limit: 2)
      |> Toast.Manager.add("one")
      |> Toast.Manager.add("two")
      |> Toast.Manager.add("three")

    assert length(manager.toasts) == 2
  end

  test "retained widget compatibility names delegate the complete pure API" do
    stream = StreamWidget.init(items: ["one"])
    assert %Frame{} = StreamWidget.view(stream, {20, 3})
    assert {%{paused: true}, [{:paused, true}]} = StreamWidget.update(Event.text(" "), stream)
    assert %{items: ["one", "two"]} = StreamWidget.push(stream, "two")

    node = TreeView.leaf(:root, "Root")
    tree = SupervisionTreeViewer.init(nodes: [node])
    assert %Frame{} = SupervisionTreeViewer.view(tree, {20, 3})
    assert {_, _messages} = SupervisionTreeViewer.update(Event.key(:down), tree)
    assert %{tree: %{nodes: []}} = SupervisionTreeViewer.set_nodes(tree, [])

    line = Line.init(label: "Name")
    assert %Frame{} = Line.view(line, {20, 2})
    assert {line, [{:changed, "A"}]} = Line.update(Event.text("A"), line)
    assert {^line, [{:submit, "A"}]} = Line.validate(line)
  end
end
