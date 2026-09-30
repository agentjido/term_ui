defmodule TermUI.Widget.Progress do
  @moduledoc "A pure determinate or indeterminate progress bar."

  @behaviour TermUI.Widget

  alias TermUI.Style
  alias TermUI.Widget.Helpers

  @type t :: %__MODULE__{
          value: number(),
          minimum: number(),
          maximum: number(),
          label: String.t() | nil,
          show_percent: boolean(),
          indeterminate: boolean(),
          phase: non_neg_integer()
        }

  defstruct value: 0,
            minimum: 0,
            maximum: 100,
            label: nil,
            show_percent: true,
            indeterminate: false,
            phase: 0

  @impl true
  def init(opts) do
    %__MODULE__{
      value: Keyword.get(opts, :value, 0),
      minimum: Keyword.get(opts, :min, 0),
      maximum: Keyword.get(opts, :max, 100),
      label: Keyword.get(opts, :label),
      show_percent: Keyword.get(opts, :show_percent, true),
      indeterminate: Keyword.get(opts, :indeterminate, false)
    }
  end

  @impl true
  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, _height} = dimensions) do
    percent = percentage(state)

    suffix =
      if state.show_percent and not state.indeterminate, do: " #{round(percent * 100)}%", else: ""

    prefix = if state.label, do: state.label <> " ", else: ""
    bar_width = max(width - String.length(prefix <> suffix) - 2, 1)

    filled =
      if state.indeterminate, do: rem(state.phase, bar_width), else: round(percent * bar_width)

    bar =
      if state.indeterminate do
        String.duplicate("░", filled) <>
          "█" <> String.duplicate("░", max(bar_width - filled - 1, 0))
      else
        String.duplicate("█", filled) <> String.duplicate("░", max(bar_width - filled, 0))
      end

    row = [prefix, {"[" <> bar <> "]", Style.new(fg: :green)}, suffix]
    Helpers.frame([row], dimensions)
  end

  @doc "Sets the current value."
  @spec set_value(t(), number()) :: t()
  def set_value(state, value), do: %{state | value: value}

  @doc "Advances an indeterminate progress bar."
  @spec tick(t()) :: t()
  def tick(state), do: %{state | phase: state.phase + 1}

  defp percentage(%{maximum: maximum, minimum: minimum}) when maximum <= minimum, do: 0.0

  defp percentage(state) do
    ((state.value - state.minimum) / (state.maximum - state.minimum))
    |> max(0.0)
    |> min(1.0)
  end
end
