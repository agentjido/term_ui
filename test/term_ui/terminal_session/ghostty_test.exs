defmodule TermUI.TerminalSession.GhosttyTest do
  use ExUnit.Case, async: true

  alias TermUI.Event
  alias TermUI.TerminalSession.Ghostty

  test "the optional SDK has explicit supported platforms and a missing-package error" do
    for architecture <- ["x86_64-linux-gnu", "aarch64-linux-gnu"] do
      assert :ok = Ghostty.platform({:unix, :linux}, architecture)
    end

    assert :ok = Ghostty.platform({:unix, :darwin}, "aarch64-apple-darwin")

    for {os, architecture} <- [
          {{:unix, :linux}, "x86_64-linux-musl"},
          {{:unix, :darwin}, "x86_64-apple-darwin"},
          {{:win32, :nt}, "x86_64-pc-windows-msvc"},
          {{:unix, :freebsd}, "x86_64-freebsd"}
        ] do
      assert {:error, {:unsupported_platform, _os, ^architecture}} =
               Ghostty.platform(os, architecture)
    end

    assert {:error, _reason} = Ghostty.available()
  end

  test "normalized keys keep Unicode, named keys, and native modifier names" do
    assert {:ok, [key: :unidentified, utf8: "é界"]} = Ghostty.key_fields(Event.text("é界"))
    assert {:ok, fields} = Ghostty.key_fields(Event.key(:up))
    assert fields[:key] == :arrow_up
    assert fields[:utf8] == nil
    assert {:ok, fields} = Ghostty.key_fields(Event.key(:backtab, modifiers: [:shift]))
    assert fields[:key] == :tab
    assert fields[:mods] == [:shift]

    assert {:ok, fields} = Ghostty.key_fields(Event.key("C", modifiers: [:ctrl, :alt, :meta]))
    assert fields[:key] == :c
    assert fields[:utf8] == "C"
    assert Enum.sort(fields[:mods]) == [:alt, :ctrl, :super]
    assert {:ok, [key: :digit_1, utf8: "1", mods: []]} = Ghostty.key_fields(Event.key("1"))
    assert {:ok, [key: :unidentified, utf8: "é", mods: []]} = Ghostty.key_fields(Event.key("é"))
    assert {:error, :unsupported_key} = Ghostty.key_fields(Event.key(:unknown_named_key))

    assert {:error, :unsupported_modifier} =
             Ghostty.key_fields(Event.key(:up, modifiers: [:unknown]))
  end

  test "mouse cells use the native fixed geometry and reject unsupported positions" do
    assert {:ok, fields} =
             Ghostty.mouse_fields(Event.mouse(:press, :left, 2, 2, modifiers: [:meta]))

    assert fields == [action: :press, button: :left, mods: [:super], x: 25.0, y: 50.0]
    assert {:ok, fields} = Ghostty.mouse_fields(Event.mouse(:drag, :left, 3, 3))
    assert fields[:action] == :motion
    assert {:ok, fields} = Ghostty.mouse_fields(Event.mouse(:release, :left, 79, 29))
    assert fields[:action] == :release

    assert {:error, :ghostty_mouse_geometry_limit} =
             Ghostty.mouse_fields(Event.mouse(:press, :left, 80, 0))

    assert {:error, :ghostty_mouse_geometry_limit} =
             Ghostty.mouse_fields(Event.mouse(:press, :left, 0, 30))

    assert {:error, :unsupported_mouse_action} =
             Ghostty.mouse_fields(Event.mouse(:scroll_up, nil, 0, 0))
  end

  test "stop is safe when a child already stopped" do
    {:ok, child} = Agent.start_link(fn -> :ok end)
    assert :ok = Ghostty.stop(child)
    assert :ok = Ghostty.stop(child)
  end
end
