defmodule TermUI.Shortcut do
  @moduledoc """
  Pure key and key-sequence routing.

  Bindings map normalized strokes or stroke sequences to parent messages. The
  router uses event timestamps for sequence expiry, so it needs no timer or
  global shortcut service.
  """

  alias TermUI.Event

  @type stroke :: %{key: atom() | String.t(), modifiers: [atom()]}
  @type binding :: %{sequence: [stroke()], message: term()}
  @type t :: %__MODULE__{
          bindings: [binding()],
          pending: [stroke()],
          timeout_ms: pos_integer(),
          last_timestamp: integer() | nil,
          enabled: boolean()
        }

  @named_keys ~w(backspace tab enter escape up down left right home end page_up page_down insert delete space)a

  defstruct bindings: [],
            pending: [],
            timeout_ms: 1_000,
            last_timestamp: nil,
            enabled: true

  @doc "Creates shortcut routing state from `{shortcut, message}` bindings."
  @spec new(Enumerable.t(), keyword()) :: t()
  def new(bindings \\ [], opts \\ []) do
    %__MODULE__{
      bindings: Enum.map(bindings, &normalize_binding/1),
      timeout_ms: opts |> Keyword.get(:timeout, 1_000) |> max(1),
      enabled: Keyword.get(opts, :enabled, true)
    }
  end

  @doc "Creates one normalized shortcut stroke."
  @spec key(atom() | String.t(), [atom()]) :: stroke()
  def key(key, modifiers \\ [])

  def key(spec, []) when is_binary(spec) do
    parts = String.split(spec, "+", trim: true)

    case parts do
      [key] ->
        %{key: normalize_key(key), modifiers: []}

      parts ->
        %{
          key: parts |> List.last() |> normalize_key(),
          modifiers: parts |> Enum.drop(-1) |> Enum.map(&normalize_modifier/1) |> Enum.sort()
        }
    end
  end

  def key(key, modifiers),
    do: %{key: normalize_key(key), modifiers: modifiers |> Enum.uniq() |> Enum.sort()}

  @doc "Routes one key or text event and returns matching parent messages."
  @spec route(Event.t(), t()) :: {t(), [term()]}
  def route(_event, %{enabled: false} = state), do: {state, []}

  def route(event, state) do
    case event_stroke(event) do
      nil ->
        {state, []}

      {stroke, timestamp} ->
        pending = if expired?(state, timestamp), do: [], else: state.pending
        match(state, pending ++ [stroke], stroke, timestamp)
    end
  end

  @doc "Clears a partial key sequence."
  @spec reset(t()) :: t()
  def reset(state), do: %{state | pending: [], last_timestamp: nil}

  @doc "Enables shortcut routing."
  @spec enable(t()) :: t()
  def enable(state), do: %{state | enabled: true}

  @doc "Disables routing and clears partial sequence state."
  @spec disable(t()) :: t()
  def disable(state), do: %{state | enabled: false, pending: [], last_timestamp: nil}

  defp match(state, candidate, stroke, timestamp) do
    case exact_binding(state.bindings, candidate) do
      %{message: message} ->
        {%{state | pending: [], last_timestamp: nil}, [message]}

      nil ->
        cond do
          prefix?(state.bindings, candidate) ->
            {%{state | pending: candidate, last_timestamp: timestamp}, []}

          binding = exact_binding(state.bindings, [stroke]) ->
            {%{state | pending: [], last_timestamp: nil}, [binding.message]}

          prefix?(state.bindings, [stroke]) ->
            {%{state | pending: [stroke], last_timestamp: timestamp}, []}

          true ->
            {%{state | pending: [], last_timestamp: nil}, []}
        end
    end
  end

  defp exact_binding(bindings, sequence), do: Enum.find(bindings, &(&1.sequence == sequence))

  defp prefix?(bindings, sequence),
    do: Enum.any?(bindings, &List.starts_with?(&1.sequence, sequence))

  defp expired?(%{pending: []}, _timestamp), do: false
  defp expired?(%{last_timestamp: nil}, _timestamp), do: false
  defp expired?(_state, 0), do: false
  defp expired?(state, timestamp), do: timestamp - state.last_timestamp > state.timeout_ms

  defp event_stroke(%Event.Key{key: key, modifiers: modifiers, timestamp: timestamp}),
    do: {key(key, modifiers), timestamp}

  defp event_stroke(%Event.Text{text: text, timestamp: timestamp}) do
    case String.graphemes(text) do
      [grapheme] -> {key(if(grapheme == " ", do: :space, else: grapheme)), timestamp}
      _other -> nil
    end
  end

  defp event_stroke(_event), do: nil

  defp normalize_binding({sequence, message}),
    do: %{sequence: normalize_sequence(sequence), message: message}

  defp normalize_binding(%{sequence: sequence, message: message}),
    do: %{sequence: normalize_sequence(sequence), message: message}

  defp normalize_binding(other),
    do:
      raise(
        ArgumentError,
        "shortcut bindings must contain a sequence and message, got: #{inspect(other)}"
      )

  defp normalize_sequence(sequence) when is_list(sequence),
    do: Enum.map(sequence, &normalize_stroke/1)

  defp normalize_sequence(sequence), do: [normalize_stroke(sequence)]

  defp normalize_stroke(%{key: key, modifiers: modifiers}), do: key(key, modifiers)
  defp normalize_stroke({key, modifiers}) when is_list(modifiers), do: key(key, modifiers)
  defp normalize_stroke(stroke), do: key(stroke)

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    normalized = String.downcase(key)

    case Enum.find(@named_keys, &(Atom.to_string(&1) == normalized)) do
      nil -> key
      named -> named
    end
  end

  defp normalize_modifier(modifier) do
    case String.downcase(modifier) do
      "ctrl" -> :ctrl
      "alt" -> :alt
      "shift" -> :shift
      "meta" -> :meta
      "super" -> :super
      other -> raise ArgumentError, "unknown shortcut modifier: #{inspect(other)}"
    end
  end
end
