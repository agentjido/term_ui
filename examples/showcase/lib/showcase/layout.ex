defmodule Showcase.Layout do
  @moduledoc false

  alias TermUI.{Frame, Style}
  alias TermUI.Widget.Block

  @spec panel(Frame.t(), String.t(), {pos_integer(), pos_integer()}, keyword()) :: Frame.t()
  def panel(%Frame{} = child, title, dimensions, opts \\ []) do
    border_style =
      if Keyword.get(opts, :active, false) do
        Style.new(fg: theme_color(Keyword.get(opts, :theme, :dark)), attrs: [:bold])
      else
        Style.new(fg: :bright_black)
      end

    [title: title, border_style: border_style]
    |> Block.init()
    |> Block.compose(dimensions, child)
  end

  @spec selector([{term(), String.t()}], term(), pos_integer()) :: Frame.t()
  def selector(items, selected, width) do
    active = Style.new(fg: :black, bg: :cyan, attrs: [:bold])
    normal = Style.new(fg: :bright_black)

    row =
      Enum.flat_map(items, fn {id, label} ->
        style = if id == selected, do: active, else: normal
        [{" " <> label <> " ", style}, " "]
      end)

    Frame.from_rows([row], width, 1)
  end

  @spec split_widths(pos_integer(), pos_integer()) :: {pos_integer(), pos_integer()}
  def split_widths(width, gap \\ 1) do
    available = max(width - gap, 2)
    left = div(available, 2)
    {max(left, 1), max(available - left, 1)}
  end

  @spec without_cursor(Frame.t()) :: Frame.t()
  def without_cursor(%Frame{} = frame), do: %{frame | cursor: nil}

  defp theme_color(:light), do: :blue
  defp theme_color(:dark), do: :cyan
end
