defmodule TermUI.Widget.Cycle1StateTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame, Selection, Style, Widget}

  alias TermUI.Widget.{
    BarChart,
    Canvas,
    ClusterDashboard,
    CommandPalette,
    ContextMenu,
    DiffViewer,
    Gauge,
    LogViewer,
    Menu,
    ProcessMonitor,
    Progress,
    Sparkline,
    SplitPane,
    Stream,
    SupervisionTree,
    SupervisionTreeViewer,
    Table,
    TextArea,
    Toast,
    TreeView,
    Viewport
  }

  test "complete root and ancestor menu clicks keep the displayed target until release" do
    items = [
      Menu.submenu(:file, "File", [Menu.action(:a, "A"), Menu.action(:b, "B")]),
      Menu.action(:help, "Help"),
      Menu.action(:exit, "Exit"),
      Menu.action(:delete, "Delete")
    ]

    menu = Menu.init(items: items) |> Menu.open_submenu()

    for {id, y} <- [help: 4, exit: 5, delete: 6] do
      {pressed, []} = Menu.mouse(Event.mouse(:press, :left, 2, y), menu, {24, 10})
      assert rows(Menu.view(pressed, {24, 10})) == rows(Menu.view(menu, {24, 10}))

      assert {_, [{:selected, ^id}]} =
               Menu.mouse(Event.mouse(:release, :left, 2, y), pressed, {24, 10})
    end

    context = ContextMenu.init(items: items)
    context = %{context | menu: menu}
    {context, []} = ContextMenu.mouse(Event.mouse(:press, :left, 2, 4), context, {24, 10})

    assert {_, [{:selected, :help}]} =
             ContextMenu.mouse(Event.mouse(:release, :left, 2, 4), context, {24, 10})

    nested =
      Menu.init(
        items: [
          Menu.submenu(:file, "File", [
            Menu.submenu(:recent, "Recent", [Menu.action(:a, "A"), Menu.action(:b, "B")]),
            Menu.action(:help, "Help"),
            Menu.action(:delete, "Delete")
          ])
        ]
      )
      |> Menu.open_submenu()
      |> Menu.open_submenu()

    {pressed, []} = Menu.mouse(Event.mouse(:press, :left, 2, 5), nested, {24, 10})
    assert pressed.open_path == nested.open_path

    assert {_, [{:selected, :help}]} =
             Menu.mouse(Event.mouse(:release, :left, 2, 5), pressed, {24, 10})
  end

  test "marked letters select the complete word without changing its source" do
    for word <- ["café", "cafe\u0301", "אְבגד", "a_1\u0301"] do
      text = word <> "! tail"

      for index <- 0..(String.length(word) - 1) do
        selection = Selection.select_word(Selection.new(), text, index)
        assert Selection.extract(selection, text) == word
      end

      assert Selection.extract(
               Selection.select_word(Selection.new(), text, String.length(word)),
               text
             ) == "!"

      assert Selection.extract(
               Selection.select_word(Selection.new(), text, String.length(word) + 1),
               text
             ) == " "
    end
  end

  test "imported line endings keep source bytes and grapheme positions across navigation and copy" do
    for ending <- ["\n", "\r\n", "\r"] do
      text = "one" <> ending <> "two" <> ending <> "three"
      assert Selection.extract(Selection.select_line(Selection.new(), text, 5), text) == "two"

      for state <- [
            TextArea.init(value: "one" <> ending <> "two"),
            TextArea.set_value(TextArea.init([]), "one" <> ending <> "two")
          ] do
        assert TextArea.view(state, {10, 3}).cursor == {4, 2}
        assert state.cursor == 7
        {home, []} = TextArea.update(Event.key(:home), state)
        assert home.cursor == 4
        {at_end, []} = TextArea.update(Event.key(:end), home)
        assert at_end.cursor == 7
        {up, []} = TextArea.update(Event.key(:up), state)
        assert up.cursor == 3
        {down, []} = TextArea.update(Event.key(:down), up)
        assert down.cursor == 7
        {clicked, []} = TextArea.mouse(Event.mouse(:press, :left, 0, 1), state, {10, 3})
        assert clicked.cursor == 4
        {selected, []} = TextArea.update(Event.key(:home, modifiers: [:shift]), state)

        assert {_, [{:copy, "two"}]} =
                 TextArea.update(Event.key("c", modifiers: [:ctrl]), selected)

        assert TextArea.value(state) == "one" <> ending <> "two"
      end
    end

    {pasted, _} = TextArea.update(Event.paste("one\r\ntwo\rthree"), TextArea.init([]))
    assert pasted.value == "one\ntwo\nthree"
    mixed = TextArea.init(value: "one\r\ntwo\nthree\rfour")
    assert TextArea.view(mixed, {10, 5}).cursor == {5, 4}
  end

  test "wrapped wide graphemes expose their displayed start to keyboard mouse and selection" do
    for wide <- ["界", "👩‍💻"] do
      state = TextArea.init(value: "a" <> wide <> "z")
      {state, []} = TextArea.update(Event.key(:left), state)
      {state, []} = TextArea.update(Event.key(:left), state)
      assert state.cursor == 1
      assert TextArea.view(state, {2, 4}).cursor == {1, 2}

      for x <- [0, 1] do
        {clicked, []} = TextArea.mouse(Event.mouse(:press, :left, x, 1), state, {2, 4})
        assert clicked.cursor == 1
      end

      {selected, []} = TextArea.update(Event.key(:right, modifiers: [:shift]), state)
      assert Selection.extract(selected.selection, selected.value) == wide
      assert :reverse in Frame.cell(TextArea.view(selected, {2, 4}), 2, 1).attrs
    end
  end

  test "palette navigation and clicks use the visible picker body with styles and cursor" do
    for dimensions <- [{20, 6}, {30, 9}] do
      state =
        CommandPalette.init(
          commands: [{:a, "AAA"}, {:b, "BBB"}, {:c, "CCC"}, {:d, "DDD"}],
          visible: true
        )

      for {id, label} <- [{:a, "AAA"}, {:b, "BBB"}, {:c, "CCC"}, {:d, "DDD"}] do
        index = Enum.find_index(state.picker.items, &(elem(&1, 0) == id))
        selected = %{state | picker: %{state.picker | cursor: index}}
        frame = CommandPalette.view(selected, dimensions)
        y = Enum.find_index(rows(frame), &String.contains?(&1, label))
        assert is_integer(y)
        assert frame.cursor == {4, 2}
        assert Frame.cell(frame, y + 1, 2).bg == :cyan

        assert {_, [{:command, {^id, ^label}}]} =
                 CommandPalette.mouse(Event.mouse(:release, :left, 2, y), selected, dimensions)

        assert {_, []} =
                 CommandPalette.mouse(
                   Event.mouse(:release, :left, 2, elem(dimensions, 1) - 2),
                   selected,
                   dimensions
                 )
      end
    end

    for dimensions <- [{1, 1}, {2, 2}, {3, 3}] do
      state = CommandPalette.init(commands: [{:a, "A"}], visible: true)
      assert %Frame{} = CommandPalette.view(state, dimensions)
      assert {_, []} = CommandPalette.mouse(Event.mouse(:release, :left, 0, 0), state, dimensions)
    end
  end

  test "root snapshot replacement normalizes the tree cursor through both public names" do
    for module <- [SupervisionTree, SupervisionTreeViewer] do
      state = module.init(nodes: Enum.map(1..10, &TreeView.leaf(&1, "node#{&1}")))
      {state, []} = module.update(Event.key(:end), state)
      state = module.set_nodes(state, [TreeView.leaf(:new, "NEW")])
      assert hd(rows(module.view(state, {20, 3}))) =~ "NEW"
      assert state.tree.cursor == 0
      assert {_, [_]} = module.update(Event.key(:enter), state)
      assert module.set_nodes(state, []).tree.cursor == 0
      disabled = module.set_nodes(state, [TreeView.leaf(:disabled, "Disabled", disabled: true)])
      assert {_, []} = module.update(Event.key(:enter), disabled)
    end

    tree =
      TreeView.init(
        nodes: [TreeView.branch(:root, "Root", [TreeView.leaf(:child, "Child")])],
        expanded: [:root],
        selected: [:child]
      )

    next = TreeView.set_nodes(tree, tree.nodes)
    assert next.expanded == tree.expanded
    assert next.selected == tree.selected
  end

  test "Home leaves viewport follow mode and styled horizontal crops retain whole cells" do
    state =
      Viewport.init(
        content: Enum.map(1..20, &Integer.to_string/1),
        follow_end: true,
        scrollbars: :both
      )

    {state, []} = Widget.update(Viewport, Event.key(:home, modifiers: [:ctrl]), state, {5, 4})
    refute state.follow_end
    assert hd(rows(Viewport.view(state, {5, 4}))) =~ "1"
    state = Viewport.set_content(state, state.rows ++ ["21"])
    {state, _} = Widget.update(Viewport, Event.key(:down), state, {5, 4})
    assert state.scroll_y == 1
    red = Style.new(fg: :red, attrs: [:bold])
    blue = Style.new(fg: :blue)
    long = Viewport.init(content: [[String.duplicate("a", 1200), {"blue", blue}]])
    long_frame = Viewport.view(%{long | scroll_x: 1200}, {4, 1})
    assert Frame.row_text(long_frame, 1) == "blue"
    assert Frame.cell(long_frame, 1, 1).fg == :blue
    charlist = Viewport.init(content: [~c"plain"])
    assert Frame.row_text(Viewport.view(charlist, {5, 1}), 1) == "plain"

    styled = Viewport.init(content: [[{"a界", red}, {"blue", blue}]])

    for {offset, first, color} <- [
          {0, "a", :red},
          {1, "界", :red},
          {2, " ", :default},
          {3, "b", :blue}
        ] do
      frame = Viewport.view(%{styled | scroll_x: offset}, {4, 1})
      assert Frame.cell(frame, 1, 1).char == first
      assert Frame.cell(frame, 1, 1).fg == color
      if color == :red, do: assert(:bold in Frame.cell(frame, 1, 1).attrs)
    end
  end

  test "a dismissed toast stays hidden on keyboard mouse and later clock ticks" do
    for duration <- [1000, :infinity] do
      state = Toast.init(id: :notice, duration: duration, message: "hello")

      for dismissed <- [
            elem(Toast.update(Event.key(:escape), state), 0),
            elem(Widget.mouse(Toast, Event.mouse(:release, :left, 0, 0), state, {10, 1}), 0)
          ] do
        refute Toast.tick(Toast.tick(dismissed, 1), 1).visible
      end
    end

    state = Toast.init(duration: 10)
    assert Toast.tick(state, 9).visible
    refute Toast.tick(state, 10).visible
  end

  test "pane drag inverts minimum allocation in both directions and preserves other panes" do
    for direction <- [:horizontal, :vertical],
        panes <- [[a: "A", b: "B"], [a: "A", b: "B", c: "C"]],
        minimum <- [1, 10, 20] do
      dimensions = if direction == :horizontal, do: {151, 4}, else: {4, 151}
      state = SplitPane.init(panes: panes, direction: direction, min_size: minimum)
      layout = SplitPane.layout(state, dimensions)
      position = hd(layout.separators).position
      pointer = minimum + 5
      {x, y} = if direction == :horizontal, do: {position, 0}, else: {0, position}
      {state, []} = SplitPane.mouse(Event.mouse(:press, :left, x, y), state, dimensions)
      {x, y} = if direction == :horizontal, do: {pointer, 0}, else: {0, pointer}
      {next, _} = SplitPane.mouse(Event.mouse(:drag, :left, x, y), state, dimensions)
      assert abs(hd(SplitPane.layout(next, dimensions).separators).position - pointer) <= 1
      if length(panes) == 3, do: assert(Enum.at(next.ratios, 2) == Enum.at(state.ratios, 2))
      assert_in_delta Enum.sum(next.ratios), Enum.sum(state.ratios), 1.0e-10
    end

    collapsed = SplitPane.init(panes: [a: "A", b: "B", c: "C"], collapsed: [:b], min_size: 20)
    separator = hd(SplitPane.layout(collapsed, {101, 4}).separators).position

    {collapsed, []} =
      SplitPane.mouse(Event.mouse(:press, :left, separator, 0), collapsed, {101, 4})

    {collapsed, _} = SplitPane.mouse(Event.mouse(:drag, :left, 25, 0), collapsed, {101, 4})
    assert abs(hd(SplitPane.layout(collapsed, {101, 4}).separators).position - 25) <= 1

    state = SplitPane.init(panes: [a: "A", b: "B"], min_size: 20)
    {state, []} = SplitPane.mouse(Event.mouse(:press, :left, 20, 0), state, {41, 4})
    assert {^state, []} = SplitPane.mouse(Event.mouse(:drag, :left, 10, 0), state, {41, 4})
  end

  test "positive pane weights are scale independent in layout keyboard resize and restore" do
    normal = SplitPane.init(panes: [a: "A", b: "B"], ratios: [1, 2])

    for factor <- [1.0e-8, 0.5, 1.0e8] do
      scaled = SplitPane.init(panes: [a: "A", b: "B"], ratios: [factor, factor * 2])
      assert sizes(scaled) == sizes(normal)
      assert Enum.sum(sizes(scaled)) + 1 == 101
      {resized, _} = SplitPane.update(Event.key(:right), scaled)
      {normal_resized, _} = SplitPane.update(Event.key(:right), normal)
      assert sizes(resized) == sizes(normal_resized)
      assert {:ok, restored} = SplitPane.restore(normal, SplitPane.serialize(scaled))
      assert sizes(restored) == sizes(normal)
    end

    collapsed =
      SplitPane.init(
        panes: [a: "A", b: "B", c: "C"],
        ratios: [1.0e-8, 1.0e-8, 1.0e-8],
        collapsed: [:b]
      )

    assert Enum.sum(sizes(collapsed)) + 1 == 101
  end

  test "chart label columns retain all samples and complete value suffixes" do
    for label <- ["A", "界", "👩‍💻", "e\u0301"] do
      spark = Sparkline.init(label: label, values: [1, 2, 3])
      width = Sparkline.natural_width(spark)
      assert width == TermUI.DisplayWidth.width(label) + 4
      assert hd(rows(Sparkline.view(spark, {width, 1}))) =~ "▁▅█"
      assert hd(rows(Gauge.view(Gauge.init(label: label, value: 50), {10, 1}))) =~ "50"
      assert hd(rows(Progress.view(Progress.init(label: label, value: 50), {12, 1}))) =~ "50%"
      chart = BarChart.init(data: [{label, 50}])
      assert hd(rows(BarChart.view(chart, {20, 1}))) =~ "50"
    end
  end

  test "table cursor identity uses exact term equality including a nil ID" do
    rows = [%{id: 1, name: "int"}, %{id: 1.0, name: "float"}, %{id: nil, name: "nil"}]
    state = Table.init(rows: rows, row_id: :id)
    {state, _} = Table.update(Event.key(:down), state)
    next = Table.set_rows(state, rows)
    assert Enum.at(next.display_rows, next.cursor).id === 1.0
    sorted = Table.sort_by(next, :name, :asc)
    assert Enum.at(sorted.display_rows, sorted.cursor).id === 1.0
    filtered = Table.set_filter(sorted, &(&1.id === 1.0))
    assert Enum.at(filtered.display_rows, filtered.cursor).id === 1.0
    {state, _} = Table.update(Event.key(:down), state)
    next = Table.set_rows(state, Enum.reverse(rows))
    assert Enum.at(next.display_rows, next.cursor).id === nil
    next = Table.set_rows(next, [hd(rows)])
    assert next.cursor == 0
    next = Table.set_rows(next, [])
    assert next.cursor == 0
    nil_row = Table.init(rows: [nil, :other]) |> Table.set_rows([:other, nil])
    assert Enum.at(nil_row.display_rows, nil_row.cursor) === nil
  end

  test "snapshot row identity remains compatible and can be selected by the caller" do
    for {module, key, option, setter} <- [
          {ProcessMonitor, :pid, :snapshots, :set_snapshots},
          {ClusterDashboard, :node, :nodes, :set_nodes}
        ] do
      first = %{key => :entity, :memory => 1}
      changed = %{key => :entity, :memory => 2}
      default = module.init([{option, [first, changed]}])
      assert length(default.table.rows) == 2
      {default, _} = module.update(Event.key(:enter), default)
      replaced = apply(module, setter, [default, [%{key => :entity, :memory => 3}]])
      assert Table.selected_rows(replaced.table) == []
      selected = module.init([{option, [first]}, {:row_id, key}])
      {selected, _} = module.update(Event.key(:enter), selected)
      replaced = apply(module, setter, [selected, [changed]])
      assert Table.selected_rows(replaced.table) == [changed]

      assert_raise ArgumentError, fn ->
        module.init([{option, [first, changed]}, {:row_id, key}])
      end
    end
  end

  test "wheel input follows existing log and stream pause policies with current dimensions" do
    entries = Enum.map(1..20, &Integer.to_string/1)
    log = LogViewer.init(entries: entries, follow: false)

    {log, [{:scrolled, 3}]} =
      Widget.mouse(LogViewer, Event.mouse(:scroll_down, nil, 0, 0), log, {10, 3})

    refute log.follow
    {log, _} = Widget.update(LogViewer, Event.key(:end), log, {10, 3})

    {log, [{:scrolled, 14}]} =
      Widget.mouse(LogViewer, Event.mouse(:scroll_up, nil, 0, 0), log, {10, 3})

    refute log.follow

    {log, [{:scrolled, 17}]} =
      Widget.mouse(LogViewer, Event.mouse(:scroll_down, nil, 0, 0), log, {10, 3})

    assert log.follow
    stream = Stream.init(items: entries)

    {stream, [{:scrolled, 15}]} =
      Widget.mouse(Stream, Event.mouse(:scroll_up, nil, 0, 0), stream, {10, 3})

    assert stream.paused

    {stream, [{:scrolled, 18}]} =
      Widget.mouse(Stream, Event.mouse(:scroll_down, nil, 0, 0), stream, {10, 3})

    assert stream.paused
    assert Stream.push(stream, "next").offset == stream.offset
  end

  test "signed canvas lines clip all edges and preserve in-frame points" do
    for {x0, y0, x1, y1, expected} <- [
          {-1, 0, 3, 0, "xxxx "},
          {0, -1, 0, 3, "x    "},
          {3, 0, 8, 0, "   xx"},
          {-3, -2, -1, -2, "     "}
        ] do
      canvas = Canvas.init(width: 5, height: 2) |> Canvas.draw_line(x0, y0, x1, y1, "x")
      assert hd(rows(Canvas.view(canvas, {5, 2}))) == expected
    end
  end

  test "diff navigation uses rendered rows with dimensions and retains end distance without them" do
    before = Enum.map_join(1..20, "\n", &"old#{&1}")
    after_text = Enum.map_join(1..20, "\n", &"new#{&1}")

    for mode <- [:unified, :split],
        {before, after_text} <- [
          {before, after_text},
          {"", after_text},
          {before, ""},
          {before, before <> "\nadded"}
        ] do
      state = DiffViewer.init(before: before, after: after_text, mode: mode)
      {at_end, _} = Widget.update(DiffViewer, Event.key(:end), state, {30, 5})
      {up, [{:scrolled, {:end, 1}}]} = Widget.update(DiffViewer, Event.key(:up), at_end, {30, 5})

      assert tl(rows(DiffViewer.view(up, {30, 5}))) ==
               Enum.take(rows(DiffViewer.view(at_end, {30, 5})), 4)

      down =
        Enum.reduce(1..100, state, fn _, acc ->
          Widget.update(DiffViewer, Event.key(:down), acc, {30, 5}) |> elem(0)
        end)

      {one_up, _} = Widget.update(DiffViewer, Event.key(:up), down, {30, 5})
      assert one_up.scroll == down.scroll - 1

      assert tl(rows(DiffViewer.view(one_up, {30, 5}))) ==
               Enum.take(rows(DiffViewer.view(down, {30, 5})), 4)

      resized = DiffViewer.set_dimensions(down, {30, 100})
      assert resized.scroll == 0
      {wheel, _} = Widget.update(DiffViewer, Event.mouse(:scroll_up, nil, 0, 0), at_end, {30, 5})
      assert wheel.scroll == {:end, 3}
    end

    state = DiffViewer.init(before: before, after: after_text)
    {state, []} = DiffViewer.update(Event.key(:end), state)
    {state, _} = DiffViewer.update(Event.key(:up), state)
    assert state.scroll == {:end, 1}
    assert %Frame{} = DiffViewer.view(state, {30, 5})
  end

  defp rows(frame), do: Enum.map(1..frame.height, &Frame.row_text(frame, &1))
  defp sizes(state), do: Enum.map(SplitPane.layout(state, {101, 4}).panes, & &1.size)
end
