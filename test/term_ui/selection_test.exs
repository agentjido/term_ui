defmodule TermUI.SelectionTest do
  use ExUnit.Case, async: true

  alias TermUI.Selection

  test "tracks a directional grapheme selection" do
    selection = Selection.new() |> Selection.start(3) |> Selection.extend(1)

    assert Selection.active?(selection)
    assert Selection.range(selection) == {1, 3}
    assert Selection.anchor(selection) == 3
    assert Selection.head(selection) == 1
    assert Selection.length(selection) == 2
  end

  test "extract and replace preserve Unicode graphemes" do
    selection = Selection.new() |> Selection.start(1) |> Selection.extend(3)

    assert Selection.extract(selection, "a界🙂z") == "界🙂"
    assert {"aXz", 2, cleared} = Selection.replace(selection, "a界🙂z", "X")
    refute Selection.active?(cleared)
  end

  test "select all, word, and line use grapheme positions" do
    assert Selection.new() |> Selection.select_all("a界🙂") |> Selection.range() == {0, 3}

    assert Selection.new() |> Selection.select_word("one two", 5) |> Selection.extract("one two") ==
             "two"

    assert Selection.new()
           |> Selection.select_line("one\ntwo\nthree", 6)
           |> Selection.extract("one\ntwo\nthree") == "two"
  end

  test "contains uses a half-open range and clear removes the selection" do
    selection = Selection.new() |> Selection.start(2) |> Selection.extend(5)

    assert Selection.contains?(selection, 2)
    refute Selection.contains?(selection, 5)
    refute selection |> Selection.clear() |> Selection.active?()
  end

  test "inactive, empty, and punctuation selections use bounded defaults" do
    assert Zoi.parse(Selection.schema(), Selection.new()) == {:ok, Selection.new()}

    selection = Selection.extend(Selection.new(), 2)
    assert Selection.range(selection) == {2, 2}

    empty = Selection.new()
    assert Selection.length(empty) == 0
    assert Selection.extract(empty, "text") == ""
    assert Selection.select_word(empty, "", 3) == Selection.start(empty, 0)

    punctuation = Selection.select_word(empty, "word... next", 5)
    assert Selection.extract(punctuation, "word... next") == "..."

    line = Selection.select_line(empty, "one line", 4)
    assert Selection.range(line) == {0, 8}
  end
end
