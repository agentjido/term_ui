defmodule TermUI.CursorOptimizer do
  @moduledoc false

  @type t :: %__MODULE__{
          row: pos_integer(),
          col: pos_integer(),
          bytes_saved: non_neg_integer()
        }

  defstruct row: 1,
            col: 1,
            bytes_saved: 0

  # Cost threshold for using spaces instead of cursor right
  @space_threshold 3

  # Maximum cursor position supported by most terminals.
  # ANSI escape sequence parameters beyond this may be truncated or
  # cause undefined behavior on some terminals.
  @max_cursor_pos 9999

  @doc """
  Creates a new cursor optimizer with cursor at position (1, 1).
  """
  @spec new() :: %__MODULE__{row: 1, col: 1, bytes_saved: 0}
  def new do
    %__MODULE__{row: 1, col: 1, bytes_saved: 0}
  end

  @doc """
  Creates a cursor optimizer with cursor at the specified position.
  """
  @spec new(pos_integer(), pos_integer()) :: t()
  def new(row, col) when row >= 1 and col >= 1 do
    %__MODULE__{row: row, col: col}
  end

  @doc """
  Moves the cursor to the target position using the optimal movement sequence.

  Returns `{sequence, updated_optimizer}` where sequence is iodata containing
  the escape sequences for the movement.

  ## Examples

      iex> optimizer = CursorOptimizer.new()
      iex> {seq, _opt} = CursorOptimizer.move_to(optimizer, 1, 5)
      iex> IO.iodata_to_binary(seq)
      "\\e[5C"
  """
  @spec move_to(t(), pos_integer(), pos_integer()) :: {iodata(), t()}
  def move_to(%__MODULE__{} = optimizer, target_row, target_col) do
    if optimizer.row == target_row and optimizer.col == target_col do
      # Already at target position
      {[], optimizer}
    else
      {sequence, cost} = optimal_move(optimizer.row, optimizer.col, target_row, target_col)
      naive_cost = cost_absolute(target_row, target_col)
      saved = max(0, naive_cost - cost)

      new_optimizer = %{
        optimizer
        | row: target_row,
          col: target_col,
          bytes_saved: optimizer.bytes_saved + saved
      }

      {sequence, new_optimizer}
    end
  end

  @doc """
  Advances the cursor position after text output.

  Call this after outputting text to keep cursor position synchronized.
  The new column position is clamped to `@max_cursor_pos` to prevent
  integer overflow issues with ANSI escape sequences.
  """
  @spec advance(t(), non_neg_integer()) :: t()
  def advance(%__MODULE__{} = optimizer, cols) do
    new_col = min(optimizer.col + cols, @max_cursor_pos)
    %{optimizer | col: new_col}
  end

  @doc """
  Returns the current cursor position as `{row, col}`.
  """
  @spec position(t()) :: {pos_integer(), pos_integer()}
  def position(%__MODULE__{row: row, col: col}) do
    {row, col}
  end

  @doc """
  Returns the total bytes saved through optimization.
  """
  @spec bytes_saved(t()) :: non_neg_integer()
  def bytes_saved(%__MODULE__{bytes_saved: saved}) do
    saved
  end

  @doc """
  Resets the cursor position to (1, 1).
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = optimizer) do
    %{optimizer | row: 1, col: 1}
  end

  @doc """
  Returns the maximum cursor position supported.

  Positions beyond this value may cause undefined behavior on some terminals.
  """
  @spec max_position() :: 9999
  def max_position, do: @max_cursor_pos

  # Cost calculation functions

  @doc """
  Calculates the byte cost of absolute positioning.

  `ESC[{row};{col}H` costs 4 + digits(row) + digits(col) bytes.
  """
  @spec cost_absolute(pos_integer(), pos_integer()) :: pos_integer()
  def cost_absolute(row, col) do
    # ESC [ row ; col H
    # 1 + 1 + digits(row) + 1 + digits(col) + 1
    4 + digits(row) + digits(col)
  end

  @doc """
  Calculates the byte cost of moving cursor up.

  `ESC[{n}A` costs 3 + digits(n) bytes, or 3 bytes for n=1.
  """
  @spec cost_up(pos_integer()) :: pos_integer()
  def cost_up(1), do: 3
  def cost_up(n) when n > 1, do: 3 + digits(n)

  @doc """
  Calculates the byte cost of moving cursor down.

  `ESC[{n}B` costs 3 + digits(n) bytes, or 3 bytes for n=1.
  """
  @spec cost_down(pos_integer()) :: pos_integer()
  def cost_down(1), do: 3
  def cost_down(n) when n > 1, do: 3 + digits(n)

  @doc """
  Calculates the byte cost of moving cursor right.

  `ESC[{n}C` costs 3 + digits(n) bytes, or 3 bytes for n=1.
  """
  @spec cost_right(pos_integer()) :: pos_integer()
  def cost_right(1), do: 3
  def cost_right(n) when n > 1, do: 3 + digits(n)

  @doc """
  Calculates the byte cost of moving cursor left.

  `ESC[{n}D` costs 3 + digits(n) bytes, or 3 bytes for n=1.
  """
  @spec cost_left(pos_integer()) :: pos_integer()
  def cost_left(1), do: 3
  def cost_left(n) when n > 1, do: 3 + digits(n)

  @doc """
  Calculates the byte cost of carriage return (move to column 1).
  """
  @spec cost_cr() :: 1
  def cost_cr, do: 1

  @doc """
  Calculates the byte cost of newline (move down one row).
  """
  @spec cost_lf() :: 1
  def cost_lf, do: 1

  @doc """
  Calculates the byte cost of home (move to 1,1).
  """
  @spec cost_home() :: 3
  def cost_home, do: 3

  # Optimal movement selection

  @doc """
  Finds the optimal movement sequence from current to target position.

  Returns `{sequence, cost}` where sequence is iodata.
  """
  @spec optimal_move(pos_integer(), pos_integer(), pos_integer(), pos_integer()) ::
          {iodata(), pos_integer()}
  def optimal_move(from_row, from_col, to_row, to_col) do
    options = generate_options(from_row, from_col, to_row, to_col)

    # Find minimum cost option
    Enum.min_by(options, fn {_seq, cost} -> cost end)
  end

  defp generate_options(from_row, from_col, to_row, to_col) do
    row_diff = to_row - from_row
    col_diff = to_col - from_col

    [absolute_option(to_row, to_col)]
    |> add_relative_options(row_diff, col_diff)
    |> add_cr_options(to_col, row_diff)
    |> add_cr_col_options(row_diff, to_col, from_col)
    |> add_home_option(to_row, to_col)
    |> add_space_option(row_diff, col_diff)
    |> add_newline_options(row_diff, from_col, to_col)
  end

  defp add_relative_options(options, row_diff, col_diff) do
    options ++ relative_options(row_diff, col_diff)
  end

  defp add_cr_options(options, 1, row_diff), do: options ++ cr_options(row_diff)
  defp add_cr_options(options, _to_col, _row_diff), do: options

  defp add_cr_col_options(options, row_diff, to_col, from_col) do
    options ++ cr_col_options(row_diff, to_col, from_col)
  end

  defp add_home_option(options, 1, 1), do: [home_option() | options]
  defp add_home_option(options, _to_row, _to_col), do: options

  defp add_space_option(options, 0, col_diff)
       when col_diff > 0 and col_diff <= @space_threshold do
    [space_option(col_diff) | options]
  end

  defp add_space_option(options, _row_diff, _col_diff), do: options

  # Use ANSI cursor-down instead of bare \n to prevent staircase rendering
  # when OPOST is disabled (OTP 28 raw mode, stty raw)
  defp add_newline_options(options, row_diff, 1, 1) when row_diff > 0 do
    {v_seq, v_cost} = vertical_sequence(row_diff)
    [{v_seq, v_cost} | options]
  end

  defp add_newline_options(options, _row_diff, _from_col, _to_col), do: options

  defp absolute_option(row, col) do
    seq = ["\e[", Integer.to_string(row), ";", Integer.to_string(col), "H"]
    {seq, cost_absolute(row, col)}
  end

  defp relative_options(row_diff, col_diff) do
    options = []

    # Vertical + horizontal relative movement
    if row_diff != 0 or col_diff != 0 do
      {v_seq, v_cost} = vertical_sequence(row_diff)
      {h_seq, h_cost} = horizontal_sequence(col_diff)

      if v_cost + h_cost < 100 do
        [{[v_seq, h_seq], v_cost + h_cost} | options]
      else
        options
      end
    else
      options
    end
  end

  defp cr_options(row_diff) do
    # CR alone for same row
    if row_diff == 0 do
      [{"\r", cost_cr()}]
    else
      # CR + vertical movement
      options = []

      # CR + ANSI cursor movement (no bare \n to avoid staircase rendering)
      {v_seq, v_cost} = vertical_sequence(row_diff)
      [{["\r", v_seq], cost_cr() + v_cost} | options]
    end
  end

  defp cr_col_options(row_diff, to_col, _from_col) do
    # CR + vertical + horizontal (for non-column-1 targets)
    if to_col > 1 do
      cr_cost = cost_cr()
      {v_seq, v_cost} = vertical_sequence(row_diff)
      h_diff = to_col - 1

      if h_diff > 0 and h_diff <= @space_threshold do
        # Use spaces
        [{["\r", v_seq, String.duplicate(" ", h_diff)], cr_cost + v_cost + h_diff}]
      else
        {h_seq, h_cost} = horizontal_sequence(h_diff)
        [{["\r", v_seq, h_seq], cr_cost + v_cost + h_cost}]
      end
    else
      []
    end
  end

  defp home_option do
    {"\e[H", cost_home()}
  end

  defp space_option(n) do
    {String.duplicate(" ", n), n}
  end

  defp vertical_sequence(0), do: {[], 0}

  defp vertical_sequence(n) when n > 0 do
    # Move down
    if n == 1 do
      {"\e[B", 3}
    else
      {["\e[", Integer.to_string(n), "B"], cost_down(n)}
    end
  end

  defp vertical_sequence(n) when n < 0 do
    # Move up
    abs_n = abs(n)

    if abs_n == 1 do
      {"\e[A", 3}
    else
      {["\e[", Integer.to_string(abs_n), "A"], cost_up(abs_n)}
    end
  end

  defp horizontal_sequence(0), do: {[], 0}

  defp horizontal_sequence(n) when n > 0 do
    # Move right
    if n == 1 do
      {"\e[C", 3}
    else
      {["\e[", Integer.to_string(n), "C"], cost_right(n)}
    end
  end

  defp horizontal_sequence(n) when n < 0 do
    # Move left
    abs_n = abs(n)

    if abs_n == 1 do
      {"\e[D", 3}
    else
      {["\e[", Integer.to_string(abs_n), "D"], cost_left(abs_n)}
    end
  end

  defp digits(n) when n < 10, do: 1
  defp digits(n) when n < 100, do: 2
  defp digits(n) when n < 1000, do: 3
  defp digits(n), do: length(Integer.digits(n))
end
