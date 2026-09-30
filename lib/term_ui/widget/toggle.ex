defmodule TermUI.Widget.Toggle do
  @moduledoc "A pure keyboard and mouse on/off control."

  @behaviour TermUI.Widget

  alias TermUI.{Event, Style}
  alias TermUI.Widget.Helpers

  @type t :: %__MODULE__{
          id: term(),
          label: String.t(),
          checked: boolean(),
          focused: boolean(),
          disabled: boolean(),
          on_text: String.t(),
          off_text: String.t(),
          style: Style.t(),
          on_style: Style.t(),
          focus_style: Style.t(),
          disabled_style: Style.t()
        }

  defstruct id: nil,
            label: "",
            checked: false,
            focused: false,
            disabled: false,
            on_text: "ON",
            off_text: "OFF",
            style: %Style{},
            on_style: %Style{fg: :green},
            focus_style: %Style{attrs: MapSet.new([:reverse])},
            disabled_style: %Style{fg: :bright_black}

  @impl true
  def init(opts) do
    %__MODULE__{
      id: Keyword.get(opts, :id),
      label: opts |> Keyword.get(:label, "") |> to_string(),
      checked: Keyword.get(opts, :checked, false),
      focused: Keyword.get(opts, :focused, false),
      disabled: Keyword.get(opts, :disabled, false),
      on_text: opts |> Keyword.get(:on_text, "ON") |> to_string(),
      off_text: opts |> Keyword.get(:off_text, "OFF") |> to_string(),
      style: Keyword.get(opts, :style, Style.new()),
      on_style: Keyword.get(opts, :on_style, Style.new(fg: :green)),
      focus_style: Keyword.get(opts, :focus_style, Style.new(attrs: [:reverse])),
      disabled_style: Keyword.get(opts, :disabled_style, Style.new(fg: :bright_black))
    }
  end

  @impl true
  def update(_event, %{disabled: true} = state), do: {state, []}
  def update(%Event.Key{key: key}, state) when key in [:enter, :space], do: change(state)
  def update(%Event.Text{text: " "}, state), do: change(state)
  def update(_event, state), do: {state, []}

  @impl true
  def mouse(_event, %{disabled: true} = state, _dimensions), do: {state, []}

  def mouse(%Event.Mouse{action: :press, button: :left} = event, state, dimensions) do
    if inside?(event, dimensions), do: {%{state | focused: true}, []}, else: {state, []}
  end

  def mouse(%Event.Mouse{action: :release, button: :left} = event, state, dimensions) do
    if inside?(event, dimensions), do: change(state), else: {state, []}
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(state, {width, _height} = dimensions) do
    value = if state.checked, do: state.on_text, else: state.off_text

    text =
      if state.label == "", do: "[ " <> value <> " ]", else: "[ " <> value <> " ] " <> state.label

    Helpers.frame([[{Helpers.align(text, width, :left), control_style(state)}]], dimensions)
  end

  @doc "Sets the on/off state."
  @spec set_checked(t(), boolean()) :: t()
  def set_checked(state, checked), do: %{state | checked: checked}

  @doc "Sets keyboard focus."
  @spec focus(t(), boolean()) :: t()
  def focus(state, focused \\ true), do: %{state | focused: focused}

  defp change(state) do
    state = %{state | checked: not state.checked}
    {state, [{:changed, state.id, state.checked}]}
  end

  defp control_style(%{disabled: true} = state), do: state.disabled_style
  defp control_style(%{focused: true} = state), do: state.focus_style
  defp control_style(%{checked: true} = state), do: state.on_style
  defp control_style(state), do: state.style

  defp inside?(%{x: x, y: y}, {width, height}),
    do: x >= 0 and x < width and y >= 0 and y < height
end
