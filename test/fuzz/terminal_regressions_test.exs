defmodule TermUI.Fuzz.TerminalRegressionsTest do
  use ExUnit.Case, async: true

  alias TermUI.{Cell, Event, Frame}
  alias TermUI.Terminal.EscapeParser
  alias TermUI.Test.BoundaryCases, as: Cases

  @corpus [
    <<0xC2>>,
    <<0xE0, 0x80>>,
    <<0xF4, 0x90, 0x80, 0x80>>,
    <<0, 255, 127>>,
    "\e",
    "\e[",
    "\eO",
    "\e[<0;999999999999999999;1M",
    "\e[<0;0;0M",
    "\e[?9999999999999999999999999",
    "\e[200~",
    "\e[200~\e[201~",
    "\e[200~\e[A\n界\e[201~",
    "\e[201~",
    "\e\x7f",
    "\e[1;5Z"
  ]

  test "fixed terminal regression corpus is bounded and normalized" do
    for input <- @corpus do
      {events, remaining} = EscapeParser.parse(input)
      assert byte_size(remaining) <= byte_size(input), inspect(input)

      assert Enum.all?(events, &match?({:ok, _event}, Zoi.parse(Event.schema(), &1))),
             inspect(input)
    end
  end

  test "malformed paste bytes are discarded without losing Unicode, embedded escapes, or following input" do
    input = "\e[200~\e[A\n" <> <<193>> <> "界\e[201~x"

    assert {[%Event.Paste{content: "\e[A\n界"}, %Event.Text{text: "x"}], ""} =
             EscapeParser.parse(input)

    assert {[%Event.Paste{content: ""}], ""} =
             EscapeParser.parse("\e[200~" <> <<255>> <> "\e[201~")
  end

  test "joined emoji, skin tones, and composed Hangul occupy one wide cell" do
    for text <- ["👩‍💻", "👨‍👩‍👧‍👦", "👍🏽", "각"] do
      assert TermUI.DisplayWidth.width(text) == 2
      assert TermUI.DisplayWidth.width(text <> "x") == 3
      assert Frame.fit(text <> "x", 3) == text <> "x"
      assert Frame.fit(text <> "x", 2) == text
      assert Frame.from_rows([text <> "x"], 3, 1) |> Frame.row_text(1) == text <> "x"
    end
  end

  test "small corpus mutations cannot crash the parser or cell constructor" do
    Cases.check(
      fn ->
        input = Cases.choose(@corpus)
        offset = Cases.integer(0, byte_size(input))
        <<before::binary-size(offset), after_bytes::binary>> = input
        before <> <<Cases.integer(0, 255)>> <> after_bytes
      end,
      fn input ->
        {events, remaining} = EscapeParser.parse(input)
        assert byte_size(remaining) <= byte_size(input)
        assert Enum.all?(events, &match?({:ok, _event}, Zoi.parse(Event.schema(), &1)))
        cell = Cell.new(input)
        assert {:ok, _cell} = Zoi.parse(Cell.schema(), cell)

        assert {:ok, _frame} =
                 Zoi.parse(Frame.schema(), Frame.put_cell(Frame.new(2, 1), 1, 1, cell))
      end
    )
  end
end
