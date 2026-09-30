defmodule TermUI.Widget.AdvancedBehaviorTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame, Style}

  alias TermUI.Widget.{
    AlertDialog,
    Block,
    Button,
    CommandPalette,
    Dialog,
    FormBuilder,
    Gauge,
    Label,
    LogViewer,
    Menu,
    PickList,
    Progress,
    ScrollBar,
    SplitPane,
    Stream,
    Tabs,
    Toast,
    TreeView,
    Viewport
  }

  test "viewport supports bounded two-axis navigation and follow mode" do
    viewport =
      Viewport.init(
        content: [
          [{"zero", Style.new(fg: :cyan)}],
          "one",
          "two",
          "three",
          "four",
          "界wide"
        ],
        page_size: 2
      )

    assert {viewport, [{:scrolled, {1, 0}}]} = Viewport.update(Event.key(:right), viewport)
    assert {viewport, [{:scrolled, {1, 1}}]} = Viewport.update(Event.key(:down), viewport)
    assert {viewport, [{:scrolled, {1, 3}}]} = Viewport.update(Event.key(:page_down), viewport)
    assert {viewport, [{:scrolled, {0, 3}}]} = Viewport.update(Event.key(:left), viewport)
    assert {viewport, []} = Viewport.update(Event.key(:home), viewport)
    assert Viewport.position(viewport) == {0, 3}

    assert {viewport, []} =
             Viewport.update(Event.key(:home, modifiers: [:ctrl]), viewport)

    assert Viewport.position(viewport) == {0, 0}

    assert {viewport, []} = Viewport.update(Event.key(:end, modifiers: [:ctrl]), viewport)
    assert Viewport.position(viewport) == {0, 4}
    assert {^viewport, []} = Viewport.update(Event.key(:end), viewport)

    assert {viewport, [{:scrolled, {0, 1}}]} =
             Viewport.update(Event.mouse(:scroll_up, nil, 0, 0), viewport)

    assert {viewport, [{:scrolled, {0, 4}}]} =
             Viewport.update(Event.mouse(:scroll_down, nil, 0, 0), viewport)

    viewport = %{viewport | scroll_x: 1}
    frame = Viewport.view(viewport, {5, 2})
    assert Frame.row_text(frame, 2) == " wide"

    followed = Viewport.init(content: "a\nb\nc", follow_end: true, page_size: 2)
    followed = Viewport.set_content(followed, "a\nb\nc\nd")
    assert Viewport.position(followed) == {0, 2}
    assert Frame.row_text(Viewport.view(followed, {3, 2}), 1) == "c  "

    assert [{"zero", %Style{}}] = hd(viewport.rows)

    assert Viewport.set_content(%{viewport | follow_end: false, scroll_y: 99}, 123).rows == [
             "123"
           ]
  end

  test "tree navigation expands, activates, selects, and replaces nested children" do
    tree =
      TreeView.init(
        nodes: [
          TreeView.branch(:root, "Root", [TreeView.leaf(:old, "Old")]),
          TreeView.leaf(:last, "Last")
        ],
        page_size: 1
      )

    assert {tree, [{:expanded, :root}]} = TreeView.update(Event.key(:right), tree)

    assert Enum.map(TreeView.visible(tree), fn {node, depth} -> {node.id, depth} end) ==
             [{:root, 0}, {:old, 1}, {:last, 0}]

    assert {tree, []} = TreeView.update(Event.key(:down), tree)
    assert {tree, [{:activated, :old, %{id: :old}}]} = TreeView.update(Event.key(:enter), tree)
    assert {tree, [{:selected, :old}]} = TreeView.update(Event.key(:space), tree)
    assert MapSet.member?(tree.selected, :old)

    assert {tree, []} = TreeView.update(Event.key(:end), tree)
    assert {tree, []} = TreeView.update(Event.key(:page_up), tree)
    assert {tree, []} = TreeView.update(Event.key(:home), tree)
    assert {tree, [{:collapsed, :root}]} = TreeView.update(Event.key(:left), tree)

    tree = TreeView.set_children(tree, :root, [TreeView.leaf(:new, "New")])
    assert get_in(tree.nodes, [Access.at(0), :children, Access.at(0), :id]) == :new

    assert %Frame{} = TreeView.view(tree, {20, 2})
    assert {^tree, []} = TreeView.mouse(Event.mouse(:release, :left, 0, 5), tree, {20, 2})

    empty = TreeView.init(nodes: [])
    assert {^empty, []} = TreeView.update(Event.key(:enter), empty)
    assert {^empty, []} = TreeView.update(Event.key(:space), empty)
  end

  test "pick list cleans queries and handles every terminal action" do
    picker = PickList.init(items: [%{label: "Alpha"}, {:b, "Beta"}, "Gamma"], page_size: 1)

    assert {picker, [{:query_changed, "a"}]} = PickList.update(Event.text("a\n"), picker)
    assert length(PickList.filtered(picker)) == 3
    assert {picker, [{:query_changed, "am"}]} = PickList.update(Event.paste("m\t"), picker)
    assert PickList.filtered(picker) == ["Gamma"]
    assert {picker, []} = PickList.update(Event.key(:end), picker)
    assert {_picker, [{:picked, "Gamma"}]} = PickList.update(Event.key(:enter), picker)
    assert {picker, [{:query_changed, "a"}]} = PickList.update(Event.key(:backspace), picker)
    assert {picker, []} = PickList.update(Event.key(:page_down), picker)
    assert {picker, []} = PickList.update(Event.key(:page_up), picker)
    assert {picker, []} = PickList.update(Event.key(:home), picker)
    assert {picker, [{:query_changed, ""}]} = PickList.update(Event.key(:escape), picker)
    assert {^picker, [:cancel]} = PickList.update(Event.key(:escape), picker)
    assert %Frame{cursor: {_column, 1}} = PickList.view(picker, {12, 3})

    empty = PickList.init(items: [])
    assert {^empty, []} = PickList.update(Event.key(:enter), empty)
    assert {^empty, []} = PickList.mouse(Event.mouse(:release, :left, 0, 0), empty, {10, 2})
  end

  test "menus skip disabled rows and keep visibility and custom messages pure" do
    items = [
      Menu.separator(),
      Menu.action(:disabled, "Disabled", disabled: true),
      %{id: :open, label: "Open", shortcut: "Ctrl+O", message: :open},
      {:save, "Save"},
      "Quit"
    ]

    menu = Menu.init(items: items, title: "File")
    assert Menu.current(menu).id == :open
    assert %Frame{} = Menu.view(menu, {24, 8})
    assert {menu, []} = Menu.update(Event.key(:up), menu)
    assert Menu.current(menu).id == "Quit"
    assert {menu, []} = Menu.update(Event.key(:down), menu)
    assert Menu.current(menu).id == :open
    assert {menu, []} = Menu.update(Event.key(:end), menu)
    assert Menu.current(menu).id == "Quit"
    assert {menu, []} = Menu.update(Event.key(:home), menu)
    assert {_menu, [:open]} = Menu.update(Event.key(:enter), menu)

    hidden = Menu.hide(menu)
    assert {^hidden, []} = Menu.update(Event.key(:down), hidden)
    assert {^hidden, []} = Menu.mouse(Event.mouse(:release, :left, 1, 1), hidden, {20, 4})
    assert Frame.cells(Menu.view(hidden, {10, 2})) == []
    assert Menu.show(hidden).visible

    assert {dismissed, [:dismissed]} = Menu.update(Event.key(:escape), menu)
    refute dismissed.visible

    empty = Menu.init(items: [])
    assert {^empty, []} = Menu.update(Event.key(:down), empty)
    assert {^empty, []} = Menu.update(Event.key(:enter), empty)
  end

  test "forms cover required errors, editing, select cycles, and empty forms" do
    form =
      FormBuilder.init(
        fields: [
          %{id: :name, label: "Name", type: :text, required: true},
          %{id: :enabled, label: "Enabled", type: :checkbox, required: true},
          %{id: :color, label: "Color", type: :select, options: [:red, :blue]}
        ]
      )

    assert {form, [{:invalid, %{enabled: "is required", name: "is required"}}]} =
             FormBuilder.update(Event.key(:enter), form)

    assert %Frame{} = FormBuilder.view(form, {24, 8})
    assert {form, [{:changed, :name, "Ada"}]} = FormBuilder.update(Event.paste("Ada\n"), form)
    assert {form, [{:changed, :name, "Ad"}]} = FormBuilder.update(Event.key(:backspace), form)
    assert {form, []} = FormBuilder.update(Event.key(:down), form)
    assert {form, [{:changed, :enabled, true}]} = FormBuilder.update(Event.key(:space), form)
    assert {form, []} = FormBuilder.update(Event.key(:tab), form)
    assert {form, [{:changed, :color, :blue}]} = FormBuilder.update(Event.key(:right), form)
    assert {form, [{:changed, :color, :red}]} = FormBuilder.update(Event.key(:left), form)
    assert {form, []} = FormBuilder.update(Event.text("ignored"), form)
    assert {form, []} = FormBuilder.update(Event.key(:up), form)
    assert FormBuilder.put_value(form, :enabled, false).values.enabled == false

    empty = FormBuilder.init(fields: [])
    assert {^empty, []} = FormBuilder.update(Event.key(:tab), empty)
    assert {^empty, []} = FormBuilder.update(Event.key(:space), empty)
    assert {^empty, []} = FormBuilder.update(Event.text("text"), empty)
    assert {^empty, [{:submit, %{}}]} = FormBuilder.update(Event.key(:enter), empty)
  end

  test "log viewer filters, wraps levels, and changes follow state" do
    logs =
      LogViewer.init(
        entries: [
          %{message: :debug, level: :debug},
          %{message: "warn", level: :warning, timestamp: "T"},
          %{message: "error", level: :error},
          "info"
        ],
        page_size: 2,
        follow: false
      )

    assert %Frame{} = LogViewer.view(logs, {8, 3})
    assert {logs, [{:scrolled, 1}]} = LogViewer.update(Event.key(:down), logs)
    assert {logs, [{:scrolled, 2}]} = LogViewer.update(Event.key(:page_down), logs)
    assert logs.follow
    assert {logs, []} = LogViewer.update(Event.key(:home), logs)
    refute logs.follow
    assert {logs, []} = LogViewer.update(Event.key(:end), logs)
    assert logs.follow
    assert {logs, [{:follow, false}]} = LogViewer.update(Event.text("f"), logs)

    logs = LogViewer.set_filter(logs, "ERR")
    assert Frame.row_text(LogViewer.view(logs, {8, 2}), 1) =~ "error"
    logs = logs |> LogViewer.set_filter(nil) |> LogViewer.append(["n", "e", "w"])
    assert List.last(logs.entries).message == "new"
  end

  test "dialogs, alerts, and palettes handle hidden, disabled, and cancel paths" do
    dialog =
      Dialog.init(
        title: "Action",
        content: 123,
        buttons: [
          %{id: :blocked, label: "Blocked", disabled: true},
          %{id: :ok, label: "OK", message: :accepted}
        ]
      )

    assert {^dialog, [:accepted]} = Dialog.update(Event.key(:enter), dialog)
    assert {dialog, []} = Dialog.update(Event.key(:right), dialog)
    assert {_dialog, [:accepted]} = Dialog.update(Event.text(" "), dialog)
    assert %Frame{} = Dialog.view(dialog, {24, 6})

    hidden = Dialog.hide(dialog)
    assert {^hidden, []} = Dialog.update(Event.key(:escape), hidden)
    assert {^hidden, []} = Dialog.mouse(Event.mouse(:release, :left, 3, 4), hidden, {24, 6})
    assert Frame.cells(Dialog.view(hidden, {10, 2})) == []
    assert Dialog.show(hidden).visible

    assert {dismissed, [:dismissed]} = Dialog.update(Event.key(:escape), dialog)
    refute dismissed.visible

    for type <- [:info, :warning, :error, :confirm] do
      alert = AlertDialog.init(type: type, message: "Message")
      assert %Frame{} = AlertDialog.view(alert, {24, 6})
    end

    confirm = AlertDialog.init(type: :confirm, message: "Continue?")
    assert {_confirm, [:confirm]} = AlertDialog.update(Event.key(:enter), confirm)

    palette = CommandPalette.init(commands: ["Open", "Close"])
    assert {^palette, []} = CommandPalette.update(Event.text("o"), palette)
    assert Frame.cells(CommandPalette.view(palette, {20, 6})) == []
    palette = CommandPalette.show(palette)
    assert {palette, [{:query_changed, "o"}]} = CommandPalette.update(Event.text("o"), palette)
    assert {palette, [query_changed: ""]} = CommandPalette.update(Event.key(:escape), palette)
    assert palette.visible
    assert {palette, [:cancel]} = CommandPalette.update(Event.key(:escape), palette)
    refute palette.visible
    assert CommandPalette.hide(CommandPalette.show(palette)).visible == false
  end

  test "scrollbars, split panes, gauges, and progress cover edge dimensions" do
    horizontal =
      ScrollBar.init(
        orientation: :horizontal,
        content_size: 10,
        viewport_size: 3,
        offset: 99
      )

    assert horizontal.offset == 7
    assert %Frame{} = ScrollBar.view(horizontal, {8, 1})
    assert {horizontal, [{:scrolled, 6}]} = ScrollBar.update(Event.key(:left), horizontal)
    assert {horizontal, [{:scrolled, 3}]} = ScrollBar.update(Event.key(:page_up), horizontal)
    assert {horizontal, [{:scrolled, 6}]} = ScrollBar.update(Event.key(:page_down), horizontal)

    assert {horizontal, [{:scrolled, 7}]} =
             ScrollBar.mouse(Event.mouse(:press, :left, 7, 0), horizontal, {8, 1})

    assert {horizontal, [{:scrolled, 0}]} =
             ScrollBar.mouse(Event.mouse(:drag, :left, 0, 0), horizontal, {8, 1})

    assert {horizontal, []} =
             ScrollBar.mouse(Event.mouse(:release, :left, 0, 0), horizontal, {8, 1})

    assert ScrollBar.set(horizontal, 0, 0, 9).offset == 0
    assert %Frame{} = ScrollBar.view(ScrollBar.init([]), {1, 1})

    split =
      SplitPane.init(
        first: fn size -> Frame.from_rows([inspect(size)], elem(size, 0), elem(size, 1)) end,
        second: ["B"],
        direction: :vertical
      )

    assert %Frame{} = SplitPane.view(split, {10, 6})
    assert {^split, []} = SplitPane.mouse(Event.mouse(:press, :left, 0, 0), split, {10, 6})

    vertical = Gauge.init(value: 80, orientation: :vertical)
    assert %Frame{} = Gauge.view(vertical, {2, 4})
    assert Gauge.set_value(vertical, 20).value == 20
    assert %Frame{} = Gauge.view(Gauge.init(value: 5, min: 5, max: 5, label: "X"), {12, 1})

    progress = Progress.init(value: 120, label: "Load")
    assert %Frame{} = Progress.view(progress, {20, 1})
    assert Progress.set_value(progress, -10).value == -10
    indeterminate = Progress.init(indeterminate: true, show_percent: false)
    assert Progress.tick(indeterminate).phase == 1
    assert %Frame{} = Progress.view(Progress.tick(indeterminate), {3, 1})
  end

  test "text containers, buttons, streams, and toasts retain pure setters" do
    block = Block.init(content: [[{"styled", Style.new()}]], title: "Box", padding: 1)
    assert %Frame{} = Block.view(block, {14, 5})
    assert Block.set_content(block, 123).rows == ["123"]

    label = Label.init(text: "long label", wrap: false, align: :right)
    assert %Frame{} = Label.view(label, {6, 1})
    assert Label.set_text(label, ["n", "e", "w"]).text == "new"

    button = Button.init(id: :go, label: "Go", disabled: true)
    assert {^button, []} = Button.update(Event.key(:enter), button)
    assert %Frame{} = Button.view(button, {10, 1})
    button = Button.focus(%{button | disabled: false})
    assert {button, []} = Button.update(Event.mouse(:press, :left, 0, 0), button)
    assert button.pressed
    assert {button, [{:pressed, :go}]} = Button.update(Event.mouse(:release, :left, 0, 0), button)
    assert {^button, []} = Button.update(Event.focus(:lost), button)
    assert button.focused
    refute Button.focus(button, false).focused

    stream = Stream.init(items: Enum.to_list(1..8), page_size: 2, formatter: &inspect/1)
    assert {stream, [{:scrolled, 1}]} = Stream.update(Event.key(:down), stream)
    assert stream.paused
    assert Stream.push(stream, 9) == stream
    assert {stream, [{:scrolled, 3}]} = Stream.update(Event.key(:page_down), stream)
    assert {stream, [{:scrolled, 1}]} = Stream.update(Event.key(:page_up), stream)
    assert {stream, []} = Stream.update(Event.key(:end), stream)
    assert %Frame{} = Stream.view(stream, {8, 3})

    toast = Toast.init(id: :notice, message: "Done", type: :error, duration: 5)
    assert %Frame{} = Toast.view(toast, {12, 3})
    assert Toast.tick(toast, 2).visible
    refute Toast.tick(toast, 5).visible
    assert Toast.tick(%{toast | duration: :infinity}, 50) == %{toast | duration: :infinity}
    assert {toast, [{:dismissed, :notice}]} = Toast.update(Event.key(:escape), toast)
    refute toast.visible
    assert Frame.cells(Toast.view(toast, {8, 2})) == []

    manager = Toast.Manager.new(limit: 1) |> Toast.Manager.add("A", :warning, duration: 1)
    assert Toast.Manager.tick(manager, 1).toasts == []
  end

  test "tabs cover disabled, frame, list, nil, and scalar content" do
    content = Frame.from_rows(["frame"], 12, 2)

    tabs =
      Tabs.init(
        tabs: [
          %{id: :frame, label: "Frame", content: content},
          %{id: :disabled, label: "No", disabled: true},
          %{id: :rows, label: "Rows", content: ["row"]},
          %{id: nil, label: "Nil", content: nil},
          %{id: :scalar, label: "Scalar", content: 123}
        ],
        selected: :frame
      )

    assert %Frame{} = Tabs.view(tabs, {12, 3})
    assert {tabs, _} = Tabs.update(Event.key(:left), tabs)
    assert {tabs, _} = Tabs.update(Event.key(:end), tabs)
    assert {tabs, _} = Tabs.update(Event.key(:home), tabs)
    assert {^tabs, []} = Tabs.update(Event.key(:unknown), tabs)

    negative_x = %Event.Mouse{
      action: :release,
      button: :left,
      x: -1,
      y: 0,
      modifiers: [],
      timestamp: 0
    }

    assert {^tabs, []} = Tabs.mouse(negative_x, tabs, {12, 3})
    assert {^tabs, []} = Tabs.mouse(Event.mouse(:release, :left, 99, 0), tabs, {12, 3})

    assert {tabs, _} = Tabs.update(Event.key(:right), tabs)
    assert {tabs, [{:selected, :rows}]} = Tabs.update(Event.key(:enter), tabs)
    assert Tabs.selected(tabs).id == :rows
    tabs = Tabs.select(tabs, :rows)
    assert Tabs.selected(tabs).id == :rows
    assert %Frame{} = Tabs.view(tabs, {12, 3})
    assert %Frame{} = Tabs.view(Tabs.select(tabs, nil), {12, 3})
    assert %Frame{} = Tabs.view(Tabs.select(tabs, :scalar), {12, 3})

    empty = Tabs.init(tabs: [])
    assert {^empty, []} = Tabs.update(Event.key(:right), empty)
    assert {^empty, []} = Tabs.update(Event.key(:enter), empty)
    assert Tabs.selected(empty) == nil
    assert %Frame{} = Tabs.view(empty, {12, 3})

    labels = Tabs.init(tabs: ["Plain"])
    assert Tabs.selected(labels) == %{id: "Plain", label: "Plain"}

    assert %Frame{} =
             Tabs.view(%{labels | tabs: [%{id: :text, label: "Text", content: "body"}]}, {12, 3})
  end
end
