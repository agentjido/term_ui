defmodule TermUI.NestedLayoutTest do
  use ExUnit.Case, async: true

  alias TermUI.{DisplayWidth, Frame, Layout}

  test "the issue 11 migration example returns the complete nested layout" do
    frame = view({50, 3})

    assert rows(frame) == [
             "Visible 1Visible 2",
             "Not visible    Also not visible",
             "Also visible"
           ]

    assert {:ok, ^frame} = Zoi.parse(Frame.schema(), frame)
  end

  test "resize clips nested children and restores the full layout" do
    for {dimensions, expected} <- [
          {{10, 3}, ["Visible 1V", "Not visibl", "Also visib"]},
          {{1, 1}, ["V"]},
          {{50, 1}, ["Visible 1Visible 2"]},
          {{50, 3}, ["Visible 1Visible 2", "Not visible    Also not visible", "Also visible"]}
        ] do
      frame = view(dimensions)
      assert {frame.width, frame.height} == dimensions
      assert rows(frame) == expected
      assert {:ok, ^frame} = Zoi.parse(Frame.schema(), frame)
    end
  end

  defp view({width, height}) do
    [top, middle, bottom] = Layout.column(Layout.new({width, height}), [1, 1, 1])

    [top_left, top_right] =
      Layout.row(top, [Layout.content(DisplayWidth.width("Visible 1")), Layout.fill()])

    [middle_left, middle_right] = Layout.row(middle, [Layout.fixed(15), Layout.fill()])

    children = [
      {top_left, "Visible 1"},
      {top_right, "Visible 2"},
      {middle_left, "Not visible"},
      {middle_right, "Also not visible"},
      {bottom, "Also visible"}
    ]

    Enum.reduce(children, Frame.new(width, height), fn {rect, text}, frame ->
      child = Frame.from_rows([text], DisplayWidth.width(text), 1)
      Layout.place(frame, child, rect)
    end)
  end

  defp rows(frame) do
    Enum.map(1..frame.height, &String.trim_trailing(Frame.row_text(frame, &1)))
  end
end
