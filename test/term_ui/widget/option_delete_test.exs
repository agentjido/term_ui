defmodule TermUI.Widget.OptionDeleteTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Selection}
  alias TermUI.Widget.{LineInput, TextArea, TextInput}

  @delete Event.key(:backspace, modifiers: [:alt])

  test "text widgets remove a Unicode word and retain following text" do
    for widget <- [TextInput, TextArea] do
      prefix = "one e\u0301 👩‍💻"
      state = %{widget.init(value: prefix <> " tail") | cursor: String.length(prefix)}

      assert {edited, [{:changed, "one e\u0301  tail"}]} = widget.update(@delete, state)
      assert edited.cursor == String.length("one e\u0301 ")

      assert {continued, [{:changed, "one e\u0301 X tail"}]} =
               widget.update(Event.text("X"), edited)

      assert continued.cursor == String.length("one e\u0301 X")
    end
  end

  test "text widgets remove trailing whitespace and the preceding word" do
    for widget <- [TextInput, TextArea], whitespace <- ["   ", "\t", "\u00a0"] do
      state = widget.init(value: "one 界🙂" <> whitespace)
      assert {edited, [{:changed, "one "}]} = widget.update(@delete, state)
      assert edited.cursor == 4
    end
  end

  test "text widgets remove an active selection before a word" do
    for widget <- [TextInput, TextArea] do
      state = widget.init(value: "one two")
      {selected, []} = widget.update(Event.key(:left, modifiers: [:shift]), state)

      assert {edited, [{:changed, "one tw"}]} = widget.update(@delete, selected)
      assert edited.cursor == 6
      refute Selection.active?(edited.selection)
    end
  end

  test "text widgets leave the start unchanged and can delete the first word" do
    for widget <- [TextInput, TextArea] do
      state = widget.init(value: "界🙂")
      start = %{state | cursor: 0}
      assert {^start, []} = widget.update(@delete, start)
      assert {edited, [{:changed, ""}]} = widget.update(@delete, state)
      assert edited.cursor == 0
    end
  end

  test "multiline word deletion preserves the preceding line break" do
    state = TextArea.init(value: "first\nsecond word  ")
    assert {edited, [{:changed, "first\nsecond "}]} = TextArea.update(@delete, state)
    assert {edited, [{:changed, "first\n"}]} = TextArea.update(@delete, edited)
    assert {^edited, []} = TextArea.update(@delete, edited)
    assert edited.cursor == String.length("first\n")
  end

  test "LineInput delegates word deletion and clears an old validation error" do
    state = %{LineInput.init(value: "one two") | error: "old error"}
    assert {edited, [{:changed, "one "}]} = LineInput.update(@delete, state)
    assert edited.input.cursor == 4
    assert edited.error == nil
  end
end
