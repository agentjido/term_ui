defmodule Showcase.Pages.Controls do
  @moduledoc false

  @behaviour Showcase.Page

  alias Showcase.Layout, as: ShowcaseLayout
  alias TermUI.{Event, Frame, Layout}
  alias TermUI.Widget.{Breadcrumb, Checkbox, RadioGroup, Select, Spinner, Toggle}

  @focus_order [:checkbox, :toggle, :radio, :select]

  @impl true
  def init do
    %{
      focus: :checkbox,
      checkbox: Checkbox.init(id: :alerts, label: "Enable alerts", checked: true),
      toggle: Toggle.init(id: :streaming, label: "Stream updates", checked: true),
      radio:
        RadioGroup.init(
          id: :density,
          options: [{:compact, "Compact"}, {:comfortable, "Comfortable"}],
          selected: :compact,
          orientation: :horizontal
        ),
      select:
        Select.init(
          id: :region,
          options: [{:local, "Local node"}, {:cluster, "Cluster"}, {:archive, "Archive"}],
          selected: :local,
          page_size: 3
        ),
      spinner: Spinner.init(label: "Parent-owned refresh timer"),
      breadcrumb:
        Breadcrumb.init(
          items: [
            Breadcrumb.item("Showcase", icon: "⌂"),
            Breadcrumb.item("Widgets"),
            Breadcrumb.item("Controls", icon: "◆")
          ]
        ),
      status: "Tab changes focus. Enter or Space changes the active control."
    }
  end

  @impl true
  def update(%Event.Key{key: :tab, modifiers: modifiers}, state) do
    delta = if :shift in modifiers, do: -1, else: 1
    {move_focus(state, delta), []}
  end

  def update(event, state) do
    {state, messages} = update_focused(state, event)
    {apply_messages(state, messages), messages}
  end

  @impl true
  def view(state, {width, height} = dimensions, theme) do
    if width >= 56 and height >= 14,
      do: wide_view(state, dimensions, theme),
      else: compact_view(state, dimensions)
  end

  @impl true
  def help, do: "Tab changes focus. Enter or Space changes the active control."

  @doc false
  def tick(state), do: %{state | spinner: Spinner.tick(state.spinner)}

  defp wide_view(state, {width, height} = dimensions, theme) do
    [selector_rect, breadcrumb_rect, body_rect, status_rect] =
      Layout.column(Layout.new(dimensions), [1, 1, :fill, 1])

    cells =
      Layout.grid(body_rect, 4, columns: 2, rows: 2, column_gap: 1, row_gap: 1)

    selector = ShowcaseLayout.selector(focus_items(), state.focus, width)
    breadcrumb = Breadcrumb.view(state.breadcrumb, Layout.dimensions(breadcrumb_rect))
    status = Frame.from_rows([state.status], Layout.dimensions(status_rect) |> elem(0), 1)

    [boolean_cell, radio_cell, select_cell, spinner_cell] = cells

    Frame.new(width, height)
    |> Layout.place(selector, selector_rect)
    |> Layout.place(breadcrumb, breadcrumb_rect)
    |> Layout.place(boolean_panel(state, boolean_cell, theme), boolean_cell)
    |> Layout.place(radio_panel(state, radio_cell, theme), radio_cell)
    |> Layout.place(select_panel(state, select_cell, theme), select_cell)
    |> Layout.place(spinner_panel(state, spinner_cell, theme), spinner_cell)
    |> Layout.place(status, status_rect)
  end

  defp compact_view(state, {width, height}) do
    radio = state.radio |> RadioGroup.focus(state.focus == :radio) |> RadioGroup.view({width, 1})
    select_height = min(max(height - 7, 1), 4)

    Frame.new(width, height)
    |> Frame.overlay(ShowcaseLayout.selector(focus_items(), state.focus, width), 1, 1)
    |> Frame.overlay(Breadcrumb.view(state.breadcrumb, {width, 1}), 1, min(2, height))
    |> Frame.overlay(Spinner.view(state.spinner, {width, 1}), 1, min(3, height))
    |> Frame.overlay(checkbox_frame(state, {width, 1}), 1, min(4, height))
    |> Frame.overlay(toggle_frame(state, {width, 1}), 1, min(5, height))
    |> Frame.overlay(radio, 1, min(6, height))
    |> Frame.overlay(select_frame(state, {width, select_height}), 1, min(7, height))
    |> Frame.put_row(height, [state.status])
  end

  defp boolean_panel(state, {_x, _y, width, height}, theme) do
    child_dimensions = {max(width - 2, 1), max(height - 2, 1)}
    {child_width, child_height} = child_dimensions

    child =
      Frame.new(child_width, child_height)
      |> Frame.overlay(checkbox_frame(state, {child_width, 1}), 1, 1)
      |> Frame.overlay(toggle_frame(state, {child_width, 1}), 1, min(2, child_height))

    ShowcaseLayout.panel(child, "Boolean controls", {width, height},
      active: state.focus in [:checkbox, :toggle],
      theme: theme
    )
  end

  defp radio_panel(state, {_x, _y, width, height}, theme) do
    dimensions = {max(width - 2, 1), max(height - 2, 1)}
    radio = state.radio |> RadioGroup.focus(state.focus == :radio) |> RadioGroup.view(dimensions)

    ShowcaseLayout.panel(radio, "Radio group", {width, height},
      active: state.focus == :radio,
      theme: theme
    )
  end

  defp select_panel(state, {_x, _y, width, height}, theme) do
    select = select_frame(state, {max(width - 2, 1), max(height - 2, 1)})

    ShowcaseLayout.panel(select, "Select", {width, height},
      active: state.focus == :select,
      theme: theme
    )
  end

  defp spinner_panel(state, {_x, _y, width, height}, theme) do
    spinner = Spinner.view(state.spinner, {max(width - 2, 1), max(height - 2, 1)})
    ShowcaseLayout.panel(spinner, "Spinner", {width, height}, theme: theme)
  end

  defp checkbox_frame(state, dimensions) do
    state.checkbox
    |> Checkbox.focus(state.focus == :checkbox)
    |> Checkbox.view(dimensions)
  end

  defp toggle_frame(state, dimensions) do
    state.toggle
    |> Toggle.focus(state.focus == :toggle)
    |> Toggle.view(dimensions)
  end

  defp select_frame(state, dimensions) do
    state.select
    |> Select.focus(state.focus == :select)
    |> Select.view(dimensions)
  end

  defp update_focused(%{focus: :checkbox} = state, event) do
    {widget, messages} = Checkbox.update(event, Checkbox.focus(state.checkbox))
    {%{state | checkbox: widget}, messages}
  end

  defp update_focused(%{focus: :toggle} = state, event) do
    {widget, messages} = Toggle.update(event, Toggle.focus(state.toggle))
    {%{state | toggle: widget}, messages}
  end

  defp update_focused(%{focus: :radio} = state, event) do
    {widget, messages} = RadioGroup.update(event, RadioGroup.focus(state.radio))
    {%{state | radio: widget}, messages}
  end

  defp update_focused(%{focus: :select} = state, event) do
    {widget, messages} = Select.update(event, Select.focus(state.select))
    {%{state | select: widget}, messages}
  end

  defp move_focus(state, delta) do
    index = Enum.find_index(@focus_order, &(&1 == state.focus)) || 0
    next = rem(index + delta + length(@focus_order), length(@focus_order))
    %{state | focus: Enum.at(@focus_order, next), select: Select.close(state.select)}
  end

  defp apply_messages(state, messages) do
    Enum.reduce(messages, state, fn
      {:changed, id, value}, acc -> %{acc | status: "#{id}: #{value}"}
      {:selected, id, value}, acc -> %{acc | status: "#{id}: #{value}"}
      _message, acc -> acc
    end)
  end

  defp focus_items,
    do: [checkbox: "Checkbox", toggle: "Toggle", radio: "Radio", select: "Select"]
end
