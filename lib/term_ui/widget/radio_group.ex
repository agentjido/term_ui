defmodule TermUI.Widget.RadioGroup do
  @moduledoc "A pure single-selection radio group."

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
          orientation: :vertical | :horizontal,
          focused: boolean(),
          disabled: boolean(),
          selected_icon: String.t(),
          unselected_icon: String.t(),
          show_brackets: boolean(),
          style: Style.t(),
          selected_style: Style.t(),
          focus_style: Style.t(),
          disabled_style: Style.t()
        }

  defstruct id: nil,
            options: [],
            selected: nil,
            cursor: 0,
            orientation: :vertical,
            focused: false,
            disabled: false,
            selected_icon: "●",
            unselected_icon: "○",
            show_brackets: true,
            style: %Style{},
            selected_style: %Style{fg: :green},
            focus_style: %Style{attrs: MapSet.new([:reverse])},
            disabled_style: %Style{fg: :bright_black}

  @doc "Creates one radio option."
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
    selected = valid_value(options, Keyword.get(opts, :selected))
    cursor = enabled_index(options, selected) || first_enabled(options)

    %__MODULE__{
      id: Keyword.get(opts, :id),
      options: options,
      selected: selected,
      cursor: cursor,
      orientation: Keyword.get(opts, :orientation, :vertical),
      focused: Keyword.get(opts, :focused, false),
      disabled: Keyword.get(opts, :disabled, false),
      selected_icon: opts |> Keyword.get(:selected_icon, characters.bullet) |> to_string(),
      unselected_icon:
        opts |> Keyword.get(:unselected_icon, characters.bullet_empty) |> to_string(),
      show_brackets: Keyword.get(opts, :show_brackets, true),
      style: Keyword.get(opts, :style, Style.new()),
      selected_style: Keyword.get(opts, :selected_style, Style.new(fg: :green)),
      focus_style: Keyword.get(opts, :focus_style, Style.new(attrs: [:reverse])),
      disabled_style: Keyword.get(opts, :disabled_style, Style.new(fg: :bright_black))
    }
  end

  @impl true
  def update(_event, %{disabled: true} = state), do: {state, []}
  def update(%Event.Key{key: key}, state) when key in [:up, :left], do: move(state, -1)
  def update(%Event.Key{key: key}, state) when key in [:down, :right], do: move(state, 1)
  def update(%Event.Key{key: :home}, state), do: move_to_edge(state, :first)
  def update(%Event.Key{key: :end}, state), do: move_to_edge(state, :last)
  def update(%Event.Key{key: key}, state) when key in [:enter, :space], do: choose(state)
  def update(%Event.Text{text: " "}, state), do: choose(state)
  def update(_event, state), do: {state, []}

  @impl true
  def mouse(_event, %{disabled: true} = state, _dimensions), do: {state, []}

  def mouse(%Event.Mouse{action: action, button: :left} = event, state, dimensions)
      when action in [:press, :release] do
    case option_at(state, event, dimensions) do
      nil ->
        {state, []}

      index ->
        state = %{state | cursor: index, focused: true}
        if action == :release, do: choose(state), else: {state, []}
    end
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(state, dimensions) do
    rows =
      case state.orientation do
        :horizontal -> [horizontal_row(state)]
        :vertical -> state.options |> Enum.with_index() |> Enum.map(&option_row(&1, state))
      end

    Helpers.frame(rows, dimensions)
  end

  @doc "Selects one enabled option without producing a message."
  @spec select(t(), term()) :: t()
  def select(state, value) do
    case enabled_index(state.options, value) do
      nil -> state
      index -> %{state | selected: value, cursor: index}
    end
  end

  @doc "Returns the selected value."
  @spec selected(t()) :: term()
  def selected(state), do: state.selected

  @doc "Sets keyboard focus."
  @spec focus(t(), boolean()) :: t()
  def focus(state, focused \\ true), do: %{state | focused: focused}

  defp choose(state) do
    case Enum.at(state.options, state.cursor) do
      %{disabled: false, value: value} ->
        {%{state | selected: value}, [{:selected, state.id, value}]}

      _option ->
        {state, []}
    end
  end

  defp move(state, delta) do
    indices = enabled_indices(state.options)

    case indices do
      [] ->
        {state, []}

      _indices ->
        position =
          Enum.find_index(indices, &(&1 == state.cursor)) || if(delta < 0, do: 0, else: -1)

        next = Enum.at(indices, rem(position + delta + length(indices), length(indices)))
        {%{state | cursor: next}, []}
    end
  end

  defp move_to_edge(state, edge) do
    index =
      if edge == :first,
        do: List.first(enabled_indices(state.options)),
        else: List.last(enabled_indices(state.options))

    if is_nil(index), do: {state, []}, else: {%{state | cursor: index}, []}
  end

  defp horizontal_row(state) do
    state.options
    |> Enum.with_index()
    |> Enum.flat_map(fn indexed -> option_row(indexed, state) ++ [" "] end)
    |> Enum.drop(-1)
  end

  defp option_row({option, index}, state) do
    selected? = option.value == state.selected
    icon = if selected?, do: state.selected_icon, else: state.unselected_icon
    mark = if state.show_brackets, do: "(" <> icon <> ")", else: icon
    [{mark <> " " <> option.label, option_style(option, index, selected?, state)}]
  end

  defp option_style(_option, _index, _selected, %{disabled: true} = state),
    do: state.disabled_style

  defp option_style(%{disabled: true}, _index, _selected, state), do: state.disabled_style

  defp option_style(_option, index, _selected, %{focused: true, cursor: index} = state),
    do: state.focus_style

  defp option_style(_option, _index, true, state), do: state.selected_style
  defp option_style(_option, _index, false, state), do: state.style

  defp option_at(%{orientation: :vertical} = state, %{x: x, y: y}, {width, height})
       when x >= 0 and x < width and y >= 0 and y < height do
    if enabled?(Enum.at(state.options, y)), do: y
  end

  defp option_at(%{orientation: :horizontal} = state, %{x: x, y: 0}, {width, _height})
       when x >= 0 and x < width do
    state.options
    |> Enum.with_index()
    |> Enum.reduce_while(0, fn {option, index}, start ->
      finish = start + Helpers.text_width(option_text(option, index, state))

      if x >= start and x < finish,
        do: {:halt, if(enabled?(option), do: {:found, index}, else: :none)},
        else: {:cont, finish + 1}
    end)
    |> case do
      {:found, index} -> index
      _other -> nil
    end
  end

  defp option_at(_state, _event, _dimensions), do: nil

  defp option_text(option, index, state) do
    option_row({option, index}, state) |> hd() |> elem(0)
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
