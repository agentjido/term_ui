defmodule TermUI.Property.WebProtocolTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Frame}
  alias TermUI.Test.BoundaryCases, as: Cases
  alias TermUI.WebBackend.Protocol

  test "bounded malformed browser messages either return a valid event or a declared error" do
    Cases.check(&payload/0, fn payload ->
      case Protocol.event(payload, {12, 40}, Protocol.default_limits()) do
        {:ok, event} -> assert {:ok, _event} = Zoi.parse(Event.schema(), event)
        {:error, reason} -> assert reason in [:invalid_input, :unsupported_version]
      end
    end)
  end

  test "row deltas reconstruct the full browser frame across edits, cursor moves, and resize" do
    Cases.check(&frame_pair/0, fn {before, after_frame} ->
      previous = Protocol.frame(nil, before, 1, nil)
      delta = Protocol.frame(before, after_frame, 2, 1)
      full = Protocol.frame(nil, after_frame, 2, nil)

      old_rows =
        if delta["full"],
          do: %{},
          else: Map.new(previous["rows"], fn [row, cells] -> {row, cells} end)

      rows =
        Enum.reduce(delta["rows"], old_rows, fn [row, cells], rows ->
          Map.put(rows, row, cells)
        end)

      expected = Map.new(full["rows"], fn [row, cells] -> {row, cells} end)
      assert rows == expected
      assert delta["cursor"] == full["cursor"]
      assert delta["width"] == full["width"]
      assert delta["height"] == full["height"]
      assert delta["seq"] == 2
      assert delta["base"] == if(delta["full"], do: nil, else: 1)
    end)
  end

  test "text and paste byte limits accept their boundary and reject the next byte" do
    Cases.check(fn -> {Cases.integer(1, 64), Cases.choose(["text", "paste"])} end, fn {limit,
                                                                                       type} ->
      {:ok, limits} = Protocol.limits(%{text_bytes: limit, paste_bytes: limit})
      payload = %{"v" => 1, "type" => type, "text" => String.duplicate("x", limit)}
      assert {:ok, _event} = Protocol.event(payload, {12, 40}, limits)

      assert {:error, :invalid_input} =
               Protocol.event(%{payload | "text" => payload["text"] <> "x"}, {12, 40}, limits)
    end)
  end

  defp payload do
    values = [
      nil,
      false,
      true,
      -1,
      0,
      1,
      40,
      300,
      "",
      "ctrl",
      ["ctrl"],
      ["unknown"],
      %{},
      Cases.bytes(),
      Cases.text()
    ]

    fields = [
      "v",
      "type",
      "text",
      "key",
      "modifiers",
      "width",
      "height",
      "x",
      "y",
      "action",
      "button",
      "focused"
    ]

    base = %{
      "v" => 1,
      "type" => Cases.choose(["text", "paste", "key", "resize", "mouse", "focus", "unknown"])
    }

    Enum.reduce(1..Cases.integer(1, 8), base, fn _index, payload ->
      Map.put(payload, Cases.choose(fields), Cases.choose(values))
    end)
  end

  defp frame_pair do
    width = Cases.integer(1, 20)
    height = Cases.integer(1, 4)
    before = Frame.from_rows(for(_row <- 1..height, do: Cases.text()), width, height)

    {after_width, after_height} =
      Cases.choose([{width, height}, {Cases.integer(1, 20), Cases.integer(1, 4)}])

    after_frame =
      Frame.from_rows(for(_row <- 1..after_height, do: Cases.text()), after_width, after_height,
        cursor: {Cases.integer(1, after_width), Cases.integer(1, after_height)}
      )

    {before, after_frame}
  end
end
