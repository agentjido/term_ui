defmodule TermUIWebExample.App do
  @moduledoc false
  use TermUI.Elm

  alias TermUI.{Command, Event, Frame, Style}

  @impl true
  def init(opts) do
    %{dimensions: Keyword.fetch!(opts, :dimensions), count: 0, text: "", last: "Ready"}
  end

  @impl true
  def event_to_msg(event, _state), do: {:msg, {:event, event}}

  @impl true
  def update({:event, %Event.Text{text: "q"}}, state), do: {state, [Command.shutdown(:normal)]}

  def update({:event, %Event.Text{text: " "}}, state),
    do: %{state | count: state.count + 1, last: "Space"}

  def update({:event, %Event.Text{text: text}}, state),
    do: %{state | text: String.slice(state.text <> text, -4_096, 4_096), last: "Text"}

  def update({:event, %Event.Key{key: :up}}, state),
    do: %{state | count: state.count + 1, last: "Up"}

  def update({:event, %Event.Paste{content: text}}, state),
    do: %{state | text: String.slice(state.text <> text, -4_096, 4_096), last: "Paste"}

  def update({:event, %Event.Resize{width: width, height: height}}, state),
    do: %{state | dimensions: {width, height}}

  def update({:event, %Event.Key{key: key, modifiers: modifiers}}, state),
    do: %{state | last: "Key #{inspect(key)} #{inspect(modifiers)}"}

  def update({:event, %Event.Mouse{x: x, y: y, action: action}}, state),
    do: %{state | last: "Mouse #{action} #{x},#{y}"}

  def update({:event, %Event.Focus{action: action}}, state),
    do: %{state | last: "Focus #{action}"}

  @impl true
  def view(state) do
    {width, height} = state.dimensions
    title = Style.new(fg: {:rgb, 240, 200, 20}, bold: true)
    blue = Style.new(bg: {:rgb, 10, 20, 180})

    Frame.from_rows(
      [
        [{"TermUI Web · #{width} × #{height}", title}],
        "Space or Up: add one. q: close. Reconnect: new state.",
        [{"Count: #{state.count}", blue}],
        "Text: #{state.text}",
        "Last: #{state.last}",
        "Unicode: é 界 👩‍💻",
        [{"Underline", Style.new(underline: true)}, {"  Reverse", Style.new(reverse: true)}]
      ],
      width,
      height,
      cursor: {min(width, 7), min(height, 4)}
    )
  end
end
