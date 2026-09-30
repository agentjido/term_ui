defmodule TermUI.Input do
  @moduledoc """
  Normalizes input from adapters into the v2 event types.

  This module is the boundary for input that does not come from a TermUI
  terminal backend. Printable text, committed input-method composition,
  special keys, and paste stay different at this boundary.

  ## Text fields

  Send printable text and committed composition to a text widget as
  `TermUI.Event.Text`. Send paste as `TermUI.Event.Paste` so the widget can
  apply its paste policy:

      {field, messages} =
        TermUI.Widget.TextInput.update(
          TermUI.Input.text("Jido 👩‍💻"),
          field
        )

      {field, messages} =
        TermUI.Widget.TextInput.update(
          TermUI.Input.composition("e\u0301"),
          field
        )

      {field, messages} =
        TermUI.Widget.TextInput.update(
          TermUI.Input.paste("first\nsecond"),
          field
        )

  Call `composition/2` only after an input method commits text. Do not send
  partial composition updates to a widget.

  ## Shortcuts

  Use `special_key/2` for named keys and modified printable keys. Common
  adapter names and modifier names are converted to the TermUI names:

      shortcuts = TermUI.Shortcut.new([{"ctrl+s", :save}])
      event = TermUI.Input.special_key("s", modifiers: [:control])
      {_shortcuts, [:save]} = TermUI.Shortcut.route(event, shortcuts)

      TermUI.Input.special_key("ArrowUp")
      #=> %TermUI.Event.Key{key: :up}

  An unmodified printable value is rejected by `special_key/2`. Use `text/2`
  for that value. There is no option that converts all printable text to key
  events.
  """

  alias TermUI.Event

  @type option :: {:timestamp, integer()} | {:modifiers, [atom()]}

  @named_keys Map.merge(
                %{
                  "arrowdown" => :down,
                  "arrowleft" => :left,
                  "arrowright" => :right,
                  "arrowup" => :up,
                  "backspace" => :backspace,
                  "delete" => :delete,
                  "down" => :down,
                  "end" => :end,
                  "enter" => :enter,
                  "esc" => :escape,
                  "escape" => :escape,
                  "home" => :home,
                  "insert" => :insert,
                  "left" => :left,
                  "pagedown" => :page_down,
                  "pageup" => :page_up,
                  "return" => :enter,
                  "right" => :right,
                  "tab" => :tab,
                  "up" => :up
                },
                Map.new(1..24, &{"f#{&1}", String.to_atom("f#{&1}")})
              )

  @modifier_names %{
    alt: :alt,
    command: :meta,
    control: :ctrl,
    ctrl: :ctrl,
    meta: :meta,
    option: :alt,
    shift: :shift,
    super: :super
  }

  @doc "Creates one text event and keeps all Unicode code points together."
  @spec text(String.t(), [option()]) :: Event.Text.t()
  def text(value, opts \\ []) do
    validate_text!(value, false)
    Event.text(value, timestamp_opts(opts))
  end

  @doc "Creates one text event for text that an input method has committed."
  @spec composition(String.t(), [option()]) :: Event.Text.t()
  def composition(value, opts \\ []) do
    validate_text!(value, false)
    Event.text(value, timestamp_opts(opts))
  end

  @doc "Creates one paste event without splitting or changing its content."
  @spec paste(String.t(), [option()]) :: Event.Paste.t()
  def paste(content, opts \\ []) do
    validate_text!(content, true)
    Event.paste(content, timestamp_opts(opts))
  end

  @doc "Creates a named-key event or a modified one-grapheme key event."
  @spec special_key(atom() | String.t(), [option()]) :: Event.Key.t()
  def special_key(key, opts \\ []) do
    modifiers = opts |> Keyword.get(:modifiers, []) |> normalize_modifiers!()
    key = normalize_key!(key, modifiers)
    Event.key(key, Keyword.put(timestamp_opts(opts), :modifiers, modifiers))
  end

  defp normalize_key!(key, _modifiers) when is_atom(key), do: key

  defp normalize_key!(key, modifiers) when is_binary(key) do
    validate_text!(key, false)

    case Map.fetch(@named_keys, normalize_key_name(key)) do
      {:ok, named_key} ->
        named_key

      :error ->
        if modifiers != [] and one_grapheme?(key) do
          key
        else
          raise ArgumentError,
                "unmodified printable input must use TermUI.Input.text/2"
        end
    end
  end

  defp normalize_key!(key, _modifiers) do
    raise ArgumentError, "special key must be an atom or a string, got: #{inspect(key)}"
  end

  defp normalize_key_name(key) do
    key
    |> String.downcase()
    |> String.replace(~r/[\s_-]/u, "")
  end

  defp normalize_modifiers!(modifiers) when is_list(modifiers) do
    modifiers
    |> Enum.map(fn modifier ->
      case Map.fetch(@modifier_names, modifier) do
        {:ok, normalized} -> normalized
        :error -> raise ArgumentError, "unsupported input modifier: #{inspect(modifier)}"
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp normalize_modifiers!(modifiers) do
    raise ArgumentError, "input modifiers must be a list, got: #{inspect(modifiers)}"
  end

  defp validate_text!(value, allow_empty?) when is_binary(value) do
    cond do
      not String.valid?(value) ->
        raise ArgumentError, "input text must be valid UTF-8"

      value == "" and not allow_empty? ->
        raise ArgumentError, "input text must not be empty"

      true ->
        :ok
    end
  end

  defp validate_text!(value, _allow_empty?) do
    raise ArgumentError, "input text must be a string, got: #{inspect(value)}"
  end

  defp one_grapheme?(value) do
    case String.graphemes(value) do
      [_grapheme] -> true
      _other -> false
    end
  end

  defp timestamp_opts(opts) do
    case Keyword.fetch(opts, :timestamp) do
      {:ok, timestamp} when is_integer(timestamp) ->
        [timestamp: timestamp]

      {:ok, timestamp} ->
        raise ArgumentError, "input timestamp must be an integer: #{inspect(timestamp)}"

      :error ->
        []
    end
  end
end
