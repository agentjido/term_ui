defmodule TermUI.Widget.MouseInteractionTest do
  use ExUnit.Case, async: true

  alias TermUI.Event
  alias TermUI.Widget

  alias TermUI.Widget.{
    AlertDialog,
    CommandPalette,
    ContextMenu,
    Dialog,
    FormBuilder,
    LineInput,
    List,
    Menu,
    PickList,
    ProcessMonitor,
    ScrollBar,
    SplitPane,
    SupervisionTree,
    SupervisionTreeViewer,
    Table,
    Tabs,
    TreeView,
    Viewport
  }

  alias TermUI.Widget.TextInput.Line, as: TextInputLine

  alias TermUI.Widget.Table.Column

  test "list and menu clicks select the local row" do
    list = List.init(items: ["one", "two", "three"])
    {list, []} = Widget.mouse(List, Event.mouse(:press, :left, 0, 1), list, {20, 3})

    assert {_list, [{:selected, "two"}]} =
             Widget.mouse(List, Event.mouse(:release, :left, 0, 1), list, {20, 3})

    menu = Menu.init(items: [Menu.action(:one, "One"), Menu.action(:two, "Two")])
    {menu, []} = Widget.mouse(Menu, Event.mouse(:press, :left, 1, 2), menu, {20, 4})

    assert {_menu, [{:selected, :two}]} =
             Widget.mouse(Menu, Event.mouse(:release, :left, 1, 2), menu, {20, 4})
  end

  test "table and tree clicks use visible row offsets" do
    table =
      Table.init(
        columns: [Column.new(:name, "Name")],
        rows: [%{name: "one"}, %{name: "two"}]
      )

    assert {_table, [{:selected, %{name: "two"}}]} =
             Widget.mouse(Table, Event.mouse(:release, :left, 0, 2), table, {20, 3})

    tree =
      TreeView.init(nodes: [TreeView.branch(:root, "Root", [TreeView.leaf(:child, "Child")])])

    assert {tree, [{:expanded, :root}]} =
             Widget.mouse(TreeView, Event.mouse(:release, :left, 0, 0), tree, {20, 3})

    assert length(TreeView.visible(tree)) == 2
  end

  test "tab clicks select the label under the pointer" do
    tabs = Tabs.init(tabs: [{:one, "One"}, {:two, "Two"}])

    assert {tabs, [{:selected, :two}]} =
             Widget.mouse(Tabs, Event.mouse(:release, :left, 7, 0), tabs, {20, 3})

    assert Tabs.selected(tabs).id == :two
  end

  test "scrollbar clicks and drags map the track to a bounded offset" do
    scrollbar = ScrollBar.init(content_size: 100, viewport_size: 10)

    assert {scrollbar, [{:scrolled, 90}]} =
             Widget.mouse(
               ScrollBar,
               Event.mouse(:press, :left, 0, 9),
               scrollbar,
               {1, 10}
             )

    assert scrollbar.dragging

    assert {scrollbar, []} =
             Widget.mouse(
               ScrollBar,
               Event.mouse(:release, :left, 0, 9),
               scrollbar,
               {1, 10}
             )

    refute scrollbar.dragging
  end

  test "viewport geometry and local scrollbar drag stay in pure state" do
    viewport =
      Viewport.init(
        content: Enum.map(1..10, &"row #{&1} abcdef"),
        scrollbars: :both
      )

    assert %{
             content_width: 13,
             content_height: 10,
             viewport_width: 5,
             viewport_height: 3,
             max_scroll_x: 8,
             max_scroll_y: 7,
             visible_columns: 0..4,
             visible_rows: 0..2
           } = Viewport.geometry(viewport, {6, 4})

    assert %TermUI.Frame{} = Viewport.view(viewport, {6, 4})

    assert {viewport, [{:scrolled, {0, 7}}]} =
             Widget.mouse(Viewport, Event.mouse(:press, :left, 5, 2), viewport, {6, 4})

    assert viewport.dragging == :vertical

    assert {viewport, [{:scrolled, {8, 7}}]} =
             Widget.mouse(Viewport, Event.mouse(:press, :left, 4, 3), viewport, {6, 4})

    assert viewport.dragging == :horizontal

    assert {viewport, []} =
             Widget.mouse(Viewport, Event.mouse(:release, :left, 4, 3), viewport, {6, 4})

    assert viewport.dragging == nil

    viewport = Viewport.scroll_into_view(%{viewport | scroll_x: 0, scroll_y: 0}, {12, 9}, {6, 4})
    assert Viewport.position(viewport) == {8, 7}
  end

  test "split pane drag updates its ratio without an owner process" do
    split = SplitPane.init(first: "left", second: "right", ratio: 0.5)

    {split, []} =
      Widget.mouse(SplitPane, Event.mouse(:press, :left, 5, 0), split, {10, 4})

    assert split.dragging

    assert {split, [{:resized, ratio}]} =
             Widget.mouse(SplitPane, Event.mouse(:drag, :left, 7, 0), split, {10, 4})

    assert ratio > 0.7

    assert {split, []} =
             Widget.mouse(SplitPane, Event.mouse(:release, :left, 7, 0), split, {10, 4})

    refute split.dragging
  end

  test "line input routes mouse selection through its label and prompt" do
    input = LineInput.init(label: "Name", prompt: "> ", value: "abcd")

    {input, []} =
      Widget.mouse(LineInput, Event.mouse(:press, :left, 3, 1), input, {12, 2})

    {input, []} =
      Widget.mouse(LineInput, Event.mouse(:drag, :left, 5, 1), input, {12, 2})

    assert TermUI.Selection.extract(input.input.selection, input.input.value) == "bc"

    frame = LineInput.view(input, {12, 2})
    assert :reverse in TermUI.Frame.cell(frame, 2, 4).attrs
  end

  test "composite wrappers keep specialized mouse behavior" do
    alert = AlertDialog.init(type: :confirm)

    assert {_alert, [_message]} =
             Widget.mouse(
               AlertDialog,
               Event.mouse(:release, :left, 10, 4),
               alert,
               {20, 6}
             )

    snapshot = %{pid: "<0.1.0>", memory: 10, reductions: 20, message_queue_len: 0}
    monitor = ProcessMonitor.init(snapshots: [snapshot])

    assert {_monitor, [{:selected, ^snapshot}]} =
             Widget.mouse(
               ProcessMonitor,
               Event.mouse(:release, :left, 0, 1),
               monitor,
               {60, 3}
             )

    nodes = [TreeView.branch(:root, "Root", [TreeView.leaf(:child, "Child")])]

    for {module, tree} <- [
          {SupervisionTree, SupervisionTree.init(nodes: nodes)},
          {SupervisionTreeViewer, SupervisionTreeViewer.init(nodes: nodes)}
        ] do
      assert {_tree, [{:expanded, :root}]} =
               Widget.mouse(module, Event.mouse(:release, :left, 0, 0), tree, {20, 3})
    end

    input = TextInputLine.init(label: "Name", prompt: "> ", value: "abcd")

    assert {input, []} =
             Widget.mouse(
               TextInputLine,
               Event.mouse(:press, :left, 3, 1),
               input,
               {12, 2}
             )

    assert input.input.cursor == 1
  end

  test "pick list clicks select visible results" do
    picker = PickList.init(items: ["one", "two", "three"])
    {picker, []} = Widget.mouse(PickList, Event.mouse(:press, :left, 0, 2), picker, {20, 4})

    assert {_picker, [{:picked, "two"}]} =
             Widget.mouse(PickList, Event.mouse(:release, :left, 0, 2), picker, {20, 4})

    unicode = PickList.init(items: ["a"], prompt: "界", query: "a")
    assert PickList.view(unicode, {10, 2}).cursor == {4, 1}
  end

  test "composed menus and palettes translate border coordinates" do
    context =
      ContextMenu.init(items: [ContextMenu.action(:one, "One"), ContextMenu.action(:two, "Two")])

    assert {_context, [{:selected, :two}]} =
             Widget.mouse(
               ContextMenu,
               Event.mouse(:release, :left, 1, 2),
               context,
               {20, 4}
             )

    palette = CommandPalette.init(commands: ["one", "two"], visible: true)

    assert {_palette, [{:command, "two"}]} =
             Widget.mouse(
               CommandPalette,
               Event.mouse(:release, :left, 2, 3),
               palette,
               {20, 6}
             )
  end

  test "dialog and form clicks activate the displayed control" do
    dialog = Dialog.init(buttons: [{:one, "One"}, {:two, "Two"}])

    assert {_dialog, [{:selected, :two}]} =
             Widget.mouse(Dialog, Event.mouse(:release, :left, 10, 4), dialog, {20, 6})

    form =
      FormBuilder.init(
        fields: [
          %{id: :name, label: "Name", type: :text},
          %{id: :enabled, label: "Enabled", type: :checkbox}
        ]
      )

    assert {form, [{:changed, :enabled, true}]} =
             Widget.mouse(FormBuilder, Event.mouse(:release, :left, 0, 1), form, {20, 3})

    assert form.active == 1
  end
end
