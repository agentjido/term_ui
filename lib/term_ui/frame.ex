defmodule TermUI.Frame do
  @moduledoc """
  A complete terminal frame.

  A frame is the only render value accepted by `TermUI.Runtime`. It stores
  terminal cells in a sparse map. Missing positions are default blank cells.
  Frame dimensions and cursor coordinates are one-based. The cursor tuple is
  `{column, row}`.
  """

  alias TermUI.{Cell, DisplayWidth, Style}

  @max_rows 500
  @max_columns 1000

  @type cursor :: {pos_integer(), pos_integer()} | nil
  @type position :: {row :: pos_integer(), column :: pos_integer()}
  @type span :: String.t() | {iodata(), Style.t()}
  @type row :: iodata() | [span()]

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer(),
          cells: %{optional(position()) => Cell.t()},
          cursor: cursor()
        }

  @coordinate_schema Zoi.integer() |> Zoi.positive()
  @position_schema Zoi.tuple({@coordinate_schema, @coordinate_schema})
  @cursor_schema Zoi.union([@position_schema, Zoi.literal(nil)])

  @schema Zoi.struct(__MODULE__, %{
            width: @coordinate_schema |> Zoi.lte(@max_columns),
            height: @coordinate_schema |> Zoi.lte(@max_rows),
            cells: Zoi.map(@position_schema, Cell.schema()) |> Zoi.default(%{}),
            cursor: @cursor_schema |> Zoi.default(nil)
          })
          |> Zoi.refine({__MODULE__, :validate_schema, []})

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for complete terminal frames."
  @spec schema() :: Zoi.schema()
  def schema, do: @schema

  @doc false
  @spec validate_schema(t(), keyword()) :: :ok | {:error, String.t()}
  def validate_schema(%__MODULE__{} = frame, _opts) do
    cursor_in_bounds? =
      case frame.cursor do
        nil -> true
        {column, row} -> column <= frame.width and row <= frame.height
      end

    cells_in_bounds? =
      Enum.all?(frame.cells, fn {{row, column}, _cell} ->
        row <= frame.height and column <= frame.width
      end)

    if cursor_in_bounds? and cells_in_bounds?,
      do: :ok,
      else: {:error, "frame cursor and cells must be inside the frame dimensions"}
  end

  @doc "Creates an empty frame."
  @spec new(pos_integer(), pos_integer(), keyword()) :: t()
  def new(width, height, opts \\ []) do
    validate_dimensions!(width, height)

    %__MODULE__{
      width: width,
      height: height,
      cells: normalize_cells(Keyword.get(opts, :cells, %{}), width, height),
      cursor: normalize_cursor(Keyword.get(opts, :cursor), width, height)
    }
  end

  @doc false
  @spec clamp_dimensions({pos_integer(), pos_integer()}) :: {pos_integer(), pos_integer()}
  def clamp_dimensions({width, height})
      when is_integer(width) and width > 0 and is_integer(height) and height > 0,
      do: {min(width, @max_columns), min(height, @max_rows)}

  @doc "Builds a frame from plain rows or styled spans."
  @spec from_rows([row()], pos_integer(), pos_integer(), keyword()) :: t()
  def from_rows(rows, width, height, opts \\ []) when is_list(rows) do
    frame = new(width, height, opts)

    rows
    |> Enum.take(height)
    |> Enum.with_index(1)
    |> Enum.reduce(frame, fn {row, row_index}, acc -> put_row(acc, row_index, row) end)
  end

  @doc "Writes one row. Content outside the frame is clipped."
  @spec put_row(t(), pos_integer(), row()) :: t()
  def put_row(%__MODULE__{} = frame, row, content) when row >= 1 and row <= frame.height do
    spans = normalize_spans(content)
    cells = clear_row(frame.cells, row)

    {cells, _column} =
      Enum.reduce(spans, {cells, 1}, fn {text, style}, {cells, column} ->
        write_text(cells, frame.width, row, column, IO.iodata_to_binary(text), style)
      end)

    %{frame | cells: cells}
  end

  def put_row(%__MODULE__{} = frame, _row, _content), do: frame

  @doc "Puts one cell. Empty default cells remain implicit."
  @spec put_cell(t(), pos_integer(), pos_integer(), Cell.t()) :: t()
  def put_cell(%__MODULE__{} = frame, row, column, %Cell{} = cell)
      when row >= 1 and row <= frame.height and column >= 1 and column <= frame.width do
    cells = put_bounded_cell(frame.cells, row, column, normalize_cell(cell), frame.width)
    %{frame | cells: cells}
  end

  def put_cell(%__MODULE__{} = frame, _row, _column, %Cell{}), do: frame

  @doc "Writes consecutive rows starting at a one-based row."
  @spec put_rows(t(), pos_integer(), [row()]) :: t()
  def put_rows(%__MODULE__{} = frame, start_row, rows)
      when is_integer(start_row) and start_row > 0 and is_list(rows) do
    rows
    |> Enum.with_index(start_row)
    |> Enum.reduce(frame, fn {content, row}, acc -> put_row(acc, row, content) end)
  end

  @doc "Overlays one frame at a one-based column and row."
  @spec overlay(t(), t(), pos_integer(), pos_integer()) :: t()
  def overlay(%__MODULE__{} = base, %__MODULE__{} = child, column, row)
      when is_integer(column) and column > 0 and is_integer(row) and row > 0 do
    if column > base.width or row > base.height do
      base
    else
      do_overlay(base, child, column, row)
    end
  end

  defp do_overlay(base, child, column, row) do
    cleared = clear_region(base, column, row, child.width, child.height)

    frame =
      Enum.reduce(child.cells, cleared, fn {{child_row, child_column}, cell}, acc ->
        put_cell(acc, row + child_row - 1, column + child_column - 1, cell)
      end)

    case child.cursor do
      nil ->
        frame

      {child_column, child_row} ->
        %{
          frame
          | cursor:
              normalize_cursor(
                {column + child_column - 1, row + child_row - 1},
                base.width,
                base.height
              )
        }
    end
  end

  @doc "Gets one cell."
  @spec cell(t(), pos_integer(), pos_integer()) :: Cell.t()
  def cell(%__MODULE__{} = frame, row, column) do
    Map.get(frame.cells, {row, column}, Cell.empty())
  end

  @doc "Returns one row as terminal text, including trailing blanks."
  @spec row_text(t(), pos_integer()) :: String.t()
  def row_text(%__MODULE__{} = frame, row) when row >= 1 and row <= frame.height do
    1..frame.width
    |> Enum.map_join(fn column ->
      case cell(frame, row, column) do
        %Cell{wide_placeholder: true} -> ""
        %Cell{char: char} -> char
      end
    end)
    |> DisplayWidth.pad(frame.width)
  end

  def row_text(%__MODULE__{}, _row), do: ""

  @doc "Returns all visible cells in backend row and column format."
  @spec cells(t()) :: [{position(), TermUI.Backend.cell()}]
  def cells(%__MODULE__{} = frame) do
    frame.cells
    |> Enum.flat_map(fn
      {_position, %Cell{wide_placeholder: true}} -> []
      {position, cell} -> [{position, backend_cell(cell)}]
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  @doc "Returns the changed backend cells between two frames."
  @spec diff(t() | nil, t()) :: [{position(), TermUI.Backend.cell()}]
  def diff(nil, %__MODULE__{} = current), do: cells(current)

  def diff(%__MODULE__{} = previous, %__MODULE__{} = current) do
    previous.cells
    |> Map.keys()
    |> Kernel.++(Map.keys(current.cells))
    |> Enum.uniq()
    |> Enum.filter(fn {row, column} -> row <= current.height and column <= current.width end)
    |> Enum.reduce([], fn position, changes ->
      old_cell = Map.get(previous.cells, position, Cell.empty())
      new_cell = Map.get(current.cells, position, Cell.empty())

      cond do
        Cell.equal?(old_cell, new_cell) ->
          changes

        new_cell.wide_placeholder ->
          changes

        Cell.empty?(new_cell) ->
          [{position, {" ", :default, :default, []}} | changes]

        true ->
          [{position, backend_cell(new_cell)} | changes]
      end
    end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  @doc "Fits text to one display row."
  @spec fit(iodata(), non_neg_integer()) :: String.t()
  def fit(_text, 0), do: ""

  def fit(text, width) when width > 0 do
    text = text |> IO.iodata_to_binary() |> String.replace(["\r", "\n"], " ")
    {content, _width} = DisplayWidth.truncate(text, width)
    DisplayWidth.pad(content, width)
  end

  @doc "Wraps text at display-width boundaries."
  @spec wrap(String.t(), pos_integer()) :: [String.t()]
  def wrap(text, width) when is_binary(text) and width > 0 do
    text
    |> String.split("\n", trim: false)
    |> Enum.flat_map(&wrap_line(&1, width))
  end

  defp normalize_spans(content) when is_binary(content), do: [{content, Style.new()}]

  defp normalize_spans(content) when is_list(content) do
    if :io_lib.printable_unicode_list(content) do
      [{IO.iodata_to_binary(content), Style.new()}]
    else
      Enum.map(content, fn
        {text, %Style{} = style} -> {text, style}
        text -> {text, Style.new()}
      end)
    end
  end

  defp normalize_spans(content), do: [{to_string(content), Style.new()}]

  defp write_text(cells, width, row, start_column, text, style) do
    text
    |> String.replace(["\r", "\n"], " ")
    |> String.graphemes()
    |> Enum.reduce_while({cells, start_column}, fn grapheme, {cells, column} ->
      cell = Style.to_cell(style, grapheme)
      cell_width = Cell.width(cell)

      cond do
        column > width ->
          {:halt, {cells, column}}

        cell_width == 2 and column == width ->
          {:halt, {cells, column}}

        cell_width == 2 ->
          cells = put_bounded_cell(cells, row, column, cell, width)
          {:cont, {cells, column + 2}}

        true ->
          {:cont, {put_bounded_cell(cells, row, column, cell, width), column + 1}}
      end
    end)
  end

  defp normalize_cells(cells, width, height) when is_map(cells) do
    cells
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(%{}, fn
      {{row, column}, %Cell{} = cell}, acc
      when row >= 1 and row <= height and column >= 1 and column <= width ->
        put_bounded_cell(acc, row, column, normalize_cell(cell), width)

      _entry, acc ->
        acc
    end)
  end

  defp normalize_cells(cells, width, height) when is_list(cells) do
    cells
    |> Map.new(fn
      {row, column, %Cell{} = cell} -> {{row, column}, cell}
      {{row, column}, %Cell{} = cell} -> {{row, column}, cell}
    end)
    |> normalize_cells(width, height)
  end

  defp put_sparse(cells, position, %Cell{} = cell) do
    if Cell.empty?(cell), do: Map.delete(cells, position), else: Map.put(cells, position, cell)
  end

  defp put_bounded_cell(cells, row, column, %Cell{wide_placeholder: true}, _width) do
    case Map.get(cells, {row, column - 1}) do
      %Cell{width: 2, wide_placeholder: false} = primary ->
        put_sparse(cells, {row, column}, Cell.wide_placeholder(primary))

      _other ->
        Map.delete(cells, {row, column})
    end
  end

  defp put_bounded_cell(cells, row, column, %Cell{width: 2} = cell, width) do
    cells = clear_cell_footprint(cells, row, column)

    if column < width do
      cells
      |> clear_cell_footprint(row, column + 1)
      |> put_sparse({row, column}, cell)
      |> put_sparse({row, column + 1}, Cell.wide_placeholder(cell))
    else
      cells
    end
  end

  defp put_bounded_cell(cells, row, column, %Cell{} = cell, _width) do
    cells
    |> clear_cell_footprint(row, column)
    |> put_sparse({row, column}, cell)
  end

  defp clear_cell_footprint(cells, row, column) do
    target = Map.get(cells, {row, column})
    previous = Map.get(cells, {row, column - 1})
    target_wide? = wide_primary?(target)
    previous_wide? = wide_primary?(previous)

    positions =
      [{row, column}]
      |> maybe_add_position(target_wide?, {row, column + 1})
      |> maybe_add_position(previous_wide?, {row, column - 1})

    Map.drop(cells, positions)
  end

  defp wide_primary?(%Cell{width: 2, wide_placeholder: false}), do: true
  defp wide_primary?(_cell), do: false

  defp maybe_add_position(positions, true, position), do: [position | positions]
  defp maybe_add_position(positions, false, _position), do: positions

  defp clear_row(cells, row) do
    Map.reject(cells, fn {{cell_row, _column}, _cell} -> cell_row == row end)
  end

  defp clear_region(frame, column, row, width, height) do
    positions =
      for target_row <- row..min(row + height - 1, frame.height),
          target_column <- column..min(column + width - 1, frame.width),
          do: {target_row, target_column}

    cells =
      Enum.reduce(positions, frame.cells, fn {target_row, target_column}, cells ->
        clear_cell_footprint(cells, target_row, target_column)
      end)

    %{frame | cells: cells}
  end

  defp normalize_cell(%Cell{wide_placeholder: true} = cell) do
    " "
    |> Cell.new(fg: cell.fg, bg: cell.bg, attrs: cell.attrs)
    |> Cell.wide_placeholder()
  end

  defp normalize_cell(%Cell{} = cell) do
    Cell.new(cell.char, fg: cell.fg, bg: cell.bg, attrs: cell.attrs)
  end

  defp normalize_cursor(nil, _width, _height), do: nil

  defp normalize_cursor({column, row}, width, height)
       when is_integer(column) and is_integer(row) do
    {column |> max(1) |> min(width), row |> max(1) |> min(height)}
  end

  defp normalize_cursor(_cursor, _width, _height), do: nil

  defp backend_cell(%Cell{char: char, fg: foreground, bg: background, attrs: attrs}) do
    {char, foreground || :default, background || :default,
     attrs |> MapSet.to_list() |> Enum.sort()}
  end

  defp wrap_line("", _width), do: [""]

  defp wrap_line(line, width) do
    line
    |> String.graphemes()
    |> Enum.reduce({[], "", 0}, fn grapheme, {lines, current, current_width} ->
      grapheme_width = max(DisplayWidth.width(grapheme), 0)

      if current != "" and current_width + grapheme_width > width do
        {[current | lines], grapheme, grapheme_width}
      else
        {lines, current <> grapheme, current_width + grapheme_width}
      end
    end)
    |> then(fn {lines, current, _current_width} -> Enum.reverse([current | lines]) end)
  end

  defp validate_dimensions!(width, height)
       when is_integer(width) and width > 0 and width <= @max_columns and
              is_integer(height) and height > 0 and height <= @max_rows,
       do: :ok

  defp validate_dimensions!(width, height) do
    raise ArgumentError,
          "frame dimensions must be within 1..#{@max_columns} by 1..#{@max_rows}, got #{inspect({width, height})}"
  end
end
