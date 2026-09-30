defmodule TermUI.InputTest do
  use ExUnit.Case, async: true

  alias TermUI.{Event, Input, Shortcut}
  alias TermUI.Widget.TextInput

  test "text keeps Unicode and multi-codepoint input in one event" do
    family = "👩‍👩‍👧‍👦"
    decomposed = "e\u0301"

    assert %Event.Text{text: ^family, timestamp: 10} = Input.text(family, timestamp: 10)
    assert %Event.Text{text: ^decomposed} = Input.text(decomposed)

    input = TextInput.init([])
    {input, [{:changed, value}]} = TextInput.update(Input.text(family <> decomposed), input)
    assert value == family <> decomposed
    assert input.value == value
  end

  test "committed composition stays text and paste stays a separate event" do
    composed = Input.composition("かな")
    paste = Input.paste("かな\nnext")
    enter = Input.special_key("Return")

    assert %Event.Text{text: "かな"} = composed
    assert %Event.Paste{content: "かな\nnext"} = paste
    assert %Event.Key{key: :enter} = enter
    assert Enum.map([composed, paste, enter], &Event.type/1) == [:text, :paste, :key]
  end

  test "special keys normalize adapter names and shortcut modifiers" do
    assert %Event.Key{key: :up, modifiers: []} = Input.special_key("Arrow_Up")

    assert %Event.Key{key: "s", modifiers: [:alt, :ctrl, :meta]} =
             Input.special_key("s", modifiers: [:control, :option, :command, :control])

    shortcuts = Shortcut.new([{"ctrl+s", :save}])

    assert {_shortcuts, [:save]} =
             Shortcut.route(Input.special_key("s", modifiers: [:control]), shortcuts)
  end

  test "special-key input does not accept unmodified printable text" do
    assert_raise ArgumentError,
                 "unmodified printable input must use TermUI.Input.text/2",
                 fn -> Input.special_key("x") end

    assert_raise ArgumentError, fn -> Input.special_key("xy", modifiers: [:ctrl]) end
    assert_raise ArgumentError, fn -> Input.special_key(:enter, modifiers: [:hyper]) end
    assert_raise ArgumentError, fn -> Input.text(<<255>>) end
  end
end
