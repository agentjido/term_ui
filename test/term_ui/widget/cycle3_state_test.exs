defmodule TermUI.Widget.Cycle3StateTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame, Layout}
  alias TermUI.Widget.{ContextMenu, MarkdownViewer, Menu, SplitPane}

  test "nested hide returns to the first enabled root and root hide preserves exact selection" do
    for orientation <- [:horizontal, :vertical], deep <- [false, true] do
      children = Enum.map(0..3, &Menu.action(&1, "child #{&1}"))
      children = if deep, do: [Menu.submenu(:deep, "Deep", children)], else: children

      menu =
        Menu.init(
          orientation: orientation,
          items: [
            Menu.action(:disabled, "Disabled", disabled: true),
            Menu.separator(),
            Menu.action(1, "One"),
            Menu.action(1.0, "Float"),
            Menu.submenu(:file, "File", children)
          ]
        )

      {menu, _} = Menu.update(Event.key(:end), menu)
      {menu, _} = Menu.update(Event.key(:enter), menu)
      menu = if deep, do: Menu.open_submenu(menu), else: menu
      {menu, _} = Menu.update(Event.key(:end), menu)
      menu = menu |> Menu.hide() |> Menu.show() |> Menu.hide() |> Menu.show()
      assert menu.open_path == []
      assert Menu.current(menu).id === 1
      assert {_, [{:selected, 1}]} = Menu.update(Event.key(:enter), menu)

      {menu, _} =
        Menu.update(Event.key(if(orientation == :horizontal, do: :right, else: :down)), menu)

      menu = menu |> Menu.hide() |> Menu.show()
      assert Menu.current(menu).id === 1.0
      assert {_, [{:selected, 1.0}]} = Menu.update(Event.key(:enter), menu)
      context = ContextMenu.init(items: menu.items)
      context = %{context | menu: menu}
      assert {_, [{:selected, 1.0}]} = ContextMenu.update(Event.key(:enter), context)
    end

    for items <- [[], [Menu.action(:off, "Off", disabled: true)], [Menu.separator()]] do
      menu = Menu.init(items: items) |> Menu.hide() |> Menu.show()
      assert {_, []} = Menu.update(Event.key(:enter), menu)
      assert %Frame{} = Menu.view(menu, {10, 3})
    end
  end

  test "bounded Markdown append keeps retained focus, copy, source order, and empty state" do
    first = "```text\none\n```\n\n"
    second = "```text\ntwo\n```"
    source = first <> second
    state = MarkdownViewer.init(content: source, content_limit: byte_size(source))
    {state, _} = MarkdownViewer.update(Event.key(:tab), state)
    assert state.focused == 1
    state = MarkdownViewer.append(state, String.duplicate(" ", byte_size(first)))
    assert state.focused == 0
    assert state.scroll == :end
    assert Enum.map(state.elements, &{&1.id, &1.content}) == [{"code-0", "two\n"}]
    assert byte_size(state.content) <= byte_size(source)

    for key <- [Event.key(:enter), Event.text("c")] do
      assert {_, [{:copy, "two\n"}]} = MarkdownViewer.update(key, state)
    end

    for key <- [Event.key(:tab), Event.key(:tab, [:shift])] do
      {next, _} = MarkdownViewer.update(key, state)
      assert next.focused == 0
    end

    assert %Frame{width: 8, height: 3} = MarkdownViewer.view(state, {8, 3})
    empty = MarkdownViewer.append(state, String.duplicate(" ", byte_size(source)))
    assert empty.elements == []
    assert empty.focused == 0
    assert {_, []} = MarkdownViewer.update(Event.key(:enter), empty)
    partial = MarkdownViewer.append(state, " xyz")
    assert partial.focused < max(length(partial.elements), 1)
  end

  test "ordinary and multiple-block retention append preserve focus and duplicate source IDs" do
    block = "```text\nsame\n```\n\n"
    source = String.duplicate(block, 3)
    state = MarkdownViewer.init(content: source, content_limit: byte_size(source) + 3)
    {state, _} = MarkdownViewer.update(Event.key(:tab), state)
    ordinary = MarkdownViewer.append(state, "  ")
    assert ordinary.focused == 1
    assert Enum.map(ordinary.elements, & &1.id) == ["code-0", "code-1", "code-2"]
    {last, _} = MarkdownViewer.update(Event.key(:tab), state)
    trimmed = MarkdownViewer.append(last, String.duplicate(" ", 2 * byte_size(block) + 3))
    assert trimmed.focused == 0
    assert [{"code-0", "same\n"}] == Enum.map(trimmed.elements, &{&1.id, &1.content})
    assert {_, [{:copy, "same\n"}]} = MarkdownViewer.update(Event.key(:enter), trimmed)
  end

  test "Layout weighted rows columns bounds and grids retain scale and huge integer allocation" do
    for weights <- [[1, 1], [1, 2], [1, 2, 1]], scale <- [1.0e-308, 1.0e-8, 1.0, 1.0e307] do
      scaled = Enum.map(weights, &(&1 * scale))

      for bounded <- [false, true] do
        tracks = tracks(scaled, bounded)
        expected = Layout.row({0, 0, 100, 4}, tracks(weights, bounded))
        assert Layout.row({0, 0, 100, 4}, tracks) == expected

        assert Enum.map(Layout.column({0, 0, 4, 100}, tracks), &elem(&1, 3)) ==
                 Enum.map(expected, &elem(&1, 2))

        assert Layout.grid({0, 0, 100, 4}, length(weights),
                 column_tracks: tracks,
                 row_tracks: [4]
               ) == expected
      end
    end

    for weights <- [
          [1.0e308, 1.0e308],
          [Integer.pow(10, 400), Integer.pow(10, 400)],
          [Integer.pow(10, 400), 1.0]
        ] do
      sizes = Layout.row({0, 0, 100, 4}, tracks(weights, false)) |> Enum.map(&elem(&1, 2))
      assert Enum.sum(sizes) == 100
      assert sizes == if(List.first(weights) == List.last(weights), do: [50, 50], else: [100, 0])
    end

    # Subnormal and full-range weights also have bounded exact shares.
    assert Layout.row({0, 0, 100, 1}, tracks([5.0e-324, 5.0e-324], false)) == [
             {0, 0, 50, 1},
             {50, 0, 50, 1}
           ]

    assert Layout.row({0, 0, 100, 1}, tracks([5.0e-324, 1.0e308], true)) == [
             {0, 0, 20, 1},
             {20, 0, 80, 1}
           ]
  end

  test "pane restore layout keys drag minima and collapse are stable across scale" do
    for direction <- [:horizontal, :vertical], scale <- [1.0e-308, 1.0e-8, 1.0, 1.0e307] do
      state =
        SplitPane.init(
          direction: direction,
          panes: [{1, "A"}, {1.0, "B"}, {:c, "C"}],
          ratios: [scale, 2 * scale, scale],
          min_size: 4
        )

      ordinary =
        SplitPane.init(
          direction: direction,
          panes: [{1, "A"}, {1.0, "B"}, {:c, "C"}],
          ratios: [1, 2, 1],
          min_size: 4
        )

      size = if direction == :horizontal, do: {102, 4}, else: {4, 102}
      assert SplitPane.layout(state, size) == SplitPane.layout(ordinary, size)
      saved = SplitPane.serialize(state)
      assert saved.version == 1
      assert saved.ratios == [scale, 2 * scale, scale]
      assert {:ok, restored} = SplitPane.restore(ordinary, saved)
      assert restored.panes == ordinary.panes
      assert SplitPane.layout(restored, size) == SplitPane.layout(ordinary, size)
      key = if direction == :horizontal, do: :right, else: :down
      {state, [_]} = SplitPane.update(Event.key(key), state)
      {ordinary, [_]} = SplitPane.update(Event.key(key), ordinary)
      assert SplitPane.layout(state, size) == SplitPane.layout(ordinary, size)
      assert Enum.at(state.ratios, 2) == scale
      state = drag(state, direction, size, 20)
      ordinary = drag(ordinary, direction, size, 20)
      assert SplitPane.layout(state, size) == SplitPane.layout(ordinary, size)

      assert SplitPane.layout(SplitPane.collapse(state, 1.0), size).panes |> Enum.map(& &1.id) ==
               [1, :c]

      assert SplitPane.restore(state, %{saved | pane_ids: [1.0, 1, :c]}) ==
               {:error, :pane_mismatch}
    end
  end

  test "overflow pair resize and legacy restore remain positive and safe" do
    state =
      SplitPane.init(
        panes: [a: "A", b: "B", c: "C"],
        ratios: [1.0e308, 1.0e308, 5.0e-324],
        min_size: 0
      )

    for _ <- 1..12, reduce: state do
      state ->
        {state, [_]} = SplitPane.update(Event.key(:right), state)
        assert Enum.all?(state.ratios, &(&1 > 0))
        assert Enum.sum(Enum.map(SplitPane.layout(state, {102, 3}).panes, & &1.size)) == 100
        assert {:ok, _} = SplitPane.restore(state, SplitPane.serialize(state))
        state
    end

    tiny = SplitPane.init(panes: [a: "A", b: "B"], ratios: [5.0e-324, 5.0e-324])

    for _ <- 1..12, reduce: tiny do
      state ->
        {state, [_]} = SplitPane.update(Event.key(:right), state)
        assert Enum.all?(state.ratios, &(&1 > 0))
        assert {:ok, _} = SplitPane.restore(state, SplitPane.serialize(state))
        state
    end

    legacy = SplitPane.init(first: "A", second: "B", keyboard_resize: true)
    saved = SplitPane.serialize(legacy)
    assert {:ok, restored} = SplitPane.restore(legacy, %{saved | ratios: [1.0e308, 1.0e308]})
    assert restored.ratio == 0.5
    assert SplitPane.layout(restored, {101, 3}) == SplitPane.layout(legacy, {101, 3})

    assert SplitPane.restore(legacy, %{saved | ratios: [Integer.pow(10, 400), 1]}) ==
             {:error, :invalid_state}

    for ratios <- [[0, 1], [-1, 1], [:bad, 1], [1]] do
      assert SplitPane.restore(legacy, %{saved | ratios: ratios}) == {:error, :invalid_state}
    end
  end

  defp tracks(weights, bounded),
    do:
      Enum.map(weights, fn w ->
        if bounded, do: Layout.bounded(Layout.ratio(w), min: 2, max: 80), else: Layout.ratio(w)
      end)

  defp drag(state, direction, dimensions, position) do
    sep = hd(SplitPane.layout(state, dimensions).separators).position
    {x, y} = if direction == :horizontal, do: {sep, 0}, else: {0, sep}
    {state, _} = SplitPane.mouse(Event.mouse(:press, :left, x, y), state, dimensions)
    {x, y} = if direction == :horizontal, do: {position, 0}, else: {0, position}
    {state, _} = SplitPane.mouse(Event.mouse(:drag, :left, x, y), state, dimensions)
    {state, _} = SplitPane.mouse(Event.mouse(:release, :left, x, y), state, dimensions)
    state
  end
end
