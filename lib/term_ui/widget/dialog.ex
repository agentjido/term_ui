defmodule TermUI.Widget.Dialog do
  @moduledoc "A pure bordered dialog with content and action buttons."

  @behaviour TermUI.Widget

  alias TermUI.{Event, Frame, Layout, Style}
  alias TermUI.Widget.Helpers

  @type button :: %{
          required(:id) => term(),
          required(:label) => String.t(),
          required(:message) => term(),
          optional(:disabled) => boolean()
        }
  @type t :: %__MODULE__{
          title: String.t(),
          content: [Frame.row()],
          buttons: [button()],
          focused: non_neg_integer(),
          visible: boolean(),
          dismiss_message: term()
        }
  defstruct title: "",
            content: [],
            buttons: [],
            focused: 0,
            visible: true,
            dismiss_message: :dismissed

  @impl true
  def init(opts) do
    buttons = opts |> Keyword.get(:buttons, []) |> Enum.map(&normalize_button/1)
    requested_focus = max(Keyword.get(opts, :focused, 0), 0)

    %__MODULE__{
      title: opts |> Keyword.get(:title, "") |> to_string(),
      content: normalize_content(Keyword.get(opts, :content, "")),
      buttons: buttons,
      focused: enabled_focus(buttons, requested_focus),
      visible: Keyword.get(opts, :visible, true),
      dismiss_message: Keyword.get(opts, :dismiss_message, :dismissed)
    }
  end

  @impl true
  def update(_event, %{visible: false} = state), do: {state, []}

  def update(%Event.Key{key: :escape}, state),
    do: {%{state | visible: false}, [state.dismiss_message]}

  def update(%Event.Key{key: key}, state) when key in [:left, :up], do: move(state, -1)
  def update(%Event.Key{key: key}, state) when key in [:right, :down, :tab], do: move(state, 1)
  def update(%Event.Key{key: key}, state) when key in [:enter, :space], do: activate(state)
  def update(%Event.Text{text: " "}, state), do: activate(state)
  def update(_event, state), do: {state, []}

  @impl true
  def mouse(_event, %{visible: false} = state, _dimensions), do: {state, []}

  def mouse(%Event.Mouse{action: action, button: :left, x: x, y: y}, state, {width, height})
      when action in [:press, :release] and width > 2 and height >= 3 do
    if y == height - 2 do
      case button_at(state.buttons, x - 1, width - 2) do
        nil ->
          {state, []}

        index ->
          state = %{state | focused: index}
          activate_on_release(action, state)
      end
    else
      {state, []}
    end
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(%{visible: false}, dimensions), do: Helpers.frame([], dimensions)

  def view(state, {width, height} = dimensions) do
    body_height = max(height - 3, 0)
    button_style = Style.new(fg: :bright_black)
    focused_style = Style.new(fg: :black, bg: :cyan, attrs: [:bold])
    disabled_style = Style.new(fg: :bright_black, attrs: [:dim])

    button_row =
      state.buttons
      |> Enum.with_index()
      |> Enum.flat_map(fn {button, index} ->
        style =
          cond do
            button.disabled -> disabled_style
            index == state.focused -> focused_style
            true -> button_style
          end

        [{button_text(button), style}, " "]
      end)

    rows =
      Enum.take(state.content, body_height) ++
        List.duplicate("", max(body_height - length(state.content), 0)) ++ [button_row]

    bordered = Helpers.border(rows, dimensions, title: state.title)
    Helpers.frame(bordered, {width, height})
  end

  @doc "Shows the dialog."
  @spec show(t()) :: t()
  def show(state), do: %{state | visible: true}

  @doc "Hides the dialog."
  @spec hide(t()) :: t()
  def hide(state), do: %{state | visible: false}

  @doc "Returns the zero-based rectangle available to child content."
  @spec content_rect(t(), TermUI.Widget.dimensions()) :: Layout.rect()
  def content_rect(_state, {width, height}) when width > 1 and height > 1,
    do: {1, 1, max(width - 2, 0), max(height - 3, 0)}

  def content_rect(_state, {width, height}), do: {0, 0, width, max(height - 1, 0)}

  @doc "Renders and clips pure child content inside the dialog body."
  @spec compose(t(), TermUI.Widget.dimensions(), TermUI.Widget.renderable()) :: Frame.t()
  def compose(%{visible: false} = state, dimensions, _child), do: view(state, dimensions)

  def compose(state, dimensions, child) do
    Helpers.compose(view(state, dimensions), content_rect(state, dimensions), child)
  end

  defp move(%{buttons: []} = state, _delta), do: {state, []}

  defp move(state, delta) do
    indices = enabled_indices(state.buttons)

    case indices do
      [] ->
        {state, []}

      _indices ->
        position =
          Enum.find_index(indices, &(&1 == state.focused)) || if(delta < 0, do: 0, else: -1)

        next = Enum.at(indices, rem(position + delta + length(indices), length(indices)))
        {%{state | focused: next}, []}
    end
  end

  defp activate(state) do
    case Enum.at(state.buttons, state.focused) do
      %{disabled: true} -> {state, []}
      %{message: message} -> {state, [message]}
      _other -> {state, []}
    end
  end

  defp activate_on_release(:release, state), do: activate(state)
  defp activate_on_release(:press, state), do: {state, []}

  defp button_at(buttons, x, inner_width) when x >= 0 and x < inner_width do
    buttons
    |> Enum.with_index()
    |> Enum.reduce_while({:after, 0}, fn {button, index}, {:after, start} ->
      finish = start + Helpers.text_width(button_text(button))

      if x >= start and x < finish,
        do: {:halt, if(button.disabled, do: :none, else: {:found, index})},
        else: {:cont, {:after, finish + 1}}
    end)
    |> case do
      {:found, index} -> index
      _other -> nil
    end
  end

  defp button_at(_buttons, _x, _inner_width), do: nil

  defp normalize_content(content) when is_binary(content),
    do: String.split(content, "\n", trim: false)

  defp normalize_content(content) when is_list(content), do: content
  defp normalize_content(content), do: [to_string(content)]

  defp normalize_button(%{id: id, label: label} = button),
    do: %{
      id: id,
      label: to_string(label),
      message: Map.get(button, :message, {:selected, id}),
      disabled: Map.get(button, :disabled, false)
    }

  defp normalize_button({id, label}),
    do: %{id: id, label: to_string(label), message: {:selected, id}, disabled: false}

  defp button_text(button), do: "[ " <> button.label <> " ]"

  defp enabled_focus(buttons, requested) do
    requested = Helpers.clamp(requested, 0, max(length(buttons) - 1, 0))

    if enabled?(Enum.at(buttons, requested)),
      do: requested,
      else: List.first(enabled_indices(buttons)) || 0
  end

  defp enabled_indices(buttons) do
    buttons
    |> Enum.with_index()
    |> Enum.filter(fn {button, _index} -> enabled?(button) end)
    |> Enum.map(&elem(&1, 1))
  end

  defp enabled?(%{disabled: false}), do: true
  defp enabled?(_button), do: false
end
