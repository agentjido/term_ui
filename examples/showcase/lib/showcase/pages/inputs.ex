defmodule Showcase.Pages.Inputs do
  @moduledoc false

  @behaviour Showcase.Page

  alias Showcase.Layout
  alias TermUI.Event
  alias TermUI.Frame
  alias TermUI.Widget.{Button, List, TextArea, TextInput}

  @focus_order [:name, :notes, :choices, :submit]

  @impl true
  def init do
    %{
      focus: :name,
      name: TextInput.init(placeholder: "Type a project name", max_length: 60),
      notes:
        TextArea.init(
          value: "TermUI keeps widget state in the parent application.",
          max_length: 500
        ),
      choices:
        List.init(
          items: ["Keyboard navigation", "Mouse input", "Clipboard", "Responsive layout"],
          mode: :multiple,
          page_size: 4
        ),
      submit: Button.init(id: :save, label: "Save example", message: :save),
      status: "Tab moves focus. Editing events go only to the focused widget."
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
  def view(state, {width, height}, theme) do
    selector = Layout.selector(focus_items(), state.focus, width)
    body_height = max(height - 1, 1)
    name_height = min(3, body_height)

    notes_height =
      min(max(div(body_height - name_height, 2), 3), max(body_height - name_height, 1))

    lower_height = max(body_height - name_height - notes_height, 1)

    name =
      state.name
      |> TextInput.view({max(width - 2, 1), 1})
      |> maybe_hide_cursor(state.focus != :name)
      |> Layout.panel("Text input", {width, name_height},
        active: state.focus == :name,
        theme: theme
      )

    notes =
      state.notes
      |> TextArea.view({max(width - 2, 1), max(notes_height - 2, 1)})
      |> maybe_hide_cursor(state.focus != :notes)
      |> Layout.panel("Text area", {width, notes_height},
        active: state.focus == :notes,
        theme: theme
      )

    lower = lower_frame(state, {width, lower_height}, theme)

    Frame.new(width, height)
    |> Frame.overlay(selector, 1, 1)
    |> Frame.overlay(name, 1, 2)
    |> Frame.overlay(notes, 1, name_height + 2)
    |> Frame.overlay(lower, 1, name_height + notes_height + 2)
  end

  @impl true
  def help, do: "Tab changes focus. Enter activates controls. Ctrl+C copies selected text."

  defp update_focused(%{focus: :name} = state, event) do
    {widget, messages} = TextInput.update(event, state.name)
    {%{state | name: widget}, messages}
  end

  defp update_focused(%{focus: :notes} = state, event) do
    {widget, messages} = TextArea.update(event, state.notes)
    {%{state | notes: widget}, messages}
  end

  defp update_focused(%{focus: :choices} = state, event) do
    {widget, messages} = List.update(event, state.choices)
    {%{state | choices: widget}, messages}
  end

  defp update_focused(%{focus: :submit} = state, event) do
    {widget, messages} = Button.update(event, Button.focus(state.submit))
    {%{state | submit: widget}, messages}
  end

  defp lower_frame(state, {width, height}, theme) when width >= 54 do
    {left_width, right_width} = Layout.split_widths(width)

    choices =
      state.choices
      |> List.view({max(left_width - 2, 1), max(height - 2, 1)})
      |> Layout.panel("Multi-select list", {left_width, height},
        active: state.focus == :choices,
        theme: theme
      )

    action = action_frame(state, {right_width - 2, max(height - 2, 1)})

    action =
      Layout.panel(action, "Application result", {right_width, height},
        active: state.focus == :submit,
        theme: theme
      )

    Frame.new(width, height)
    |> Frame.overlay(choices, 1, 1)
    |> Frame.overlay(action, left_width + 2, 1)
  end

  defp lower_frame(state, {width, height}, theme) do
    if state.focus == :choices do
      if height < 3 do
        List.view(state.choices, {width, height})
      else
        choices = List.view(state.choices, {max(width - 2, 1), height - 2})
        Layout.panel(choices, "Multi-select list", {width, height}, active: true, theme: theme)
      end
    else
      action = action_frame(state, {max(width - 2, 1), max(height - 2, 1)})

      Layout.panel(action, "Application result", {width, height},
        active: state.focus == :submit,
        theme: theme
      )
    end
  end

  defp action_frame(state, {width, height}) do
    button = state.submit |> Button.focus(state.focus == :submit) |> Button.view({width, 1})
    status = Frame.from_rows(Frame.wrap(state.status, width), width, max(height - 2, 1))

    Frame.new(width, height)
    |> Frame.overlay(button, 1, 1)
    |> Frame.overlay(status, 1, min(3, height))
  end

  defp move_focus(state, delta) do
    index = Enum.find_index(@focus_order, &(&1 == state.focus)) || 0
    next = rem(index + delta + length(@focus_order), length(@focus_order))
    %{state | focus: Enum.at(@focus_order, next)}
  end

  defp apply_messages(state, messages) do
    Enum.reduce(messages, state, fn
      :save, acc ->
        %{
          acc
          | status:
              "Saved #{inspect(acc.name.value)} with #{MapSet.size(acc.choices.selected)} choices"
        }

      {:submit, value}, acc ->
        %{acc | status: "Submitted #{inspect(value)}"}

      {:selected, value}, acc ->
        %{acc | status: "Selected #{value}"}

      {:toggled, value}, acc ->
        %{acc | status: "Toggled #{value}"}

      _message, acc ->
        acc
    end)
  end

  defp focus_items,
    do: [name: "Name", notes: "Notes", choices: "Choices", submit: "Submit"]

  defp maybe_hide_cursor(frame, true), do: Layout.without_cursor(frame)
  defp maybe_hide_cursor(frame, false), do: frame
end
