defmodule TermUI.Widget.BarChart do
  @moduledoc "A pure horizontal bar chart."

  @behaviour TermUI.Widget

  alias TermUI.Style
  alias TermUI.Widget.{ChartHelpers, Helpers}

  @type datum :: %{
          required(:label) => String.t(),
          required(:value) => number(),
          optional(:color) => atom()
        }
  @type t :: %__MODULE__{
          data: [datum()],
          minimum: number() | nil,
          maximum: number() | nil,
          show_values: boolean()
        }
  defstruct data: [],
            minimum: nil,
            maximum: nil,
            show_values: true

  @impl true
  def init(opts),
    do: %__MODULE__{
      data: opts |> Keyword.get(:data, []) |> Enum.map(&normalize/1),
      minimum: Keyword.get(opts, :min),
      maximum: Keyword.get(opts, :max),
      show_values: Keyword.get(opts, :show_values, true)
    }

  @impl true
  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, height} = dimensions) do
    data = Enum.take(state.data, height)
    values = Enum.map(data, & &1.value)

    {minimum, maximum} =
      ChartHelpers.range(values,
        min: state.minimum || Enum.min(values, fn -> 0 end),
        max: state.maximum || Enum.max(values, fn -> 1 end)
      )

    label_width =
      data |> Enum.map(&String.length(&1.label)) |> Enum.max(fn -> 0 end) |> min(div(width, 3))

    rows =
      Enum.map(data, fn datum ->
        value_text = if state.show_values, do: " " <> ChartHelpers.number(datum.value), else: ""
        bar_width = max(width - label_width - String.length(value_text) - 1, 1)
        fill = round(ChartHelpers.normalize(datum.value, minimum, maximum) * bar_width)

        [
          Helpers.align(datum.label, label_width, :right),
          " ",
          {String.duplicate("█", fill), Style.new(fg: datum.color)},
          String.duplicate(" ", max(bar_width - fill, 0)),
          value_text
        ]
      end)

    Helpers.frame(rows, dimensions)
  end

  defp normalize(%{label: label, value: value} = datum),
    do: %{label: to_string(label), value: value, color: Map.get(datum, :color, :cyan)}

  defp normalize({label, value}), do: %{label: to_string(label), value: value, color: :cyan}
end
