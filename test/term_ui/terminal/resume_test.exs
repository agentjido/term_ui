defmodule TermUI.Terminal.ResumeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias TermUI.Terminal
  alias TermUI.Terminal.State

  test "resume restores owned output without replacing the saved terminal settings" do
    state = %State{
      alternate_screen_active: true,
      cursor_visible: false,
      mouse_tracking: :all,
      bracketed_paste: true,
      focus_events: true,
      original_settings: "saved settings",
      resize_callbacks: [self()]
    }

    output =
      capture_io(fn -> assert {:noreply, ^state} = Terminal.handle_info(:sigcont, state) end)

    assert output =~ "\e[?1049h"
    assert output =~ "\e[?25l"
    assert output =~ "\e[?1003h\e[?1006h"
    assert output =~ "\e[?2004h"
    assert output =~ "\e[?1004h"
    assert_receive :terminal_resume
  end

  test "an idle terminal owner sends no mode changes" do
    state = State.new()

    assert "" ==
             capture_io(fn ->
               assert {:noreply, ^state} = Terminal.handle_info(:sigcont, state)
             end)
  end

  test "resume restores the selected mouse mode without enabling other features" do
    for {mode, sequence} <- [click: "\e[?1000h", drag: "\e[?1002h"] do
      state = %{State.new() | mouse_tracking: mode}
      output = capture_io(fn -> Terminal.handle_info(:sigcont, state) end)
      assert output =~ sequence <> "\e[?1006h"
      refute output =~ "\e[?1049h"
      refute output =~ "\e[?25l"
      refute output =~ "\e[?2004h"
      refute output =~ "\e[?1004h"
    end
  end

  test "a runtime that is stopping ignores resume" do
    state = %{shutting_down: true}
    assert {:noreply, ^state} = TermUI.Runtime.handle_info(:terminal_resume, state)
  end
end
