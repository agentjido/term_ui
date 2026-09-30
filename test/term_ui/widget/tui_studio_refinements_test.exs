defmodule TermUI.Widget.TUIStudioRefinementsTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame, Style}
  alias TermUI.Widget.{Block, Breadcrumb, Button, Dialog, List, Menu, Tabs, TreeView}

  test "button renders optional prefix and suffix without changing its message" do
    button = Button.init(id: :save, label: "Save", prefix: "◆", suffix: "⌘S")
    assert Frame.row_text(Button.view(button, {18, 1}), 1) == "  [ ◆ Save ⌘S ]   "
    assert {_button, [{:pressed, :save}]} = Button.update(Event.key(:enter), button)
  end

  test "list renders item icons and right-side shortcuts" do
    list =
      List.init(
        items: [
          %{id: :open, label: "Open", icon: "◆", shortcut: "⌘O"},
          %{id: :save, label: "Save", hotkey: "⌘S"}
        ]
      )

    assert Frame.row_text(List.view(list, {16, 2}), 1) == "> ◆ Open      ⌘O"
    assert Frame.row_text(List.view(list, {16, 2}), 2) == "  Save        ⌘S"
    assert {_list, [{:selected, %{id: :open}}]} = List.update(Event.key(:enter), list)
  end

  test "tree nodes render optional icons" do
    tree =
      TreeView.init(
        nodes: [
          TreeView.branch(:root, "Root", [TreeView.leaf(:leaf, "Leaf", icon: "◆")], icon: "▣")
        ],
        expanded: [:root]
      )

    frame = TreeView.view(tree, {20, 3})
    assert Frame.row_text(frame, 1) =~ "▾ ▣ Root"
    assert Frame.row_text(frame, 2) =~ "• ◆ Leaf"
  end

  test "tree navigation and mouse selection skip disabled nodes" do
    tree =
      TreeView.init(
        nodes: [
          TreeView.leaf(:blocked, "Blocked", disabled: true),
          TreeView.leaf(:ready, "Ready")
        ]
      )

    assert tree.cursor == 1
    assert {^tree, []} = TreeView.update(Event.key(:up), tree)
    assert {^tree, []} = TreeView.mouse(Event.mouse(:release, :left, 0, 0), tree, {20, 2})
    assert {^tree, []} = TreeView.mouse(Event.mouse(:release, :left, 30, 1), tree, {20, 2})
    assert {_tree, [{:selected, :ready}]} = TreeView.update(Event.key(:space), tree)
  end

  test "tree page movement counts visible rows before it skips disabled nodes" do
    tree =
      TreeView.init(
        nodes: [
          TreeView.leaf(:one, "One"),
          TreeView.leaf(:two, "Two", disabled: true),
          TreeView.leaf(:three, "Three", disabled: true),
          TreeView.leaf(:four, "Four"),
          TreeView.leaf(:five, "Five")
        ],
        page_size: 2
      )

    assert {%{cursor: 3}, []} = TreeView.update(Event.key(:page_down), tree)

    disabled = TreeView.init(nodes: [TreeView.leaf(:off, "Off", disabled: true)], page_size: 2)
    assert {^disabled, []} = TreeView.update(Event.key(:page_down), disabled)
  end

  test "horizontal menu uses the same labels for view and mouse hit testing" do
    menu =
      Menu.init(
        items: [
          Menu.action(:file, "File", icon: "◆"),
          Menu.action(:edit, "Edit", disabled: true),
          Menu.action(:view, "View", shortcut: "v")
        ],
        orientation: :horizontal,
        variant: :filled
      )

    assert Frame.row_text(Menu.view(menu, {32, 3}), 2) =~ "◆ File"
    assert {menu, []} = Menu.update(Event.key(:right), menu)
    assert Menu.current(menu).id == :view

    assert {menu, [{:selected, :view}]} =
             Menu.mouse(Event.mouse(:release, :left, 22, 1), menu, {32, 3})

    assert Menu.current(menu).id == :view
    assert {^menu, []} = Menu.mouse(Event.mouse(:release, :left, 12, 0), menu, {32, 3})

    vertical = Menu.init(items: [Menu.action(:one, "One")])

    assert {^vertical, []} =
             Menu.mouse(Event.mouse(:release, :left, 99, 1), vertical, {20, 3})

    gaps =
      Menu.init(
        items: [Menu.action(:one, "One"), Menu.separator(), Menu.action(:two, "Two")],
        orientation: :horizontal
      )

    assert {^gaps, []} = Menu.mouse(Event.mouse(:release, :left, 6, 1), gaps, {24, 3})

    assert {_gaps, [{:selected, :two}]} =
             Menu.mouse(Event.mouse(:release, :left, 11, 1), gaps, {24, 3})
  end

  test "menu maps hotkeys and normalizes iodata shortcuts" do
    menu =
      Menu.init(items: [%{id: :open, label: "Open", hotkey: [?x]}, Menu.action(:save, "Save")])

    assert Frame.row_text(Menu.view(menu, {20, 4}), 2) =~ "x"
  end

  test "tabs align metadata and skip disabled tabs" do
    tabs =
      Tabs.init(
        tabs: [
          %{id: :one, label: "One", icon: "◆", status: "2"},
          %{id: :blocked, label: "No", disabled: true},
          %{id: :three, label: "Three", shortcut: "3"}
        ],
        alignment: :right
      )

    assert String.starts_with?(Frame.row_text(Tabs.view(tabs, {30, 2}), 1), "     ")
    assert {tabs, _messages} = Tabs.update(Event.key(:right), tabs)
    assert tabs.focused == 2
    assert {tabs, [{:selected, :three}]} = Tabs.update(Event.key(:enter), tabs)
    assert Tabs.selected(tabs).id == :three

    assert {^tabs, []} =
             Tabs.mouse(Event.mouse(:release, :left, 16, 0), tabs, {30, 2})
  end

  test "tabs map TUIStudio status and hotkey metadata" do
    tabs =
      Tabs.init(
        tabs: [
          %{id: :active, label: "Active", status: true, hotkey: [?a]},
          %{id: :quiet, label: "Quiet", status: false}
        ]
      )

    row = Frame.row_text(Tabs.view(tabs, {32, 1}), 1)
    assert row =~ "Active ● a"
    refute row =~ "true"
    refute row =~ "false"
  end

  test "tabs do not select or render content when all tabs are disabled" do
    tabs = Tabs.init(tabs: [%{id: :off, label: "Off", disabled: true, content: "hidden"}])

    assert Tabs.selected(tabs) == nil
    refute Frame.row_text(Tabs.view(tabs, {20, 2}), 2) =~ "hidden"
    assert {^tabs, []} = Tabs.update(Event.key(:enter), tabs)
  end

  test "two-item breadcrumbs compact without a middle ellipsis" do
    breadcrumb = Breadcrumb.init(items: ["A", "VeryLong"])

    assert Frame.row_text(Breadcrumb.view(breadcrumb, {9, 1}), 1) == "A / VeryL"
  end

  test "blocks and dialogs expose child rectangles and clip pure child frames" do
    block = Block.init(title: "Data", padding: 1)
    assert Block.content_rect(block, {12, 6}) == {2, 2, 8, 2}

    block_frame =
      Block.compose(block, {12, 6}, fn dimensions ->
        Frame.from_rows(["child"], elem(dimensions, 0), elem(dimensions, 1))
      end)

    assert Frame.row_text(block_frame, 3) =~ "child"

    dialog =
      Dialog.init(
        title: "Confirm",
        buttons: [
          %{id: :blocked, label: "No", disabled: true},
          %{id: :ok, label: "OK"}
        ]
      )

    assert dialog.focused == 1
    assert Dialog.content_rect(dialog, {16, 6}) == {1, 1, 14, 3}

    dialog_frame = Dialog.compose(dialog, {16, 6}, Frame.from_rows(["body"], 14, 3))
    assert Frame.row_text(dialog_frame, 2) =~ "body"
    assert {^dialog, [{:selected, :ok}]} = Dialog.update(Event.key(:enter), dialog)
    assert {dialog, []} = Dialog.update(Event.key(:right), dialog)
    assert dialog.focused == 1

    assert {^dialog, []} =
             Dialog.mouse(Event.mouse(:release, :left, 2, 4), dialog, {16, 6})

    assert {^dialog, []} =
             Dialog.mouse(Event.mouse(:release, :left, 7, 4), dialog, {16, 6})

    assert {^dialog, []} =
             Dialog.mouse(Event.mouse(:release, :left, 1, 0), dialog, {16, 2})
  end

  test "block wrapping keeps span styles" do
    red = Style.new(fg: :red)
    blue = Style.new(fg: :blue)
    block = Block.init(content: [[{"red", red}, {"blue", blue}]])
    frame = Block.view(block, {7, 4})

    assert Frame.row_text(frame, 2) == "│redbl│"
    assert Frame.row_text(frame, 3) == "│ue   │"
    assert Frame.cell(frame, 2, 2).fg == :red
    assert Frame.cell(frame, 2, 5).fg == :blue
    assert Frame.cell(frame, 3, 2).fg == :blue
  end
end
