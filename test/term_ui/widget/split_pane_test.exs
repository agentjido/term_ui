defmodule TermUI.Widget.SplitPaneTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame}
  alias TermUI.Widget.SplitPane

  defmodule OversizedWidget do
    @behaviour TermUI.Widget

    def init(_opts), do: nil
    def update(_event, state), do: {state, []}
    def view(_state, _dimensions), do: Frame.from_rows(["ABCDEFGHIJ"], 10, 2)
  end

  test "named multi-pane layout allocates exact space and preserves collapse state" do
    state =
      SplitPane.init(
        panes: [
          %{id: :nav, content: "nav"},
          %{id: :main, content: "main"},
          %{id: :inspector, content: "inspect", collapsed: true}
        ],
        ratios: [1, 2, 1]
      )

    assert SplitPane.collapsed?(state, :inspector)
    assert %{panes: panes, separators: [_separator]} = SplitPane.layout(state, {12, 4})
    assert Enum.map(panes, & &1.id) == [:nav, :main]
    assert Enum.sum(Enum.map(panes, & &1.size)) + 1 == 12

    state = SplitPane.expand(state, :inspector)
    refute SplitPane.collapsed?(state, :inspector)

    assert %{panes: panes, separators: separators} = SplitPane.layout(state, {14, 4})
    assert Enum.map(panes, &{&1.id, &1.size}) == [nav: 3, main: 6, inspector: 3]
    assert Enum.map(separators, & &1.position) == [3, 10]
    assert %Frame{width: 14, height: 4} = SplitPane.view(state, {14, 4})

    state = SplitPane.toggle(state, :main)
    assert SplitPane.collapsed?(state, :main)
    state = SplitPane.toggle(state, :main)
    refute SplitPane.collapsed?(state, :main)
  end

  test "multi-pane separators support focus, keyboard resize, and mouse drag" do
    state =
      SplitPane.init(
        panes: [left: "left", center: "center", right: "right"],
        ratios: [1, 2, 1]
      )

    assert {state, [{:separator_focused, 1}]} = SplitPane.update(Event.key(:tab), state)
    assert state.focused_separator == 1

    assert {state, [{:resized, %{separator: 1, ratios: ratios}}]} =
             SplitPane.update(Event.key(:left), state)

    assert length(ratios) == 3

    second_separator = state |> SplitPane.layout({14, 4}) |> Map.fetch!(:separators) |> Enum.at(1)

    assert {state, []} =
             SplitPane.mouse(
               Event.mouse(:press, :left, second_separator.position, 0),
               state,
               {14, 4}
             )

    assert state.dragging
    assert state.drag_separator == 1

    assert {state, [{:resized, %{separator: 1}}]} =
             SplitPane.mouse(Event.mouse(:drag, :left, 8, 0), state, {14, 4})

    assert {state, []} =
             SplitPane.mouse(Event.mouse(:release, :left, 8, 0), state, {14, 4})

    refute state.dragging
    assert state.drag_separator == nil
  end

  test "legacy fields and pane replacement remain compatible" do
    state = SplitPane.init(first: "left", second: "right", ratio: 0.5)
    assert %{panes: [%{id: :first}, %{id: :second}]} = SplitPane.layout(state, {10, 3})
    assert {^state, []} = SplitPane.update(Event.key(:right), state)

    state = SplitPane.put_pane(state, :first, "changed")
    assert state.first == "changed"
    assert Frame.row_text(SplitPane.view(state, {10, 3}), 1) =~ "chang"

    assert SplitPane.collapse(state, :missing) == state

    assert_raise ArgumentError, fn ->
      SplitPane.init(panes: [same: "one", same: "two"])
    end
  end

  test "pane content is clipped before it is composed" do
    oversized = Frame.from_rows(["ABCDEFGHIJ"], 10, 2)

    for content <- [oversized, fn _dimensions -> oversized end, {OversizedWidget, nil}] do
      state = SplitPane.init(first: content, second: "R", ratio: 0.5)
      separator = state |> SplitPane.layout({10, 2}) |> Map.fetch!(:separators) |> hd()
      frame = SplitPane.view(state, {10, 2})

      assert Frame.cell(frame, 1, separator.position + 1).char == "│"
      assert Frame.cell(frame, 1, separator.position + 2).char == "R"
    end

    oversized_cursor = Frame.from_rows(["ABCDEFGHIJ", "cursor"], 10, 2, cursor: {10, 2})
    state = SplitPane.init(first: oversized_cursor, second: "R", ratio: 0.5)
    assert SplitPane.view(state, {10, 2}).cursor == nil
  end

  test "versioned multi-pane state round trips without content or drag state" do
    source =
      SplitPane.init(
        panes: [nav: "source nav", main: "source main", inspector: "source inspector"],
        ratios: [1, 3, 2],
        direction: :vertical,
        min_size: 2,
        keyboard_resize: true
      )
      |> SplitPane.focus_separator(1)
      |> SplitPane.collapse(:inspector)

    serialized = SplitPane.serialize(source)

    assert serialized == %{
             version: 1,
             mode: :multi,
             pane_ids: [:nav, :main, :inspector],
             direction: :vertical,
             ratios: [1.0, 3.0, 2.0],
             collapsed: [:inspector],
             focused_separator: 1,
             min_size: 2,
             keyboard_resize: true
           }

    target =
      SplitPane.init(
        panes: [nav: "target nav", main: "target main", inspector: "target inspector"],
        ratios: [2, 1, 1]
      )
      |> Map.merge(%{dragging: true, drag_separator: 0})

    assert {:ok, restored} = SplitPane.restore(target, serialized)
    assert SplitPane.serialize(restored) == serialized

    assert Enum.map(restored.panes, & &1.content) == [
             "target nav",
             "target main",
             "target inspector"
           ]

    refute restored.dragging
    assert restored.drag_separator == nil
  end

  test "legacy state round trips into the current content" do
    serialized =
      SplitPane.init(
        first: "old left",
        second: "old right",
        ratio: 0.7,
        direction: :vertical
      )
      |> SplitPane.serialize()

    target = SplitPane.init(first: "new left", second: "new right", ratio: 0.2)

    assert {:ok, restored} = SplitPane.restore(target, serialized)
    assert restored.ratio == 0.7
    assert restored.ratios == serialized.ratios
    assert_in_delta Enum.at(restored.ratios, 1), 0.3, 1.0e-12
    assert restored.first == "new left"
    assert restored.second == "new right"
    assert SplitPane.serialize(restored) == serialized
  end

  test "invalid, old, and mismatched stored values return safe errors" do
    state = SplitPane.init(panes: [nav: "nav", main: "main"], ratios: [1, 2])
    serialized = SplitPane.serialize(state)

    assert SplitPane.restore(state, %{serialized | version: 0}) ==
             {:error, {:unsupported_version, 0}}

    assert SplitPane.restore(state, Map.delete(serialized, :ratios)) ==
             {:error, :invalid_state}

    assert SplitPane.restore(state, %{serialized | pane_ids: [:main, :nav]}) ==
             {:error, :pane_mismatch}

    assert SplitPane.restore(state, %{serialized | mode: :legacy}) ==
             {:error, :pane_mismatch}

    for invalid <- [
          %{serialized | direction: :diagonal},
          %{serialized | ratios: [1.0, 0.0]},
          %{serialized | collapsed: [:missing]},
          %{serialized | focused_separator: 2},
          %{serialized | min_size: 0},
          %{serialized | keyboard_resize: :yes}
        ] do
      assert SplitPane.restore(state, invalid) == {:error, :invalid_state}
    end

    assert state == SplitPane.init(panes: [nav: "nav", main: "main"], ratios: [1, 2])
  end
end
