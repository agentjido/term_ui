defmodule TermUI.Widget.Block do
  @moduledoc """
  A container widget that draws a border around its content.

  Block is the fundamental layout container. It renders a border,
  optional title, and manages the layout of children within
  its bordered area.

  This module uses the earlier `TermUI.Widget` namespace and accepts a props map
  directly. It is not mounted by `TermUI.Runtime`; call its state/render
  callbacks explicitly. Its `TermUI.Container` child callbacks require a
  custom host and are not interpreted by the Elm runtime.

  ## Usage

      Block.render(%{
        border: :single,
        title: "Panel"
      }, state, area)

  ## Props

  - `:border` - Border style: `:none`, `:single`, `:double`, `:rounded`, `:thick`
  - `:title` - Optional title text
  - `:title_align` - Title alignment: `:left`, `:center`, `:right`
  - `:padding` - Padding inside border (integer or map with :top, :right, :bottom, :left)
  - `:style` - Border style options
  """

  use TermUI.Container

  alias TermUI.Component.RenderNode
  alias TermUI.Renderer.Style

  # Dialyzer: Suppress opaque type warnings for Style helpers
  # Dialyzer: no_return warnings for functions that don't return
  # no_opaque: Style contains MapSet which triggers false positive call_without_opaque warnings
  @dialyzer [
    :no_opaque,
    nowarn_function: [
      build_style: 1,
      positioned_cell_safe: 4,
      do_render_top: 5,
      render_bottom_border: 3,
      render_side_borders: 3
    ]
  ]

  # Border character sets
  @borders %{
    none: %{tl: " ", tr: " ", bl: " ", br: " ", h: " ", v: " "},
    single: %{tl: "┌", tr: "┐", bl: "└", br: "┘", h: "─", v: "│"},
    double: %{tl: "╔", tr: "╗", bl: "╚", br: "╝", h: "═", v: "║"},
    rounded: %{tl: "╭", tr: "╮", bl: "╰", br: "╯", h: "─", v: "│"},
    thick: %{tl: "┏", tr: "┓", bl: "┗", br: "┛", h: "━", v: "┃"}
  }

  @doc """
  Initializes the block state.
  """
  @impl true
  def init(props) do
    {:ok, %{props: props}}
  end

  @doc """
  Returns children to render.
  """
  @impl true
  def children(_state) do
    # Block delegates children management to parent
    []
  end

  @doc """
  Calculates layout for children within the block.
  """
  @impl true
  def layout(children, area, _state) do
    # Children get the inner area (after border and padding)
    Enum.map(children, fn child ->
      {child, area}
    end)
  end

  @doc """
  Handles events for the block.
  """
  @impl true
  def handle_event(_event, state) do
    {:ok, state}
  end

  @doc """
  Renders the block border and content area.
  """
  @impl true
  def render(state, area) do
    props = state.props
    border_type = Map.get(props, :border, :single)
    title = Map.get(props, :title)
    title_align = Map.get(props, :title_align, :left)
    style_opts = Map.get(props, :style, %{})

    style = build_style(style_opts)
    border_chars = Map.get(@borders, border_type, @borders.single)

    cells = render_border(border_chars, title, title_align, area, style)

    RenderNode.cells(cells)
  end

  @doc """
  Calculates the inner area after border and padding.
  """
  def inner_area(props, area) do
    border_type = Map.get(props, :border, :single)
    padding = normalize_padding(Map.get(props, :padding, 0))

    # Border takes 1 cell on each side (unless :none)
    border_offset = if border_type == :none, do: 0, else: 1

    %{
      x: area.x + border_offset + padding.left,
      y: area.y + border_offset + padding.top,
      width: max(0, area.width - 2 * border_offset - padding.left - padding.right),
      height: max(0, area.height - 2 * border_offset - padding.top - padding.bottom)
    }
  end

  # Private Functions

  defp render_border(chars, title, title_align, area, style) do
    cells = []

    # Top border
    cells = cells ++ render_top_border(chars, title, title_align, area, style)

    # Side borders
    cells = cells ++ render_side_borders(chars, area, style)

    # Bottom border
    cells = cells ++ render_bottom_border(chars, area, style)

    cells
  end

  defp render_top_border(chars, title, title_align, area, style) do
    if area.height < 1 || area.width < 1,
      do: [],
      else: do_render_top(chars, title, title_align, area, style)
  end

  defp do_render_top(chars, nil, _title_align, area, style) do
    # No title - just border
    [positioned_cell_safe(0, 0, chars.tl, style)] ++
      for(x <- 1..(area.width - 2), do: positioned_cell_safe(x, 0, chars.h, style)) ++
      [positioned_cell_safe(area.width - 1, 0, chars.tr, style)]
  end

  defp do_render_top(chars, title, title_align, area, style) do
    # With title
    inner_width = area.width - 2

    if inner_width < 1 do
      [
        positioned_cell_safe(0, 0, chars.tl, style),
        positioned_cell_safe(area.width - 1, 0, chars.tr, style)
      ]
    else
      title_text = String.slice(title, 0, inner_width)
      title_len = String.length(title_text)
      remaining = inner_width - title_len

      {left_pad, right_pad} =
        case title_align do
          :left -> {0, remaining}
          :right -> {remaining, 0}
          :center -> {div(remaining, 2), remaining - div(remaining, 2)}
        end

      top_cells = [positioned_cell_safe(0, 0, chars.tl, style)]

      # Left padding
      top_cells =
        if left_pad > 0 do
          top_cells ++ render_top_padding(left_pad, 1, chars.h, style)
        else
          top_cells
        end

      # Title
      top_cells =
        top_cells ++
          (title_text
           |> String.graphemes()
           |> Enum.with_index()
           |> Enum.map(fn {char, i} ->
             positioned_cell_safe(1 + left_pad + i, 0, char, style)
           end))

      # Right padding
      top_cells =
        if right_pad > 0 do
          top_cells ++
            render_top_padding(right_pad, 1 + left_pad + title_len, chars.h, style)
        else
          top_cells
        end

      top_cells ++ [positioned_cell_safe(area.width - 1, 0, chars.tr, style)]
    end
  end

  defp render_top_padding(count, offset, char, style) do
    Enum.map(0..(count - 1), fn i ->
      positioned_cell_safe(offset + i, 0, char, style)
    end)
  end

  defp render_side_borders(chars, area, style) do
    if area.height < 3 || area.width < 2 do
      []
    else
      for y <- 1..(area.height - 2) do
        [
          positioned_cell_safe(0, y, chars.v, style),
          positioned_cell_safe(area.width - 1, y, chars.v, style)
        ]
      end
      |> List.flatten()
    end
  end

  defp render_bottom_border(chars, area, style) do
    if area.height < 2 || area.width < 1 do
      []
    else
      y = area.height - 1

      [positioned_cell_safe(0, y, chars.bl, style)] ++
        for(x <- 1..(area.width - 2), do: positioned_cell_safe(x, y, chars.h, style)) ++
        [positioned_cell_safe(area.width - 1, y, chars.br, style)]
    end
  end

  defp normalize_padding(padding) when is_integer(padding) do
    %{top: padding, right: padding, bottom: padding, left: padding}
  end

  defp normalize_padding(padding) when is_map(padding) do
    %{
      top: Map.get(padding, :top, 0),
      right: Map.get(padding, :right, 0),
      bottom: Map.get(padding, :bottom, 0),
      left: Map.get(padding, :left, 0)
    }
  end

  defp normalize_padding(_), do: %{top: 0, right: 0, bottom: 0, left: 0}

  # ----------------------------------------------------------------------------
  # Style Helper Functions
  # ----------------------------------------------------------------------------

  @spec positioned_cell_safe(integer(), integer(), String.t(), Style.t()) :: RenderNode.t()
  defp positioned_cell_safe(x, y, char, style),
    do: positioned_cell(x, y, char, style)

  # ----------------------------------------------------------------------------
  # Style Building
  # ----------------------------------------------------------------------------

  defp build_style(opts) when is_map(opts) do
    style_list =
      opts
      |> Enum.map(fn
        {:fg, color} -> {:fg, color}
        {:bg, color} -> {:bg, color}
        {:bold, true} -> {:attrs, [:bold]}
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    Style.new(style_list)
  end

  defp build_style(_), do: Style.new()
end
