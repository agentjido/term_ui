defmodule TermUI.Cycle1RenderingTest do
  use ExUnit.Case, async: true

  alias TermUI.Backend.Renderer
  alias TermUI.{Cell, DisplayWidth, Frame, Markdown, Style, SyntaxHighlighter, Theme}
  alias TermUI.Markdown.Document
  alias TermUI.Test.AnsiScreen
  alias TermUI.Widget.MarkdownViewer

  defmodule SplitAdapter do
    @behaviour SyntaxHighlighter
    def highlight(source, _language) do
      {:ok,
       source
       |> String.codepoints()
       |> Enum.with_index()
       |> Enum.map(fn {text, index} ->
         {if(rem(index, 2) == 0, do: :name, else: :keyword), text}
       end)}
    end
  end

  test "standalone zero-width cells emit one column in frames and sparse differences" do
    for mark <- ["\u200B", "\u2060", "\u0301"] do
      assert Cell.new(mark).char == " "
      assert Cell.put_char(Cell.new("x"), mark).char == " "
      frame = Frame.from_rows([["a", mark, "b"]], 3, 1)
      assert Frame.row_text(frame, 1) == "a b"
      assert Frame.cell(frame, 1, 3).char == "b"

      output =
        frame |> Frame.cells() |> Renderer.render(:true_color, :unicode) |> IO.iodata_to_binary()

      assert output =~ "\e[1;3H"
      assert strip_ansi(output) == "ab"
      assert DisplayWidth.width(Frame.row_text(frame, 1)) == frame.width
      previous = Frame.from_rows(["axb"], 3, 1)

      delta =
        Frame.diff(previous, frame)
        |> Renderer.render(:true_color, :unicode)
        |> IO.iodata_to_binary()

      assert delta =~ "\e[1;2H"
      assert strip_ansi(delta) == " "
      screen = AnsiScreen.new() |> AnsiScreen.feed(output)
      assert elem(screen.cells[{1, 3}], 0) == "b"
      leading = Frame.from_rows([mark <> "ab"], 3, 1)
      assert Frame.row_text(leading, 1) == " ab"
    end

    manual =
      Frame.new(3, 1,
        cells: %{
          {1, 1} => %Cell{char: "\u200B", width: 1},
          {1, 2} => Cell.new("a"),
          {1, 3} => Cell.new("b")
        }
      )

    assert Frame.row_text(manual, 1) == " ab"

    for grapheme <- ["e\u0301", "👩‍💻", "🇺🇸"] do
      assert Cell.new(grapheme).char == grapheme
      assert Cell.put_char(Cell.new("x"), grapheme).char == grapheme
    end
  end

  test "reference links and images retain complete source context across every append split" do
    for source <- [
          "[label][ref]\n\nsecond\n\n[ref]: https://example.com\n",
          "[ref]: https://example.com\n\nfirst\n\n[label][ref]\n",
          "![image][ref]\n\n[ref]: https://example.com/image.png\n",
          "> [label][ref]\n>\n> [ref]: https://example.com\n",
          "- [label][ref]\n\n  [ref]: https://example.com\n",
          "[multi\nline]: https://example.com\n\n[label][multi line]\n",
          "[label][] and [label]\n\n[label]:\n  https://example.com\n  \"Title\"\n"
        ] do
      full = Markdown.render_with_elements(source, 16)

      for split <- 0..byte_size(source), String.valid?(binary_part(source, 0, split)) do
        first = binary_part(source, 0, split)
        rest = binary_part(source, split, byte_size(source) - split)
        document = Document.new(first) |> Document.append(rest)
        assert Markdown.render_with_elements(document, 16) == full
        assert document.content == source
      end

      assert Markdown.render(Document.replace(Document.new("old"), source), 16) == full.lines
    end

    source = "discard\n\n[label][r]\n\n[r]: https://example.com\n\n```text\nx\n```"
    document = Document.new("discard", content_limit: 64) |> Document.append(source)
    assert byte_size(document.content) <= 64

    assert Markdown.render_with_elements(document, 8) ==
             Markdown.render_with_elements(document.content, 8)
  end

  test "CR LF and CRLF offsets preserve source and render each paragraph once" do
    for ending <- ["\r", "\n", "\r\n"],
        source <- [
          "first" <> ending <> ending <> "second",
          "first" <>
            ending <>
            ending <> "```text" <> ending <> "x" <> ending <> "```" <> ending <> ending <> "tail"
        ] do
      for split <- 0..byte_size(source) do
        document =
          Document.new(binary_part(source, 0, split))
          |> Document.append(binary_part(source, split, byte_size(source) - split))

        assert Enum.map_join(document.segments, & &1.source) <> document.pending == source
        assert Markdown.render(document, 40) == Markdown.render(source, 40)

        assert Markdown.render(Document.replace(document, source), 40) ==
                 Markdown.render(source, 40)
      end
    end

    source = "first\r\rsecond\r\n\r\nthird\n\nlast"
    assert Markdown.render(Document.new(source), 40) == Markdown.render(source, 40)
  end

  test "split highlighter tokens retain whole graphemes and plain row metadata" do
    for text <- ["e\u0301e\u0301", "👩‍💻👩‍💻", "🇺🇸🇨🇦"] do
      assert SyntaxHighlighter.spans(text, "text", adapter: SplitAdapter) ==
               SyntaxHighlighter.spans(text, "text")

      source = "```text\n" <> text <> "\n```\n\n```text\ntail\n```"

      for width <- [4, 5, 6, 8] do
        highlighted_result =
          Markdown.render_with_elements(source, width, highlighter: SplitAdapter)

        plain_result = Markdown.render_with_elements(source, width)
        assert highlighted_result.content_height == plain_result.content_height
        assert highlighted_result.elements == plain_result.elements
        assert plain_rows(highlighted_result.lines) == plain_rows(plain_result.lines)

        plain = MarkdownViewer.init(content: source)
        highlighted = MarkdownViewer.init(content: source, highlighter: SplitAdapter)
        {plain, _} = MarkdownViewer.update(TermUI.Event.key(:end), plain, {width, 3})
        {highlighted, _} = MarkdownViewer.update(TermUI.Event.key(:end), highlighted, {width, 3})
        {plain, _} = MarkdownViewer.update(TermUI.Event.key(:up), plain, {width, 3})
        {highlighted, _} = MarkdownViewer.update(TermUI.Event.key(:up), highlighted, {width, 3})

        plain_frame = MarkdownViewer.view(plain, {width, 3})
        highlighted_frame = MarkdownViewer.view(highlighted, {width, 3})

        assert Enum.map(1..3, &Frame.row_text(plain_frame, &1)) ==
                 Enum.map(1..3, &Frame.row_text(highlighted_frame, &1))
      end
    end
  end

  test "theme default colors survive capability conversion and actual ANSI rendering" do
    for mode <- [:true_color, :color_256, :color_16, :monochrome] do
      theme =
        Theme.new(
          styles: %{
            text: Style.new(fg: :default, bg: :default),
            button: %{normal: Style.new(fg: :default, bg: :default)}
          }
        )
        |> Theme.for_capabilities(%{colors: mode})

      for style <- [Theme.style(theme, :text), Theme.style(theme, :button)] do
        output =
          Frame.from_rows([[{"x", style}]], 1, 1)
          |> Frame.cells()
          |> Renderer.render(mode, :unicode)
          |> IO.iodata_to_binary()

        refute output =~ "\e[37m"
        refute output =~ "\e[47m"
      end
    end

    assert Style.to_named(:default) == :white
  end

  defp plain_rows(lines),
    do:
      Enum.map(lines, fn line ->
        Enum.map_join(line, fn
          {text, _style} -> IO.iodata_to_binary(text)
          text -> IO.iodata_to_binary(text)
        end)
      end)

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*[A-Za-z]/, text, "")
end
