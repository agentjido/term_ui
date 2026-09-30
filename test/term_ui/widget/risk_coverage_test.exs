defmodule TermUI.Widget.RiskCoverageTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame}

  alias TermUI.Widget.{
    Canvas,
    CommandPalette,
    Dialog,
    FormBuilder,
    LineInput,
    SplitPane,
    Stream,
    StreamWidget,
    TreeView
  }

  test "canvas clear, erasure, braille clipping, resize, and fallback update are pure" do
    canvas = Canvas.init(width: 4, height: 2)
    assert {^canvas, []} = Canvas.update(Event.focus(:gained), canvas)
    canvas = Canvas.set_char(canvas, 0, 0, "x")
    canvas = Canvas.set_char(canvas, 0, 0, " ")
    assert canvas.cells == %{}

    canvas =
      canvas
      |> Canvas.draw_braille_line(-2, -2, 3, 3)
      |> Canvas.clear_dot(0, 0)
      |> Canvas.set_char(3, 1, "z")
      |> Canvas.set_dot(7, 7)
      |> Canvas.set_dot(20, 20)

    assert Canvas.braille_resolution(canvas) == {8, 8}
    resized = Canvas.resize(canvas, 2, 1)
    assert resized.width == 2
    assert resized.height == 1
    assert resized.cells == %{}
    refute MapSet.member?(resized.dots, {20, 20})
    assert %Frame{} = Canvas.view(resized, {2, 1})
    assert Canvas.clear(resized).dots == MapSet.new()
  end

  test "tree navigation and mouse actions cover empty, branch, leaf, and outside paths" do
    branch = TreeView.branch(:root, "Root", [TreeView.leaf(:child, "Child")])
    state = TreeView.init(nodes: [branch, TreeView.leaf(:last, "Last")], page_size: 1)
    {state, []} = TreeView.update(Event.key(:up), state)
    {state, []} = TreeView.update(Event.key(:page_down), state)
    assert state.cursor == 1
    assert {^state, []} = TreeView.update(Event.focus(:gained), state)

    {pressed, []} = TreeView.mouse(Event.mouse(:press, :left, 0, 0), state, {20, 1})
    assert pressed.cursor >= 0

    {selected, [{:selected, _id}]} =
      TreeView.mouse(Event.mouse(:release, :left, 10, 0), state, {20, 1})

    assert MapSet.size(selected.selected) == 1
    assert {^state, []} = TreeView.mouse(Event.focus(:lost), state, {20, 1})
    assert {^state, []} = TreeView.mouse(Event.mouse(:release, :left, 0, 0), state, {20, 0})

    empty = TreeView.init(nodes: [])
    assert {^empty, []} = TreeView.update(Event.key(:right), empty)
    assert {^empty, []} = TreeView.update(Event.key(:left), empty)
  end

  test "form field types, validation rows, mouse bounds, and fallback input are observable" do
    state =
      FormBuilder.init(
        fields: [
          {:name, "Name"},
          %{id: :enabled, label: "Enabled", type: :checkbox, required: true},
          %{id: :color, label: "Color", type: :select, options: []}
        ]
      )

    assert {^state, []} = FormBuilder.update(Event.focus(:gained), state)
    assert {^state, []} = FormBuilder.mouse(Event.focus(:lost), state, {20, 4})
    assert {^state, []} = FormBuilder.mouse(Event.mouse(:release, :left, 0, 9), state, {20, 4})

    {state, []} = FormBuilder.update(Event.key(:down), state)
    {state, [{:changed, :enabled, true}]} = FormBuilder.update(Event.key(:space), state)
    assert Frame.row_text(FormBuilder.view(state, {20, 4}), 2) =~ "[x]"
    {state, []} = FormBuilder.update(Event.key(:down), state)
    assert {^state, []} = FormBuilder.update(Event.key(:space), state)
    assert {^state, []} = FormBuilder.update(Event.text("x"), state)

    invalid = FormBuilder.init(fields: [%{id: :required, label: "Required", required: true}])

    {invalid, [{:invalid, %{required: "is required"}}]} =
      FormBuilder.update(Event.key(:enter), invalid)

    assert Frame.row_text(FormBuilder.view(invalid, {20, 3}), 2) =~ "is required"

    assert {^invalid, []} =
             FormBuilder.mouse(Event.mouse(:release, :left, 0, 1), invalid, {20, 3})
  end

  test "dialog movement, empty activation, mouse press, bounds, and list content are safe" do
    empty = Dialog.init(content: ["one", "two"], buttons: [])
    assert {^empty, []} = Dialog.update(Event.key(:left), empty)
    assert {^empty, []} = Dialog.update(Event.key(:enter), empty)
    assert {^empty, []} = Dialog.update(Event.focus(:gained), empty)

    dialog = Dialog.init(content: 123, buttons: [{:one, "One"}, {:two, "Two"}])
    {dialog, []} = Dialog.update(Event.key(:right), dialog)
    {dialog, []} = Dialog.update(Event.key(:up), dialog)
    assert dialog.focused == 0

    assert {pressed, []} =
             Dialog.mouse(Event.mouse(:press, :left, 2, 4), dialog, {20, 6})

    assert pressed.focused == 0
    assert {^dialog, []} = Dialog.mouse(Event.mouse(:release, :left, 19, 4), dialog, {20, 6})
    assert {^dialog, []} = Dialog.mouse(Event.mouse(:release, :left, 2, 0), dialog, {20, 6})
    assert {^dialog, []} = Dialog.mouse(Event.focus(:lost), dialog, {20, 6})
  end

  test "visible command palette renders and maps mouse picks while hidden mouse is inert" do
    hidden = CommandPalette.init(commands: ["Open", "Close"], title: "Actions")

    assert {^hidden, []} =
             CommandPalette.mouse(Event.mouse(:release, :left, 1, 1), hidden, {20, 6})

    visible = CommandPalette.show(hidden)
    assert %Frame{} = CommandPalette.view(visible, {20, 6})

    {picked, messages} =
      CommandPalette.mouse(Event.mouse(:release, :left, 2, 2), visible, {20, 6})

    assert picked.visible
    assert is_list(messages)

    assert {^visible, []} =
             CommandPalette.mouse(Event.mouse(:release, :left, 0, 0), visible, {20, 6})
  end

  test "line input validates submit results and routes non-input-row mouse events" do
    plain = LineInput.init(value: "ok")
    assert {^plain, [{:submit, "ok"}]} = LineInput.validate(plain)

    valid = LineInput.init(value: "ok", validator: fn _value -> :ok end)
    assert {valid, [{:submit, "ok"}]} = LineInput.update(Event.key(:enter), valid)
    assert valid.error == nil

    invalid = LineInput.init(value: "bad", validator: fn _value -> {:error, "invalid"} end)
    assert {invalid, [{:invalid, "invalid"}]} = LineInput.update(Event.key(:enter), invalid)
    assert Frame.row_text(LineInput.view(invalid, {20, 2}), 2) =~ "invalid"

    labelled = LineInput.init(label: "Name", value: "x")

    assert {^labelled, []} =
             LineInput.mouse(Event.mouse(:release, :right, 0, 0), labelled, {20, 2})
  end

  test "split panes support content forms, compact layouts, focus, and invalid ratios" do
    state =
      SplitPane.init(
        panes: ["plain", {:named, "named"}, %{id: :map, content: "map"}],
        collapsed: [:missing]
      )

    assert Enum.map(state.panes, & &1.id) == [0, :named, :map]
    assert state.ratios == [1.0, 1.0, 1.0]
    assert state.collapsed == []
    assert %Frame{} = SplitPane.view(state, {1, 2})

    state = SplitPane.focus_separator(state, 99)
    assert state.focused_separator == 1
    assert {state, [{:resized, %{separator: 1}}]} = SplitPane.update(Event.key(:right), state)
    assert {^state, []} = SplitPane.mouse(Event.focus(:gained), state, {12, 2})

    invalid_drag = %{state | dragging: true, drag_separator: 99}

    assert {^invalid_drag, []} =
             SplitPane.mouse(Event.mouse(:drag, :left, 5, 0), invalid_drag, {12, 2})

    all_collapsed =
      state |> SplitPane.collapse(0) |> SplitPane.collapse(:named) |> SplitPane.collapse(:map)

    assert SplitPane.layout(all_collapsed, {4, 2}).panes == []
    assert %Frame{} = SplitPane.view(all_collapsed, {4, 2})
    assert {^all_collapsed, []} = SplitPane.update(Event.key(:right), all_collapsed)

    legacy = SplitPane.init(first: "left", second: "right")
    legacy = SplitPane.put_pane(legacy, :second, "changed")
    assert legacy.second == "changed"
    generic = SplitPane.put_pane(state, :map, "changed")
    assert Enum.find(generic.panes, &(&1.id == :map)).content == "changed"

    assert_raise ArgumentError, ~r/positive numbers/, fn ->
      SplitPane.init(panes: [a: "a", b: "b"], ratios: [1, 0])
    end

    assert_raise ArgumentError, ~r/one value for each/, fn ->
      SplitPane.init(panes: [a: "a", b: "b"], ratios: [1])
    end
  end

  test "stream widget compatibility delegates all public state operations" do
    state = StreamWidget.init(limit: 2)
    state = StreamWidget.push_many(state, [1, 2, 3])
    assert StreamWidget.stats(state).buffered == 2
    {state, %{accepted: 2}} = StreamWidget.offer_many(state, [4, 5])
    state = StreamWidget.set_overflow(state, :drop_newest)
    assert state.overflow == :drop_newest
    assert StreamWidget.reset_stats(state).dropped_count == 0
    assert StreamWidget.clear(state).items == Stream.init(limit: 2).items
  end
end
