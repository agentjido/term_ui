defmodule TermUI.Widget.BlockTest do
  use ExUnit.Case, async: true

  alias TermUI.Component.RenderNode
  alias TermUI.Widget.Block

  @area %{x: 0, y: 0, width: 20, height: 10}

  describe "init/1" do
    test "initializes with props in state" do
      props = %{border: :double, title: "Test"}
      {:ok, state} = Block.init(props)
      assert state.props == props
    end
  end

  describe "children/1" do
    test "returns empty list" do
      {:ok, state} = Block.init(%{})
      assert Block.children(state) == []
    end
  end

  describe "layout/3" do
    test "assigns each child the given area" do
      {:ok, state} = Block.init(%{})
      children = [{:child1, %{}}, {:child2, %{}}]
      result = Block.layout(children, @area, state)

      assert length(result) == 2
      assert Enum.all?(result, fn {_child, area} -> area == @area end)
    end
  end

  describe "handle_event/2" do
    test "returns state unchanged for any event" do
      {:ok, state} = Block.init(%{})
      {:ok, new_state} = Block.handle_event(:any_event, state)
      assert new_state == state
    end
  end

  describe "render/2" do
    test "renders single border" do
      props = %{border: :single}
      {:ok, state} = Block.init(props)
      result = Block.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result

      # Find corner characters
      chars = for c <- cells, do: {c.x, c.y, c.cell.char}

      assert {0, 0, "┌"} in chars
      assert {19, 0, "┐"} in chars
      assert {0, 9, "└"} in chars
      assert {19, 9, "┘"} in chars
    end

    test "renders double border" do
      props = %{border: :double}
      {:ok, state} = Block.init(props)
      result = Block.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result
      chars = for c <- cells, do: {c.x, c.y, c.cell.char}

      assert {0, 0, "╔"} in chars
      assert {19, 0, "╗"} in chars
    end

    test "renders rounded border" do
      props = %{border: :rounded}
      {:ok, state} = Block.init(props)
      result = Block.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result
      chars = for c <- cells, do: {c.x, c.y, c.cell.char}

      assert {0, 0, "╭"} in chars
      assert {19, 0, "╮"} in chars
    end

    test "renders thick border" do
      props = %{border: :thick}
      {:ok, state} = Block.init(props)
      result = Block.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result
      chars = for c <- cells, do: {c.x, c.y, c.cell.char}

      assert {0, 0, "┏"} in chars
      assert {19, 0, "┓"} in chars
    end

    test "renders horizontal border lines" do
      props = %{border: :single}
      {:ok, state} = Block.init(props)
      result = Block.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result

      # Top horizontal line (excluding corners)
      top_line = Enum.filter(cells, fn c -> c.y == 0 && c.x > 0 && c.x < 19 end)
      assert Enum.all?(top_line, fn c -> c.cell.char == "─" end)

      # Bottom horizontal line
      bottom_line = Enum.filter(cells, fn c -> c.y == 9 && c.x > 0 && c.x < 19 end)
      assert Enum.all?(bottom_line, fn c -> c.cell.char == "─" end)
    end

    test "renders vertical border lines" do
      props = %{border: :single}
      {:ok, state} = Block.init(props)
      result = Block.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result

      # Left vertical line
      left_line = Enum.filter(cells, fn c -> c.x == 0 && c.y > 0 && c.y < 9 end)
      assert Enum.all?(left_line, fn c -> c.cell.char == "│" end)

      # Right vertical line
      right_line = Enum.filter(cells, fn c -> c.x == 19 && c.y > 0 && c.y < 9 end)
      assert Enum.all?(right_line, fn c -> c.cell.char == "│" end)
    end

    test "renders left-aligned title" do
      props = %{border: :single, title: "Test", title_align: :left}
      {:ok, state} = Block.init(props)
      result = Block.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result

      # Title should start at x=1 (after corner)
      t_cell = Enum.find(cells, fn c -> c.y == 0 && c.x == 1 end)
      assert t_cell.cell.char == "T"
    end

    test "renders center-aligned title" do
      props = %{border: :single, title: "Hi", title_align: :center}
      {:ok, state} = Block.init(props)
      result = Block.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result

      # "Hi" is 2 chars, inner width is 18, so left padding = 8
      h_cell = Enum.find(cells, fn c -> c.y == 0 && c.cell.char == "H" end)
      # 1 (corner) + 8 (padding)
      assert h_cell.x == 9
    end

    test "renders right-aligned title" do
      props = %{border: :single, title: "Hi", title_align: :right}
      {:ok, state} = Block.init(props)
      result = Block.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result

      # "Hi" should end at x=18 (before corner at 19)
      i_cell = Enum.find(cells, fn c -> c.y == 0 && c.cell.char == "i" end)
      assert i_cell.x == 18
    end

    test "truncates long title" do
      props = %{border: :single, title: "This is a very long title"}
      {:ok, state} = Block.init(props)
      result = Block.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result
      # Title should fit in inner width (18 chars)
      title_cells = Enum.filter(cells, fn c -> c.y == 0 && c.x > 0 && c.x < 19 end)
      assert length(title_cells) == 18
    end

    test "applies style to border" do
      props = %{border: :single, style: %{fg: :blue}}
      {:ok, state} = Block.init(props)
      result = Block.render(state, @area)

      assert %RenderNode{type: :cells, cells: cells} = result
      first_cell = hd(cells)
      assert first_cell.cell.fg == :blue
    end

    test "handles small area" do
      small_area = %{x: 0, y: 0, width: 3, height: 3}
      props = %{border: :single}
      {:ok, state} = Block.init(props)
      result = Block.render(state, small_area)

      assert %RenderNode{type: :cells, cells: cells} = result
      assert cells != []
    end

    test "handles zero width" do
      zero_area = %{x: 0, y: 0, width: 0, height: 5}
      props = %{border: :single}
      {:ok, state} = Block.init(props)
      result = Block.render(state, zero_area)

      assert %RenderNode{type: :cells, cells: []} = result
    end

    test "handles zero height" do
      zero_area = %{x: 0, y: 0, width: 5, height: 0}
      props = %{border: :single}
      {:ok, state} = Block.init(props)
      result = Block.render(state, zero_area)

      assert %RenderNode{type: :cells, cells: []} = result
    end
  end

  describe "inner_area/2" do
    test "calculates inner area with border" do
      props = %{border: :single}
      inner = Block.inner_area(props, @area)

      assert inner.x == 1
      assert inner.y == 1
      assert inner.width == 18
      assert inner.height == 8
    end

    test "calculates inner area without border" do
      props = %{border: :none}
      inner = Block.inner_area(props, @area)

      assert inner.x == 0
      assert inner.y == 0
      assert inner.width == 20
      assert inner.height == 10
    end

    test "calculates inner area with integer padding" do
      props = %{border: :single, padding: 2}
      inner = Block.inner_area(props, @area)

      # 1 border + 2 padding
      assert inner.x == 3
      assert inner.y == 3
      # 20 - 2 - 4
      assert inner.width == 14
      # 10 - 2 - 4
      assert inner.height == 4
    end

    test "calculates inner area with directional padding" do
      props = %{border: :single, padding: %{top: 1, right: 2, bottom: 3, left: 4}}
      inner = Block.inner_area(props, @area)

      # 1 border + 4 left
      assert inner.x == 5
      # 1 border + 1 top
      assert inner.y == 2
      # 20 - 2 - 4 - 2
      assert inner.width == 12
      # 10 - 2 - 1 - 3
      assert inner.height == 4
    end

    test "handles negative inner dimensions" do
      small_area = %{x: 0, y: 0, width: 2, height: 2}
      props = %{border: :single, padding: 5}
      inner = Block.inner_area(props, small_area)

      assert inner.width == 0
      assert inner.height == 0
    end
  end
end
