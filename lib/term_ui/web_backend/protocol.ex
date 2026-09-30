defmodule TermUI.WebBackend.Protocol do
  @moduledoc """
  Version 1 of the transport-neutral browser protocol.

  Messages contain string keys and JSON-compatible values. The host owns JSON
  encoding, authentication, allowed application modules, origin checks, and
  transport limits. TermUI does not start a web server.

  A frame contains complete changed rows. Row and cursor positions are
  one-based. Mouse coordinates use the existing zero-based event contract.
  Each cell is `[text, width, foreground, background, attributes]`. A wide
  character has width 2 and its following placeholder has width 0. Default
  colors are `null`, named colors are strings, palette colors are integers,
  and RGB colors are three-element arrays.

  Apply a changed-row frame only to its stated `base` sequence. Confirm the
  sequence after the browser applies it. A full frame has a null base and
  replaces all rows. Reconnect or a missing base requires a full frame.
  """

  alias TermUI.{Cell, Event, Frame, Input}

  @version 1
  @default_limits %{width: 300, height: 120, text_bytes: 4_096, paste_bytes: 65_536}
  @modifiers %{"alt" => :alt, "ctrl" => :ctrl, "meta" => :meta, "shift" => :shift}
  @mouse_actions %{
    "press" => :press,
    "release" => :release,
    "move" => :move,
    "drag" => :drag,
    "scroll_up" => :scroll_up,
    "scroll_down" => :scroll_down
  }
  @mouse_buttons %{"left" => :left, "middle" => :middle, "right" => :right, nil => nil}

  @type limits :: %{
          width: pos_integer(),
          height: pos_integer(),
          text_bytes: pos_integer(),
          paste_bytes: pos_integer()
        }

  @doc "Returns the browser protocol version."
  @spec version() :: 1
  def version, do: @version

  @doc "Returns the default input and terminal-size limits."
  @spec default_limits() :: %{width: 300, height: 120, text_bytes: 4_096, paste_bytes: 65_536}
  def default_limits, do: @default_limits

  @doc "Validates host-selected limits within the public Frame bounds."
  @spec limits(map()) :: {:ok, limits()} | {:error, :invalid_limits}
  def limits(overrides) when is_map(overrides) do
    values = Map.merge(@default_limits, overrides)

    if map_size(values) == map_size(@default_limits) and
         Enum.all?(values, fn {_key, value} -> is_integer(value) and value > 0 end) and
         values.width <= 1_000 and values.height <= 500 do
      {:ok, values}
    else
      {:error, :invalid_limits}
    end
  end

  def limits(_overrides), do: {:error, :invalid_limits}

  @doc "Validates dimensions in rows and columns."
  @spec size(term(), limits()) :: {:ok, TermUI.Backend.size()} | {:error, :invalid_size}
  def size({rows, columns} = size, limits)
      when is_integer(rows) and rows > 0 and is_integer(columns) and columns > 0 do
    if rows <= limits.height and columns <= limits.width,
      do: {:ok, size},
      else: {:error, :invalid_size}
  end

  def size(_size, _limits), do: {:error, :invalid_size}

  @doc "Encodes a complete frame or complete changed rows against a confirmed frame."
  @spec frame(Frame.t() | nil, Frame.t(), pos_integer(), pos_integer() | nil) :: map()
  def frame(previous, %Frame{} = current, sequence, base)
      when is_integer(sequence) and sequence > 0 do
    full? =
      is_nil(previous) or is_nil(base) or
        previous.width != current.width or previous.height != current.height

    rows =
      for row <- 1..current.height,
          full? or changed_row?(previous, current, row),
          do: [row, encode_row(current, row)]

    %{
      "v" => @version,
      "type" => "frame",
      "seq" => sequence,
      "base" => if(full?, do: nil, else: base),
      "full" => full?,
      "width" => current.width,
      "height" => current.height,
      "rows" => rows,
      "cursor" => if(current.cursor, do: Tuple.to_list(current.cursor), else: nil)
    }
  end

  @doc "Validates a browser input message and creates an existing TermUI event."
  @spec event(term(), TermUI.Backend.size(), limits()) ::
          {:ok, Event.t()} | {:error, :invalid_input | :unsupported_version}
  def event(%{"v" => @version} = payload, size, limits) do
    decode_event(payload, size, limits)
  rescue
    ArgumentError -> {:error, :invalid_input}
  end

  def event(%{"v" => _version}, _size, _limits), do: {:error, :unsupported_version}
  def event(_payload, _size, _limits), do: {:error, :invalid_input}

  defp decode_event(%{"type" => "text", "text" => text}, _size, limits) do
    with :ok <- text_limit(text, limits.text_bytes, false), do: {:ok, Input.text(text)}
  end

  defp decode_event(%{"type" => "paste", "text" => text}, _size, limits) do
    with :ok <- text_limit(text, limits.paste_bytes, true), do: {:ok, Input.paste(text)}
  end

  defp decode_event(%{"type" => "key", "key" => key} = payload, _size, limits) do
    with :ok <- text_limit(key, limits.text_bytes, false),
         {:ok, modifiers} <- modifiers(Map.get(payload, "modifiers", [])) do
      {:ok, Input.special_key(key, modifiers: modifiers)}
    end
  end

  defp decode_event(%{"type" => "resize", "width" => width, "height" => height}, _size, limits) do
    case size({height, width}, limits) do
      {:ok, _size} -> {:ok, Event.resize(width, height)}
      _invalid -> {:error, :invalid_input}
    end
  end

  defp decode_event(%{"type" => "focus", "focused" => focused}, _size, _limits)
       when is_boolean(focused),
       do: {:ok, Event.focus(if(focused, do: :gained, else: :lost))}

  defp decode_event(%{"type" => "mouse", "x" => x, "y" => y} = payload, {rows, columns}, _limits)
       when is_integer(x) and is_integer(y) and x >= 0 and y >= 0 and x < columns and y < rows do
    with {:ok, action} <- Map.fetch(@mouse_actions, payload["action"]),
         {:ok, button} <- Map.fetch(@mouse_buttons, payload["button"]),
         {:ok, modifiers} <- modifiers(Map.get(payload, "modifiers", [])) do
      {:ok, Event.mouse(action, button, x, y, modifiers: modifiers)}
    else
      _invalid -> {:error, :invalid_input}
    end
  end

  defp decode_event(_payload, _size, _limits), do: {:error, :invalid_input}

  defp text_limit(text, maximum, allow_empty?) when is_binary(text) do
    if String.valid?(text) and byte_size(text) <= maximum and (allow_empty? or text != ""),
      do: :ok,
      else: {:error, :invalid_input}
  end

  defp text_limit(_text, _maximum, _allow_empty?), do: {:error, :invalid_input}

  defp modifiers(values) when is_list(values) and length(values) <= 4 do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, result} ->
      case Map.fetch(@modifiers, value) do
        {:ok, modifier} -> {:cont, {:ok, [modifier | result]}}
        :error -> {:halt, {:error, :invalid_input}}
      end
    end)
  end

  defp modifiers(_values), do: {:error, :invalid_input}

  defp changed_row?(previous, current, row) do
    Enum.any?(1..current.width, fn column ->
      not Cell.equal?(Frame.cell(previous, row, column), Frame.cell(current, row, column))
    end)
  end

  defp encode_row(frame, row) do
    for column <- 1..frame.width do
      cell = Frame.cell(frame, row, column)
      attributes = cell.attrs |> Enum.map(&Atom.to_string/1) |> Enum.sort()
      [cell.char, cell.width, color(cell.fg), color(cell.bg), attributes]
    end
  end

  defp color(:default), do: nil
  defp color(name) when is_atom(name), do: Atom.to_string(name)
  defp color(index) when is_integer(index), do: index
  defp color({red, green, blue}), do: [red, green, blue]
end
