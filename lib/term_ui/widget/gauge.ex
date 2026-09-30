defmodule TermUI.Widget.Gauge do
  @moduledoc "A pure horizontal or vertical value gauge."

  @behaviour TermUI.Widget

  alias TermUI.Style
  alias TermUI.Widget.{ChartHelpers, Helpers}

  @type t :: %__MODULE__{
          value: number(),
          minimum: number(),
          maximum: number(),
          label: String.t() | nil,
          orientation: :horizontal | :vertical,
          zones: [{number(), atom()}]
        }
  defstruct value: 0,
            minimum: 0,
            maximum: 100,
            label: nil,
            orientation: :horizontal,
            zones: [{0.8, :red}, {0.6, :yellow}, {0.0, :green}]

  @impl true
  def init(opts),
    do: %__MODULE__{
      value: Keyword.get(opts, :value, 0),
      minimum: Keyword.get(opts, :min, 0),
      maximum: Keyword.get(opts, :max, 100),
      label: Keyword.get(opts, :label),
      orientation: Keyword.get(opts, :orientation, :horizontal),
      zones: Keyword.get(opts, :zones, [{0.8, :red}, {0.6, :yellow}, {0.0, :green}])
    }

  @impl true
  def update(_event, state), do: {state, []}

  @impl true
  def view(%{orientation: :vertical} = state, {width, height} = dimensions) do
    ratio = ratio(state)
    fill = round(height * ratio)
    style = Style.new(fg: color(state, ratio))

    rows =
      for row <- 1..height,
          do: [{if(row > height - fill, do: "█", else: "░") |> String.duplicate(width), style}]

    Helpers.frame(rows, dimensions)
  end

  def view(state, {width, _height} = dimensions) do
    ratio = ratio(state)
    label = if state.label, do: state.label <> " ", else: ""
    value = " " <> ChartHelpers.number(state.value)
    bar_width = max(width - String.length(label <> value), 1)
    fill = round(bar_width * ratio)
    style = Style.new(fg: color(state, ratio))

    row = [
      label,
      {String.duplicate("█", fill) <> String.duplicate("░", max(bar_width - fill, 0)), style},
      value
    ]

    Helpers.frame([row], dimensions)
  end

  @doc "Sets the gauge value."
  @spec set_value(t(), number()) :: t()
  def set_value(state, value), do: %{state | value: value}

  defp ratio(state), do: ChartHelpers.normalize(state.value, state.minimum, state.maximum)

  defp color(state, ratio),
    do:
      state.zones
      |> Enum.sort_by(&elem(&1, 0), :desc)
      |> Enum.find_value(:green, fn {threshold, color} -> if ratio >= threshold, do: color end)
end
