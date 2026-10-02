defmodule IExCounter.Recipes.Stream do
  @moduledoc "A bounded stream fed by an application-owned async command."

  use TermUI.Elm

  alias TermUI.{Command, Event, Frame}
  alias TermUI.Widget.Stream

  @impl true
  def init(opts) do
    %{
      dimensions: Keyword.fetch!(opts, :dimensions),
      stream: Stream.init(limit: 3, overflow: :drop_oldest),
      loader: Keyword.get(opts, :loader, fn -> ["alpha", "beta", "gamma", "delta"] end),
      loading: false,
      status: "L: load   F: fail   Space: pause"
    }
  end

  @impl true
  def event_to_msg(%Event.Key{key: :escape}, _state), do: {:msg, :quit}

  def event_to_msg(%Event.Resize{width: width, height: height}, _state),
    do: {:msg, {:resize, width, height}}

  def event_to_msg(%Event.Text{text: text}, _state) when text in ["l", "L"], do: {:msg, :load}
  def event_to_msg(%Event.Text{text: text}, _state) when text in ["f", "F"], do: {:msg, :fail}
  def event_to_msg(event, _state), do: {:msg, {:event, event}}

  @impl true
  def update(:quit, state), do: {state, [Command.shutdown()]}
  def update({:resize, width, height}, state), do: %{state | dimensions: {width, height}}
  def update(message, %{loading: true} = state) when message in [:load, :fail], do: state
  def update(:load, state), do: load(state, state.loader)
  def update(:fail, state), do: load(state, fn -> raise "sample failure" end)

  def update({:loaded, {:ok, items}}, state) when is_list(items) do
    {stream, result} = Stream.offer_many(state.stream, items)

    status =
      "Accepted: #{result.accepted} Dropped: #{result.dropped} Rejected: #{result.rejected}"

    %{state | stream: stream, loading: false, status: status}
  end

  def update({:loaded, _failure}, state),
    do: %{state | loading: false, status: "Load failed; press L to retry"}

  def update({:event, event}, state) do
    {width, height} = state.dimensions
    {stream, _messages} = Stream.update(event, state.stream, {width, max(height - 2, 1)})
    %{state | stream: stream}
  end

  @impl true
  def view(%{dimensions: {width, height}} = state) do
    Frame.new(width, height)
    |> Frame.overlay(Stream.view(state.stream, {width, max(height - 2, 1)}), 1, 1)
    |> Frame.put_row(max(height - 1, 1), state.status)
    |> Frame.put_row(height, "Esc: quit")
  end

  defp load(state, function) do
    {%{state | loading: true, status: "Loading"}, [Command.async(function, &{:loaded, &1})]}
  end
end
