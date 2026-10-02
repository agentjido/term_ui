defmodule TermUI.Cycle2RenderingTest do
  use ExUnit.Case, async: true

  alias TermUI.Backend.Renderer
  alias TermUI.{Cell, DisplayWidth, Frame, Markdown, Style, Theme}
  alias TermUI.Color.Converter
  alias TermUI.Widget.{Block, Helpers, Label, TextArea, Viewport}

  test "valid complete plain iodata rows work in setters, viewports, and blocks" do
    for row <- [
          [65, "B"],
          ["A", 66],
          [65, [66]],
          ["A" | "B"],
          [65, 66],
          [[65, "B"]],
          [<<0xC3>>, [0xA9], "x"]
        ] do
      text = IO.iodata_to_binary(row)
      frame = Frame.from_rows([row], 2, 1)
      assert Frame.row_text(frame, 1) == text
      assert Frame.row_text(Frame.put_row(Frame.new(2, 1), 1, row), 1) == text
      assert Frame.row_text(Frame.put_rows(Frame.new(2, 1), 1, [row]), 1) == text
      viewport = Viewport.init(content: [row])
      assert Viewport.content_dimensions(viewport) == {2, 1}
      assert Frame.row_text(Viewport.view(viewport, {2, 1}), 1) == text
      block = Block.init(content: [row]) |> Block.view({4, 3})
      assert Frame.row_text(block, 2) == "│" <> text <> "│"

      assert Helpers.fit_row(row, 2) |> then(&Frame.from_rows([&1], 2, 1)) |> Frame.row_text(1) ==
               text
    end
  end

  test "complete plain spans keep standalone mark boundaries" do
    for mark <- ["\u0301", "\u200B", "\u2060"] do
      row = ["a", mark, "b"]
      assert Frame.row_text(Frame.from_rows([row], 3, 1), 1) == "a b"
      assert Frame.row_text(Viewport.view(Viewport.init(content: [row]), {3, 1}), 1) == "a b"
      assert Frame.row_text(Block.view(Block.init(content: [row]), {5, 3}), 2) == "│a b│"
    end

    assert Frame.row_text(Frame.from_rows(["a\u0301b"], 2, 1), 1) == "a\u0301b"
  end

  test "styled iodata keeps its style through normalization and cropping" do
    style = Style.new(fg: :red, attrs: [:bold])
    row = [{[65, [66] | "C"], style}, "D"]
    assert Frame.cell(Frame.from_rows([row], 4, 1), 1, 2).fg == :red
    viewport = Viewport.init(content: [row], scroll_x: 1)
    frame = Viewport.view(viewport, {2, 1})
    assert Frame.row_text(frame, 1) == "BC"
    assert Frame.cell(frame, 1, 1).fg == :red
    block = Block.init(content: [row]) |> Block.view({4, 4})
    assert Frame.row_text(block, 2) == "│AB│"
    assert Frame.row_text(block, 3) == "│CD│"
    assert Frame.cell(block, 2, 2).fg == :red
  end

  test "Cell widths govern plain and styled wrap, fit, alignment, and editor coordinates" do
    for mark <- ["\u200B", "\u2060", "\u0301"] do
      source = if mark == "\u0301", do: mark <> "ab", else: "a" <> mark <> "b"
      expected = if mark == "\u0301", do: [" a", "b "], else: ["a ", "b "]
      assert DisplayWidth.width(source) == 2
      assert Cell.text_width(source) == 3
      wrapped = Frame.wrap(source, 2)
      assert Enum.join(wrapped) == source
      assert length(wrapped) == 2
      frame = Frame.from_rows(wrapped, 2, 2)
      assert rows(frame) == expected
      assert Frame.row_text(Frame.from_rows([Frame.fit(source, 2)], 2, 1), 1) == hd(expected)
      assert rows(Label.view(Label.init(text: source), {2, 2})) == expected
      markdown = Markdown.render_with_elements(source, 2)
      assert markdown.content_height == 2
      assert rows(Frame.from_rows(markdown.lines, 2, 2)) == expected

      for content <- [source, [[{source, Style.new(fg: :red)}]]] do
        block = Block.init(content: content) |> Block.view({4, 4})
        assert rows(block) == ["┌──┐", "│" <> hd(expected) <> "│", "│b │", "└──┘"]
      end

      state = TextArea.init(value: source)
      area = TextArea.view(state, {2, 3})
      assert Enum.take(rows(area), 2) == expected
      assert area.cursor == {2, 2}
      {state, _} = TextArea.mouse(TermUI.Event.mouse(:press, :left, 0, 1), state, {2, 3})
      assert state.cursor == 2
      {state, _} = TextArea.update(TermUI.Event.key("a", modifiers: [:ctrl]), state)

      assert {_, [{:copy, ^source}]} =
               TextArea.update(TermUI.Event.key("c", modifiers: [:ctrl]), state)

      for alignment <- [:left, :center, :right] do
        assert Cell.text_width(Helpers.align(source, 5, alignment)) == 5
      end
    end
  end

  test "named Arabic and Hebrew marks keep base columns and standalone replacement" do
    for {plain, marked} <- [{"أ", "ا\u0654"}, {"ש", "ש\u05B0"}] do
      assert DisplayWidth.width(plain) == 1
      assert DisplayWidth.width(marked) == 1
      assert Cell.new(marked).char == marked
      frame = Frame.from_rows([marked <> "x"], 4, 1)
      assert Frame.cell(frame, 1, 2).char == "x"

      full =
        frame |> Frame.cells() |> Renderer.render(:true_color, :unicode) |> IO.iodata_to_binary()

      assert full =~ marked <> "x"
      next = Frame.put_cell(frame, 1, 2, Cell.new("y"))

      diff =
        Frame.diff(frame, next) |> Renderer.render(:true_color, :unicode) |> IO.iodata_to_binary()

      assert diff =~ "\e[1;2H"
      assert diff =~ "y"
    end

    for mark <- [
          "\u0654",
          "\u05B0",
          "\u0591",
          "\u0610",
          "\u0670",
          "\u06D6",
          "\u06DF",
          "\u06E7",
          "\u06EA"
        ] do
      assert DisplayWidth.width(mark) == 0
      assert Cell.new(mark).char == " "
      assert Cell.put_char(Cell.new("x"), mark).char == " "
    end

    for {text, width} <- [{"界", 2}, {"👩‍💻", 2}, {"🇺🇸", 2}, {"e\u0301", 1}] do
      assert Cell.new(text).width == width
      assert Cell.new(text).char == text
    end
  end

  test "all exact gray ramp levels match direct and Theme foreground and background" do
    for index <- 0..23 do
      gray = 8 + 10 * index
      rgb = {gray, gray, gray}
      expected = 232 + index
      assert Converter.rgb_to_256(rgb) == expected
      style = Style.new(fg: {:rgb, gray, gray, gray}, bg: {:rgb, gray, gray, gray})

      theme_style =
        Theme.new(styles: %{a: style})
        |> Theme.for_capabilities(%{colors: :color_256})
        |> Theme.style(:a)

      assert theme_style.fg == {:indexed, expected}
      assert theme_style.bg == {:indexed, expected}

      render = fn s ->
        Frame.from_rows([[{"x", s}]], 1, 1)
        |> Frame.cells()
        |> Renderer.render(:color_256, :unicode)
        |> IO.iodata_to_binary()
      end

      assert render.(style) == render.(theme_style)
      assert render.(style) =~ "38;5;#{expected}"
      assert render.(style) =~ "48;5;#{expected}"
    end

    assert Converter.rgb_to_256({0, 0, 0}) == 232
    assert Converter.rgb_to_256({255, 255, 255}) == 255
    assert Converter.rgb_to_256({255, 0, 0}) == 196
  end

  defp rows(frame), do: Enum.map(1..frame.height, &Frame.row_text(frame, &1))
end
