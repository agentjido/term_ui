defmodule TermUI.Widget.Checkbox do
  @moduledoc "A pure keyboard and mouse checkbox."

  @behaviour TermUI.Widget

  alias TermUI.{Event, Style}
  alias TermUI.Widget.Helpers

  @type t :: %__MODULE__{
          id: term(),
          label: String.t(),
          checked: boolean(),
          focused: boolean(),
          disabled: boolean(),
          checked_icon: String.t(),
          unchecked_icon: String.t(),
          show_brackets: boolean(),
          style: Style.t(),
          checked_style: Style.t(),
          focus_style: Style.t(),
          disabled_style: Style.t()
        }

  defstruct id: nil,
            label: "",
            checked: false,
            focused: false,
            disabled: false,
            checked_icon: "x",
            unchecked_icon: " ",
            show_brackets: true,
            style: %Style{},
            checked_style: %Style{fg: :green},
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
      checked_icon: opts |> Keyword.get(:checked_icon, "x") |> to_string(),
      unchecked_icon: opts |> Keyword.get(:unchecked_icon, " ") |> to_string(),
      show_brackets: Keyword.get(opts, :show_brackets, true),
      style: Keyword.get(opts, :style, Style.new()),
      checked_style: Keyword.get(opts, :checked_style, Style.new(fg: :green)),
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
    icon = if state.checked, do: state.checked_icon, else: state.unchecked_icon
    mark = if state.show_brackets, do: "[" <> icon <> "]", else: icon
    text = if state.label == "", do: mark, else: mark <> " " <> state.label
    Helpers.frame([[{Helpers.align(text, width, :left), control_style(state)}]], dimensions)
  end

  @doc "Sets the checked state."
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
  defp control_style(%{checked: true} = state), do: state.checked_style
  defp control_style(state), do: state.style

  defp inside?(%{x: x, y: y}, {width, height}),
    do: x >= 0 and x < width and y >= 0 and y < height
end
