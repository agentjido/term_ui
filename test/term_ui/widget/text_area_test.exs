defmodule TermUI.Widget.TextAreaTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame, Selection}
  alias TermUI.Widget
  alias TermUI.Widget.TextArea

  test "multiline shift navigation, copy, and replacement use grapheme selection" do
    state = TextArea.init(value: "one\ntwo")
    {state, []} = TextArea.update(Event.key(:left, modifiers: [:shift]), state)
    {state, []} = TextArea.update(Event.key(:left, modifiers: [:shift]), state)

    assert Selection.extract(state.selection, state.value) == "wo"
    assert {state, [{:copy, "wo"}]} = TextArea.update(Event.key("c", modifiers: [:ctrl]), state)

    frame = TextArea.view(state, {8, 2})
    assert :reverse in Frame.cell(frame, 2, 2).attrs
    assert :reverse in Frame.cell(frame, 2, 3).attrs

    assert {state, [{:changed, "one\ntX"}]} = TextArea.update(Event.text("X"), state)
    refute Selection.active?(state.selection)
  end

  test "routed mouse press and drag select a visual line" do
    state = TextArea.init(value: "one\ntwo")

    {state, []} =
      Widget.mouse(TextArea, Event.mouse(:press, :left, 0, 1), state, {8, 2})

    {state, []} =
      Widget.mouse(TextArea, Event.mouse(:drag, :left, 3, 1), state, {8, 2})

    assert Selection.extract(state.selection, state.value) == "two"
    assert state.cursor == 7
  end

  test "select all and cut work across newlines" do
    state = TextArea.init(value: "one\ntwo")
    {state, []} = TextArea.update(Event.key("a", modifiers: [:ctrl]), state)

    assert {state, [{:copy, "one\ntwo"}, {:changed, ""}]} =
             TextArea.update(Event.key("x", modifiers: [:ctrl]), state)

    assert state.cursor == 0
  end

  test "paste normalization, length limits, accessors, and submit are public behavior" do
    state = TextArea.init(value: "a", max_length: 5)

    assert {state, [{:changed, "a\nb  "}]} =
             TextArea.update(Event.paste("\r\nb\t\0"), state)

    assert TextArea.value(state) == "a\nb  "

    assert {^state, [{:submit, "a\nb  "}]} =
             TextArea.update(Event.key(:enter, modifiers: [:ctrl]), state)

    reset = TextArea.set_value(state, "界🙂")
    assert reset.cursor == 2
    refute Selection.active?(reset.selection)
  end

  test "navigation follows line boundaries and supports selection collapse" do
    state = TextArea.init(value: "ab\ncdef\ng")
    {state, []} = TextArea.update(Event.key(:home), state)
    assert state.cursor == 8
    {state, []} = TextArea.update(Event.key(:up), state)
    assert state.cursor == 3
    {state, []} = TextArea.update(Event.key(:home), state)
    assert state.cursor == 3
    {state, []} = TextArea.update(Event.key(:end), state)
    assert state.cursor == 7
    {state, []} = TextArea.update(Event.key(:down), state)
    assert state.cursor == 9

    {selected, []} = TextArea.update(Event.key(:left, modifiers: [:shift]), state)
    {collapsed_left, []} = TextArea.update(Event.key(:left), selected)
    assert collapsed_left.cursor == 8
    {selected, []} = TextArea.update(Event.key(:right, modifiers: [:shift]), collapsed_left)
    {collapsed_right, []} = TextArea.update(Event.key(:right), selected)
    assert collapsed_right.cursor == 9
  end

  test "backspace and delete handle start, end, ordinary text, and selections" do
    start = %{TextArea.init(value: "abc") | cursor: 0}
    assert {^start, []} = TextArea.update(Event.key(:backspace), start)

    assert {deleted, [{:changed, "bc"}]} = TextArea.update(Event.key(:delete), start)
    assert deleted.cursor == 0

    finish = TextArea.init(value: "abc")
    assert {^finish, []} = TextArea.update(Event.key(:delete), finish)
    assert {backspaced, [{:changed, "ab"}]} = TextArea.update(Event.key(:backspace), finish)
    assert backspaced.cursor == 2

    {selected, []} = TextArea.update(Event.key(:left, modifiers: [:shift]), finish)

    assert {selected_deleted, [{:changed, "ab"}]} =
             TextArea.update(Event.key(:delete), selected)

    assert selected_deleted.cursor == 2
    refute Selection.active?(selected_deleted.selection)
  end

  test "non-control keys and fallback mouse events leave state unchanged" do
    state = TextArea.init(value: "abc")

    assert {^state, []} = TextArea.update(Event.key("a"), state)
    assert {^state, []} = TextArea.update(Event.key("c"), state)
    assert {^state, []} = TextArea.update(Event.key("x"), state)
    assert {^state, []} = TextArea.update(Event.focus(:gained), state)
    assert {^state, []} = TextArea.mouse(Event.focus(:lost), state, {5, 2})
  end

  test "mouse shift and drag selection honor wrapped visual rows" do
    state = TextArea.init(value: "abcd")
    {state, []} = TextArea.mouse(Event.mouse(:press, :left, 0, 0), state, {4, 2})

    {state, []} =
      TextArea.mouse(
        Event.mouse(:press, :left, 2, 0, modifiers: [:shift]),
        state,
        {4, 2}
      )

    assert Selection.extract(state.selection, state.value) == "ab"

    fresh = TextArea.init(value: "abcd")
    {dragged, []} = TextArea.mouse(Event.mouse(:drag, :left, 0, 0), fresh, {2, 2})
    assert Selection.active?(dragged.selection)

    {past_end, []} = TextArea.mouse(Event.mouse(:press, :left, 0, 9), fresh, {2, 2})
    assert past_end.cursor == 4
  end

  test "view keeps wide graphemes and a cursor visible after soft wrapping" do
    state = TextArea.init(value: "a界b\ncd")
    frame = TextArea.view(state, {2, 2})

    assert frame.cursor
    assert frame.width == 2
    assert frame.height == 2
  end

  test "text and paste insertion measure joined Unicode before cursor and length limits" do
    alias TermUI.{Event, Frame, Selection}
    alias TermUI.Widget.TextArea

    for event <- [Event.text("\u0301"), Event.paste("\u0301")] do
      {state, [{:changed, "e\u0301"}]} =
        TextArea.update(event, TextArea.init(value: "e", max_length: 1))

      assert state.cursor == 1
      assert %Frame{} = TextArea.view(state, {10, 2})
      {state, _} = TextArea.update(Event.key(:backspace), state)
      assert state.value == "" and state.cursor == 0
    end

    for {initial, cursor, inserted, expected, expected_cursor} <- [
          {"ex", 1, "\u0301", "e\u0301x", 1},
          {"👩x", 1, "\u200D💻", "👩‍💻x", 1},
          {"👩💻x", 1, "\u200D", "👩‍💻x", 1},
          {"🇺x", 1, "🇸", "🇺🇸x", 1}
        ] do
      initial = %{TextArea.init(value: initial) | cursor: cursor}
      {state, _} = TextArea.update(Event.paste(inserted), initial)
      assert state.value == expected
      assert state.cursor == expected_cursor
      assert %Frame{} = TextArea.view(state, {10, 2})
    end

    selection = Selection.new() |> Selection.start(1) |> Selection.extend(2)
    state = %{TextArea.init(value: "eXx") | selection: selection}
    {state, _} = TextArea.update(Event.text("\u0301"), state)
    assert state.value == "e\u0301x" and state.cursor == 1
    assert Selection.empty?(state.selection)
  end
end
