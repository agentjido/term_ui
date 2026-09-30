defmodule TermUI.Markdown do
  @moduledoc """
  Converts MDEx Markdown documents to styled terminal rows.

  The renderer supports headings, emphasis, strong text, strike-through text,
  inline code, links, images, quotes, lists, task lists, fenced code blocks,
  rules, and tables. Raw HTML is shown as plain text and never becomes terminal
  control data. Fenced blocks can use an optional syntax-highlighter adapter.
  """

  alias TermUI.{DisplayWidth, Frame, Style, SyntaxHighlighter}
  alias TermUI.Markdown.Document
  alias TermUI.Markdown.Parser

  # Styles stored in MDEx node spans contain MapSet's opaque representation.
  @dialyzer {:nowarn_function, inline_node: 2}

  @plain Style.new()
  @heading1 Style.new(fg: :cyan, attrs: [:bold, :underline])
  @heading2 Style.new(fg: :cyan, attrs: [:bold])
  @heading Style.new(attrs: [:bold])
  @strong Style.new(attrs: [:bold])
  @emphasis Style.new(attrs: [:italic])
  @strike Style.new(attrs: [:strikethrough])
  @code Style.new(fg: :yellow)
  @code_border Style.new(fg: :bright_black)
  @quote Style.new(fg: :bright_black)
  @link Style.new(fg: :blue, attrs: [:underline])
  @bullet Style.new(fg: :cyan)
  @rule Style.new(fg: :bright_black)
  @table_header Style.new(fg: :cyan, attrs: [:bold])

  @type styled_line :: [Frame.span()]
  @type element :: %{
          id: String.t(),
          type: :code_block,
          content: String.t(),
          language: String.t() | nil,
          start_line: non_neg_integer(),
          end_line: non_neg_integer()
        }
  @type result :: %{
          lines: [styled_line()],
          elements: [element()],
          content_height: non_neg_integer()
        }

  @doc "Returns true because MDEx is a required dependency."
  @spec available?() :: true
  def available?, do: true

  @doc "Parses Markdown with the supported CommonMark extensions."
  @spec parse(String.t()) :: {:ok, MDEx.Document.t()} | {:error, term()}
  defdelegate parse(markdown), to: Parser

  @doc "Renders Markdown to styled terminal rows."
  @spec render(String.t() | Document.t(), pos_integer(), keyword()) :: [styled_line()]
  def render(markdown, width, opts \\ []) do
    render_with_elements(markdown, width, opts).lines
  end

  @doc "Renders Markdown and returns code-block metadata."
  @spec render_with_elements(String.t() | Document.t(), pos_integer(), keyword()) :: result()
  def render_with_elements(markdown, width, opts \\ [])

  def render_with_elements(%Document{} = document, width, opts) when width > 0 do
    groups =
      Enum.map(document.segments, &{:nodes, &1.nodes}) ++
        if(document.pending == "", do: [], else: [pending_group(document.pending)])

    {lines, elements} = render_groups(groups, width, opts)
    lines = if lines == [], do: [[""]], else: trim_blank_tail(lines)
    %{lines: lines, elements: elements, content_height: length(lines)}
  end

  def render_with_elements(markdown, width, opts) when is_binary(markdown) and width > 0 do
    case parse(markdown) do
      {:ok, %MDEx.Document{nodes: nodes}} ->
        {lines, elements} = render_nodes(nodes, width, opts)
        lines = if lines == [], do: [[""]], else: trim_blank_tail(lines)
        %{lines: lines, elements: elements, content_height: length(lines)}

      {:error, _reason} ->
        lines =
          markdown |> String.split("\n", trim: false) |> Enum.flat_map(&wrap_spans([&1], width))

        %{lines: lines, elements: [], content_height: length(lines)}
    end
  end

  @doc "Returns code blocks in source order without rendering the document."
  @spec code_blocks(String.t() | Document.t()) :: [element()]
  def code_blocks(markdown) do
    render_with_elements(markdown, 80).elements
  end

  defp render_nodes(nodes, width, opts, start_index \\ 0) do
    {lines, elements, _index} =
      Enum.reduce(nodes, {[], [], start_index}, fn node, {lines, elements, line_index} ->
        {node_lines, node_elements} = render_block(node, width, opts, line_index)
        separator = if lines == [] or node_lines == [], do: [], else: [[""]]
        start_shift = length(separator)
        node_elements = Enum.map(node_elements, &shift_element(&1, start_shift))
        next_lines = lines ++ separator ++ node_lines
        {next_lines, elements ++ node_elements, start_index + length(next_lines)}
      end)

    {lines, elements}
  end

  defp pending_group(pending) do
    case parse(pending) do
      {:ok, %MDEx.Document{nodes: nodes}} -> {:nodes, nodes}
      {:error, _reason} -> {:source, pending}
    end
  end

  defp render_groups(groups, width, opts) do
    Enum.reduce(groups, {[], []}, fn group, {lines, elements} ->
      separator = if lines == [], do: [], else: [[""]]
      start_index = length(lines) + length(separator)

      {group_lines, group_elements} =
        case group do
          {:nodes, nodes} ->
            render_nodes(nodes, width, opts, start_index)

          {:source, source} ->
            rendered =
              source |> String.split("\n", trim: false) |> Enum.flat_map(&wrap_spans([&1], width))

            {rendered, []}
        end

      {lines ++ separator ++ group_lines, elements ++ group_elements}
    end)
  end

  defp render_block(%MDEx.Heading{nodes: nodes, level: level}, width, _focused, _index) do
    style =
      case level do
        1 -> @heading1
        2 -> @heading2
        _ -> @heading
      end

    {wrap_spans(inline(nodes, style), width), []}
  end

  defp render_block(%MDEx.Paragraph{nodes: nodes}, width, _focused, _index),
    do: {wrap_spans(inline(nodes, @plain), width), []}

  defp render_block(%MDEx.BlockQuote{nodes: nodes}, width, opts, line_index) do
    {lines, elements} =
      render_nodes_without_spacing(nodes, max(width - 2, 1), opts, line_index)

    quoted = Enum.map(lines, fn line -> [{"│ ", @quote} | line] end)
    {quoted, elements}
  end

  defp render_block(%MDEx.List{} = list, width, opts, line_index) do
    {lines, elements, _number} =
      Enum.reduce(list.nodes, {[], [], list.start || 1}, fn item, {lines, elements, number} ->
        marker = list_marker(list, item, number)

        {item_lines, item_elements} =
          render_list_item(
            item,
            max(width - DisplayWidth.width(marker), 1),
            opts,
            line_index + length(lines)
          )

        item_lines = Enum.with_index(item_lines, &prefix_list_line(&1, &2, marker))

        {lines ++ item_lines, elements ++ item_elements, number + 1}
      end)

    {lines, elements}
  end

  defp render_block(%MDEx.CodeBlock{literal: code, info: info}, width, opts, line_index) do
    language = info |> to_string() |> String.trim() |> empty_to_nil()
    id = "code-" <> Integer.to_string(:erlang.phash2({code, line_index}))
    focused_id = Keyword.get(opts, :focused_element_id)
    focused? = id == focused_id
    border_style = if focused?, do: Style.new(fg: :cyan, attrs: [:bold]), else: @code_border

    label =
      if language,
        do: "─ " <> language <> if(focused?, do: " [selected] ", else: " "),
        else: if(focused?, do: "─ [selected] ", else: "─")

    top = [[{"┌" <> Frame.fit(label, max(width - 1, 0)), border_style}]]

    body =
      code
      |> String.trim_trailing("\n")
      |> SyntaxHighlighter.lines(language,
        adapter: Keyword.get(opts, :highlighter),
        max_bytes: Keyword.get(opts, :highlight_limit, SyntaxHighlighter.default_max_bytes())
      )
      |> Enum.flat_map(fn line -> wrap_spans([{"│ ", border_style} | line], width) end)

    bottom = [[{"└" <> String.duplicate("─", max(width - 1, 0)), border_style}]]
    lines = top ++ body ++ bottom

    element = %{
      id: id,
      type: :code_block,
      content: code,
      language: language,
      start_line: line_index,
      end_line: line_index + length(lines) - 1
    }

    {lines, [element]}
  end

  defp render_block(%MDEx.ThematicBreak{}, width, _focused, _index),
    do: {[[{String.duplicate("─", width), @rule}]], []}

  defp render_block(%MDEx.Table{nodes: rows, alignments: alignments}, width, _focused, _index) do
    column_count = rows |> List.first(%{nodes: []}) |> Map.get(:nodes, []) |> length() |> max(1)
    column_width = max(div(max(width - column_count - 1, column_count), column_count), 1)

    rendered =
      Enum.map(rows, fn %MDEx.TableRow{nodes: cells, header: header?} ->
        style = if header?, do: @table_header, else: @plain

        cells
        |> Enum.with_index()
        |> Enum.flat_map(fn {%MDEx.TableCell{nodes: nodes}, index} ->
          alignment = Enum.at(alignments, index, :left) |> normalize_alignment()
          text = nodes |> inline(@plain) |> plain_text()
          [{"│", @rule}, {align(text, column_width, alignment), style}]
        end)
        |> Kernel.++([{"│", @rule}])
      end)

    {rendered, []}
  end

  defp render_block(%{literal: literal}, width, _focused, _index) when is_binary(literal) do
    text = Regex.replace(~r/<[^>]*>/u, literal, "")
    {text |> String.split("\n", trim: false) |> Enum.flat_map(&wrap_spans([&1], width)), []}
  end

  defp render_block(%{nodes: nodes}, width, opts, line_index) when is_list(nodes),
    do: render_nodes_without_spacing(nodes, width, opts, line_index)

  defp render_block(_node, _width, _focused, _index), do: {[], []}

  defp align(text, width, alignment) do
    text = Frame.fit(text, width)
    content = String.trim_trailing(text)
    room = max(width - DisplayWidth.width(content), 0)

    case alignment do
      :right -> String.duplicate(" ", room) <> content
      :center -> String.duplicate(" ", div(room, 2)) <> content
      :left -> text
    end
    |> Frame.fit(width)
  end

  defp prefix_list_line(line, 0, marker), do: [{marker, @bullet} | line]

  defp prefix_list_line(line, _index, marker),
    do: [{String.duplicate(" ", String.length(marker)), @bullet} | line]

  defp render_list_item(%{nodes: nodes}, width, opts, line_index),
    do: render_nodes_without_spacing(nodes, width, opts, line_index)

  defp render_nodes_without_spacing(nodes, width, opts, line_index) do
    {lines, elements, _index} =
      Enum.reduce(nodes, {[], [], line_index}, fn node, {lines, elements, index} ->
        {node_lines, node_elements} = render_block(node, width, opts, index)
        {lines ++ node_lines, elements ++ node_elements, index + length(node_lines)}
      end)

    {lines, elements}
  end

  defp inline(nodes, style), do: Enum.flat_map(nodes, &inline_node(&1, style))
  defp inline_node(%MDEx.Text{literal: literal}, style), do: [{literal, style}]

  defp inline_node(%MDEx.Code{literal: literal}, style),
    do: [{literal, Style.merge(style, @code)}]

  defp inline_node(%MDEx.Strong{nodes: nodes}, style),
    do: inline(nodes, Style.merge(style, @strong))

  defp inline_node(%MDEx.Emph{nodes: nodes}, style),
    do: inline(nodes, Style.merge(style, @emphasis))

  defp inline_node(%MDEx.Strikethrough{nodes: nodes}, style),
    do: inline(nodes, Style.merge(style, @strike))

  defp inline_node(%MDEx.Link{nodes: nodes}, style), do: inline(nodes, Style.merge(style, @link))

  defp inline_node(%MDEx.Image{nodes: nodes}, style),
    do: [{"[image: " <> plain_text(inline(nodes, style)) <> "]", Style.merge(style, @link)}]

  defp inline_node(%{nodes: nodes}, style) when is_list(nodes), do: inline(nodes, style)
  defp inline_node(%{literal: literal}, style) when is_binary(literal), do: [{literal, style}]
  defp inline_node(_node, _style), do: []

  defp wrap_spans(spans, width) do
    {lines, current, _used} =
      Enum.reduce(spans, {[], [], 0}, fn span, acc -> add_span(span, acc, width) end)

    Enum.reverse([Enum.reverse(current) | lines])
  end

  defp add_span({text, %Style{} = style}, acc, width),
    do: add_graphemes(IO.iodata_to_binary(text), style, acc, width)

  defp add_span(text, acc, width),
    do: add_graphemes(IO.iodata_to_binary(text), @plain, acc, width)

  defp add_graphemes(text, style, acc, width) do
    text
    |> String.graphemes()
    |> Enum.reduce(acc, fn
      "\n", {lines, current, _used} ->
        {[Enum.reverse(current) | lines], [], 0}

      grapheme, {lines, current, used} ->
        grapheme_width = max(DisplayWidth.width(grapheme), 0)

        if current != [] and used + grapheme_width > width,
          do: {[Enum.reverse(current) | lines], [{grapheme, style}], grapheme_width},
          else: {lines, merge_grapheme(current, grapheme, style), used + grapheme_width}
    end)
  end

  defp merge_grapheme([{text, style} | rest], grapheme, style),
    do: [{text <> grapheme, style} | rest]

  defp merge_grapheme(current, grapheme, style), do: [{grapheme, style} | current]

  defp list_marker(%MDEx.List{list_type: :ordered}, _item, number), do: "#{number}. "
  defp list_marker(_list, %MDEx.TaskItem{checked: true}, _number), do: "[x] "
  defp list_marker(_list, %MDEx.TaskItem{}, _number), do: "[ ] "
  defp list_marker(_list, _item, _number), do: "• "

  defp plain_text(spans),
    do:
      Enum.map_join(spans, fn
        {text, _style} -> IO.iodata_to_binary(text)
        text -> IO.iodata_to_binary(text)
      end)

  defp normalize_alignment(:center), do: :center
  defp normalize_alignment(:right), do: :right
  defp normalize_alignment(_alignment), do: :left
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(text), do: text

  defp trim_blank_tail(lines),
    do: Enum.reverse(Enum.drop_while(Enum.reverse(lines), &(&1 in [[], [""]])))

  defp shift_element(element, 0), do: element

  defp shift_element(element, shift),
    do: %{element | start_line: element.start_line + shift, end_line: element.end_line + shift}
end
