defmodule TermUI.Widget.Sparkline do
  @moduledoc "A pure one-row sparkline for numeric samples."

  import Kernel, except: [to_string: 1]

  @behaviour TermUI.Widget

  alias TermUI.Style
  alias TermUI.Widget.{ChartHelpers, Helpers}

  @levels String.graphemes("▁▂▃▄▅▆▇█")
  @type t :: %__MODULE__{
          values: [number()],
          minimum: number() | nil,
          maximum: number() | nil,
          style: Style.t(),
          label: String.t() | nil,
          show_range: boolean(),
          color_ranges: [{number(), atom()}]
        }
  defstruct values: [],
            minimum: nil,
            maximum: nil,
            style: %Style{fg: :cyan},
            label: nil,
            show_range: false,
            color_ranges: []

  @impl true
  def init(opts),
    do: %__MODULE__{
      values: normalize_values(Keyword.get(opts, :values, [])),
      minimum: Keyword.get(opts, :min),
      maximum: Keyword.get(opts, :max),
      style: Keyword.get(opts, :style, Style.new(fg: :cyan)),
      label: normalize_label(Keyword.get(opts, :label)),
      show_range: Keyword.get(opts, :show_range, false),
      color_ranges: Keyword.get(opts, :color_ranges, [])
    }

  @impl true
  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, _height} = dimensions) do
    {minimum, maximum} = range(state.values, min: state.minimum, max: state.maximum)
    prefix = prefix(state, minimum)
    suffix = suffix(state, maximum)
    sample_width = max(width - String.length(prefix <> suffix), 0)
    values = Enum.take(state.values, -sample_width)

    chars = render_values(values, minimum, maximum, state)

    Helpers.frame([[prefix] ++ List.wrap(chars) ++ [suffix]], dimensions)
  end

  @doc "Returns the eight characters used for sparkline levels."
  @spec bar_characters() :: [String.t()]
  def bar_characters, do: @levels

  @doc "Maps one numeric value to a sparkline character."
  @spec value_to_bar(term(), term(), term()) :: String.t()
  def value_to_bar(value, minimum, maximum)
      when is_number(value) and is_number(minimum) and is_number(maximum) do
    if maximum > minimum do
      Enum.at(@levels, round(ChartHelpers.normalize(value, minimum, maximum) * 7))
    else
      Enum.at(@levels, div(length(@levels), 2))
    end
  end

  def value_to_bar(_value, _minimum, _maximum),
    do: Enum.at(@levels, div(length(@levels), 2))

  @doc "Converts numeric values to an unstyled sparkline string."
  @spec to_sparkline(term(), keyword()) :: String.t()
  def to_sparkline(values, opts \\ [])

  def to_sparkline([], _opts), do: ""

  def to_sparkline(values, opts) when is_list(values) do
    if Enum.all?(values, &is_number/1) do
      {minimum, maximum} = range(values, opts)
      Enum.map_join(values, &value_to_bar(&1, minimum, maximum))
    else
      ""
    end
  end

  def to_sparkline(_values, _opts), do: ""

  @doc false
  @spec to_string(term(), keyword()) :: String.t()
  def to_string(values, opts \\ []), do: to_sparkline(values, opts)

  @doc "Returns the natural one-row width for the current values and labels."
  @spec natural_width(t()) :: pos_integer()
  def natural_width(state) do
    {minimum, maximum} = range(state.values, min: state.minimum, max: state.maximum)
    max(String.length(prefix(state, minimum) <> suffix(state, maximum)) + length(state.values), 1)
  end

  @doc "Appends one value and retains at most limit values."
  @spec push(t(), number(), pos_integer()) :: t()
  def push(state, value, limit \\ 1_000),
    do: %{state | values: Enum.take(state.values ++ [value], -max(limit, 1))}

  defp render_values(values, minimum, maximum, %{color_ranges: []} = state) do
    {Enum.map_join(values, &value_to_bar(&1, minimum, maximum)), state.style}
  end

  defp render_values(values, minimum, maximum, state) do
    Enum.map(values, fn value ->
      color = color_for(value, state.color_ranges)
      style = if is_nil(color), do: state.style, else: %{state.style | fg: color}
      {value_to_bar(value, minimum, maximum), style}
    end)
  end

  defp color_for(value, ranges) do
    ranges
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.find_value(fn {threshold, color} -> if value >= threshold, do: color end)
  end

  defp prefix(state, minimum) do
    label = if state.label, do: state.label <> " ", else: ""
    range = if state.show_range and state.values != [], do: range_number(minimum) <> " ", else: ""
    label <> range
  end

  defp suffix(state, maximum) do
    if state.show_range and state.values != [], do: " " <> range_number(maximum), else: ""
  end

  defp range([], _opts), do: {0, 1}

  defp range(values, opts) do
    minimum = Keyword.get(opts, :min) || Enum.min(values)
    maximum = Keyword.get(opts, :max) || Enum.max(values)
    {minimum, maximum}
  end

  defp range_number(value) when is_integer(value), do: Integer.to_string(value)
  defp range_number(value), do: :erlang.float_to_binary(value / 1, decimals: 1)

  defp normalize_values(values) when is_list(values) do
    if Enum.all?(values, &is_number/1), do: values, else: []
  end

  defp normalize_values(_values), do: []
  defp normalize_label(nil), do: nil
  defp normalize_label(label), do: Kernel.to_string(label)
end
