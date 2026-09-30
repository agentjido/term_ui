defmodule TermUIWebExample.AppTest do
  use ExUnit.Case, async: true
  alias TermUI.{Command, Event, Frame}
  alias TermUIWebExample.{App, Router, Socket}

  test "the example uses a complete frame and normal shutdown commands" do
    state = App.init(dimensions: {80, 24})
    state = App.update({:event, Event.text(" ")}, state)
    state = App.update({:event, Event.key(:up)}, state)
    state = App.update({:event, Event.text("é界")}, state)
    state = App.update({:event, Event.paste("one\ntwo")}, state)
    assert %Frame{width: 80, height: 24} = frame = App.view(state)
    assert Frame.row_text(frame, 3) =~ "Count: 2"
    assert Frame.row_text(frame, 4) =~ "Text: é界one two"

    assert {^state, [%Command{kind: :shutdown, value: :normal}]} =
             App.update({:event, Event.text("q")}, state)

    state = App.update({:event, Event.resize(1, 1)}, state)
    assert %Frame{width: 1, height: 1, cursor: {1, 1}} = App.view(state)
  end

  test "the host refuses missing or different origins before starting a session" do
    for origin <- [nil, "http://untrusted.invalid", "http://127.0.0.1:9999"] do
      conn = Plug.Test.conn(:get, "http://127.0.0.1:4040/ws")
      conn = if origin, do: Plug.Conn.put_req_header(conn, "origin", origin), else: conn
      assert %{status: 403, resp_body: "Origin refused"} = Router.call(conn, Router.init([]))
    end
  end

  test "the host limits complete input bytes and message rate" do
    {:ok, state} = Socket.init(%{})
    on_exit(fn -> TermUI.WebBackend.disconnect(state.session) end)

    assert {:stop, :normal, {1008, _reason}, ^state} =
             Socket.handle_in({String.duplicate("x", 70_001), [opcode: :text]}, state)

    assert {:stop, :normal, {1008, _reason}, ^state} =
             Socket.handle_in({"{}", [opcode: :binary]}, state)

    assert {:stop, :normal, {1008, _reason}, %{messages: 1}} =
             Socket.handle_in({"invalid", [opcode: :text]}, state)

    rate_state = %{state | messages: 300, window: System.monotonic_time(:millisecond)}

    assert {:stop, :normal, {1008, "Input rate limit"}, _next} =
             Socket.handle_in({"{}", [opcode: :text]}, rate_state)
  end
end
