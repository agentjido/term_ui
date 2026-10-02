defmodule TermUI.Widget.Helpers do
  @moduledoc false

  alias TermUI.{Cell, Frame, Layout, Style}

  @doc "Builds a frame from widget rows and dimensions."
  @spec frame([Frame.row()], TermUI.Widget.dimensions(), keyword()) :: Frame.t()
  def frame(rows, {width, height}, opts \\ []) do
    Frame.from_rows(rows, width, height, opts)
  end

  @doc "Renders a frame, widget state pair, or pure renderer function."
  @spec render(TermUI.Widget.renderable(), TermUI.Widget.dimensions()) :: Frame.t()
  def render(%Frame{} = frame, _dimensions), do: frame

  def render({module, state}, dimensions) when is_atom(module),
    do: TermUI.Widget.view(module, state, dimensions)

  def render(renderer, dimensions) when is_function(renderer, 1) do
    case renderer.(dimensions) do
      %Frame{} = frame -> frame
      other -> raise ArgumentError, "renderer returned #{inspect(other)}, expected TermUI.Frame"
    end
  end

  @doc "Renders and clips child content inside a frame rectangle."
  @spec compose(Frame.t(), Layout.rect(), TermUI.Widget.renderable()) :: Frame.t()
  def compose(%Frame{} = base, rect, child) do
    case Layout.dimensions(rect) do
      {0, _height} -> base
      {_width, 0} -> base
      dimensions -> Layout.place(base, render(child, dimensions), rect)
    end
  end

  @doc "Clamps an integer between minimum and maximum values."
  @spec clamp(integer(), integer(), integer()) :: integer()
  def clamp(value, minimum, maximum), do: value |> max(minimum) |> min(maximum)

  @doc "Finds the preceding word after skipping spaces on the current line."
  @spec previous_word_start(String.t(), non_neg_integer()) :: non_neg_integer()
  def previous_word_start(value, cursor) do
    {before_cursor, _after_cursor} = String.split_at(value, cursor)

    before_cursor
    |> String.replace(~r/[^\S\r\n]+\z/u, "")
    |> String.replace(~r/\S+\z/u, "")
    |> String.length()
  end

  @doc "Returns the terminal display width of text."
  @spec text_width(iodata()) :: non_neg_integer()
  def text_width(text), do: Cell.text_width(text)

  @doc "Fits and aligns text in a fixed display width."
  @spec align(iodata(), non_neg_integer(), :left | :center | :right) :: String.t()
  def align(_text, 0, _alignment), do: ""

  def align(text, width, alignment) do
    text = Frame.fit(text, width)
    used = text |> String.trim_trailing() |> Cell.text_width()
    room = max(width - used, 0)

    case alignment do
      :right -> String.duplicate(" ", room) <> String.trim_trailing(text)
      :center -> String.duplicate(" ", div(room, 2)) <> String.trim_trailing(text)
      :left -> text
    end
    |> Frame.fit(width)
  end

  @doc "Adds a styled border and optional title around widget rows."
  @spec border([Frame.row()], TermUI.Widget.dimensions(), keyword()) :: [Frame.row()]
  def border(rows, dimensions, opts \\ [])

  def border(rows, {width, height}, opts) when width > 1 and height > 1 do
    title = Keyword.get(opts, :title)
    border_style = Keyword.get(opts, :border_style, Style.new(fg: :bright_black))

    border =
      Keyword.get(opts, :border, %{
        top_left: "┌",
        top_right: "┐",
        bottom_left: "└",
        bottom_right: "┘",
        horizontal: "─",
        vertical: "│"
      })

    inner_width = max(width - 2, 0)
    inner_height = max(height - 2, 0)

    top_text =
      case title do
        nil ->
          String.duplicate(border.horizontal, inner_width)

        text ->
          label = " #{text} "
          label <> String.duplicate(border.horizontal, max(inner_width - text_width(label), 0))
      end

    top = [
      {border.top_left <> Frame.fit(top_text, inner_width) <> border.top_right, border_style}
    ]

    bottom = [
      {border.bottom_left <>
         String.duplicate(border.horizontal, inner_width) <> border.bottom_right, border_style}
    ]

    body =
      rows
      |> Enum.take(inner_height)
      |> then(&(&1 ++ List.duplicate("", max(inner_height - length(&1), 0))))
      |> Enum.map(fn row ->
        [{border.vertical, border_style}] ++
          fit_row(row, inner_width) ++ [{border.vertical, border_style}]
      end)

    [top | body] ++ [bottom]
  end

  def border(rows, _dimensions, _opts), do: rows

  @doc "Converts one frame row to a list of spans."
  @spec normalize_row(Frame.row()) :: [Frame.span()]
  def normalize_row(row), do: Frame.normalize_row(row)

  @doc "Clips one styled row to a display width."
  @spec fit_row(Frame.row(), non_neg_integer()) :: [Frame.span()]
  def fit_row(_row, 0), do: []

  def fit_row(row, width) do
    {spans, used} =
      row
      |> normalize_row()
      |> Enum.reduce_while({[], 0}, fn span, {rendered, used} ->
        fit_span(span, rendered, used, width - used)
      end)

    Enum.reverse(spans) ++ [String.duplicate(" ", max(width - used, 0))]
  end

  defp fit_span(_span, rendered, used, remaining) when remaining <= 0,
    do: {:halt, {rendered, used}}

  defp fit_span(span, rendered, used, remaining) do
    {text, style} = split_span(span)
    {visible, visible_width} = Cell.truncate(IO.iodata_to_binary(text), remaining)
    rendered_span = if style, do: {visible, style}, else: visible
    {:cont, {[rendered_span | rendered], used + visible_width}}
  end

  @doc "Returns one bounded page from a list."
  @spec page([term()], non_neg_integer(), non_neg_integer()) :: [term()]
  def page(items, offset, height), do: Enum.slice(items, max(offset, 0), max(height, 0))

  @doc "Returns the largest valid scroll offset."
  @spec max_scroll(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def max_scroll(content_height, viewport_height), do: max(content_height - viewport_height, 0)

  @doc "Moves and clamps a scroll offset."
  @spec scroll(non_neg_integer(), integer(), non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def scroll(offset, delta, content_height, viewport_height) do
    clamp(offset + delta, 0, max_scroll(content_height, viewport_height))
  end

  defp split_span({text, %Style{} = style}), do: {text, style}
  defp split_span(text), do: {text, nil}
end
