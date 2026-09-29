defmodule TermUI.Widget.DiffViewerTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame}
  alias TermUI.Widget.DiffViewer

  test "compares two texts with line numbers and changed-line pairing" do
    state = DiffViewer.init(before: "same\nold\nend", after: "same\nnew\nend", context: 3)

    assert Enum.any?(
             state.rows,
             &(&1.kind == :changed and &1.old_text == "old" and &1.new_text == "new")
           )

    frame = DiffViewer.view(state, {50, 10})
    text = Enum.map_join(1..frame.height, "\n", &Frame.row_text(frame, &1))
    assert text =~ "-old"
    assert text =~ "+new"
  end

  test "switches to a side-by-side frame" do
    state = DiffViewer.init(before: "old", after: "new")
    assert {state, [{:mode, :split}]} = DiffViewer.update(Event.text("s"), state)

    frame = DiffViewer.view(state, {60, 5})
    assert Frame.row_text(frame, 1) =~ "before"
    assert Frame.row_text(frame, 1) =~ "after"
    assert Frame.row_text(frame, 2) =~ "old"
    assert Frame.row_text(frame, 2) =~ "new"
  end

  test "comparison treats CRLF and LF as the same line ending" do
    rows = DiffViewer.compare("same\r\nold\r\nend", "same\nold\nend")

    assert Enum.map(rows, &{&1.kind, &1.old_text, &1.new_text}) == [
             {:context, "same", "same"},
             {:context, "old", "old"},
             {:context, "end", "end"}
           ]
  end

  test "unified parsing accepts CRLF and retains carriage returns within content" do
    diff =
      Enum.join(
        ["--- a/file", "+++ b/file", "@@ -1,2 +1,2 @@", "-old", "+new", " same\rmiddle"],
        "\r\n"
      )

    state = DiffViewer.init(unified_diff: diff, context: 3)

    assert Enum.map(state.rows, &{&1.kind, &1.text, &1.old_text, &1.new_text}) == [
             {:header, "--- a/file", nil, nil},
             {:header, "+++ b/file", nil, nil},
             {:hunk, "@@ -1,2 +1,2 @@", nil, nil},
             {:removed, nil, "old", nil},
             {:added, nil, nil, "new"},
             {:context, nil, "same\rmiddle", "same\rmiddle"}
           ]
  end

  test "renders an existing unified diff and collapses long context" do
    diff = """
    --- a/file
    +++ b/file
    @@ -1,8 +1,8 @@
     one
     two
     three
     four
    -old
    +new
     five
     six
    """

    state = DiffViewer.init(unified_diff: diff, context: 1)
    assert Enum.any?(state.rows, &(&1.kind == :fold))
    assert %Frame{} = DiffViewer.view(state, {50, 12})
  end

  test "unified parsing removes only one content marker" do
    diff = """
    --- a/file
    +++ b/file
    @@ -1,3 +1,3 @@
    +++literal
    ---literal
       indented
    """

    state = DiffViewer.init(unified_diff: diff, context: 3)

    assert Enum.any?(state.rows, &(&1.kind == :added and &1.new_text == "++literal"))
    assert Enum.any?(state.rows, &(&1.kind == :removed and &1.old_text == "--literal"))

    assert Enum.any?(
             state.rows,
             &(&1.kind == :context and &1.old_text == "  indented")
           )
  end

  test "file-header text inside a hunk remains added or removed content" do
    diff = """
    --- a/file
    +++ b/file
    @@ -1 +1 @@
    --- literal
    +++ literal
    """

    state = DiffViewer.init(unified_diff: diff, context: 3)

    assert Enum.any?(state.rows, &(&1.kind == :removed and &1.old_text == "-- literal"))
    assert Enum.any?(state.rows, &(&1.kind == :added and &1.new_text == "++ literal"))
  end

  test "navigation, wheel input, unified mode, and fallback input update scroll state" do
    state = DiffViewer.init(before: Enum.join(1..20, "\n"), after: "", page_size: 4)

    {state, [{:scrolled, 1}]} = DiffViewer.update(Event.key(:down), state)
    {state, [{:scrolled, 0}]} = DiffViewer.update(Event.key(:up), state)
    {state, [{:scrolled, 4}]} = DiffViewer.update(Event.key(:page_down), state)
    {state, [{:scrolled, 0}]} = DiffViewer.update(Event.key(:page_up), state)

    {state, [{:scrolled, 3}]} =
      DiffViewer.update(Event.mouse(:scroll_down, nil, 0, 0), state)

    {state, [{:scrolled, 0}]} = DiffViewer.update(Event.mouse(:scroll_up, nil, 0, 0), state)
    {state, []} = DiffViewer.update(Event.key(:end), state)
    assert state.scroll == :end
    assert %Frame{} = DiffViewer.view(state, {20, 3})
    {state, [{:scrolled, scroll}]} = DiffViewer.update(Event.key(:up), state)
    assert scroll >= 0
    {state, []} = DiffViewer.update(Event.key(:home), state)
    assert state.scroll == 0
    {state, [{:mode, :unified}]} = DiffViewer.update(Event.text("u"), state)
    assert state.mode == :unified
    assert {^state, []} = DiffViewer.update(Event.focus(:gained), state)
  end

  test "comparison represents unpaired additions and removals and resets replaced text" do
    removed = DiffViewer.compare("one\ntwo", "one")
    assert Enum.any?(removed, &(&1.kind == :removed and &1.old_text == "two"))

    added = DiffViewer.compare("one", "one\ntwo\nthree")
    assert Enum.any?(added, &(&1.kind == :added and &1.new_text == "three"))

    state = DiffViewer.init(before: "old", after: "new")
    state = DiffViewer.set_texts(%{state | scroll: 5}, "", "added", 1)
    assert state.scroll == 0
    assert length(state.rows) == 1
  end

  test "unified parsing handles missing hunk counts, marker headers, and malformed hunks" do
    diff = """
    metadata
    @@ -2 +4 @@
    -old
    +new
    \\ No newline at end of file
    @@ malformed @@
     context
    """

    state = DiffViewer.init(unified_diff: diff, context: 0)
    assert Enum.any?(state.rows, &(&1.kind == :removed and &1.old_number == 2))
    assert Enum.any?(state.rows, &(&1.kind == :added and &1.new_number == 4))
    assert Enum.any?(state.rows, &(&1.kind == :header and &1.text =~ "No newline"))
    assert Enum.any?(state.rows, &(&1.kind == :hunk and &1.text == "@@ malformed @@"))
    assert %Frame{} = DiffViewer.view(%{state | mode: :split}, {7, 8})
  end
end
