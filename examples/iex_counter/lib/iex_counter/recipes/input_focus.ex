defmodule IExCounter.Recipes.InputFocus do
  @moduledoc "Two text inputs whose state and focus belong to the parent."

  use TermUI.Elm

  alias TermUI.{Clipboard, Command, Event, Focus, Frame}
  alias TermUI.Widget.TextInput

  @impl true
  def init(opts) do
    %{
      dimensions: Keyword.fetch!(opts, :dimensions),
      focus: Focus.new([:name, :city]),
      inputs: %{name: TextInput.init([]), city: TextInput.init([])},
      status: "Tab: focus   Esc: quit"
    }
  end

  @impl true
  def event_to_msg(%Event.Key{key: :escape}, _state), do: {:msg, :quit}

  def event_to_msg(%Event.Resize{width: width, height: height}, _state),
    do: {:msg, {:resize, width, height}}

  def event_to_msg(event, _state), do: {:msg, {:event, event}}

  @impl true
  def update(:quit, state), do: {state, [Command.shutdown()]}
  def update({:resize, width, height}, state), do: %{state | dimensions: {width, height}}

  def update({:event, %Event.Key{key: :tab} = event}, state) do
    {focus, _messages} = Focus.route(event, state.focus)
    %{state | focus: focus}
  end

  def update({:event, %Event.Focus{} = event}, state) do
    {focus, _messages} = Focus.route(event, state.focus)
    %{state | focus: focus}
  end

  def update({:clipboard_result, :ok}, state), do: %{state | status: "Selection copied"}

  def update({:clipboard_result, {:error, _reason}}, state),
    do: %{state | status: "Copy failed; try again"}

  def update({:event, event}, state) do
    id = state.focus.current
    {input, messages} = TextInput.update(event, Map.fetch!(state.inputs, id))
    commands = for {:copy, text} <- messages, do: Clipboard.copy(text)
    {%{state | inputs: Map.put(state.inputs, id, input)}, commands}
  end

  @impl true
  def view(%{dimensions: {width, height}} = state) do
    base = Frame.from_rows(["Name", "", "City", "", state.status], width, height)

    Enum.reduce([{:name, 2}, {:city, 4}], base, fn {id, row}, frame ->
      child = TextInput.view(Map.fetch!(state.inputs, id), {width, 1})
      child = if Focus.focused?(state.focus, id), do: child, else: %{child | cursor: nil}
      Frame.overlay(frame, child, 1, row)
    end)
  end
end
