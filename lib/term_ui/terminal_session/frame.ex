defmodule TermUI.TerminalSession.Frame do
  @moduledoc """
  Converts a Ghostty render snapshot into a complete TermUI frame.

  This function is pure and does not require the Ghostty package. An application
  stores the resulting frame and overlays it in its own complete view. The
  snapshot uses the public Ghostty 0.5 cell and cursor format. Zero-based cursor
  positions become one-based frame positions. Wide tails follow TermUI's cell
  contract. Unsupported overline styling is omitted.
  """

  import Bitwise

  alias TermUI.{Cell, Frame}

  @attributes [
    {1, :bold},
    {2, :italic},
    {4, :dim},
    {8, :underline},
    {16, :strikethrough},
    {32, :reverse},
    {64, :blink}
  ]

  @doc "Converts one emulator snapshot for dimensions in rows and columns."
  @spec from_snapshot(map(), TermUI.Backend.size()) :: Frame.t()
  def from_snapshot(%{cells: rows} = snapshot, {height, width}) do
    frame = Frame.new(width, height)
    frame = %{frame | cursor: cursor(snapshot, {frame.height, frame.width})}

    rows
    |> Enum.take(height)
    |> Enum.with_index(1)
    |> Enum.reduce(frame, fn {cells, row}, frame ->
      put_row(frame, row, cells, snapshot)
    end)
  end

  defp put_row(frame, row, cells, snapshot) do
    {frame, _tail?} =
      cells
      |> Enum.take(frame.width)
      |> Enum.with_index(1)
      |> Enum.reduce({frame, false}, fn
        {_cell, _column}, {frame, true} ->
          {frame, false}

        {{text, foreground, background, flags}, column}, {frame, false} ->
          cell =
            Cell.new(if(text == "", do: " ", else: text),
              fg: foreground || Map.get(snapshot, :foreground) || :default,
              bg: background || Map.get(snapshot, :background) || :default,
              attrs: for({bit, attribute} <- @attributes, (flags &&& bit) != 0, do: attribute)
            )

          {Frame.put_cell(frame, row, column, cell), Cell.wide?(cell)}
      end)

    frame
  end

  defp cursor(%{cursor: %{visible: true, x: x, y: y}}, {height, width})
       when is_integer(x) and is_integer(y) and x >= 0 and y >= 0 and x < width and y < height,
       do: {x + 1, y + 1}

  defp cursor(_snapshot, _size), do: nil
end
