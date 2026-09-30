defmodule TermUI.Widget.Canvas do
  @moduledoc "A pure character and braille-dot drawing canvas."

  @behaviour TermUI.Widget

  import Bitwise, only: [<<<: 2]

  alias TermUI.{Cell, Frame, Style}

  # Dialyzer loses the MapSet opaque type when the dot set becomes empty.
  @dialyzer {:nowarn_function, clear: 1}

  @braille_base 0x2800
  @dot_bits %{
    {0, 0} => 0,
    {0, 1} => 1,
    {0, 2} => 2,
    {1, 0} => 3,
    {1, 1} => 4,
    {1, 2} => 5,
    {0, 3} => 6,
    {1, 3} => 7
  }

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          cells: map(),
          dots: MapSet.t({non_neg_integer(), non_neg_integer()}),
          style: Style.t()
        }
  defstruct width: 1,
            height: 1,
            cells: %{},
            dots: MapSet.new(),
            style: %Style{}

  @impl true
  def init(opts),
    do: %__MODULE__{
      width: max(Keyword.get(opts, :width, 1), 1),
      height: max(Keyword.get(opts, :height, 1), 1),
      style: Keyword.get(opts, :style, Style.new())
    }

  @impl true
  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, height}) do
    frame = Frame.new(width, height)

    frame =
      Enum.reduce(state.cells, frame, fn {{x, y}, cell}, acc ->
        Frame.put_cell(acc, y + 1, x + 1, cell)
      end)

    Enum.reduce(braille_cells(state.dots), frame, fn {{x, y}, char}, acc ->
      Frame.put_cell(acc, y + 1, x + 1, Style.to_cell(state.style, char))
    end)
  end

  @doc "Clears characters and braille dots."
  @spec clear(t()) :: t()
  def clear(state), do: %{state | cells: %{}, dots: MapSet.new()}

  @doc "Writes one zero-based character cell."
  @spec set_char(t(), non_neg_integer(), non_neg_integer(), String.t(), Style.t() | nil) :: t()
  def set_char(state, x, y, char, style \\ nil) when x >= 0 and y >= 0 do
    if x < state.width and y < state.height do
      cell = Style.to_cell(style || state.style, char)

      %{
        state
        | cells:
            if(Cell.empty?(cell),
              do: Map.delete(state.cells, {x, y}),
              else: Map.put(state.cells, {x, y}, cell)
            )
      }
    else
      state
    end
  end

  @doc "Draws text from one zero-based position."
  @spec draw_text(t(), non_neg_integer(), non_neg_integer(), iodata(), Style.t() | nil) :: t()
  def draw_text(state, x, y, text, style \\ nil),
    do:
      text
      |> IO.iodata_to_binary()
      |> String.graphemes()
      |> Enum.reduce({state, x}, fn char, {canvas, column} ->
        cell = Style.to_cell(style || canvas.style, char)
        {set_char(canvas, column, y, char, style), column + Cell.width(cell)}
      end)
      |> elem(0)

  @doc "Draws a character line with Bresenham's algorithm."
  @spec draw_line(t(), integer(), integer(), integer(), integer(), String.t()) :: t()
  def draw_line(state, x0, y0, x1, y1, char \\ "•") do
    points(x0, y0, x1, y1) |> Enum.reduce(state, fn {x, y}, acc -> set_char(acc, x, y, char) end)
  end

  @doc "Draws a rectangle."
  @spec draw_rect(t(), non_neg_integer(), non_neg_integer(), pos_integer(), pos_integer()) :: t()
  def draw_rect(state, x, y, width, height) do
    state
    |> draw_line(x, y, x + width - 1, y, "─")
    |> draw_line(x, y + height - 1, x + width - 1, y + height - 1, "─")
    |> draw_line(x, y, x, y + height - 1, "│")
    |> draw_line(x + width - 1, y, x + width - 1, y + height - 1, "│")
    |> set_char(x, y, "┌")
    |> set_char(x + width - 1, y, "┐")
    |> set_char(x, y + height - 1, "└")
    |> set_char(x + width - 1, y + height - 1, "┘")
  end

  @doc "Sets one zero-based braille dot."
  @spec set_dot(t(), non_neg_integer(), non_neg_integer()) :: t()
  def set_dot(state, x, y), do: %{state | dots: MapSet.put(state.dots, {x, y})}

  @doc "Clears one zero-based braille dot."
  @spec clear_dot(t(), non_neg_integer(), non_neg_integer()) :: t()
  def clear_dot(state, x, y), do: %{state | dots: MapSet.delete(state.dots, {x, y})}

  @doc "Draws a line in braille-dot coordinates."
  @spec draw_braille_line(t(), integer(), integer(), integer(), integer()) :: t()
  def draw_braille_line(state, x0, y0, x1, y1),
    do:
      points(x0, y0, x1, y1)
      |> Enum.reduce(state, fn {x, y}, acc ->
        if x >= 0 and y >= 0, do: set_dot(acc, x, y), else: acc
      end)

  @doc "Returns braille-dot dimensions."
  @spec braille_resolution(t()) :: {pos_integer(), pos_integer()}
  def braille_resolution(state), do: {state.width * 2, state.height * 4}

  @doc "Resizes and clips canvas data."
  @spec resize(t(), pos_integer(), pos_integer()) :: t()
  def resize(state, width, height) do
    cells = Map.filter(state.cells, fn {{x, y}, _cell} -> x < width and y < height end)

    dots =
      Enum.reduce(state.dots, MapSet.new(), fn {x, y} = dot, acc ->
        if x < width * 2 and y < height * 4, do: MapSet.put(acc, dot), else: acc
      end)

    %{state | width: width, height: height, cells: cells, dots: dots}
  end

  defp braille_cells(dots) do
    Enum.reduce(dots, %{}, fn {x, y}, cells ->
      position = {div(x, 2), div(y, 4)}
      bit = Map.fetch!(@dot_bits, {rem(x, 2), rem(y, 4)})
      Map.update(cells, position, 1 <<< bit, &Bitwise.bor(&1, 1 <<< bit))
    end)
    |> Map.new(fn {position, bits} -> {position, <<@braille_base + bits::utf8>>} end)
  end

  defp points(x0, y0, x1, y1),
    do:
      do_points(
        {x0, y0},
        {x1, y1},
        {abs(x1 - x0), if(x0 < x1, do: 1, else: -1), -abs(y1 - y0), if(y0 < y1, do: 1, else: -1)},
        abs(x1 - x0) - abs(y1 - y0),
        []
      )

  defp do_points({x, y}, {x1, y1} = destination, {dx, sx, dy, sy} = steps, error, points) do
    points = [{x, y} | points]

    if x == x1 and y == y1 do
      Enum.reverse(points)
    else
      doubled = 2 * error
      {x, error} = if doubled >= dy, do: {x + sx, error + dy}, else: {x, error}
      {y, error} = if doubled <= dx, do: {y + sy, error + dx}, else: {y, error}
      do_points({x, y}, destination, steps, error, points)
    end
  end
end
