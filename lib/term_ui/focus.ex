defmodule TermUI.Focus do
  @moduledoc """
  Pure focus traversal state for an Elm application.

  The router handles Tab, Shift+Tab, Home, End, and terminal focus events. It
  returns parent messages and never sends events or stores global state.
  """

  alias TermUI.Event

  @type t :: %__MODULE__{
          order: [term()],
          current: term() | nil,
          disabled: [term()],
          wrap: boolean(),
          active: boolean()
        }

  defstruct order: [],
            current: nil,
            disabled: [],
            wrap: true,
            active: true

  @doc "Creates focus state from ids or `%{id: id, disabled: boolean}` entries."
  @spec new(Enumerable.t(), keyword()) :: t()
  def new(items \\ [], opts \\ []) do
    {order, item_disabled} = normalize_items(items)
    disabled = Enum.uniq(item_disabled ++ Keyword.get(opts, :disabled, []))
    requested = Keyword.get(opts, :current)

    current =
      if requested in order and requested not in disabled,
        do: requested,
        else: first_enabled(order, disabled)

    %__MODULE__{
      order: order,
      current: current,
      disabled: disabled,
      wrap: Keyword.get(opts, :wrap, true),
      active: Keyword.get(opts, :active, true)
    }
  end

  @doc "Routes one normalized event and returns focus messages."
  @spec route(Event.t(), t()) :: {t(), [term()]}
  def route(%Event.Key{key: :tab, modifiers: modifiers}, state),
    do: move_with_message(state, if(:shift in modifiers, do: -1, else: 1))

  def route(%Event.Key{key: :home}, state),
    do: change(state, first_enabled(state.order, state.disabled))

  def route(%Event.Key{key: :end}, state),
    do: change(state, last_enabled(state.order, state.disabled))

  def route(%Event.Focus{action: :lost}, state),
    do: {%{state | active: false}, [{:focus_active, false}]}

  def route(%Event.Focus{action: :gained}, state),
    do: {%{state | active: true}, [{:focus_active, true}]}

  def route(_event, state), do: {state, []}

  @doc "Moves focus forward by one enabled item."
  @spec next(t()) :: t()
  def next(state), do: state |> move(1) |> elem(0)

  @doc "Moves focus backward by one enabled item."
  @spec previous(t()) :: t()
  def previous(state), do: state |> move(-1) |> elem(0)

  @doc "Focuses one enabled id."
  @spec focus(t(), term()) :: t()
  def focus(state, id), do: state |> change(id) |> elem(0)

  @doc "Disables one id and moves away from it when needed."
  @spec disable(t(), term()) :: t()
  def disable(state, id) do
    state =
      if id in state.order,
        do: %{state | disabled: Enum.uniq(state.disabled ++ [id])},
        else: state

    if state.current == id, do: next(state), else: state
  end

  @doc "Enables one id."
  @spec enable(t(), term()) :: t()
  def enable(state, id), do: %{state | disabled: List.delete(state.disabled, id)}

  @doc "Returns true when an id owns active focus."
  @spec focused?(t(), term()) :: boolean()
  def focused?(state, id), do: state.active and state.current == id

  defp move_with_message(state, delta), do: move(state, delta)

  defp move(state, delta) do
    enabled = Enum.reject(state.order, &(&1 in state.disabled))

    case enabled do
      [] ->
        change(state, nil)

      _items ->
        current_index = Enum.find_index(enabled, &(&1 == state.current))
        next_index = next_index(current_index, delta, length(enabled), state.wrap)
        change(state, Enum.at(enabled, next_index))
    end
  end

  defp change(state, id) do
    valid? = is_nil(id) or (id in state.order and id not in state.disabled)

    cond do
      not valid? -> {state, []}
      state.current == id -> {state, []}
      true -> {%{state | current: id}, [{:focus_changed, state.current, id}]}
    end
  end

  defp next_index(nil, delta, count, _wrap), do: if(delta < 0, do: count - 1, else: 0)
  defp next_index(index, delta, count, true), do: rem(index + delta + count, count)
  defp next_index(index, delta, count, false), do: min(max(index + delta, 0), count - 1)

  defp normalize_items(items) do
    items
    |> Enum.reduce({[], []}, fn
      %{id: id, disabled: true}, {order, disabled} -> {order ++ [id], disabled ++ [id]}
      %{id: id}, {order, disabled} -> {order ++ [id], disabled}
      id, {order, disabled} -> {order ++ [id], disabled}
    end)
    |> then(fn {order, disabled} -> {Enum.uniq(order), Enum.uniq(disabled)} end)
  end

  defp first_enabled(order, disabled), do: Enum.find(order, &(&1 not in disabled))
  defp last_enabled(order, disabled), do: order |> Enum.reverse() |> first_enabled(disabled)
end
