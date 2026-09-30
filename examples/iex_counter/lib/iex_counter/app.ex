defmodule IExCounter.App do
  @moduledoc "A small counter that uses the complete TermUI public contract."

  use TermUI.Elm

  alias TermUI.{Command, Event, Frame, Style}

  @impl true
  def init(opts) do
    %{count: 0, dimensions: Keyword.fetch!(opts, :dimensions)}
  end

  @impl true
  def event_to_msg(%Event.Key{key: :up}, _state), do: {:msg, :increment}
  def event_to_msg(%Event.Key{key: :down}, _state), do: {:msg, :decrement}
  def event_to_msg(%Event.Text{text: text}, _state) when text in ["r", "R"], do: {:msg, :reset}
  def event_to_msg(%Event.Text{text: text}, _state) when text in ["q", "Q"], do: {:msg, :quit}

  def event_to_msg(%Event.Resize{width: width, height: height}, _state),
    do: {:msg, {:resize, width, height}}

  def event_to_msg(_event, _state), do: :ignore

  @impl true
  def update(:increment, state), do: %{state | count: state.count + 1}
  def update(:decrement, state), do: %{state | count: state.count - 1}
  def update(:reset, state), do: %{state | count: 0}
  def update(:quit, state), do: {state, [Command.shutdown()]}
  def update({:resize, width, height}, state), do: %{state | dimensions: {width, height}}

  @impl true
  def view(%{count: count, dimensions: {width, height}}) do
    title = Style.new(fg: :cyan, attrs: [:bold])
    value = Style.new(fg: :green, attrs: [:bold])

    rows = [
      [{"TermUI counter", title}],
      "",
      [{"Count: #{count}", value}],
      "",
      "Up/Down: change   R: reset   Q: quit"
    ]

    Frame.from_rows(rows, width, height)
  end

  @doc "Runs the example in the current terminal."
  def run(opts \\ []), do: TermUI.run(__MODULE__, opts)
end
