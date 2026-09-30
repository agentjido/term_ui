defmodule TermUI.Backend.RendererTest do
  use ExUnit.Case, async: true

  alias TermUI.Backend.Renderer

  test "renders a dense row as one cursor run with bounded output" do
    output =
      [
        {{1, 1}, {"a", :default, :default, []}},
        {{1, 2}, {"b", :default, :default, []}},
        {{1, 3}, {"c", :default, :default, []}},
        {{1, 4}, {"d", :default, :default, []}}
      ]
      |> Renderer.render(:true_color, :unicode)
      |> IO.iodata_to_binary()

    assert output == "\e[1;1H\e[0mabcd\e[0m"
    assert byte_size(output) == 18
  end

  test "changes terminal style only at a style boundary" do
    output =
      [
        {{1, 1}, {"x", :red, :default, [:bold]}},
        {{1, 2}, {"y", :red, :default, [:bold]}},
        {{1, 3}, {"z", :green, :default, [:bold]}}
      ]
      |> Renderer.render(:true_color, :unicode)
      |> IO.iodata_to_binary()

    assert output == "\e[1;1H\e[0m\e[31m\e[1mxy\e[0m\e[32m\e[1mz\e[0m"
  end

  test "starts a new run for sparse row and column gaps while rendering erased cells" do
    output =
      [
        {{1, 1}, {"a", :default, :default, []}},
        {{1, 3}, {" ", :default, :default, []}},
        {{2, 1}, {"b", :default, :default, []}}
      ]
      |> Renderer.render(:true_color, :unicode)
      |> IO.iodata_to_binary()

    assert output == "\e[1;1H\e[0ma\e[1;3H \e[2;1Hb\e[0m"
  end

  test "keeps a wide grapheme and its following narrow cell in one run" do
    output =
      [
        {{1, 1}, {"界", :default, :default, []}},
        {{1, 3}, {"b", :default, :default, []}}
      ]
      |> Renderer.render(:true_color, :unicode)
      |> IO.iodata_to_binary()

    assert output == "\e[1;1H\e[0m界b\e[0m"
    refute output =~ "\e[1;3H"
  end

  test "maps adjacent Unicode box drawing cells to ASCII" do
    output =
      [
        {{1, 1}, {"┌", :default, :default, []}},
        {{1, 2}, {"─", :default, :default, []}}
      ]
      |> Renderer.render(:true_color, :ascii)
      |> IO.iodata_to_binary()

    assert output == "\e[1;1H\e[0m+-\e[0m"
  end

  test "maps Unicode spinner and sparkline level lists to ASCII" do
    output =
      [
        {{1, 1}, {"⣾", :default, :default, []}},
        {{1, 2}, {"▁", :default, :default, []}},
        {{1, 3}, {"▇", :default, :default, []}}
      ]
      |> Renderer.render(:true_color, :ascii)
      |> IO.iodata_to_binary()

    assert output == "\e[1;1H\e[0m|_=\e[0m"
  end

  test "renders every color mode and supported text attribute" do
    attributes = [
      :bold,
      :dim,
      :italic,
      :underline,
      :blink,
      :reverse,
      :hidden,
      :strikethrough,
      :unknown
    ]

    true_color =
      Renderer.render(
        [{{1, 1}, {"x", {1, 2, 3}, {4, 5, 6}, attributes}}],
        :true_color,
        :unicode
      )
      |> IO.iodata_to_binary()

    assert true_color =~ "\e[38;2;1;2;3m"
    assert true_color =~ "\e[48;2;4;5;6m"

    color_256 =
      Renderer.render(
        [
          {{1, 1}, {"x", 42, 43, []}},
          {{2, 1}, {"y", {255, 0, 0}, {0, 255, 0}, []}}
        ],
        :color_256,
        :unicode
      )
      |> IO.iodata_to_binary()

    assert color_256 =~ "\e[38;5;42m"
    assert color_256 =~ "\e[48;5;43m"

    color_16 =
      Renderer.render(
        [{{1, 1}, {"x", {255, 0, 0}, {0, 0, 255}, []}}],
        :color_16,
        :unicode
      )
      |> IO.iodata_to_binary()

    assert color_16 =~ "x"

    monochrome =
      Renderer.render([{{1, 1}, {"x", :red, :blue, []}}], :monochrome, :unicode)
      |> IO.iodata_to_binary()

    refute monochrome =~ "\e[31m"
    assert Renderer.render([], :true_color, :unicode) |> IO.iodata_to_binary() == "\e[0m"
  end
end
