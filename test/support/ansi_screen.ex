defmodule TermUI.Test.AnsiScreen do
  @moduledoc false

  # This decoder checks the ASCII matrix fixtures against terminal behavior,
  # rather than the renderer's cached style. It supports only the sequences
  # used by these fixtures and rejects other sequences.
  # https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
  @colors [:black, :red, :green, :yellow, :blue, :magenta, :cyan, :white]
  @attributes %{1 => :bold, 2 => :dim, 3 => :italic, 4 => :underline}

  def new, do: %{row: 1, column: 1, fg: :default, bg: :default, attrs: MapSet.new(), cells: %{}}

  def feed(screen, ""), do: screen

  def feed(screen, "\e[" <> _rest = output) do
    [sequence, parameters, command] = Regex.run(~r/^\e\[([0-9;?]*)([@-~])/, output)
    next = control(screen, parameters, command)
    feed(next, binary_part(output, byte_size(sequence), byte_size(output) - byte_size(sequence)))
  end

  def feed(screen, <<character, rest::binary>>) when character in 32..126 do
    cell = {<<character>>, screen.fg, screen.bg, screen.attrs}
    cells = Map.put(screen.cells, {screen.row, screen.column}, cell)
    feed(%{screen | cells: cells, column: screen.column + 1}, rest)
  end

  def feed(screen, "\r" <> rest), do: feed(%{screen | column: 1}, rest)
  def feed(screen, "\n" <> rest), do: feed(%{screen | row: screen.row + 1}, rest)
  def feed(_screen, output), do: raise("Unsupported matrix output: #{inspect(output)}")

  defp control(screen, "?" <> _mode, command) when command in ["h", "l"], do: screen
  defp control(screen, "2", "J"), do: %{screen | cells: %{}}

  defp control(screen, parameters, "H") do
    [row, column] = if parameters == "", do: [1, 1], else: numbers(parameters)
    %{screen | row: row, column: column}
  end

  defp control(screen, parameters, "m"), do: rendition(screen, numbers(parameters))

  defp control(_screen, parameters, command),
    do: raise("Unsupported matrix control: #{inspect({parameters, command})}")

  defp numbers(""), do: [0]
  defp numbers(parameters), do: parameters |> String.split(";") |> Enum.map(&String.to_integer/1)

  defp rendition(screen, []), do: screen

  defp rendition(screen, [0 | rest]),
    do: rendition(%{screen | fg: :default, bg: :default, attrs: MapSet.new()}, rest)

  defp rendition(screen, [39 | rest]), do: rendition(%{screen | fg: :default}, rest)
  defp rendition(screen, [49 | rest]), do: rendition(%{screen | bg: :default}, rest)

  defp rendition(screen, [code, 5, index | rest]) when code in [38, 48],
    do: rendition(Map.put(screen, color_field(code), index), rest)

  defp rendition(screen, [code, 2, red, green, blue | rest]) when code in [38, 48],
    do: rendition(Map.put(screen, color_field(code), {red, green, blue}), rest)

  defp rendition(screen, [code | rest]) when code in 30..37,
    do: rendition(%{screen | fg: Enum.at(@colors, code - 30)}, rest)

  defp rendition(screen, [code | rest]) when code in 40..47,
    do: rendition(%{screen | bg: Enum.at(@colors, code - 40)}, rest)

  defp rendition(screen, [code | rest]) when is_map_key(@attributes, code),
    do:
      rendition(%{screen | attrs: MapSet.put(screen.attrs, Map.fetch!(@attributes, code))}, rest)

  defp rendition(_screen, codes), do: raise("Unsupported matrix rendition: #{inspect(codes)}")

  defp color_field(38), do: :fg
  defp color_field(48), do: :bg
end
