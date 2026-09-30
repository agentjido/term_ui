defmodule TermUI.WebBackend.ProtocolTest do
  use ExUnit.Case, async: true

  alias TermUI.{Cell, Event, Frame, Style}
  alias TermUI.WebBackend.Protocol

  test "a full frame includes sparse blanks, Unicode, wide tails, styles, and cursor" do
    style = Style.new(fg: {:rgb, 10, 20, 30}, bg: {:indexed, 42}, bold: true, underline: true)
    frame = Frame.from_rows([[{"é界", style}]], 4, 2, cursor: {4, 2})
    output = Protocol.frame(nil, frame, 1, nil)

    assert %{
             "v" => 1,
             "type" => "frame",
             "seq" => 1,
             "base" => nil,
             "full" => true,
             "width" => 4,
             "height" => 2,
             "cursor" => [4, 2]
           } = output

    assert output["rows"] == [
             [
               1,
               [
                 ["é", 1, [10, 20, 30], 42, ["bold", "underline"]],
                 ["界", 2, [10, 20, 30], 42, ["bold", "underline"]],
                 ["", 0, [10, 20, 30], 42, ["bold", "underline"]],
                 [" ", 1, nil, nil, []]
               ]
             ],
             [2, List.duplicate([" ", 1, nil, nil, []], 4)]
           ]
  end

  test "row updates clear removed cells and use their confirmed base" do
    before = Frame.from_rows(["abcd", "same"], 4, 2)
    after_frame = Frame.from_rows(["a", "same"], 4, 2)
    output = Protocol.frame(before, after_frame, 8, 6)

    assert output["full"] == false
    assert output["base"] == 6
    assert output["seq"] == 8

    assert output["rows"] == [
             [1, [["a", 1, nil, nil, []] | List.duplicate([" ", 1, nil, nil, []], 3)]]
           ]
  end

  test "background-only changes reach blank cells and resize always replaces the frame" do
    before = Frame.new(2, 1)
    after_frame = Frame.put_cell(before, 1, 2, Cell.new(" ", bg: :blue))

    assert Protocol.frame(before, after_frame, 2, 1)["rows"] ==
             [[1, [[" ", 1, nil, nil, []], [" ", 1, nil, "blue", []]]]]

    for frame <- [Frame.new(3, 1), Frame.new(1, 2)] do
      assert %{"full" => true, "base" => nil} = Protocol.frame(before, frame, 3, 2)
    end

    assert %{"full" => true, "base" => nil} = Protocol.frame(before, before, 4, nil)

    assert %{"full" => false, "rows" => [], "cursor" => [2, 1]} =
             Protocol.frame(before, %{before | cursor: {2, 1}}, 5, 4)
  end

  test "browser input uses the existing event types without client timestamps" do
    cases = [
      {%{"type" => "text", "text" => "👩‍💻é"}, %Event.Text{text: "👩‍💻é"}},
      {%{"type" => "paste", "text" => "one\ntwo"}, %Event.Paste{content: "one\ntwo"}},
      {%{"type" => "paste", "text" => ""}, %Event.Paste{content: ""}},
      {%{"type" => "key", "key" => "ArrowUp"}, %Event.Key{key: :up}},
      {%{"type" => "key", "key" => "s", "modifiers" => ["ctrl"]},
       %Event.Key{key: "s", modifiers: [:ctrl]}},
      {%{"type" => "focus", "focused" => true}, %Event.Focus{action: :gained}},
      {%{"type" => "focus", "focused" => false}, %Event.Focus{action: :lost}},
      {%{"type" => "resize", "width" => 100, "height" => 40},
       %Event.Resize{width: 100, height: 40}},
      {%{"type" => "mouse", "action" => "press", "button" => "left", "x" => 79, "y" => 23},
       %Event.Mouse{action: :press, button: :left, x: 79, y: 23}}
    ]

    for {payload, expected} <- cases do
      payload = Map.merge(payload, %{"v" => 1, "timestamp" => "untrusted"})
      assert {:ok, event} = Protocol.event(payload, {24, 80}, Protocol.default_limits())
      assert Map.delete(event, :timestamp) == Map.delete(expected, :timestamp)
      assert is_integer(event.timestamp)
    end
  end

  test "invalid versions, input, dimensions, coordinates, and modifier names are rejected" do
    invalid = [
      %{"type" => "text", "text" => ""},
      %{"type" => "text", "text" => <<255>>},
      %{"type" => "text", "text" => String.duplicate("a", 4_097)},
      %{"type" => "paste", "text" => String.duplicate("a", 65_537)},
      %{"type" => "text", "text" => :atom},
      %{"type" => "key", "key" => "s"},
      %{"type" => "key", "key" => "ArrowUp", "modifiers" => ["unknown_atom"]},
      %{"type" => "key", "key" => "ArrowUp", "modifiers" => "ctrl"},
      %{"type" => "key", "key" => "ArrowUp", "modifiers" => List.duplicate("ctrl", 5)},
      %{"type" => "mouse", "action" => "unknown", "x" => 1, "y" => 1},
      %{"type" => "mouse", "action" => "press", "button" => "unknown", "x" => 1, "y" => 1},
      %{"type" => "mouse", "action" => "move", "x" => 80, "y" => 0},
      %{"type" => "mouse", "action" => "move", "x" => -1, "y" => 0},
      %{"type" => "focus", "focused" => "true"},
      %{"type" => "resize", "width" => 301, "height" => 24},
      %{"type" => "resize", "width" => 80, "height" => 0},
      %{"type" => "unknown"}
    ]

    for payload <- invalid do
      assert {:error, :invalid_input} =
               Protocol.event(Map.put(payload, "v", 1), {24, 80}, Protocol.default_limits())
    end

    assert {:error, :unsupported_version} = Protocol.event(%{"v" => 2}, {24, 80}, %{})
    assert {:error, :invalid_input} = Protocol.event(nil, {24, 80}, %{})
    assert Protocol.version() == 1
  end

  test "host limits stay within public Frame bounds" do
    assert {:ok, %{width: 1_000, height: 500}} = Protocol.limits(%{width: 1_000, height: 500})

    for value <- [
          %{width: 1_001},
          %{height: 501},
          %{width: 0},
          %{text_bytes: nil},
          %{unknown: 1},
          []
        ] do
      assert {:error, :invalid_limits} = Protocol.limits(value)
    end

    assert {:error, :invalid_size} = Protocol.size(nil, Protocol.default_limits())
    assert {:error, :invalid_size} = Protocol.size({-1, 80}, Protocol.default_limits())
  end
end
