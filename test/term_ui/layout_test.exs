defmodule TermUI.LayoutTest do
  use ExUnit.Case, async: true

  alias TermUI.{Frame, Layout, Mouse}

  test "creates, insets, and clips zero-based rectangles" do
    root = Layout.new({12, 8})

    assert root == {0, 0, 12, 8}
    assert Layout.dimensions(root) == {12, 8}
    assert Layout.inset(root, 2) == {2, 2, 8, 4}
    assert Layout.inset(root, {1, 2, 3, 4}) == {4, 1, 6, 4}
    assert Layout.inset(root, {20, 20, 20, 20}) == {12, 8, 0, 0}
    assert Layout.at({2, 3, 5, 4}, {3, 2}, {8, 8}) == {5, 5, 2, 2}
  end

  test "allocates fixed and weighted row tracks with stable remainders" do
    assert Layout.row({2, 3, 11, 4}, [3, :fill, {:weight, 2}], gap: 1) == [
             {2, 3, 3, 4},
             {6, 3, 2, 4},
             {9, 3, 4, 4}
           ]

    assert Layout.row({0, 0, 7, 1}, [:fill, :fill, :fill]) == [
             {0, 0, 3, 1},
             {3, 0, 2, 1},
             {5, 0, 2, 1}
           ]

    assert Layout.column({0, 0, 2, 5}, [{:weight, 3}, :fill]) == [
             {0, 0, 2, 4},
             {0, 4, 2, 1}
           ]

    assert Layout.row({0, 0, 5, 1}, []) == []
  end

  test "keeps zero-sized overflow tracks inside the parent" do
    assert Layout.row({0, 0, 5, 2}, [4, 4, :fill], gap: 2) == [
             {0, 0, 1, 2},
             {3, 0, 0, 2},
             {5, 0, 0, 2}
           ]

    assert Layout.column({1, 2, 3, 4}, [4, 4], gap: 3) == [
             {1, 2, 3, 1},
             {1, 6, 3, 0}
           ]
  end

  test "builds a row-major grid and handles empty input" do
    assert Layout.grid({0, 0, 9, 5}, 5, columns: 3, column_gap: 1, row_gap: 1) == [
             {0, 0, 3, 2},
             {4, 0, 2, 2},
             {7, 0, 2, 2},
             {0, 3, 3, 2},
             {4, 3, 2, 2}
           ]

    assert Layout.grid({0, 0, 9, 5}, 0) == []
    assert Layout.grid({0, 0, 10, 4}, 1, columns: 2) == [{0, 0, 5, 4}]
    assert Layout.grid({0, 0, 10, 4}, 1, columns: 2, rows: 2) == [{0, 0, 5, 2}]
    assert Layout.grid({0, 0, 9, 5}, 1, columns: 100_000_000) == [{0, 0, 1, 5}]

    assert length(Layout.grid({0, 0, 8, 4}, 5, columns: 2, rows: 2)) == 4

    assert_raise ArgumentError, fn -> Layout.grid({0, 0, 9, 5}, 1, columns: 0) end
    assert_raise ArgumentError, fn -> Layout.grid({0, 0, 9, 5}, 1, rows: 0) end
    assert_raise ArgumentError, fn -> Layout.row({0, 0, 9, 5}, [:fill], gap: 1.5) end
  end

  test "places clipped frames and creates matching mouse regions" do
    base = Frame.new(6, 3)
    child = Frame.from_rows(["abcd", "efgh"], 4, 2)
    frame = Layout.place(base, child, {4, 1, 4, 2})

    assert Frame.row_text(frame, 2) == "    ab"
    assert Frame.row_text(frame, 3) == "    ef"

    region = Layout.region(:body, {4, 1, 2, 2}, z_index: 3, metadata: %{kind: :panel})
    assert region.z_index == 3
    assert region.metadata == %{kind: :panel}
    assert Mouse.contains?(region, 5, 2)
    assert Layout.region(:empty, {0, 0, 0, 2}) == nil
    assert Layout.region(:empty, {0, 0, 2, 0}) == nil
    assert Layout.place(frame, child, {0, 0, 0, 2}) == frame
    assert Layout.place(frame, child, {0, 0, 2, 0}) == frame
    assert Layout.place(frame, child, {99, 99, 10_000, 10_000}) == frame

    oversized = Layout.place(Frame.new(2, 2), child, {1, 1, 10_000, 10_000})
    assert Frame.cell(oversized, 2, 2).char == "a"
  end

  test "creates fixed, fill, percentage, ratio, bounded, and content tracks" do
    assert Layout.fixed(8) == 8
    assert Layout.fill() == :fill
    assert Layout.percentage(25) == {:percentage, 25}
    assert Layout.ratio(2) == {:weight, 2}
    assert Layout.bounded(:fill, min: 4, max: 12) == {:bounded, :fill, 4, 12}
    assert Layout.content(30, max: 9) == {:bounded, 30, 0, 9}

    tracks = [
      Layout.fixed(8),
      Layout.percentage(25),
      Layout.ratio(1),
      Layout.bounded(Layout.fill(), min: 10, max: 12),
      Layout.content(30, max: 9)
    ]

    assert Layout.row({0, 0, 60, 4}, tracks) == [
             {0, 0, 8, 4},
             {8, 0, 15, 4},
             {23, 0, 16, 4},
             {39, 0, 12, 4},
             {51, 0, 9, 4}
           ]
  end

  test "nests constrained rows, columns, and grids without a solver" do
    root = Layout.new({100, 30})
    [header, body] = Layout.column(root, [Layout.fixed(3), Layout.fill()])
    [navigation, main] = Layout.row(body, [Layout.percentage(20), Layout.ratio(3)])

    assert header == {0, 0, 100, 3}
    assert navigation == {0, 3, 20, 27}
    assert main == {20, 3, 80, 27}

    cells =
      Layout.grid(main, 6,
        column_tracks: [
          Layout.content(12, max: 10),
          Layout.bounded(Layout.ratio(1), min: 8),
          Layout.fill()
        ],
        row_tracks: [
          Layout.fixed(5),
          Layout.bounded(Layout.fill(), min: 6, max: 10)
        ],
        column_gap: 1,
        row_gap: 1
      )

    assert cells == [
             {20, 3, 10, 5},
             {31, 3, 38, 5},
             {70, 3, 30, 5},
             {20, 9, 10, 10},
             {31, 9, 38, 10},
             {70, 9, 30, 10}
           ]
  end

  test "resize keeps percentage, ratio, minimum, maximum, and content bounds" do
    for {width, expected} <- [{40, [10, 10, 20]}, {80, [20, 20, 40]}, {120, [30, 30, 60]}] do
      rects =
        Layout.row(
          {0, 0, width, 1},
          [Layout.percentage(25), Layout.ratio(1), Layout.ratio(2)]
        )

      assert Enum.map(rects, fn {_x, _y, track_width, _height} -> track_width end) == expected
    end

    for width <- [40, 80, 120] do
      [bounded, content, _fill] =
        Layout.row(
          {0, 0, width, 1},
          [Layout.bounded(:fill, min: 10, max: 20), Layout.content(50, max: 15), :fill]
        )

      assert elem(bounded, 2) in 10..20
      assert elem(content, 2) == 15
    end

    assert Layout.row(
             {0, 0, 5, 1},
             [Layout.bounded(:fill, min: 4), Layout.bounded(:fill, min: 4)]
           ) == [
             {0, 0, 3, 1},
             {3, 0, 2, 1}
           ]
  end

  test "rejects invalid constraint helper values" do
    assert_raise ArgumentError, fn -> Layout.fixed(-1) end
    assert_raise ArgumentError, fn -> Layout.percentage(101) end
    assert_raise ArgumentError, fn -> Layout.ratio(0) end
    assert_raise ArgumentError, fn -> Layout.bounded(:fill, min: 5, max: 4) end
    assert_raise ArgumentError, fn -> Layout.bounded(:fill, unknown: 1) end
    assert_raise ArgumentError, fn -> Layout.row({0, 0, 10, 1}, [{:percentage, 101}]) end

    assert_raise ArgumentError, fn ->
      Layout.grid({0, 0, 10, 5}, 1, column_tracks: [])
    end
  end
end
