defmodule TermUI.ClipboardEnvironmentTest do
  use ExUnit.Case, async: false

  alias TermUI.Clipboard

  @variables ["TERM", "TERM_PROGRAM", "KITTY_WINDOW_ID"]

  setup do
    original = Map.new(@variables, &{&1, System.get_env(&1)})
    Enum.each(@variables, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(original, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    :ok
  end

  test "detects common OSC 52 terminal environments" do
    refute Clipboard.osc52_supported?()

    System.put_env("TERM", "xterm-256color")
    assert Clipboard.osc52_supported?()

    System.delete_env("TERM")
    System.put_env("TERM_PROGRAM", "WezTerm")
    assert Clipboard.osc52_supported?()

    System.delete_env("TERM_PROGRAM")
    System.put_env("KITTY_WINDOW_ID", "1")
    assert Clipboard.osc52_supported?()

    System.delete_env("KITTY_WINDOW_ID")
    System.put_env("TERM", "foot")
    assert Clipboard.osc52_supported?()
  end
end
