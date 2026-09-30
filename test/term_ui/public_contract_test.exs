defmodule TermUI.PublicContractTest do
  use ExUnit.Case, async: true

  alias TermUI.{Command, Elm, Event, Frame}

  test "commands are effect data without component identities" do
    assert %Command{kind: :message, value: :next} = Command.message(:next)
    assert %Command{kind: :timer, value: {10, :tick}} = Command.timer(10, :tick)
    assert %Command{kind: :shutdown, value: :normal} = Command.shutdown()

    command = Command.async(fn -> 1 end, &{:done, &1})
    refute Map.has_key?(command, :component_id)
    assert command.kind == :async
  end

  test "events separate text from named and modified keys" do
    assert %Event.Text{text: "界"} = Event.text("界", timestamp: 1)
    assert %Event.Key{key: :enter, modifiers: []} = Event.key(:enter, timestamp: 1)
    assert %Event.Key{key: "c", modifiers: [:ctrl]} = Event.key("c", modifiers: [:ctrl, :ctrl])
    assert %Event.Paste{content: "a\nb"} = Event.paste("a\nb")
    assert %Event.Mouse{action: :press, x: 2, y: 3} = Event.mouse(:press, :left, 2, 3)
    assert %Event.Resize{width: 80, height: 24} = Event.resize(80, 24)
    assert %Event.Focus{action: :gained} = Event.focus(:gained)

    assert_raise FunctionClauseError, fn -> Event.resize("80", 24) end
  end

  test "Elm normalization keeps state and command lists explicit" do
    frame = Frame.from_rows(["ok"], 2, 1)
    shutdown = Command.shutdown()
    assert {%{value: 1}, []} = Elm.normalize_init_result(%{value: 1})

    assert {%{value: 2}, [^shutdown]} =
             Elm.normalize_update_result({%{value: 2}, [shutdown]}, %{})

    assert %Frame{} = frame
  end
end
