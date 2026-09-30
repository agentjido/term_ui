defmodule TermUI.Widget.Block do
  @moduledoc "A bordered content block that produces a frame."

  @behaviour TermUI.Widget

  alias TermUI.{Frame, Layout, Style}
  alias TermUI.Widget.Helpers

  @type t :: %__MODULE__{
          rows: [Frame.row()],
          title: String.t() | nil,
          padding: non_neg_integer(),
          style: Style.t(),
          border_style: Style.t()
        }

  defstruct rows: [],
            title: nil,
            padding: 0,
            style: %Style{},
            border_style: %Style{fg: :bright_black}

  @impl true
  def init(opts) do
    %__MODULE__{
      rows: normalize_content(Keyword.get(opts, :content, Keyword.get(opts, :rows, []))),
      title: Keyword.get(opts, :title),
      padding: max(Keyword.get(opts, :padding, 0), 0),
      style: Keyword.get(opts, :style, Style.new()),
      border_style: Keyword.get(opts, :border_style, Style.new(fg: :bright_black))
    }
  end

  @impl true
  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, _height} = dimensions) do
    inner_width = max(width - 2 - state.padding * 2, 0)
    padding = String.duplicate(" ", state.padding)

    rows =
      List.duplicate("", state.padding) ++
        Enum.flat_map(state.rows, fn row ->
          row
          |> wrap_row(max(inner_width, 1), state.style)
          |> Enum.map(fn line -> [{padding, state.style}] ++ line ++ [{padding, state.style}] end)
        end) ++ List.duplicate("", state.padding)

    rows = Helpers.border(rows, dimensions, title: state.title, border_style: state.border_style)
    Helpers.frame(rows, dimensions)
  end

  @doc "Replaces the block content."
  @spec set_content(t(), String.t() | [Frame.row()]) :: t()
  def set_content(state, content), do: %{state | rows: normalize_content(content)}

  @doc "Returns the zero-based rectangle available to child content."
  @spec content_rect(t(), TermUI.Widget.dimensions()) :: Layout.rect()
  def content_rect(state, dimensions) do
    border = if elem(dimensions, 0) > 1 and elem(dimensions, 1) > 1, do: 1, else: 0
    dimensions |> Layout.new() |> Layout.inset(border + state.padding)
  end

  @doc "Renders and clips pure child content inside the block."
  @spec compose(t(), TermUI.Widget.dimensions(), TermUI.Widget.renderable()) :: Frame.t()
  def compose(state, dimensions, child) do
    Helpers.compose(view(state, dimensions), content_rect(state, dimensions), child)
  end

  defp normalize_content(content) when is_binary(content),
    do: String.split(content, "\n", trim: false)

  defp normalize_content(content) when is_list(content), do: content
  defp normalize_content(content), do: [to_string(content)]

  defp wrap_row(row, width, style) when is_binary(row) do
    row
    |> Frame.wrap(width)
    |> Enum.map(&[{&1, style}])
  end

  defp wrap_row(row, width, default_style) when is_list(row) do
    row
    |> styled_graphemes(default_style)
    |> Enum.reduce({[], [], 0}, fn {grapheme, style}, {lines, current, used} ->
      grapheme_width = Helpers.text_width(grapheme)

      cond do
        grapheme == "\n" ->
          {[Enum.reverse(current) | lines], [], 0}

        current != [] and used + grapheme_width > width ->
          {[Enum.reverse(current) | lines], [{grapheme, style}], grapheme_width}

        true ->
          {lines, [{grapheme, style} | current], used + grapheme_width}
      end
    end)
    |> then(fn {lines, current, _used} -> Enum.reverse([Enum.reverse(current) | lines]) end)
  end

  defp styled_graphemes(row, default_style) do
    Enum.flat_map(row, fn
      {text, %Style{} = style} -> graphemes_with_style(text, style)
      text -> graphemes_with_style(text, default_style)
    end)
  end

  defp graphemes_with_style(text, style) do
    text
    |> IO.iodata_to_binary()
    |> String.graphemes()
    |> Enum.map(&{&1, style})
  end
end
