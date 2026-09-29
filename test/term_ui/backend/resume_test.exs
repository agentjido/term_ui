defmodule TermUI.Backend.ResumeTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias TermUI.Backend.TTY

  test "TTY resume restores owned modes and invalidates incremental output" do
    output =
      capture_io(fn ->
        {:ok, state} = TTY.init(size: {2, 8}, alternate_screen: true, line_mode: :incremental)
        cells = [{{1, 1}, {"X", :green, :default, []}}]
        {:ok, state} = TTY.draw_cells(state, cells)
        assert is_map(state.last_frame)
        {:ok, state} = TTY.resume(state)
        assert state.last_frame == nil
        assert state.size == {2, 8}
        assert {:ok, _state} = TTY.draw_cells(state, cells)
      end)

    assert length(:binary.matches(output, "\e[?1049h")) == 2
    assert length(:binary.matches(output, "X")) == 2
    assert output =~ "\e[?25l"
  end
end
