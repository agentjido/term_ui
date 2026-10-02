defmodule TermUI.Widget.CommandPalette do
  @moduledoc "A pure searchable command palette."

  @behaviour TermUI.Widget

  alias TermUI.Event
  alias TermUI.Widget.{Dialog, PickList}

  @type t :: %__MODULE__{picker: PickList.t(), title: String.t(), visible: boolean()}
  defstruct picker: %PickList{},
            title: "Commands",
            visible: false

  @impl true
  def init(opts) do
    %__MODULE__{
      picker:
        PickList.init(
          items: Keyword.get(opts, :commands, []),
          prompt: Keyword.get(opts, :prompt, "> ")
        ),
      title: Keyword.get(opts, :title, "Commands"),
      visible: Keyword.get(opts, :visible, false)
    }
  end

  @impl true
  def update(_event, %{visible: false} = state), do: {state, []}

  def update(event, state) do
    {picker, messages} = PickList.update(event, state.picker)
    finish(state, picker, messages)
  end

  @impl true
  def mouse(_event, %{visible: false} = state, _dimensions), do: {state, []}

  def mouse(%Event.Mouse{x: x, y: y} = event, state, {width, height}) do
    {left, top, inner_width, inner_height} = Dialog.content_rect(dialog(state), {width, height})

    if inner_width > 0 and inner_height > 0 and x >= left and x < left + inner_width and
         y >= top and y < top + inner_height do
      local_event = %{event | x: x - left, y: y - top}
      {picker, messages} = PickList.mouse(local_event, state.picker, {inner_width, inner_height})
      finish(state, picker, messages)
    else
      {state, []}
    end
  end

  defp finish(state, picker, messages) do
    messages =
      Enum.map(messages, fn
        {:picked, command} -> {:command, command}
        message -> message
      end)

    visible = :cancel not in messages
    {%{state | picker: picker, visible: visible}, messages}
  end

  @impl true
  def view(%{visible: false}, dimensions),
    do: TermUI.Frame.new(elem(dimensions, 0), elem(dimensions, 1))

  def view(state, dimensions) do
    dialog = dialog(state)
    {_left, _top, width, height} = Dialog.content_rect(dialog, dimensions)

    if width > 0 and height > 0,
      do: Dialog.compose(dialog, dimensions, PickList.view(state.picker, {width, height})),
      else: Dialog.view(dialog, dimensions)
  end

  defp dialog(state), do: Dialog.init(title: state.title, buttons: [])

  @doc "Shows and resets the palette query."
  @spec show(t()) :: t()
  def show(state), do: %{state | visible: true, picker: %{state.picker | query: "", cursor: 0}}

  @doc "Hides the palette."
  @spec hide(t()) :: t()
  def hide(state), do: %{state | visible: false}
end
