defmodule TermUI.Cycle3RenderingTest do
  use ExUnit.Case, async: true

  alias TermUI.Backend.Renderer
  alias TermUI.{Cell, DisplayWidth, Frame, Style, Theme}
  alias TermUI.Color.Converter
  alias TermUI.Widget.Label

  test "Theme gray edges and all exact ramp levels render in both channels and entry forms" do
    for gray <- [0, 7, 247, 248, 249, 255] ++ Enum.map(0..23, &(8 + 10 * &1)),
        field <- [:fg, :bg],
        variant <- [false, true] do
      rgb = {:rgb, gray, gray, gray}
      style = Style.new([{field, rgb}])
      entry = if variant, do: %{normal: style}, else: style
      theme = Theme.new(styles: %{text: entry}) |> Theme.for_capabilities(%{colors: :color_256})
      converted = Theme.style(theme, :text)
      {:indexed, index} = Map.fetch!(converted, field)
      assert index in 0..255
      frame = Label.init(text: "x", style: converted) |> Label.view({1, 1})
      assert Frame.row_text(frame, 1) == "x"
      assert Map.fetch!(Frame.cell(frame, 1, 1), field) == index
      assert Zoi.parse(Frame.schema(), frame) == {:ok, frame}
      assert render(frame) =~ "x"
      if gray == 248, do: assert(index == 255)
      if gray < 8, do: assert(index == 16)
      if gray > 248, do: assert(index == 231)
    end

    assert Converter.rgb_to_256({248, 248, 248}) == 255
    assert Style.rgb_to_indexed({0, 0, 0}) == 16
    assert Converter.rgb_to_256({0, 0, 0}) == 232

    for mode <- [:color_16, :color_256, :true_color, :monochrome] do
      style =
        Theme.new(styles: %{text: Style.new(fg: :default)})
        |> Theme.for_capabilities(%{colors: mode})
        |> Theme.style(:text)

      assert style.fg == if(mode == :monochrome, do: nil, else: :default)
      assert style.bg == nil
    end

    assert Style.rgb_to_indexed({255, 0, 0}) == 196
  end

  test "Frame schema rejects incomplete wide footprints and keeps valid sparse styled pairs" do
    wide = Cell.new("界", fg: :red, bg: 42, attrs: [:bold])
    tail = Cell.wide_placeholder(wide)

    for frame <- [
          %{Frame.new(1, 1) | cells: %{{1, 1} => wide}},
          %{Frame.new(3, 1) | cells: %{{1, 1} => wide, {1, 3} => Cell.new("x")}},
          %{Frame.new(3, 1) | cells: %{{1, 1} => tail, {1, 2} => Cell.new("x")}},
          %{Frame.new(3, 1) | cells: %{{1, 2} => wide, {1, 3} => Cell.new("x")}}
        ],
        do: assert(match?({:error, _}, Zoi.parse(Frame.schema(), frame)))

    for width <- [2, 3, 5] do
      frame = Frame.new(width, 2, cells: %{{2, width - 1} => wide})
      assert Zoi.parse(Frame.schema(), frame) == {:ok, frame}
      assert Frame.cell(frame, 2, width).wide_placeholder

      for col <- [width - 1, width] do
        overwritten = Frame.put_cell(frame, 2, col, Cell.new("x"))
        assert Zoi.parse(Frame.schema(), overwritten) == {:ok, overwritten}
        assert render_diff(frame, overwritten) =~ "x"
      end
    end

    sparse = %{Frame.new(5, 2) | cells: %{{2, 5} => Cell.new("x")}}
    assert Zoi.parse(Frame.schema(), sparse) == {:ok, sparse}
    base = Frame.from_rows(["界x"], 3, 1)
    overlay = Frame.overlay(base, Frame.from_rows(["y"], 1, 1), 2, 1)
    assert Zoi.parse(Frame.schema(), overlay) == {:ok, overlay}
  end

  test "Unicode 17 named Thai and Tamil nonspacing marks retain narrow bases and raw source" do
    # UnicodeData 17.0.0: U+0E48 and U+0BCD are Mn/NSM.
    for {base, mark} <- [{"ก", "\u0E48"}, {"க", "\u0BCD"}] do
      text = base <> mark
      assert DisplayWidth.width(base) == 1
      assert DisplayWidth.width(mark) == 0
      assert DisplayWidth.width(text) == 1
      frame = Frame.from_rows([text <> "x"], 2, 1)
      assert Frame.cell(frame, 1, 1).char == text
      assert Frame.cell(frame, 1, 2).char == "x"
      assert render(frame) =~ text <> "x"
      assert Frame.row_text(Frame.from_rows([mark <> "x"], 2, 1), 1) == " x"
      assert Frame.wrap(text <> "x", 1) == [text, "x"]
      next = Frame.put_cell(frame, 1, 2, Cell.new("y"))
      assert render_diff(frame, next) =~ "y"
      assert Zoi.parse(Frame.schema(), frame) == {:ok, frame}
    end

    for {text, width} <- [
          {"e\u0301", 1},
          {"א\u05B0", 1},
          {"ا\u0654", 1},
          {"界", 2},
          {"👩‍💻", 2},
          {"🇺🇸", 2},
          {"·", 1}
        ] do
      assert DisplayWidth.width(text) == width
      assert Frame.cell(Frame.from_rows([text <> "x"], width + 1, 1), 1, width + 1).char == "x"
    end
  end

  defp render(frame),
    do: frame |> Frame.cells() |> Renderer.render(:true_color, :unicode) |> IO.iodata_to_binary()

  defp render_diff(first, last),
    do: Frame.diff(first, last) |> Renderer.render(:true_color, :unicode) |> IO.iodata_to_binary()
end
