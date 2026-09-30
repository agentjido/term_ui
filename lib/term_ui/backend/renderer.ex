defmodule TermUI.Backend.Renderer do
  @moduledoc false

  alias TermUI.{ANSI, Cell}
  alias TermUI.Color.Converter

  @unicode_chars TermUI.CharacterSet.get(:unicode)
  @ascii_chars TermUI.CharacterSet.get(:ascii)

  @unicode_to_ascii_map (
                          list_keys = [:bar_levels, :sparkline_levels, :spinner_frames]
                          keys = TermUI.CharacterSet.keys() -- list_keys

                          base =
                            Map.new(keys, fn key -> {@unicode_chars[key], @ascii_chars[key]} end)

                          levels =
                            [:bar_levels, :sparkline_levels]
                            |> Enum.flat_map(fn key ->
                              unicode_levels = @unicode_chars[key]
                              ascii_levels = @ascii_chars[key]
                              unicode_max = max(length(unicode_levels) - 1, 1)
                              ascii_max = max(length(ascii_levels) - 1, 0)

                              unicode_levels
                              |> Enum.with_index()
                              |> Enum.map(fn {character, index} ->
                                ascii_index = round(index * ascii_max / unicode_max)
                                {character, Enum.at(ascii_levels, ascii_index)}
                              end)
                            end)

                          spinner_frames =
                            Enum.zip(
                              @unicode_chars.spinner_frames,
                              Stream.cycle(@ascii_chars.spinner_frames)
                            )

                          Map.new(levels ++ spinner_frames ++ Map.to_list(base))
                        )

  @doc "Converts changed backend cells to a minimal ANSI output sequence."
  @spec render(
          [{TermUI.Backend.position(), TermUI.Backend.cell()}],
          :true_color | :color_256 | :color_16 | :monochrome,
          :unicode | :ascii
        ) :: iolist()
  def render(changes, color_mode, character_set) do
    [
      changes
      |> contiguous_runs(character_set)
      |> render_runs(color_mode),
      ANSI.reset()
    ]
  end

  defp contiguous_runs(changes, character_set) do
    {runs, current} =
      Enum.reduce(changes, {[], nil}, fn change, {runs, current} ->
        cell = render_cell(change, character_set)

        if adjacent?(current, cell) do
          {runs, append_to_run(current, cell)}
        else
          {complete_run(runs, current), new_run(cell)}
        end
      end)

    runs
    |> complete_run(current)
    |> Enum.reverse()
  end

  defp complete_run(runs, nil), do: runs
  defp complete_run(runs, run), do: [run | runs]

  defp render_cell({{row, column}, {char, foreground, background, attrs}}, character_set) do
    cell = Cell.new(char)
    char = map_character(cell.char, character_set)
    width = if char == cell.char, do: Cell.width(cell), else: char |> Cell.new() |> Cell.width()

    %{row: row, column: column, char: char, width: width, style: {foreground, background, attrs}}
  end

  defp adjacent?(nil, _cell), do: false

  defp adjacent?(run, cell) do
    run.row == cell.row and run.last_column + run.last_width == cell.column
  end

  defp new_run(cell) do
    %{
      row: cell.row,
      column: cell.column,
      last_column: cell.column,
      last_width: cell.width,
      cells: [cell]
    }
  end

  defp append_to_run(run, cell) do
    %{run | last_column: cell.column, last_width: cell.width, cells: [cell | run.cells]}
  end

  defp render_runs(runs, color_mode) do
    {_style, output} =
      Enum.reduce(runs, {nil, []}, fn run, {previous_style, output} ->
        {style, cells} = render_run_cells(Enum.reverse(run.cells), color_mode, previous_style)

        {style, [output, ANSI.cursor_position(run.row, run.column), cells]}
      end)

    output
  end

  defp render_run_cells(cells, color_mode, initial_style) do
    Enum.reduce(cells, {initial_style, []}, fn cell, {previous_style, output} ->
      style = cell.style
      sequence = if style == previous_style, do: [], else: style_sequence(style, color_mode)
      {style, [output, sequence, cell.char]}
    end)
  end

  defp style_sequence({foreground, background, attrs}, color_mode) do
    [
      ANSI.reset(),
      color(:fg, foreground, color_mode),
      color(:bg, background, color_mode),
      Enum.map(attrs, &attribute/1)
    ]
  end

  defp map_character(char, :unicode), do: char
  defp map_character(char, :ascii), do: Map.get(@unicode_to_ascii_map, char, char)

  defp color(_type, _color, :monochrome), do: []
  defp color(_type, :default, _mode), do: []
  defp color(:fg, color, _mode) when is_atom(color), do: ANSI.foreground(color)
  defp color(:bg, color, _mode) when is_atom(color), do: ANSI.background(color)
  defp color(:fg, index, _mode) when is_integer(index), do: ANSI.foreground_256(index)
  defp color(:bg, index, _mode) when is_integer(index), do: ANSI.background_256(index)
  defp color(:fg, {red, green, blue}, :true_color), do: ANSI.foreground_rgb(red, green, blue)
  defp color(:bg, {red, green, blue}, :true_color), do: ANSI.background_rgb(red, green, blue)

  defp color(:fg, rgb, :color_256), do: rgb |> Converter.rgb_to_256() |> ANSI.foreground_256()
  defp color(:bg, rgb, :color_256), do: rgb |> Converter.rgb_to_256() |> ANSI.background_256()

  defp color(:fg, rgb, :color_16),
    do: ["\e[", Integer.to_string(Converter.rgb_to_16(rgb, :fg)), "m"]

  defp color(:bg, rgb, :color_16),
    do: ["\e[", Integer.to_string(Converter.rgb_to_16(rgb, :bg)), "m"]

  defp attribute(:bold), do: ANSI.bold()
  defp attribute(:dim), do: ANSI.dim()
  defp attribute(:italic), do: ANSI.italic()
  defp attribute(:underline), do: ANSI.underline()
  defp attribute(:blink), do: ANSI.blink()
  defp attribute(:reverse), do: ANSI.reverse()
  defp attribute(:hidden), do: ANSI.hidden()
  defp attribute(:strikethrough), do: ANSI.strikethrough()
  defp attribute(_unknown), do: []
end
