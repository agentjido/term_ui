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
    if x >= 1 and x < width - 1 and y >= 1 and y < height - 1 do
      inner_dimensions = {max(width - 2, 1), max(height - 2, 1)}
      local_event = %{event | x: x - 1, y: y - 1}
      {picker, messages} = PickList.mouse(local_event, state.picker, inner_dimensions)
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
    content =
      PickList.view(
        state.picker,
        {max(elem(dimensions, 0) - 2, 1), max(elem(dimensions, 1) - 2, 1)}
      )

    dialog =
      Dialog.init(
        title: state.title,
        content: Enum.map(1..content.height, &TermUI.Frame.row_text(content, &1)),
        buttons: []
      )

    Dialog.view(dialog, dimensions)
  end

  @doc "Shows and resets the palette query."
  @spec show(t()) :: t()
  def show(state), do: %{state | visible: true, picker: %{state.picker | query: "", cursor: 0}}

  @doc "Hides the palette."
  @spec hide(t()) :: t()
  def hide(state), do: %{state | visible: false}
end
