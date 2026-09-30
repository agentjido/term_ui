defmodule TermUI.Widget.ScrollBar do
  @moduledoc "A pure vertical or horizontal scrollbar."

  @behaviour TermUI.Widget

  alias TermUI.{Event, Style}
  alias TermUI.Widget.Helpers

  @type t :: %__MODULE__{
          orientation: :vertical | :horizontal,
          content_size: non_neg_integer(),
          viewport_size: non_neg_integer(),
          offset: non_neg_integer(),
          dragging: boolean()
        }

  defstruct orientation: :vertical,
            content_size: 0,
            viewport_size: 0,
            offset: 0,
            dragging: false

  @impl true
  def init(opts) do
    %__MODULE__{
      orientation: Keyword.get(opts, :orientation, :vertical),
      content_size: max(Keyword.get(opts, :content_size, 0), 0),
      viewport_size: max(Keyword.get(opts, :viewport_size, 0), 0),
      offset: max(Keyword.get(opts, :offset, 0), 0),
      dragging: false
    }
    |> normalize()
  end

  @impl true
  def update(%Event.Key{key: key}, state) when key in [:up, :left], do: move(state, -1)
  def update(%Event.Key{key: key}, state) when key in [:down, :right], do: move(state, 1)
  def update(%Event.Key{key: :page_up}, state), do: move(state, -state.viewport_size)
  def update(%Event.Key{key: :page_down}, state), do: move(state, state.viewport_size)
  def update(_event, state), do: {state, []}

  @impl true
  def mouse(%Event.Mouse{action: :press, button: :left} = event, state, dimensions) do
    state
    |> Map.put(:dragging, true)
    |> move_to_pointer(event, dimensions)
  end

  def mouse(
        %Event.Mouse{action: :drag, button: :left} = event,
        %{dragging: true} = state,
        dimensions
      ),
      do: move_to_pointer(state, event, dimensions)

  def mouse(%Event.Mouse{action: :release, button: :left}, state, _dimensions),
    do: {%{state | dragging: false}, []}

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(%{orientation: :horizontal} = state, {width, _height} = dimensions) do
    {start, thumb} = thumb(state, width)

    track =
      String.duplicate("─", start) <>
        String.duplicate("━", thumb) <> String.duplicate("─", max(width - start - thumb, 0))

    Helpers.frame([[{track, Style.new(fg: :bright_black)}]], dimensions)
  end

  def view(state, {_width, height} = dimensions) do
    {start, thumb} = thumb(state, height)

    rows =
      for index <- 0..(height - 1) do
        char = if index >= start and index < start + thumb, do: "┃", else: "│"
        [{char, Style.new(fg: :bright_black)}]
      end

    Helpers.frame(rows, dimensions)
  end

  @doc "Updates the measured content, viewport, and offset."
  @spec set(t(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: t()
  def set(state, content_size, viewport_size, offset) do
    normalize(%{
      state
      | content_size: max(content_size, 0),
        viewport_size: max(viewport_size, 0),
        offset: max(offset, 0)
    })
  end

  defp move(state, delta) do
    state = normalize(%{state | offset: state.offset + delta})
    {state, [{:scrolled, state.offset}]}
  end

  defp move_to_pointer(state, event, dimensions) do
    {position, track_size} = pointer_position(state.orientation, event, dimensions)
    maximum_offset = max(state.content_size - state.viewport_size, 0)
    denominator = max(track_size - 1, 1)

    offset =
      round(Helpers.clamp(position, 0, max(track_size - 1, 0)) / denominator * maximum_offset)

    state = normalize(%{state | offset: offset})
    {state, [{:scrolled, state.offset}]}
  end

  defp pointer_position(:horizontal, event, {width, _height}), do: {event.x, width}
  defp pointer_position(:vertical, event, {_width, height}), do: {event.y, height}

  defp normalize(state),
    do: %{
      state
      | offset: Helpers.clamp(state.offset, 0, max(state.content_size - state.viewport_size, 0))
    }

  defp thumb(_state, track_size) when track_size <= 0, do: {0, 0}
  defp thumb(%{content_size: size} = _state, track_size) when size <= 0, do: {0, track_size}

  defp thumb(state, track_size) do
    thumb_size = max(round(track_size * min(state.viewport_size / state.content_size, 1.0)), 1)
    maximum_offset = max(state.content_size - state.viewport_size, 1)
    start = round((track_size - thumb_size) * state.offset / maximum_offset)
    {start, thumb_size}
  end
end
