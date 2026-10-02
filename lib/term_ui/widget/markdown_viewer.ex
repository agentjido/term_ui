defmodule TermUI.Widget.MarkdownViewer do
  @moduledoc """
  A pure, scrollable MDEx Markdown viewer with selectable code blocks.

  The optional `:highlighter` is a `TermUI.SyntaxHighlighter` adapter module.
  `:highlight_limit` bounds the source bytes sent to that adapter.

  Scroll positions are row offsets, `:end`, `{:end, distance}`, or
  `{:element, id, relative_rows}`. End distance and element anchors resolve
  against the current render width and height. `{:scrolled, position}` carries
  this same value. Supply dimensions with `update/3` or `set_dimensions/2` to
  bound movement at both ends. `view/2` stays pure.
  """

  @behaviour TermUI.Widget

  alias TermUI.{Event, Frame, Markdown, SyntaxHighlighter}
  alias TermUI.Markdown.Document

  @type t :: %__MODULE__{
          content: String.t(),
          scroll: scroll(),
          dimensions: TermUI.Widget.dimensions() | nil,
          page_size: pos_integer(),
          elements: [Markdown.element()],
          focused: non_neg_integer(),
          content_limit: pos_integer(),
          highlighter: module() | nil,
          highlight_limit: pos_integer(),
          document: Document.t()
        }

  @type scroll ::
          non_neg_integer() | :end | {:end, non_neg_integer()} | {:element, String.t(), integer()}

  defstruct dimensions: nil,
            content: "",
            scroll: 0,
            page_size: 20,
            elements: [],
            focused: 0,
            content_limit: 2_000_000,
            highlighter: nil,
            highlight_limit: 100_000,
            document: %Document{}

  @impl true
  def init(opts) do
    content_limit = max(Keyword.get(opts, :content_limit, 2_000_000), 1)

    document =
      Document.new(Keyword.get(opts, :content, "") |> to_string(), content_limit: content_limit)

    %__MODULE__{
      dimensions: Keyword.get(opts, :dimensions),
      content: document.content,
      page_size: max(Keyword.get(opts, :page_size, 20), 1),
      elements: Markdown.code_blocks(document),
      content_limit: content_limit,
      highlighter: Keyword.get(opts, :highlighter),
      highlight_limit:
        max(Keyword.get(opts, :highlight_limit, SyntaxHighlighter.default_max_bytes()), 1),
      document: document
    }
  end

  @impl true
  def update(%Event.Key{key: :up}, state), do: scroll(state, -1)
  def update(%Event.Key{key: :down}, state), do: scroll(state, 1)
  def update(%Event.Key{key: :page_up}, state), do: scroll(state, -state.page_size)
  def update(%Event.Key{key: :page_down}, state), do: scroll(state, state.page_size)
  def update(%Event.Key{key: :home}, state), do: {%{state | scroll: 0}, []}
  def update(%Event.Key{key: :end}, state), do: {%{state | scroll: :end}, []}

  def update(%Event.Key{key: :tab, modifiers: modifiers}, state),
    do: focus(state, if(:shift in modifiers, do: -1, else: 1))

  def update(%Event.Key{key: :enter}, state), do: copy_focused(state)
  def update(%Event.Text{text: "c"}, state), do: copy_focused(state)
  def update(%Event.Mouse{action: :scroll_up}, state), do: scroll(state, -3)
  def update(%Event.Mouse{action: :scroll_down}, state), do: scroll(state, 3)
  def update(_event, state), do: {state, []}

  @impl true
  def view(state, {width, height} = dimensions) do
    focused_id = state.elements |> Enum.at(state.focused) |> then(&if(&1, do: &1.id))

    result =
      Markdown.render_with_elements(state.document, width,
        focused_element_id: focused_id,
        highlighter: state.highlighter,
        highlight_limit: state.highlight_limit
      )

    offset = resolved_offset(state.scroll, result, height)

    rows = Enum.slice(result.lines, offset, height)
    Frame.from_rows(rows, elem(dimensions, 0), elem(dimensions, 1))
  end

  @doc "Replaces Markdown content and resets navigation."
  @spec set_content(t(), String.t()) :: t()
  def set_content(state, content) do
    document = Document.replace(state.document, content)

    %{
      state
      | content: document.content,
        document: document,
        scroll: 0,
        focused: 0,
        elements: Markdown.code_blocks(document)
    }
  end

  @doc "Appends a Markdown fragment within the configured content bound."
  @spec append(t(), String.t()) :: t()
  def append(state, fragment) do
    document = Document.append(state.document, fragment)
    elements = Markdown.code_blocks(document)

    %{
      state
      | content: document.content,
        document: document,
        elements: elements,
        focused: min(state.focused, max(length(elements) - 1, 0)),
        scroll: :end
    }
  end

  @doc "Stores the current view size for bounded navigation."
  @spec set_dimensions(t(), TermUI.Widget.dimensions()) :: t()
  def set_dimensions(state, {width, height} = dimensions) when width > 0 and height > 0 do
    next = %{state | dimensions: dimensions}

    scroll =
      case next.scroll do
        {:element, _id, _distance} -> next.scroll
        scroll -> bound_scroll(scroll, next)
      end

    %{next | scroll: scroll}
  end

  @impl true
  def update(event, state, dimensions), do: update(event, set_dimensions(state, dimensions))

  defp scroll(state, delta) do
    scroll =
      case state.scroll do
        :end -> end_scroll(max(-delta, 0))
        {:end, distance} -> end_scroll(max(distance - delta, 0))
        {:element, id, distance} -> {:element, id, distance + delta}
        offset -> max(offset + delta, 0)
      end

    scroll = bound_scroll(scroll, state)
    {%{state | scroll: scroll}, [{:scrolled, scroll}]}
  end

  defp bound_scroll(scroll, %{dimensions: nil}), do: scroll

  defp bound_scroll(scroll, state) do
    {width, height} = state.dimensions
    result = Markdown.render_with_elements(state.document, width)
    maximum = max(result.content_height - height, 0)

    case scroll do
      :end -> :end
      {:end, distance} -> end_scroll(min(distance, maximum))
      {:element, _id, _distance} -> resolved_offset(scroll, result, height)
      offset -> min(offset, maximum)
    end
  end

  defp resolved_offset(scroll, result, height) do
    maximum = max(result.content_height - height, 0)

    offset =
      case scroll do
        :end ->
          maximum

        {:end, distance} ->
          maximum - distance

        {:element, id, distance} ->
          element = Enum.find(result.elements, &(&1.id == id))
          if element, do: element.start_line + distance, else: 0

        offset ->
          offset
      end

    offset |> max(0) |> min(maximum)
  end

  defp end_scroll(0), do: :end
  defp end_scroll(distance), do: {:end, distance}

  defp focus(%{elements: []} = state, _delta), do: {state, []}

  defp focus(state, delta) do
    focused = rem(state.focused + delta + length(state.elements), length(state.elements))
    element = Enum.at(state.elements, focused)
    {%{state | focused: focused, scroll: {:element, element.id, 0}}, [{:focused, element}]}
  end

  defp copy_focused(state) do
    case Enum.at(state.elements, state.focused) do
      nil -> {state, []}
      element -> {state, [{:copy, element.content}]}
    end
  end
end
