defmodule TermUI.Widget.ChartHelpers do
  @moduledoc false

  @doc "Returns the configured or measured numeric range for chart values."
  @spec range([number()], keyword()) :: {number(), number()}
  def range(values, opts \\ [])
  def range([], _opts), do: {0, 1}

  def range(values, opts) do
    minimum = Keyword.get(opts, :min, Enum.min(values))
    maximum = Keyword.get(opts, :max, Enum.max(values))
    if minimum == maximum, do: {minimum, maximum + 1}, else: {minimum, maximum}
  end

  @doc "Normalizes one value to the inclusive range from zero to one."
  @spec normalize(number(), number(), number()) :: float()
  def normalize(_value, minimum, maximum) when maximum <= minimum, do: 0.0

  def normalize(value, minimum, maximum),
    do: ((value - minimum) / (maximum - minimum)) |> max(0.0) |> min(1.0)

  @doc "Formats a chart number with at most two decimal places."
  @spec number(number()) :: String.t()
  def number(value) when is_integer(value), do: Integer.to_string(value)
  def number(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
end
