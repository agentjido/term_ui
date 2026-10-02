defmodule TermUI.Widget.Cycle2StateTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Focus, Frame, Selection, Style}

  alias TermUI.Widget.{
    Canvas,
    Checkbox,
    CommandPalette,
    FormBuilder,
    Menu,
    PickList,
    RadioGroup,
    Router,
    Select,
    SplitPane,
    Table,
    Tabs,
    TextArea,
    TextInput,
    Toast,
    TreeView
  }

  test "full PickList and Palette clicks retain each visible item before release" do
    items = Enum.map(1..15, &"item-#{&1}")

    for cursor <- [5, 9, 14], height <- [2, 5], row <- 1..(height - 1), query <- ["", "item-"] do
      state = %{PickList.init(items: items, query: query) | cursor: cursor}
      initial = PickList.view(state, {20, height})
      label = Frame.row_text(initial, row + 1) |> String.slice(2..-1//1) |> String.trim()
      {pressed, []} = PickList.mouse(Event.mouse(:press, :left, 2, row), state, {20, height})

      assert Frame.row_text(PickList.view(pressed, {20, height}), row + 1)
             |> String.slice(2..-1//1)
             |> String.trim() == label

      assert {_, [{:picked, ^label}]} =
               PickList.mouse(Event.mouse(:release, :left, 2, row), pressed, {20, height})
    end

    for row <- 2..5 do
      state = CommandPalette.init(commands: items, visible: true)
      {state, _} = CommandPalette.update(Event.key(:end), state)
      frame = CommandPalette.view(state, {20, 8})
      label = Frame.row_text(frame, row + 1) |> String.slice(3..-2//1) |> String.trim()
      {pressed, []} = CommandPalette.mouse(Event.mouse(:press, :left, 2, row), state, {20, 8})

      assert {_, [{:command, ^label}]} =
               CommandPalette.mouse(Event.mouse(:release, :left, 2, row), pressed, {20, 8})
    end

    state = PickList.init(items: items)
    assert {^state, []} = PickList.mouse(Event.mouse(:press, :left, 0, 0), state, {20, 1})
    {pressed, []} = PickList.mouse(Event.mouse(:press, :left, 2, 2), state, {20, 20})
    assert pressed.cursor == 1
  end

  test "focus and routes retain exact numeric and compound identities" do
    for {integer, float} <- [{1, 1.0}, {{:id, 1}, {:id, 1.0}}] do
      focus = Focus.new([integer, float])
      assert Focus.focused?(focus, integer)
      refute Focus.focused?(focus, float)
      assert {next, [{:focus_changed, ^integer, ^float}]} = Focus.route(Event.key(:tab), focus)
      assert next.current === float
      assert Focus.focus(focus, float).current === float
      assert Focus.disable(focus, integer).current === float
      assert Focus.enable(Focus.disable(next, integer), integer).disabled == []
      refute Router.focused?(Router.new(float, Checkbox, [:b]), focus)
    end
  end

  test "selection labels, styles, messages, and tabs use exact IDs including nil" do
    for module <- [Select, RadioGroup] do
      state = module.init(options: [{1, "integer"}, {1.0, "float"}], selected: 1.0, open: true)
      assert state.cursor == 1
      assert {_, [{:selected, nil, value}]} = module.update(Event.key(:enter), state)
      assert value === 1.0
      frame = module.view(state, {20, 3})
      if module == Select, do: assert(Frame.row_text(frame, 1) =~ "float")

      if module == RadioGroup,
        do:
          assert(
            Enum.map_join(1..3, &Frame.row_text(frame, &1))
            |> String.graphemes()
            |> Enum.count(&(&1 == "●")) == 1
          )
    end

    tabs = Tabs.init(tabs: [{1, "integer"}, {1.0, "float"}, {nil, "Nil"}], selected: 1.0)
    assert Tabs.selected(tabs).id === 1.0
    assert Tabs.selected(Tabs.select(tabs, nil)).id === nil

    assert Tabs.selected(Tabs.init(tabs: [{:other, "Other"}, {nil, "Nil"}], selected: nil)).id ===
             nil

    assert Tabs.selected(Tabs.init(tabs: [{:other, "Other"}, {nil, "Nil"}])).id == :other
    assert Tabs.select(tabs, :missing) == tabs
  end

  test "Menu paths open and close the exact submenu and preserve click topology" do
    items = [
      Menu.submenu(1, "integer", [Menu.action(:i, "I")]),
      Menu.submenu(1.0, "float", [Menu.action(:f, "F")])
    ]

    for orientation <- [:vertical, :horizontal] do
      menu = %{Menu.init(items: items, orientation: orientation) | cursor: 1}
      {menu, _} = Menu.update(Event.key(:enter), menu)
      assert menu.open_path === [1.0]
      assert {_, [{:selected, :f}]} = Menu.update(Event.key(:enter), menu)
      {closed, _} = Menu.update(Event.key(:escape), menu)
      assert closed.cursor == 1
      assert closed.open_path == []
    end
  end

  test "tree, panes, and Toast operations change only the exact numeric identity" do
    tree =
      TreeView.init(nodes: [TreeView.branch(1, "integer", []), TreeView.branch(1.0, "float", [])])
      |> TreeView.set_children(1.0, [TreeView.leaf(:c, "child")])

    assert Enum.map(tree.nodes, &length(&1.children)) == [0, 1]

    panes =
      SplitPane.init(panes: [{1, "integer"}, {1.0, "float"}]) |> SplitPane.put_pane(1.0, "new")

    assert Enum.map(panes.panes, & &1.content) == ["integer", "new"]

    assert {:error, :pane_mismatch} =
             SplitPane.restore(panes, Map.put(SplitPane.serialize(panes), :pane_ids, [1.0, 1]))

    assert {:ok, _} = SplitPane.restore(panes, SplitPane.serialize(panes))
    assert SplitPane.collapse(panes, 1.0).collapsed === [1.0]

    manager =
      Toast.Manager.new()
      |> Toast.Manager.add("integer", :info, id: 1)
      |> Toast.Manager.add("float", :info, id: 1.0)

    assert length(manager.toasts) == 2
    dismissed = Toast.Manager.dismiss(manager, 1.0)
    assert Enum.map(dismissed.toasts, & &1.id) === [1]
    replaced = Toast.Manager.add(manager, "new float", :info, id: 1.0)
    assert length(replaced.toasts) == 2
    float = Enum.find(manager.toasts, &(&1.id === 1.0))

    expired =
      Toast.Manager.expire(manager, {:term_ui_toast_expire, manager.id, 1.0, float.expiry_token})

    assert Enum.map(expired.toasts, & &1.id) === [1]
  end

  test "Form validation, groups, cycling, and Table sort markers use exact identities" do
    form =
      FormBuilder.init(
        fields: [%{id: 1, label: "integer"}, %{id: 1.0, label: "float", required: true}]
      )

    assert FormBuilder.validate(form).errors == %{1.0 => "is required"}

    assert {_, [{:invalid, %{1.0 => "is required"}}]} =
             FormBuilder.update(Event.key(:enter, modifiers: [:ctrl]), form)

    form =
      FormBuilder.init(
        fields: [%{id: :a, label: "A"}, %{id: :b, label: "B"}],
        groups: [
          %{id: 1, fields: [:a], validators: [fn _ -> {:error, :a, "first"} end]},
          %{id: 1.0, fields: [:b], validators: [fn _ -> {:error, :b, "second"} end]}
        ]
      )

    assert FormBuilder.validate_group(form, 1.0).errors == %{b: "second"}

    form =
      FormBuilder.init(
        fields: [%{id: :choice, label: "Choice", type: :select, options: [1, 1.0]}]
      )

    {form, _} = FormBuilder.update(Event.key(:right), form)
    {form, _} = FormBuilder.update(Event.key(:right), form)
    assert form.values.choice === 1

    table =
      Table.init(columns: [{1, "integer"}, {1.0, "float"}], rows: [%{1 => "i", 1.0 => "f"}])
      |> Table.sort_by(1.0, :asc)

    row = Frame.row_text(Table.view(table, {30, 2}), 1)
    assert String.graphemes(row) |> Enum.count(&(&1 == "↑")) == 1
    assert row =~ "float ↑"
  end

  test "nil items activate through keyboard and mouse while empty lists do nothing" do
    for module <- [Table, TermUI.Widget.List, PickList] do
      option = if module == Table, do: :rows, else: :items
      state = module.init([{option, [nil]}])
      tag = if module == PickList, do: :picked, else: :selected
      assert {_, [{^tag, nil}]} = module.update(Event.key(:enter), state)
      y = if module == TermUI.Widget.List, do: 0, else: 1
      {pressed, _} = module.mouse(Event.mouse(:press, :left, 0, y), state, {10, 3})

      assert {_, [{^tag, nil}]} =
               module.mouse(Event.mouse(:release, :left, 0, y), pressed, {10, 3})

      empty = module.init([{option, []}])
      assert {^empty, []} = module.update(Event.key(:enter), empty)
    end

    list = TermUI.Widget.List.init(items: [nil], mode: :multiple)
    assert {selected, [{:toggled, nil}]} = TermUI.Widget.List.update(Event.key(:space), list)
    assert selected.selected == MapSet.new([0])
  end

  test "select-all and ordinary deletions keep both editor selections at the cursor" do
    for module <- [TextInput, TextArea] do
      {state, _} = module.update(Event.key(:home), module.init(value: "abcd"))
      {state, _} = module.update(Event.key("a", modifiers: [:ctrl]), state)
      assert state.cursor == 4
      {state, _} = module.update(Event.key(:left, modifiers: [:shift]), state)
      assert Selection.extract(state.selection, state.value) == "abc"
      assert {_, [{:copy, "abc"}]} = module.update(Event.key("c", modifiers: [:ctrl]), state)

      for {key, modifiers, expected} <- [
            {:backspace, [], "b"},
            {:delete, [], "c"},
            {:backspace, [:alt], ""}
          ] do
        {state, _} =
          module.mouse(Event.mouse(:press, :left, 3, 0), module.init(value: "abcd"), {10, 2})

        {state, _} = module.update(Event.key(key, modifiers: modifiers), state)
        assert Selection.empty?(state.selection)
        {state, _} = module.update(Event.key(:left, modifiers: [:shift]), state)
        assert Selection.extract(state.selection, state.value) == expected
      end
    end
  end

  test "word deletion stops at every imported line ending" do
    for ending <- ["\r", "\n", "\r\n"] do
      for suffix <- ["", "   "] do
        state = TextArea.init(value: "first" <> ending <> suffix)
        {next, _} = TextArea.update(Event.key(:backspace, modifiers: [:alt]), state)
        assert next.value == "first" <> ending
      end

      state = TextArea.init(value: "first" <> ending <> "word   ")
      {next, _} = TextArea.update(Event.key(:backspace, modifiers: [:alt]), state)
      assert next.value == "first" <> ending
    end
  end

  test "word selection retains NFC and NFD Hangul and previous marked-letter controls" do
    for word <- ["한글", String.normalize("한글", :nfd), "e\u0301", "क\u093F"] do
      source = "!" <> word <> "! tail"

      for position <- 1..String.length(word) do
        selection = Selection.select_word(Selection.new(), source, position)
        assert Selection.extract(selection, source) == word
      end
    end
  end

  test "Canvas writes and erasures follow overlap order on either half" do
    style = Style.new(fg: :red)
    canvas = Canvas.init(width: 5, height: 1)

    for x <- [0, 1] do
      wide = Canvas.set_char(canvas, 0, 0, "界", style)
      erased = Canvas.set_char(wide, x, 0, " ")
      assert Frame.row_text(Canvas.view(erased, {5, 1}), 1) == "     "
      narrow = Canvas.set_char(wide, x, 0, "x")

      assert Frame.row_text(Canvas.view(narrow, {5, 1}), 1) ==
               String.duplicate(" ", x) <> "x" <> String.duplicate(" ", 4 - x)

      newer = Canvas.set_char(narrow, 0, 0, "界", style)
      assert Frame.row_text(Canvas.view(newer, {5, 1}), 1) == "界   "
      assert Frame.cell(Canvas.view(newer, {5, 1}), 1, 1).fg == :red
      assert Canvas.view(newer, {5, 1}) == Canvas.view(newer, {5, 1})
    end

    canvas = Canvas.set_char(canvas, 1, 0, "x") |> Canvas.draw_text(0, 0, "界b")
    assert Frame.row_text(Canvas.view(canvas, {5, 1}), 1) == "界b  "
  end

  test "Router schema rejects isolated empty paths and retains nested routes" do
    invalid = %Router{id: :child, module: Checkbox, path: [], map_message: fn _, msg -> msg end}
    assert {:error, _} = Zoi.parse(Router.schema(), invalid)
    router = Router.new(:child, Checkbox, [:nested, :child])
    parent = %{nested: %{child: Checkbox.init([])}}
    assert {:ok, _} = Zoi.parse(Router.schema(), router)
    {updated, [_]} = Router.update(router, Event.key(:space), parent)
    assert updated.nested.child.checked
  end
end
