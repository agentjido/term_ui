defmodule TermUI.Widget.Button do
  @moduledoc "A pure keyboard and mouse button."

  @behaviour TermUI.Widget

  alias TermUI.{Event, Style}
  alias TermUI.Widget.Helpers

  @type t :: %__MODULE__{
          id: term(),
          label: String.t(),
          prefix: String.t(),
          suffix: String.t(),
          focused: boolean(),
          pressed: boolean(),
          disabled: boolean(),
          message: term(),
          style: Style.t(),
          focus_style: Style.t(),
          disabled_style: Style.t()
        }

  defstruct id: nil,
            label: "Button",
            prefix: "",
            suffix: "",
            focused: false,
            pressed: false,
            disabled: false,
            message: nil,
            style: %Style{},
            focus_style: %Style{fg: :cyan, attrs: MapSet.new([:bold])},
            disabled_style: %Style{fg: :bright_black}

  @impl true
  def init(opts) do
    id = Keyword.get(opts, :id)

    %__MODULE__{
      id: id,
      label: opts |> Keyword.get(:label, "Button") |> to_string(),
      prefix: opts |> Keyword.get(:prefix, "") |> to_string(),
      suffix: opts |> Keyword.get(:suffix, "") |> to_string(),
      focused: Keyword.get(opts, :focused, false),
      disabled: Keyword.get(opts, :disabled, false),
      message: Keyword.get(opts, :message, {:pressed, id}),
      style: Keyword.get(opts, :style, Style.new()),
      focus_style: Keyword.get(opts, :focus_style, Style.new(fg: :cyan, attrs: [:bold])),
      disabled_style: Keyword.get(opts, :disabled_style, Style.new(fg: :bright_black))
    }
  end

  @impl true
  def update(_event, %{disabled: true} = state), do: {state, []}
  def update(%Event.Key{key: key}, state) when key in [:enter, :space], do: press(state)
  def update(%Event.Text{text: " "}, state), do: press(state)

  def update(%Event.Mouse{action: :press, button: :left}, state),
    do: {%{state | pressed: true}, []}

  def update(%Event.Mouse{action: :release, button: :left}, state),
    do: press(%{state | pressed: false})

  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, _height} = dimensions) do
    style =
      cond do
        state.disabled -> state.disabled_style
        state.focused or state.pressed -> state.focus_style
        true -> state.style
      end

    marker = if state.pressed, do: "<", else: "["
    end_marker = if state.pressed, do: ">", else: "]"

    label =
      [state.prefix, state.label, state.suffix] |> Enum.reject(&(&1 == "")) |> Enum.join(" ")

    row = [{Helpers.align(marker <> " " <> label <> " " <> end_marker, width, :center), style}]

    Helpers.frame([row], dimensions)
  end

  @doc "Sets keyboard focus."
  @spec focus(t(), boolean()) :: t()
  def focus(state, focused \\ true), do: %{state | focused: focused}

  defp press(state), do: {%{state | pressed: false}, [state.message]}
end
