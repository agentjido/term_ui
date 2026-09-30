defmodule TermUI.Widget.LineChart do
  @moduledoc "A pure line chart rendered on a character canvas."

  @behaviour TermUI.Widget

  alias TermUI.Widget.{Canvas, ChartHelpers}

  @type t :: %__MODULE__{
          series: [[number()]],
          colors: [atom()],
          minimum: number() | nil,
          maximum: number() | nil
        }
  defstruct series: [],
            colors: [:cyan, :green, :yellow, :magenta],
            minimum: nil,
            maximum: nil

  @impl true
  def init(opts) do
    series =
      case Keyword.get(opts, :series, []) do
        [] -> []
        [first | _] = values when is_number(first) -> [values]
        series -> series
      end

    colors =
      case Keyword.get(opts, :colors, [:cyan, :green, :yellow, :magenta]) do
        [] -> [:cyan]
        colors -> colors
      end

    %__MODULE__{
      series: series,
      colors: colors,
      minimum: Keyword.get(opts, :min),
      maximum: Keyword.get(opts, :max)
    }
  end

  @impl true
  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, height} = dimensions) do
    values = List.flatten(state.series)

    {minimum, maximum} =
      ChartHelpers.range(values,
        min: state.minimum || Enum.min(values, fn -> 0 end),
        max: state.maximum || Enum.max(values, fn -> 1 end)
      )

    canvas = Canvas.init(width: width, height: height)

    canvas =
      state.series
      |> Enum.with_index()
      |> Enum.reduce(canvas, fn {series, series_index}, canvas ->
        color = Enum.at(state.colors, rem(series_index, length(state.colors)))
        style = TermUI.Style.new(fg: color)

        points =
          series
          |> Enum.take(-width)
          |> Enum.with_index()
          |> Enum.map(fn {value, x} ->
            {x,
             height - 1 -
               round(ChartHelpers.normalize(value, minimum, maximum) * max(height - 1, 0))}
          end)

        canvas =
          Enum.reduce(points, %{canvas | style: style}, fn {x, y}, acc ->
            Canvas.set_char(acc, x, y, "•")
          end)

        points
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.reduce(canvas, fn [{x0, y0}, {x1, y1}], acc ->
          Canvas.draw_line(acc, x0, y0, x1, y1, "•")
        end)
      end)

    Canvas.view(canvas, dimensions)
  end
end
