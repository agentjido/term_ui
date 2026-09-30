defmodule TermUI.TerminalSession.FrameTest do
  use ExUnit.Case, async: true

  alias TermUI.{Cell, Frame}
  alias TermUI.TerminalSession.Frame, as: TerminalFrame

  test "Unicode wide cells keep their tails and blank-cell colors" do
    snapshot = %{
      cells: [
        [
          {"é", nil, nil, 0},
          {"界", {10, 20, 30}, {40, 50, 60}, 1},
          {"", nil, nil, 0},
          {"", nil, {70, 80, 90}, 0}
        ]
      ],
      foreground: {200, 210, 220},
      background: {1, 2, 3},
      cursor: %{visible: true, x: 3, y: 0, wide_tail: false}
    }

    frame = TerminalFrame.from_snapshot(snapshot, {2, 4})
    assert Frame.row_text(frame, 1) == "é界 "
    assert frame.cursor == {4, 1}
    assert %Cell{fg: {200, 210, 220}, bg: {1, 2, 3}} = Frame.cell(frame, 1, 1)

    assert %Cell{char: "界", width: 2, fg: {10, 20, 30}, bg: {40, 50, 60}} =
             Frame.cell(frame, 1, 2)

    assert %Cell{char: "", width: 0, wide_placeholder: true, bg: {40, 50, 60}} =
             Frame.cell(frame, 1, 3)

    assert %Cell{char: " ", bg: {70, 80, 90}} = Frame.cell(frame, 1, 4)
    assert Frame.row_text(frame, 2) == "    "
    assert Cell.has_attr?(Frame.cell(frame, 1, 3), :bold)
  end

  test "supported attributes preserve the public Ghostty flag mapping" do
    for {flag, attribute} <- [
          {1, :bold},
          {2, :italic},
          {4, :dim},
          {8, :underline},
          {16, :strikethrough},
          {32, :reverse},
          {64, :blink}
        ] do
      frame = TerminalFrame.from_snapshot(%{cells: [[{"x", nil, nil, flag}]]}, {1, 1})
      assert Frame.cell(frame, 1, 1).attrs == MapSet.new([attribute])
    end

    frame = TerminalFrame.from_snapshot(%{cells: [[{"x", nil, nil, 128}]]}, {1, 1})
    assert Frame.cell(frame, 1, 1).attrs == MapSet.new()
  end

  test "small regions clip wide cells and hidden or outside cursors" do
    snapshot = %{
      cells: [[{"界", nil, nil, 0}, {"", nil, nil, 0}]],
      cursor: %{visible: true, x: 1, y: 0}
    }

    frame = TerminalFrame.from_snapshot(snapshot, {1, 1})
    assert Frame.row_text(frame, 1) == " "
    assert frame.cursor == nil

    assert TerminalFrame.from_snapshot(
             %{snapshot | cursor: %{visible: false, x: 0, y: 0}},
             {1, 2}
           ).cursor == nil
  end
end
