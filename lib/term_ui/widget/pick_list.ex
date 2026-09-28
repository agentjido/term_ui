defmodule TermUI.Widget.PickList do
  @moduledoc """
  A modal pick-list widget for selecting from a list of items.

  PickList displays a centered modal overlay with a scrollable list,
  keyboard navigation, and type-ahead filtering. Used for provider
  and model selection dialogs.

  This module uses the earlier `TermUI.Widget` namespace, accepts a props map
  directly, and must be embedded as an explicit state machine in the Elm root.

  ## Usage

      PickList.render(%{
        items: ["Apple", "Banana", "Cherry"],
        title: "Select Fruit",
        on_select: fn item -> IO.puts("Selected: \#{item}") end,
        on_cancel: fn -> IO.puts("Cancelled") end
      }, state, area)

  ## Props

  - `:items` - List of items to display (required)
  - `:title` - Modal title (optional)
  - `:on_select` - Callback when item selected `fn item -> ... end`
  - `:on_cancel` - Callback when cancelled `fn -> ... end`
  - `:width` - Modal width (default: 40)
  - `:height` - Modal height (default: 10)
  - `:style` - Border/text style options
  - `:highlight_style` - Style for selected item (default: inverted colors)

  ## Keyboard Controls

  - `Up/Down` - Navigate items
  - `Page Up/Down` - Jump 10 items
  - `Home/End` - Jump to first/last item
  - `Enter` - Confirm selection
  - `Escape` - Cancel
  - Typing - Filter items (type-ahead search)
  - `Backspace` - Remove filter character
  """

  use TermUI.StatefulComponent

  alias TermUI.Component.RenderNode
  alias TermUI.Event
  alias TermUI.Renderer.Style

  # Dialyzer: Suppress opaque type warnings for Style helpers
  # Dialyzer: unused_fun and no_return warnings for private helper functions
  @dialyzer {:nowarn_function,
             build_style: 1,
             positioned_cell_safe: 4,
             render_border: 6,
             render_items: 1,
             render_item_list: 1,
             render_item_cells: 5,
             render_empty_items: 4,
             truncate_item_text: 2,
             render_status_line: 5,
             item_style: 4,
             render_filter_line: 5,
             render: 2}

  # Border characters (single style)
  @border %{tl: "┌", tr: "┐", bl: "└", br: "┘", h: "─", v: "│"}

  @doc """
  Initializes the pick-list state.
  """
  @impl true
  def init(props) do
    items = Map.get(props, :items, [])

    state = %{
      selected_index: 0,
      scroll_offset: 0,
      filter_text: "",
      filtered_items: items,
      original_items: items,
      props: props
    }

    {:ok, state}
  end

  @doc """
  Handles keyboard events for the pick-list.
  """
  @impl true
  def handle_event(%Event.Key{key: :up}, state) do
    new_index = max(0, state.selected_index - 1)
    new_scroll = adjust_scroll(new_index, state.scroll_offset, visible_height(state))
    {:ok, %{state | selected_index: new_index, scroll_offset: new_scroll}}
  end

  def handle_event(%Event.Key{key: :down}, state) do
    max_index = max(0, length(state.filtered_items) - 1)
    new_index = min(max_index, state.selected_index + 1)
    new_scroll = adjust_scroll(new_index, state.scroll_offset, visible_height(state))
    {:ok, %{state | selected_index: new_index, scroll_offset: new_scroll}}
  end

  def handle_event(%Event.Key{key: :page_up}, state) do
    new_index = max(0, state.selected_index - 10)
    new_scroll = adjust_scroll(new_index, state.scroll_offset, visible_height(state))
    {:ok, %{state | selected_index: new_index, scroll_offset: new_scroll}}
  end

  def handle_event(%Event.Key{key: :page_down}, state) do
    max_index = max(0, length(state.filtered_items) - 1)
    new_index = min(max_index, state.selected_index + 10)
    new_scroll = adjust_scroll(new_index, state.scroll_offset, visible_height(state))
    {:ok, %{state | selected_index: new_index, scroll_offset: new_scroll}}
  end

  def handle_event(%Event.Key{key: :home}, state) do
    {:ok, %{state | selected_index: 0, scroll_offset: 0}}
  end

  def handle_event(%Event.Key{key: :end}, state) do
    max_index = max(0, length(state.filtered_items) - 1)
    new_scroll = adjust_scroll(max_index, 0, visible_height(state))
    {:ok, %{state | selected_index: max_index, scroll_offset: new_scroll}}
  end

  def handle_event(%Event.Key{key: :enter}, state) do
    if state.filtered_items != [] do
      item = Enum.at(state.filtered_items, state.selected_index)
      {:ok, state, [{:send, self(), {:select, item}}]}
    else
      {:ok, state}
    end
  end

  def handle_event(%Event.Key{key: :escape}, state) do
    {:ok, state, [{:send, self(), :cancel}]}
  end

  def handle_event(%Event.Key{key: :backspace}, state) do
    if state.filter_text != "" do
      new_filter = String.slice(state.filter_text, 0..-2//1)
      new_state = apply_filter(state, new_filter)
      {:ok, new_state}
    else
      {:ok, state}
    end
  end

  def handle_event(%Event.Key{char: char}, state) when is_binary(char) and char != "" do
    # Type-ahead filtering
    new_filter = state.filter_text <> char
    new_state = apply_filter(state, new_filter)
    {:ok, new_state}
  end

  def handle_event(_event, state) do
    {:ok, state}
  end

  @doc """
  Handles messages to the pick-list.
  """
  @impl true
  def handle_info({:select, item}, state) do
    props = state.props
    on_select = Map.get(props, :on_select)

    if is_function(on_select, 1) do
      on_select.(item)
    end

    {:ok, state}
  end

  def handle_info(:cancel, state) do
    props = state.props
    on_cancel = Map.get(props, :on_cancel)

    if is_function(on_cancel, 0) do
      on_cancel.()
    end

    {:ok, state}
  end

  def handle_info({:set_items, items}, state) do
    new_state = %{state | original_items: items}
    new_state = apply_filter(new_state, state.filter_text)
    {:ok, new_state}
  end

  def handle_info(_msg, state) do
    {:ok, state}
  end

  @doc """
  Renders the pick-list modal.
  """
  @impl true
  def render(state, area) do
    props = state.props
    title = Map.get(props, :title, "Select")
    modal_width = Map.get(props, :width, 40)
    modal_height = Map.get(props, :height, 10)
    style_opts = Map.get(props, :style, %{})
    highlight_opts = Map.get(props, :highlight_style, %{fg: :black, bg: :white})

    style = build_style(style_opts)
    highlight_style = build_style(highlight_opts)

    # Calculate modal position (centered)
    modal_x = div(area.width - modal_width, 2)
    modal_y = div(area.height - modal_height, 2)

    # Ensure modal fits in area
    modal_width = min(modal_width, area.width)
    modal_height = min(modal_height, area.height)

    cells = []

    # Render border
    cells = cells ++ render_border(title, modal_x, modal_y, modal_width, modal_height, style)

    # Render filter line if filtering
    {cells, content_start_y, content_height} =
      if state.filter_text != "" do
        filter_cells = render_filter_line(state.filter_text, modal_x, modal_y, modal_width, style)
        {cells ++ filter_cells, modal_y + 2, modal_height - 4}
      else
        {cells, modal_y + 1, modal_height - 3}
      end

    # Render items
    cells =
      cells ++
        render_items(%{
          items: state.filtered_items,
          selected_index: state.selected_index,
          scroll_offset: state.scroll_offset,
          x: modal_x + 1,
          y: content_start_y,
          width: modal_width - 2,
          height: content_height,
          style: style,
          highlight_style: highlight_style
        })

    # Render status line
    cells =
      cells ++ render_status_line(state, modal_x, modal_y + modal_height - 2, modal_width, style)

    RenderNode.cells(cells)
  end

  # Private Functions

  defp apply_filter(state, filter_text) do
    filtered =
      if filter_text == "" do
        state.original_items
      else
        filter_lower = String.downcase(filter_text)

        Enum.filter(state.original_items, fn item ->
          String.downcase(to_string(item)) |> String.contains?(filter_lower)
        end)
      end

    # Reset selection when filter changes
    %{
      state
      | filter_text: filter_text,
        filtered_items: filtered,
        selected_index: 0,
        scroll_offset: 0
    }
  end

  defp visible_height(state) do
    props = state.props
    modal_height = Map.get(props, :height, 10)
    # Account for border (2), status line (1), and filter line if present
    filter_offset = if state.filter_text != "", do: 1, else: 0
    max(1, modal_height - 3 - filter_offset)
  end

  defp adjust_scroll(selected_index, current_scroll, visible_height) do
    cond do
      selected_index < current_scroll ->
        selected_index

      selected_index >= current_scroll + visible_height ->
        selected_index - visible_height + 1

      true ->
        current_scroll
    end
  end

  defp render_border(title, x, y, width, height, style) do
    cells = []

    # Top border with title
    title_text = String.slice(title, 0, width - 4)
    title_padded = " " <> title_text <> " "
    title_start = 2

    cells = cells ++ [positioned_cell_safe(x, y, @border.tl, style)]

    cells =
      cells ++
        for(i <- 1..(title_start - 1), do: positioned_cell_safe(x + i, y, @border.h, style))

    cells =
      cells ++
        (title_padded
         |> String.graphemes()
         |> Enum.with_index()
         |> Enum.map(fn {char, i} ->
           positioned_cell_safe(x + title_start + i, y, char, style)
         end))

    title_end = title_start + String.length(title_padded)

    cells =
      cells ++
        for(i <- title_end..(width - 2), do: positioned_cell_safe(x + i, y, @border.h, style))

    cells = cells ++ [positioned_cell_safe(x + width - 1, y, @border.tr, style)]

    # Side borders
    cells =
      (cells ++
         for row <- 1..(height - 2) do
           [
             positioned_cell_safe(x, y + row, @border.v, style),
             positioned_cell_safe(x + width - 1, y + row, @border.v, style)
           ]
         end)
      |> List.flatten()

    # Bottom border
    cells = cells ++ [positioned_cell_safe(x, y + height - 1, @border.bl, style)]

    cells =
      cells ++
        for(
          i <- 1..(width - 2),
          do: positioned_cell_safe(x + i, y + height - 1, @border.h, style)
        )

    cells = cells ++ [positioned_cell_safe(x + width - 1, y + height - 1, @border.br, style)]

    cells
  end

  defp render_filter_line(filter_text, modal_x, modal_y, modal_width, style) do
    inner_width = modal_width - 2
    filter_display = "Filter: " <> filter_text
    filter_display = String.slice(filter_display, 0, inner_width)
    filter_display = String.pad_trailing(filter_display, inner_width)

    filter_display
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn {char, i} ->
      positioned_cell_safe(modal_x + 1 + i, modal_y + 1, char, style)
    end)
  end

  defp render_items(params) do
    %{
      items: items,
      selected_index: _selected_index,
      scroll_offset: _scroll_offset,
      x: x,
      y: y,
      width: width,
      height: _height,
      style: style,
      highlight_style: _highlight_style
    } = params

    if items == [] do
      render_empty_items(x, y, width, style)
    else
      render_item_list(params)
    end
  end

  defp render_empty_items(x, y, width, style) do
    msg = "(No items)"
    msg = String.pad_leading(msg, div(width + String.length(msg), 2))
    msg = String.pad_trailing(msg, width)

    msg
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn {char, i} ->
      positioned_cell_safe(x + i, y, char, style)
    end)
  end

  defp render_item_list(params) do
    %{
      items: items,
      selected_index: selected_index,
      scroll_offset: scroll_offset,
      x: x,
      y: y,
      width: width,
      height: height,
      style: style,
      highlight_style: highlight_style
    } = params

    items
    |> Enum.with_index()
    |> Enum.drop(scroll_offset)
    |> Enum.take(height)
    |> Enum.with_index()
    |> Enum.flat_map(fn {{item, item_index}, display_y} ->
      item_style = item_style(item_index, selected_index, highlight_style, style)
      render_item_cells(item, x, y + display_y, width, item_style)
    end)
  end

  defp item_style(item_index, selected_index, highlight_style, style) do
    if item_index == selected_index, do: highlight_style, else: style
  end

  defp render_item_cells(item, x, y, width, style) do
    item_text = to_string(item)
    item_text = truncate_item_text(item_text, width)

    item_text
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn {char, i} ->
      positioned_cell_safe(x + i, y, char, style)
    end)
  end

  defp truncate_item_text(text, width) do
    if String.length(text) > width do
      String.slice(text, 0, width - 1) <> "…"
    else
      String.pad_trailing(text, width)
    end
  end

  defp render_status_line(state, modal_x, y, modal_width, style) do
    inner_width = modal_width - 2
    total = length(state.filtered_items)

    status =
      if total == 0 do
        if state.filter_text != "" do
          "No matches"
        else
          "Empty list"
        end
      else
        "Item #{state.selected_index + 1} of #{total}"
      end

    status = String.pad_leading(status, div(inner_width + String.length(status), 2))
    status = String.pad_trailing(status, inner_width)

    status
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn {char, i} ->
      positioned_cell_safe(modal_x + 1 + i, y, char, style)
    end)
  end

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
