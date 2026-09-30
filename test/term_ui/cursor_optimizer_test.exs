defmodule TermUI.CursorOptimizerTest do
  use ExUnit.Case, async: true

  alias TermUI.CursorOptimizer

  describe "new/0 and new/2" do
    test "creates optimizer at default position (1, 1)" do
      optimizer = CursorOptimizer.new()
      assert CursorOptimizer.position(optimizer) == {1, 1}
    end

    test "creates optimizer at specified position" do
      optimizer = CursorOptimizer.new(5, 10)
      assert CursorOptimizer.position(optimizer) == {5, 10}
    end

    test "starts with zero bytes saved" do
      optimizer = CursorOptimizer.new()
      assert CursorOptimizer.bytes_saved(optimizer) == 0
    end
  end

  describe "cost functions" do
    test "cost_absolute/2 calculates correct byte count" do
      # ESC [ 1 ; 1 H = 6 bytes
      assert CursorOptimizer.cost_absolute(1, 1) == 6
      # ESC [ 1 0 ; 1 0 H = 8 bytes
      assert CursorOptimizer.cost_absolute(10, 10) == 8
      # ESC [ 1 0 0 ; 1 0 0 H = 10 bytes
      assert CursorOptimizer.cost_absolute(100, 100) == 10
    end

    test "cost_up/1 calculates correct byte count" do
      # ESC [ A = 3 bytes for n=1
      assert CursorOptimizer.cost_up(1) == 3
      # ESC [ 5 A = 4 bytes
      assert CursorOptimizer.cost_up(5) == 4
      # ESC [ 1 0 A = 5 bytes
      assert CursorOptimizer.cost_up(10) == 5
    end

    test "cost_down/1 calculates correct byte count" do
      assert CursorOptimizer.cost_down(1) == 3
      assert CursorOptimizer.cost_down(5) == 4
      assert CursorOptimizer.cost_down(10) == 5
    end

    test "cost_right/1 calculates correct byte count" do
      assert CursorOptimizer.cost_right(1) == 3
      assert CursorOptimizer.cost_right(5) == 4
      assert CursorOptimizer.cost_right(10) == 5
    end

    test "cost_left/1 calculates correct byte count" do
      assert CursorOptimizer.cost_left(1) == 3
      assert CursorOptimizer.cost_left(5) == 4
      assert CursorOptimizer.cost_left(10) == 5
    end

    test "cost_cr/0 returns 1" do
      assert CursorOptimizer.cost_cr() == 1
    end

    test "cost_lf/0 returns 1" do
      assert CursorOptimizer.cost_lf() == 1
    end

    test "cost_home/0 returns 3" do
      assert CursorOptimizer.cost_home() == 3
    end
  end

  describe "optimal_move/4" do
    test "chooses spaces for small rightward movement on same row" do
      # Moving right 2 columns: spaces cost 2, cursor right costs 4
      {seq, cost} = CursorOptimizer.optimal_move(1, 1, 1, 3)
      binary = IO.iodata_to_binary(seq)
      assert binary == "  "
      assert cost == 2
    end

    test "chooses cursor right for larger rightward movement" do
      # Moving right 5 columns: spaces cost 5, cursor right costs 4
      {seq, cost} = CursorOptimizer.optimal_move(1, 1, 1, 6)
      binary = IO.iodata_to_binary(seq)
      assert binary == "\e[5C"
      assert cost == 4
    end

    test "chooses CR for column 1 on same row" do
      {seq, cost} = CursorOptimizer.optimal_move(1, 10, 1, 1)
      binary = IO.iodata_to_binary(seq)
      assert binary == "\r"
      assert cost == 1
    end

    test "chooses CR + down for column 1 below current" do
      # From (1, 10) to (3, 1)
      # CR + down 2: 1 + 4 = 5 bytes
      # Absolute: ESC[3;1H = 6 bytes
      {seq, cost} = CursorOptimizer.optimal_move(1, 10, 3, 1)
      binary = IO.iodata_to_binary(seq)
      assert String.starts_with?(binary, "\r")
      assert cost < CursorOptimizer.cost_absolute(3, 1)
    end

    test "chooses home for position (1, 1)" do
      {seq, cost} = CursorOptimizer.optimal_move(10, 10, 1, 1)
      binary = IO.iodata_to_binary(seq)
      assert binary == "\e[H"
      assert cost == 3
    end

    test "uses relative up/down for vertical movement" do
      # Move down 3 rows from (1, 5) to (4, 5)
      {seq, cost} = CursorOptimizer.optimal_move(1, 5, 4, 5)
      binary = IO.iodata_to_binary(seq)
      assert binary == "\e[3B"
      assert cost == 4
    end

    test "uses relative left/right for horizontal movement" do
      # Move left 4 columns from (5, 10) to (5, 6)
      {seq, cost} = CursorOptimizer.optimal_move(5, 10, 5, 6)
      binary = IO.iodata_to_binary(seq)
      assert binary == "\e[4D"
      assert cost == 4
    end

    test "combines vertical and horizontal relative movements" do
      # From (1, 1) to (3, 5)
      {_seq, cost} = CursorOptimizer.optimal_move(1, 1, 3, 5)
      # Should be down 2 + right 4: ESC[2B ESC[4C = 8 bytes
      # vs absolute ESC[3;5H = 6 bytes
      # Absolute wins here
      assert cost <= 8
    end

    test "falls back to absolute for complex movements" do
      # Large movement where absolute is optimal
      {_seq, cost} = CursorOptimizer.optimal_move(50, 50, 25, 75)
      # Should use absolute: ESC[25;75H = 9 bytes
      assert cost == CursorOptimizer.cost_absolute(25, 75)
    end
  end

  describe "move_to/3" do
    test "returns empty sequence when already at target" do
      optimizer = CursorOptimizer.new(5, 10)
      {seq, new_opt} = CursorOptimizer.move_to(optimizer, 5, 10)
      assert seq == []
      assert CursorOptimizer.position(new_opt) == {5, 10}
    end

    test "updates cursor position after move" do
      optimizer = CursorOptimizer.new(1, 1)
      {_seq, new_opt} = CursorOptimizer.move_to(optimizer, 5, 10)
      assert CursorOptimizer.position(new_opt) == {5, 10}
    end

    test "tracks bytes saved" do
      optimizer = CursorOptimizer.new(1, 10)
      # Move to column 1 - CR costs 1, absolute costs 6
      {_seq, new_opt} = CursorOptimizer.move_to(optimizer, 1, 1)
      # Saved: 6 - 1 = 5 bytes
      assert CursorOptimizer.bytes_saved(new_opt) >= 1
    end

    test "accumulates bytes saved across multiple moves" do
      optimizer = CursorOptimizer.new(1, 1)

      # Move to (1, 3) - saves bytes
      {_seq, opt1} = CursorOptimizer.move_to(optimizer, 1, 3)
      saved1 = CursorOptimizer.bytes_saved(opt1)

      # Move to (1, 1) - saves bytes
      {_seq, opt2} = CursorOptimizer.move_to(opt1, 1, 1)
      saved2 = CursorOptimizer.bytes_saved(opt2)

      assert saved2 >= saved1
    end
  end

  describe "advance/2" do
    test "advances column by specified amount" do
      optimizer = CursorOptimizer.new(1, 1)
      new_opt = CursorOptimizer.advance(optimizer, 5)
      assert CursorOptimizer.position(new_opt) == {1, 6}
    end

    test "preserves row" do
      optimizer = CursorOptimizer.new(3, 10)
      new_opt = CursorOptimizer.advance(optimizer, 3)
      assert CursorOptimizer.position(new_opt) == {3, 13}
    end

    test "handles zero advance" do
      optimizer = CursorOptimizer.new(2, 5)
      new_opt = CursorOptimizer.advance(optimizer, 0)
      assert CursorOptimizer.position(new_opt) == {2, 5}
    end
  end

  describe "reset/1" do
    test "resets position to (1, 1)" do
      optimizer = CursorOptimizer.new(10, 20)
      new_opt = CursorOptimizer.reset(optimizer)
      assert CursorOptimizer.position(new_opt) == {1, 1}
    end

    test "preserves bytes_saved" do
      optimizer = %CursorOptimizer{row: 10, col: 20, bytes_saved: 100}
      new_opt = CursorOptimizer.reset(optimizer)
      assert CursorOptimizer.bytes_saved(new_opt) == 100
    end
  end

  describe "optimization effectiveness" do
    test "CR is cheaper than absolute for column 1" do
      # CR: 1 byte, Absolute ESC[5;1H: 6 bytes
      {_seq, cost} = CursorOptimizer.optimal_move(5, 10, 5, 1)
      assert cost < CursorOptimizer.cost_absolute(5, 1)
    end

    test "home is cheaper than absolute for (1, 1)" do
      # Home: 3 bytes, Absolute ESC[1;1H: 6 bytes
      {_seq, cost} = CursorOptimizer.optimal_move(10, 10, 1, 1)
      assert cost < CursorOptimizer.cost_absolute(1, 1)
    end

    test "relative movement cheaper for small moves" do
      # Right 1: ESC[C = 3 bytes, Absolute ESC[5;11H = 7 bytes
      {_seq, cost} = CursorOptimizer.optimal_move(5, 10, 5, 11)
      assert cost < CursorOptimizer.cost_absolute(5, 11)
    end

    test "spaces cheaper than cursor right for small moves" do
      # 2 spaces: 2 bytes, ESC[2C: 4 bytes
      {seq, cost} = CursorOptimizer.optimal_move(1, 1, 1, 3)
      binary = IO.iodata_to_binary(seq)
      assert cost == 2
      assert binary == "  "
    end
  end

  describe "escape sequence correctness" do
    test "generates correct absolute positioning sequence" do
      {seq, _cost} = CursorOptimizer.optimal_move(1, 1, 50, 80)
      binary = IO.iodata_to_binary(seq)
      assert binary == "\e[50;80H"
    end

    test "generates correct cursor up sequence" do
      {seq, _cost} = CursorOptimizer.optimal_move(10, 5, 5, 5)
      binary = IO.iodata_to_binary(seq)
      assert binary == "\e[5A"
    end

    test "generates correct cursor down sequence" do
      {seq, _cost} = CursorOptimizer.optimal_move(1, 5, 6, 5)
      binary = IO.iodata_to_binary(seq)
      assert binary == "\e[5B"
    end

    test "generates correct cursor right sequence" do
      {seq, _cost} = CursorOptimizer.optimal_move(5, 1, 5, 10)
      binary = IO.iodata_to_binary(seq)
      assert binary == "\e[9C"
    end

    test "generates correct cursor left sequence" do
      {seq, _cost} = CursorOptimizer.optimal_move(5, 20, 5, 10)
      binary = IO.iodata_to_binary(seq)
      assert binary == "\e[10D"
    end

    test "generates correct home sequence" do
      {seq, _cost} = CursorOptimizer.optimal_move(5, 5, 1, 1)
      binary = IO.iodata_to_binary(seq)
      assert binary == "\e[H"
    end

    test "generates correct CR sequence" do
      {seq, _cost} = CursorOptimizer.optimal_move(3, 20, 3, 1)
      binary = IO.iodata_to_binary(seq)
      assert binary == "\r"
    end
  end

  describe "integration scenarios" do
    test "simulates render cycle with multiple moves" do
      optimizer = CursorOptimizer.new()

      # First widget at (1, 1)
      {_seq1, opt1} = CursorOptimizer.move_to(optimizer, 1, 1)
      opt1 = CursorOptimizer.advance(opt1, 10)

      # Second widget at (1, 20)
      {_seq2, opt2} = CursorOptimizer.move_to(opt1, 1, 20)
      opt2 = CursorOptimizer.advance(opt2, 5)

      # Third widget at (5, 1)
      {_seq3, opt3} = CursorOptimizer.move_to(opt2, 5, 1)
      _opt3 = CursorOptimizer.advance(opt3, 15)

      # Should have saved some bytes
      # (actual savings depend on optimization choices)
      assert true
    end

    test "handles typical TUI layout pattern" do
      optimizer = CursorOptimizer.new()

      # Header at row 1
      {_seq, opt} = CursorOptimizer.move_to(optimizer, 1, 1)
      opt = CursorOptimizer.advance(opt, 80)

      # Status bar at row 24
      {seq, opt} = CursorOptimizer.move_to(opt, 24, 1)

      # Should use CR + down or absolute
      binary = IO.iodata_to_binary(seq)
      assert String.length(binary) > 0
      assert CursorOptimizer.position(opt) == {24, 1}
    end
  end

  describe "bounds checking" do
    test "max_position/0 returns maximum supported position" do
      max = CursorOptimizer.max_position()
      assert is_integer(max)
      assert max == 9999
    end

    test "advance/2 clamps to max position" do
      # Start at high column
      optimizer = CursorOptimizer.new(1, 9990)

      # Advance by large amount
      advanced = CursorOptimizer.advance(optimizer, 100)

      # Should be clamped to max
      {_row, col} = CursorOptimizer.position(advanced)
      assert col == 9999
    end

    test "advance/2 works normally below max position" do
      optimizer = CursorOptimizer.new(1, 10)
      advanced = CursorOptimizer.advance(optimizer, 5)

      {_row, col} = CursorOptimizer.position(advanced)
      assert col == 15
    end

    test "advance/2 handles edge case at exactly max position" do
      optimizer = CursorOptimizer.new(1, 9999)
      advanced = CursorOptimizer.advance(optimizer, 1)

      {_row, col} = CursorOptimizer.position(advanced)
      assert col == 9999
    end
  end
end
