defmodule TermUI.Widget.Select do
  @moduledoc "A pure compact select control with an in-frame option list."

  @behaviour TermUI.Widget

  alias TermUI.{CharacterSet, Event, Style}
  alias TermUI.Widget.Helpers

  @type option :: %{
          required(:value) => term(),
          required(:label) => String.t(),
          optional(:disabled) => boolean()
        }
  @type t :: %__MODULE__{
          id: term(),
          options: [option()],
          selected: term(),
          cursor: non_neg_integer(),
          offset: non_neg_integer(),
          page_size: pos_integer(),
          open: boolean(),
          focused: boolean(),
          disabled: boolean(),
          placeholder: String.t(),
          open_icon: String.t(),
          closed_icon: String.t(),
          style: Style.t(),
          focus_style: Style.t(),
          selected_style: Style.t(),
          disabled_style: Style.t()
        }

  defstruct id: nil,
            options: [],
            selected: nil,
            cursor: 0,
            offset: 0,
            page_size: 6,
            open: false,
            focused: false,
            disabled: false,
            placeholder: "Select…",
            open_icon: "▲",
            closed_icon: "▼",
            style: %Style{},
            focus_style: %Style{attrs: MapSet.new([:reverse])},
            selected_style: %Style{fg: :cyan},
            disabled_style: %Style{fg: :bright_black}

  @doc "Creates one select option."
  @spec option(term(), iodata(), keyword()) :: option()
  def option(value, label, opts \\ []),
    do: %{
      value: value,
      label: normalize_label(label),
      disabled: Keyword.get(opts, :disabled, false)
    }

  @impl true
  def init(opts) do
    characters = CharacterSet.get(Keyword.get(opts, :character_set, CharacterSet.current()))
    options = opts |> Keyword.get(:options, []) |> normalize_options()
    selected = valid_value(options, Keyword.get(opts, :selected, Keyword.get(opts, :value)))
    cursor = enabled_index(options, selected) || first_enabled(options)
    disabled = Keyword.get(opts, :disabled, false)
    open = Keyword.get(opts, :open, false) and not disabled and enabled_indices(options) != []

    %__MODULE__{
      id: Keyword.get(opts, :id),
      options: options,
      selected: selected,
      cursor: cursor,
      page_size: max(Keyword.get(opts, :page_size, 6), 1),
      open: open,
      focused: Keyword.get(opts, :focused, false),
      disabled: disabled,
      placeholder:
        opts |> Keyword.get(:placeholder, "Select" <> characters.ellipsis) |> to_string(),
      open_icon: opts |> Keyword.get(:open_icon, characters.triangle_up) |> to_string(),
      closed_icon: opts |> Keyword.get(:closed_icon, characters.triangle_down) |> to_string(),
      style: Keyword.get(opts, :style, Style.new()),
      focus_style: Keyword.get(opts, :focus_style, Style.new(attrs: [:reverse])),
      selected_style: Keyword.get(opts, :selected_style, Style.new(fg: :cyan)),
      disabled_style: Keyword.get(opts, :disabled_style, Style.new(fg: :bright_black))
    }
    |> normalize_offset()
  end

  @impl true
  def update(_event, %{disabled: true} = state), do: {state, []}
  def update(%Event.Key{key: :escape}, %{open: true} = state), do: {%{state | open: false}, []}
  def update(%Event.Key{key: :up}, %{open: true} = state), do: move(state, -1)
  def update(%Event.Key{key: :down}, %{open: true} = state), do: move(state, 1)
  def update(%Event.Key{key: :home}, %{open: true} = state), do: move_to_edge(state, :first)
  def update(%Event.Key{key: :end}, %{open: true} = state), do: move_to_edge(state, :last)

  def update(%Event.Key{key: key}, %{open: true} = state) when key in [:enter, :space],
    do: choose(state)

  def update(%Event.Text{text: " "}, %{open: true} = state), do: choose(state)

  def update(%Event.Key{key: key}, state) when key in [:enter, :space],
    do: {open(state), []}

  def update(%Event.Text{text: " "}, state), do: {open(state), []}
  def update(_event, state), do: {state, []}

  @impl true
  def mouse(_event, %{disabled: true} = state, _dimensions), do: {state, []}

  def mouse(%Event.Mouse{action: action, button: :left, x: x, y: 0}, state, {width, height})
      when action in [:press, :release] and x >= 0 and x < width and height > 0 do
    mouse_header(action, state)
  end

  def mouse(
        %Event.Mouse{action: action, button: :left, x: x, y: y},
        %{open: true} = state,
        {width, height}
      )
      when action in [:press, :release] and x >= 0 and x < width and y > 0 and y < height do
    visible_height = min(state.page_size, height - 1)

    if y <= visible_height do
      state = normalize_offset(state, visible_height)
      mouse_option(action, state, state.offset + y - 1)
    else
      {state, []}
    end
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(state, {_width, height} = dimensions) do
    header_style =
      cond do
        state.disabled -> state.disabled_style
        state.focused -> state.focus_style
        true -> state.style
      end

    icon = if state.open, do: state.open_icon, else: state.closed_icon
    rows = [[{selected_label(state) <> " " <> icon, header_style}]]

    rows =
      if state.open and height > 1 do
        visible_height = min(state.page_size, height - 1)
        state = normalize_offset(state, visible_height)

        option_rows =
          state.options
          |> Enum.slice(state.offset, visible_height)
          |> Enum.with_index(state.offset)
          |> Enum.map(&option_row(&1, state))

        rows ++ option_rows
      else
        rows
      end

    Helpers.frame(rows, dimensions)
  end

  @doc "Opens the option list."
  @spec open(t()) :: t()
  def open(%{disabled: true} = state), do: state

  def open(state) do
    if enabled_indices(state.options) == [], do: state, else: %{state | open: true}
  end

  @doc "Closes the option list."
  @spec close(t()) :: t()
  def close(state), do: %{state | open: false}

  @doc "Selects one enabled option without producing a message."
  @spec select(t(), term()) :: t()
  def select(state, value) do
    case enabled_index(state.options, value) do
      nil -> state
      index -> %{state | selected: value, cursor: index} |> normalize_offset()
    end
  end

  @doc "Returns the selected value."
  @spec selected(t()) :: term()
  def selected(state), do: state.selected

  @doc "Replaces all options and keeps valid selection state."
  @spec set_options(t(), [term()]) :: t()
  def set_options(state, options) do
    options = normalize_options(options)
    selected = valid_value(options, state.selected)
    cursor = enabled_index(options, selected) || first_enabled(options)
    %{state | options: options, selected: selected, cursor: cursor, offset: 0, open: false}
  end

  @doc "Sets keyboard focus."
  @spec focus(t(), boolean()) :: t()
  def focus(state, focused \\ true), do: %{state | focused: focused}

  defp choose(state) do
    case Enum.at(state.options, state.cursor) do
      %{disabled: false, value: value} ->
        {%{state | selected: value, open: false}, [{:selected, state.id, value}]}

      _option ->
        {state, []}
    end
  end

  defp mouse_option(action, state, index) do
    case Enum.at(state.options, index) do
      %{disabled: false} ->
        state = %{state | cursor: index, focused: true}
        if action == :release, do: choose(state), else: {state, []}

      _option ->
        {state, []}
    end
  end

  defp mouse_header(action, state) do
    case enabled_indices(state.options) do
      [] -> {state, []}
      _indices -> mouse_header_enabled(action, %{state | focused: true})
    end
  end

  defp mouse_header_enabled(:press, state), do: {state, []}

  defp mouse_header_enabled(:release, %{open: true} = state), do: {close(state), []}
  defp mouse_header_enabled(:release, state), do: {open(state), []}

  defp move(state, delta) do
    indices = enabled_indices(state.options)

    case indices do
      [] ->
        {state, []}

      _indices ->
        position =
          Enum.find_index(indices, &(&1 == state.cursor)) || if(delta < 0, do: 0, else: -1)

        next = Enum.at(indices, rem(position + delta + length(indices), length(indices)))
        {%{state | cursor: next} |> normalize_offset(), []}
    end
  end

  defp move_to_edge(state, edge) do
    index =
      if edge == :first,
        do: List.first(enabled_indices(state.options)),
        else: List.last(enabled_indices(state.options))

    if is_nil(index),
      do: {state, []},
      else: {%{state | cursor: index} |> normalize_offset(), []}
  end

  defp option_row({option, index}, state) do
    marker = if index == state.cursor, do: "> ", else: "  "

    style =
      cond do
        option.disabled -> state.disabled_style
        index == state.cursor -> state.focus_style
        option.value == state.selected -> state.selected_style
        true -> state.style
      end

    [{marker <> option.label, style}]
  end

  defp selected_label(state) do
    case Enum.find(state.options, &(&1.value == state.selected)) do
      nil -> state.placeholder
      option -> option.label
    end
  end

  defp normalize_offset(state, height \\ nil)
  defp normalize_offset(%{options: []} = state, _height), do: %{state | cursor: 0, offset: 0}

  defp normalize_offset(state, height) do
    height = max(height || state.page_size, 1)
    maximum = max(length(state.options) - height, 0)

    offset =
      cond do
        state.cursor < state.offset -> state.cursor
        state.cursor >= state.offset + height -> state.cursor - height + 1
        true -> state.offset
      end

    %{state | offset: Helpers.clamp(offset, 0, maximum)}
  end

  defp normalize_options(options) do
    options
    |> Enum.map(&normalize_option/1)
    |> Enum.uniq_by(& &1.value)
  end

  defp normalize_option(%{value: value, label: label} = option),
    do: %{value: value, label: to_string(label), disabled: Map.get(option, :disabled, false)}

  defp normalize_option({value, label}), do: option(value, label)
  defp normalize_option(value), do: option(value, to_string(value))
  defp valid_value(options, value), do: if(enabled_index(options, value), do: value)

  defp enabled_index(options, value),
    do: Enum.find_index(options, &(&1.value == value and enabled?(&1)))

  defp enabled_indices(options),
    do:
      options
      |> Enum.with_index()
      |> Enum.filter(fn {option, _index} -> enabled?(option) end)
      |> Enum.map(&elem(&1, 1))

  defp first_enabled(options), do: List.first(enabled_indices(options)) || 0
  defp enabled?(%{disabled: false}), do: true
  defp enabled?(_option), do: false

  defp normalize_label(label) when is_binary(label) or is_list(label),
    do: IO.iodata_to_binary(label)

  defp normalize_label(label), do: to_string(label)
end
