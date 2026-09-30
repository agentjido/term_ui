defmodule TermUI.Widget.Viewport do
  @moduledoc """
  A pure viewport for vertically and horizontally scrollable text rows.

  Optional local scrollbars reserve the last row or column. Their drag state
  remains in the widget value. `geometry/2` exposes the measured content,
  viewport, limits, and visible ranges to the parent application.
  """

  @behaviour TermUI.Widget

  alias TermUI.{DisplayWidth, Event, Frame}
  alias TermUI.Widget.{Helpers, ScrollBar}

  @type t :: %__MODULE__{
          rows: [Frame.row()],
          scroll_x: non_neg_integer(),
          scroll_y: non_neg_integer(),
          page_size: pos_integer(),
          follow_end: boolean(),
          scrollbars: :none | :vertical | :horizontal | :both,
          dragging: :vertical | :horizontal | nil
        }

  @type geometry :: %{
          content_width: non_neg_integer(),
          content_height: non_neg_integer(),
          viewport_width: pos_integer(),
          viewport_height: pos_integer(),
          max_scroll_x: non_neg_integer(),
          max_scroll_y: non_neg_integer(),
          scroll_x: non_neg_integer(),
          scroll_y: non_neg_integer(),
          visible_columns: Range.t() | nil,
          visible_rows: Range.t() | nil
        }

  defstruct rows: [],
            scroll_x: 0,
            scroll_y: 0,
            page_size: 10,
            follow_end: false,
            scrollbars: :none,
            dragging: nil

  @impl true
  def init(opts) do
    %__MODULE__{
      rows: normalize_content(Keyword.get(opts, :content, [])),
      scroll_x: max(Keyword.get(opts, :scroll_x, 0), 0),
      scroll_y: max(Keyword.get(opts, :scroll_y, 0), 0),
      page_size: max(Keyword.get(opts, :page_size, 10), 1),
      follow_end: Keyword.get(opts, :follow_end, false),
      scrollbars: normalize_scrollbars(Keyword.get(opts, :scrollbars, :none))
    }
  end

  @impl true
  def update(%Event.Key{key: :up}, state), do: scroll(state, 0, -1)
  def update(%Event.Key{key: :down}, state), do: scroll(state, 0, 1)
  def update(%Event.Key{key: :left}, state), do: scroll(state, -1, 0)
  def update(%Event.Key{key: :right}, state), do: scroll(state, 1, 0)
  def update(%Event.Key{key: :page_up}, state), do: scroll(state, 0, -state.page_size)
  def update(%Event.Key{key: :page_down}, state), do: scroll(state, 0, state.page_size)

  def update(%Event.Key{key: :home, modifiers: modifiers}, state) do
    if :ctrl in modifiers, do: {%{state | scroll_y: 0}, []}, else: {%{state | scroll_x: 0}, []}
  end

  def update(%Event.Key{key: :end, modifiers: modifiers}, state) do
    if :ctrl in modifiers,
      do: {%{state | scroll_y: max(length(state.rows) - state.page_size, 0)}, []},
      else: {state, []}
  end

  def update(%Event.Mouse{action: :scroll_up}, state), do: scroll(state, 0, -3)
  def update(%Event.Mouse{action: :scroll_down}, state), do: scroll(state, 0, 3)
  def update(_event, state), do: {state, []}

  @impl true
  def mouse(%Event.Mouse{action: :press, button: :left} = event, state, dimensions) do
    case scrollbar_at(state, event, dimensions) do
      nil -> update(event, state)
      axis -> drag_scrollbar(%{state | dragging: axis}, axis, event, dimensions)
    end
  end

  def mouse(
        %Event.Mouse{action: :drag, button: :left} = event,
        %{dragging: axis} = state,
        dimensions
      )
      when axis in [:vertical, :horizontal],
      do: drag_scrollbar(state, axis, event, dimensions)

  def mouse(%Event.Mouse{action: :release, button: :left}, state, _dimensions),
    do: {%{state | dragging: nil}, []}

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(state, {width, height} = dimensions) do
    geometry = geometry(state, dimensions)

    offset =
      if state.follow_end,
        do: geometry.max_scroll_y,
        else: geometry.scroll_y

    rows =
      state.rows
      |> Enum.slice(offset, geometry.viewport_height)
      |> Enum.map(fn row ->
        row |> plain_text() |> drop_width(geometry.scroll_x) |> Frame.fit(geometry.viewport_width)
      end)

    base =
      Frame.new(width, height)
      |> Frame.overlay(
        Helpers.frame(rows, {geometry.viewport_width, geometry.viewport_height}),
        1,
        1
      )

    draw_scrollbars(base, state, geometry)
  end

  @doc "Replaces the content rows and keeps the scroll position valid."
  @spec set_content(t(), String.t() | [Frame.row()]) :: t()
  def set_content(state, content) do
    rows = normalize_content(content)

    scroll_y =
      if state.follow_end,
        do: max(length(rows) - state.page_size, 0),
        else: min(state.scroll_y, max(length(rows) - 1, 0))

    %{state | rows: rows, scroll_y: scroll_y}
  end

  @doc "Returns the horizontal and vertical scroll offsets."
  @spec position(t()) :: {non_neg_integer(), non_neg_integer()}
  def position(state), do: {state.scroll_x, state.scroll_y}

  @doc "Returns content size, viewport size, bounded offsets, and visible ranges."
  @spec geometry(t(), TermUI.Widget.dimensions()) :: geometry()
  def geometry(state, {width, height}) when width > 0 and height > 0 do
    vertical? = vertical_scrollbar?(state.scrollbars) and width > 1
    horizontal? = horizontal_scrollbar?(state.scrollbars) and height > 1
    viewport_width = max(width - if(vertical?, do: 1, else: 0), 1)
    viewport_height = max(height - if(horizontal?, do: 1, else: 0), 1)
    {content_width, content_height} = content_dimensions(state)
    max_scroll_x = max(content_width - viewport_width, 0)
    max_scroll_y = max(content_height - viewport_height, 0)
    scroll_x = Helpers.clamp(state.scroll_x, 0, max_scroll_x)
    scroll_y = Helpers.clamp(state.scroll_y, 0, max_scroll_y)

    %{
      content_width: content_width,
      content_height: content_height,
      viewport_width: viewport_width,
      viewport_height: viewport_height,
      max_scroll_x: max_scroll_x,
      max_scroll_y: max_scroll_y,
      scroll_x: scroll_x,
      scroll_y: scroll_y,
      visible_columns: visible_range(scroll_x, viewport_width, content_width),
      visible_rows: visible_range(scroll_y, viewport_height, content_height)
    }
  end

  @doc "Returns the maximum display width and the row count."
  @spec content_dimensions(t()) :: {non_neg_integer(), non_neg_integer()}
  def content_dimensions(state) do
    width =
      state.rows
      |> Enum.map(&plain_text/1)
      |> Enum.map(&DisplayWidth.width/1)
      |> Enum.max(fn -> 0 end)

    {width, length(state.rows)}
  end

  @doc "Moves the viewport enough to include a zero-based content position."
  @spec scroll_into_view(t(), {non_neg_integer(), non_neg_integer()}, TermUI.Widget.dimensions()) ::
          t()
  def scroll_into_view(state, {x, y}, dimensions) when x >= 0 and y >= 0 do
    geometry = geometry(state, dimensions)

    scroll_x = reveal(x, geometry.scroll_x, geometry.viewport_width, geometry.max_scroll_x)
    scroll_y = reveal(y, geometry.scroll_y, geometry.viewport_height, geometry.max_scroll_y)
    %{state | scroll_x: scroll_x, scroll_y: scroll_y, follow_end: false}
  end

  defp scroll(state, dx, dy) do
    {max_x, _height} = content_dimensions(state)

    max_y = max(length(state.rows) - state.page_size, 0)

    next = %{
      state
      | scroll_x: Helpers.clamp(state.scroll_x + dx, 0, max_x),
        scroll_y: Helpers.clamp(state.scroll_y + dy, 0, max_y),
        follow_end: false
    }

    {next, [{:scrolled, {next.scroll_x, next.scroll_y}}]}
  end

  defp drag_scrollbar(state, :vertical, event, dimensions) do
    geometry = geometry(state, dimensions)

    scrollbar =
      ScrollBar.init(
        content_size: geometry.content_height,
        viewport_size: geometry.viewport_height,
        offset: geometry.scroll_y
      )

    local_event = %{event | x: 0, action: :press}

    {scrollbar, _messages} =
      ScrollBar.mouse(local_event, scrollbar, {1, geometry.viewport_height})

    next = %{state | scroll_y: scrollbar.offset, follow_end: false}
    {next, [{:scrolled, {next.scroll_x, next.scroll_y}}]}
  end

  defp drag_scrollbar(state, :horizontal, event, dimensions) do
    geometry = geometry(state, dimensions)

    scrollbar =
      ScrollBar.init(
        orientation: :horizontal,
        content_size: geometry.content_width,
        viewport_size: geometry.viewport_width,
        offset: geometry.scroll_x
      )

    local_event = %{event | y: 0, action: :press}
    {scrollbar, _messages} = ScrollBar.mouse(local_event, scrollbar, {geometry.viewport_width, 1})
    next = %{state | scroll_x: scrollbar.offset, follow_end: false}
    {next, [{:scrolled, {next.scroll_x, next.scroll_y}}]}
  end

  defp draw_scrollbars(frame, state, geometry) do
    frame =
      if vertical_scrollbar?(state.scrollbars) and frame.width > 1 do
        scrollbar =
          ScrollBar.init(
            content_size: geometry.content_height,
            viewport_size: geometry.viewport_height,
            offset: geometry.scroll_y
          )

        Frame.overlay(
          frame,
          ScrollBar.view(scrollbar, {1, geometry.viewport_height}),
          frame.width,
          1
        )
      else
        frame
      end

    if horizontal_scrollbar?(state.scrollbars) and frame.height > 1 do
      scrollbar =
        ScrollBar.init(
          orientation: :horizontal,
          content_size: geometry.content_width,
          viewport_size: geometry.viewport_width,
          offset: geometry.scroll_x
        )

      Frame.overlay(
        frame,
        ScrollBar.view(scrollbar, {geometry.viewport_width, 1}),
        1,
        frame.height
      )
    else
      frame
    end
  end

  defp scrollbar_at(state, event, {width, height}) do
    cond do
      vertical_hit?(state, event, width, height) ->
        :vertical

      horizontal_hit?(state, event, width, height) ->
        :horizontal

      true ->
        nil
    end
  end

  defp vertical_hit?(state, event, width, height) do
    track_height = height - if(horizontal_scrollbar?(state.scrollbars), do: 1, else: 0)

    vertical_scrollbar?(state.scrollbars) and width > 1 and event.x == width - 1 and
      event.y < track_height
  end

  defp horizontal_hit?(state, event, width, height) do
    track_width = width - if(vertical_scrollbar?(state.scrollbars), do: 1, else: 0)

    horizontal_scrollbar?(state.scrollbars) and height > 1 and event.y == height - 1 and
      event.x < track_width
  end

  defp normalize_scrollbars(true), do: :both
  defp normalize_scrollbars(false), do: :none
  defp normalize_scrollbars(value) when value in [:none, :vertical, :horizontal, :both], do: value

  defp normalize_scrollbars(value) do
    raise ArgumentError,
          "viewport scrollbars must be :none, :vertical, :horizontal, :both, or a boolean, got: #{inspect(value)}"
  end

  defp vertical_scrollbar?(value), do: value in [:vertical, :both]
  defp horizontal_scrollbar?(value), do: value in [:horizontal, :both]

  defp visible_range(_start, _size, 0), do: nil
  defp visible_range(start, size, total), do: start..min(start + size - 1, total - 1)

  defp reveal(position, offset, size, maximum) do
    cond do
      position < offset -> position
      position >= offset + size -> position - size + 1
      true -> offset
    end
    |> Helpers.clamp(0, maximum)
  end

  defp normalize_content(content) when is_binary(content),
    do: String.split(content, "\n", trim: false)

  defp normalize_content(content) when is_list(content), do: content
  defp normalize_content(content), do: [to_string(content)]
  defp plain_text(row) when is_binary(row), do: row

  defp plain_text(row),
    do:
      Enum.map_join(row, fn
        {text, _style} -> IO.iodata_to_binary(text)
        text -> IO.iodata_to_binary(text)
      end)

  defp drop_width(text, 0), do: text
  defp drop_width(text, width), do: text |> String.graphemes() |> do_drop_width(width)

  defp do_drop_width(graphemes, width) when width <= 0, do: Enum.join(graphemes)
  defp do_drop_width([], _width), do: ""

  defp do_drop_width([grapheme | rest], width) do
    grapheme_width = max(DisplayWidth.width(grapheme), 0)

    if grapheme_width <= width,
      do: do_drop_width(rest, width - grapheme_width),
      else: " " <> Enum.join(rest)
  end
end
