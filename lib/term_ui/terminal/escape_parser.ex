defmodule TermUI.Terminal.EscapeParser do
  @moduledoc false

  import Bitwise

  alias TermUI.{Event, Input}

  @escape 0x1B
  @delete 0x7F

  # Maximum coordinate value for mouse events.
  # Provides defense against malicious input with huge coordinates.
  @max_mouse_coordinate 9999

  # Maximum bytes to buffer for an unterminated bracketed-paste sequence.
  # Generous enough that real pastes never trip it; prevents unbounded memory
  # growth from a stuck terminal that emits ESC[200~ but never the end marker.
  @max_paste_buffer 8 * 1024 * 1024

  @doc """
  Parses input bytes into a list of events and remaining bytes.

  Returns `{events, remaining}` where events is a list of Event.Key structs
  and remaining is bytes that couldn't be parsed yet (partial sequences).
  """
  @spec parse(binary()) :: {[Event.t()], binary()}
  def parse(<<>>), do: {[], <<>>}

  def parse(input) when is_binary(input) do
    parse_bytes(input, [])
  end

  defp parse_bytes(<<>>, events), do: {Enum.reverse(events), <<>>}

  # Escape sequence start
  defp parse_bytes(<<@escape, rest::binary>>, events) do
    case parse_escape_sequence(rest) do
      {:ok, event, remaining} ->
        parse_bytes(remaining, [event | events])

      :incomplete ->
        # Return ESC + rest as remaining for buffering
        {Enum.reverse(events), <<@escape, rest::binary>>}
    end
  end

  # Backspace / Ctrl+H
  defp parse_bytes(<<8, rest::binary>>, events) do
    event = Input.special_key(:backspace)
    parse_bytes(rest, [event | events])
  end

  # Tab / Ctrl+I
  defp parse_bytes(<<9, rest::binary>>, events) do
    event = Input.special_key(:tab)
    parse_bytes(rest, [event | events])
  end

  # Enter / Ctrl+J or Ctrl+M
  defp parse_bytes(<<char, rest::binary>>, events) when char in [10, 13] do
    event = Input.special_key(:enter)
    parse_bytes(rest, [event | events])
  end

  # Control characters (Ctrl+A through Ctrl+Z, except backspace/tab/enter)
  defp parse_bytes(<<char, rest::binary>>, events) when char in 1..26 do
    # Convert to lowercase letter
    key = <<char + 96>>
    event = Input.special_key(key, modifiers: [:ctrl])
    parse_bytes(rest, [event | events])
  end

  # Delete key
  defp parse_bytes(<<@delete, rest::binary>>, events) do
    event = Input.special_key(:backspace)
    parse_bytes(rest, [event | events])
  end

  # Regular printable ASCII
  defp parse_bytes(<<char, rest::binary>>, events) when char in 32..126 do
    char_str = <<char>>
    event = Input.text(char_str)
    parse_bytes(rest, [event | events])
  end

  # UTF-8 multi-byte sequences
  defp parse_bytes(<<lead, _rest::binary>> = input, events) when lead in 0xC2..0xDF,
    do: parse_utf8(input, 2, events)

  defp parse_bytes(<<lead, _rest::binary>> = input, events) when lead in 0xE0..0xEF,
    do: parse_utf8(input, 3, events)

  defp parse_bytes(<<lead, _rest::binary>> = input, events) when lead in 0xF0..0xF4,
    do: parse_utf8(input, 4, events)

  # Unknown byte - skip it
  defp parse_bytes(<<_char, rest::binary>>, events) do
    parse_bytes(rest, events)
  end

  defp parse_utf8(input, expected_bytes, events) when byte_size(input) < expected_bytes,
    do: {Enum.reverse(events), input}

  defp parse_utf8(input, expected_bytes, events) do
    character = binary_part(input, 0, expected_bytes)
    rest = binary_part(input, expected_bytes, byte_size(input) - expected_bytes)

    if String.valid?(character) do
      parse_bytes(rest, [Input.text(character) | events])
    else
      <<_invalid_lead, rest::binary>> = input
      parse_bytes(rest, events)
    end
  end

  # Parse escape sequences
  # Match normal input handling: discard malformed bytes and keep valid text.
  # Do this only after paste collection so a UTF-8 character may span reads.
  defp valid_paste_text(bytes) do
    bytes |> valid_paste_chunks([]) |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp valid_paste_chunks(bytes, chunks) do
    case :unicode.characters_to_binary(bytes) do
      text when is_binary(text) ->
        [text | chunks]

      {:incomplete, text, _remaining} ->
        [text | chunks]

      {:error, text, <<_invalid, rest::binary>>} ->
        chunks = if text == "", do: chunks, else: [text | chunks]
        valid_paste_chunks(rest, chunks)
    end
  end

  defp parse_escape_sequence(<<>>) do
    :incomplete
  end

  # CSI sequences (ESC [)
  defp parse_escape_sequence(<<"[", rest::binary>>) do
    parse_csi_sequence(rest)
  end

  # SS3 sequences (ESC O) - typically function keys
  defp parse_escape_sequence(<<"O", rest::binary>>) do
    parse_ss3_sequence(rest)
  end

  # Option+Delete / Alt+Backspace uses ESC DEL or ESC BS.
  defp parse_escape_sequence(<<char, rest::binary>>) when char in [8, @delete] do
    {:ok, Input.special_key(:backspace, modifiers: [:alt]), rest}
  end

  # Alt+key (ESC followed by printable character)
  defp parse_escape_sequence(<<char, rest::binary>>) when char in 32..126 do
    char_str = <<char>>
    event = Input.special_key(char_str, modifiers: [:alt])
    {:ok, event, rest}
  end

  # Just ESC key (no following sequence) - but need to wait for timeout
  defp parse_escape_sequence(_rest) do
    :incomplete
  end

  # CSI sequence parsing
  defp parse_csi_sequence(<<>>) do
    :incomplete
  end

  # Arrow keys
  defp parse_csi_sequence(<<"A", rest::binary>>), do: {:ok, Input.special_key(:up), rest}
  defp parse_csi_sequence(<<"B", rest::binary>>), do: {:ok, Input.special_key(:down), rest}
  defp parse_csi_sequence(<<"C", rest::binary>>), do: {:ok, Input.special_key(:right), rest}
  defp parse_csi_sequence(<<"D", rest::binary>>), do: {:ok, Input.special_key(:left), rest}

  defp parse_csi_sequence(<<"Z", rest::binary>>),
    do: {:ok, Input.special_key(:tab, modifiers: [:shift]), rest}

  # Home/End
  defp parse_csi_sequence(<<"H", rest::binary>>), do: {:ok, Input.special_key(:home), rest}
  defp parse_csi_sequence(<<"F", rest::binary>>), do: {:ok, Input.special_key(:end), rest}

  # Terminal focus tracking
  defp parse_csi_sequence(<<"I", rest::binary>>), do: {:ok, Event.focus(:gained), rest}
  defp parse_csi_sequence(<<"O", rest::binary>>), do: {:ok, Event.focus(:lost), rest}

  # X10 mouse events: ESC [ M Cb Cx Cy. Each value has an offset of 32.
  defp parse_csi_sequence(<<"M", rest::binary>>) when byte_size(rest) < 3,
    do: :incomplete

  defp parse_csi_sequence(<<"M", cb, cx, cy, rest::binary>>)
       when cb >= 32 and cx >= 33 and cy >= 33 do
    event = decode_mouse_event(cb - 32, cx - 32, cy - 32, :x10)
    {:ok, event, rest}
  end

  # Tilde sequences: ESC [ number ~
  defp parse_csi_sequence(<<"1~", rest::binary>>), do: {:ok, Input.special_key(:home), rest}
  defp parse_csi_sequence(<<"2~", rest::binary>>), do: {:ok, Input.special_key(:insert), rest}
  defp parse_csi_sequence(<<"3~", rest::binary>>), do: {:ok, Input.special_key(:delete), rest}
  defp parse_csi_sequence(<<"4~", rest::binary>>), do: {:ok, Input.special_key(:end), rest}
  defp parse_csi_sequence(<<"5~", rest::binary>>), do: {:ok, Input.special_key(:page_up), rest}
  defp parse_csi_sequence(<<"6~", rest::binary>>), do: {:ok, Input.special_key(:page_down), rest}

  # Bracketed paste: ESC [ 200 ~ content ESC [ 201 ~
  # Scan forward for the end marker and emit the parked content as a single
  # Paste event. Without the end marker, return :incomplete so InputReader
  # keeps buffering — up to @max_paste_buffer, after which we bail out and
  # emit whatever we have so the buffer cannot grow without bound. An
  # eventually arriving \e[201~ is then swallowed by the stray-end clause.
  defp parse_csi_sequence(<<"200~", rest::binary>>) do
    case :binary.match(rest, <<@escape, "[201~">>) do
      {pos, _len} ->
        content = binary_part(rest, 0, pos)
        tail = binary_part(rest, pos + 6, byte_size(rest) - pos - 6)
        {:ok, Input.paste(valid_paste_text(content)), tail}

      :nomatch when byte_size(rest) > @max_paste_buffer ->
        {:ok, Input.paste(valid_paste_text(rest)), <<>>}

      :nomatch ->
        :incomplete
    end
  end

  # Stray paste-end marker (defensive): consume silently.
  defp parse_csi_sequence(<<"201~", rest::binary>>),
    do: {:ok, Input.special_key(:unknown), rest}

  # Function keys F1-F4 (some terminals)
  defp parse_csi_sequence(<<"11~", rest::binary>>), do: {:ok, Input.special_key(:f1), rest}
  defp parse_csi_sequence(<<"12~", rest::binary>>), do: {:ok, Input.special_key(:f2), rest}
  defp parse_csi_sequence(<<"13~", rest::binary>>), do: {:ok, Input.special_key(:f3), rest}
  defp parse_csi_sequence(<<"14~", rest::binary>>), do: {:ok, Input.special_key(:f4), rest}

  # Function keys F5-F12
  defp parse_csi_sequence(<<"15~", rest::binary>>), do: {:ok, Input.special_key(:f5), rest}
  defp parse_csi_sequence(<<"17~", rest::binary>>), do: {:ok, Input.special_key(:f6), rest}
  defp parse_csi_sequence(<<"18~", rest::binary>>), do: {:ok, Input.special_key(:f7), rest}
  defp parse_csi_sequence(<<"19~", rest::binary>>), do: {:ok, Input.special_key(:f8), rest}
  defp parse_csi_sequence(<<"20~", rest::binary>>), do: {:ok, Input.special_key(:f9), rest}
  defp parse_csi_sequence(<<"21~", rest::binary>>), do: {:ok, Input.special_key(:f10), rest}
  defp parse_csi_sequence(<<"23~", rest::binary>>), do: {:ok, Input.special_key(:f11), rest}
  defp parse_csi_sequence(<<"24~", rest::binary>>), do: {:ok, Input.special_key(:f12), rest}

  # Modified arrow keys with modifiers: ESC [ 1 ; modifier A/B/C/D
  defp parse_csi_sequence(<<"1;", modifier, dir, rest::binary>>)
       when modifier in ?0..?9 and dir in [?A, ?B, ?C, ?D] do
    key =
      case dir do
        ?A -> :up
        ?B -> :down
        ?C -> :right
        ?D -> :left
      end

    modifiers = decode_modifier(modifier - ?0)
    event = Input.special_key(key, modifiers: modifiers)
    {:ok, event, rest}
  end

  # Modified Shift+Tab sequence: ESC [ 1 ; modifier Z
  defp parse_csi_sequence(<<"1;", modifier, "Z", rest::binary>>) when modifier in ?0..?9 do
    modifiers = decode_modifier(modifier - ?0)
    event = Input.special_key(:tab, modifiers: modifiers)
    {:ok, event, rest}
  end

  # SGR mouse events: ESC [ < Cb ; Cx ; Cy M/m
  defp parse_csi_sequence(<<"<", rest::binary>>) do
    parse_sgr_mouse(rest)
  end

  # Consume an unsupported CSI sequence through its final byte. Returning the
  # original input here would parse its parameters as ordinary text.
  defp parse_csi_sequence(input) do
    case consume_unknown_csi(input) do
      {:ok, rest} -> {:ok, Input.special_key(:unknown), rest}
      :incomplete -> :incomplete
    end
  end

  defp consume_unknown_csi(<<>>), do: :incomplete

  defp consume_unknown_csi(<<final, rest::binary>>) when final in 0x40..0x7E,
    do: {:ok, rest}

  defp consume_unknown_csi(<<byte, rest::binary>>) when byte in 0x20..0x3F,
    do: consume_unknown_csi(rest)

  defp consume_unknown_csi(<<_invalid, rest::binary>>), do: {:ok, rest}

  # SS3 sequence parsing (ESC O)
  defp parse_ss3_sequence(<<>>) do
    :incomplete
  end

  # Function keys F1-F4
  defp parse_ss3_sequence(<<"P", rest::binary>>), do: {:ok, Input.special_key(:f1), rest}
  defp parse_ss3_sequence(<<"Q", rest::binary>>), do: {:ok, Input.special_key(:f2), rest}
  defp parse_ss3_sequence(<<"R", rest::binary>>), do: {:ok, Input.special_key(:f3), rest}
  defp parse_ss3_sequence(<<"S", rest::binary>>), do: {:ok, Input.special_key(:f4), rest}

  # Keypad arrows (application mode)
  defp parse_ss3_sequence(<<"A", rest::binary>>), do: {:ok, Input.special_key(:up), rest}
  defp parse_ss3_sequence(<<"B", rest::binary>>), do: {:ok, Input.special_key(:down), rest}
  defp parse_ss3_sequence(<<"C", rest::binary>>), do: {:ok, Input.special_key(:right), rest}
  defp parse_ss3_sequence(<<"D", rest::binary>>), do: {:ok, Input.special_key(:left), rest}

  # Home/End (keypad)
  defp parse_ss3_sequence(<<"H", rest::binary>>), do: {:ok, Input.special_key(:home), rest}
  defp parse_ss3_sequence(<<"F", rest::binary>>), do: {:ok, Input.special_key(:end), rest}

  defp parse_ss3_sequence(_input) do
    :incomplete
  end

  # SGR mouse sequence parsing: Cb;Cx;CyM or Cb;Cx;Cym
  defp parse_sgr_mouse(input) do
    # Find the terminator (M for press, m for release)
    case find_mouse_terminator(input) do
      {:ok, params, terminator, rest} ->
        case parse_mouse_params(params) do
          {:ok, cb, cx, cy} ->
            event = decode_mouse_event(cb, cx, cy, terminator)
            {:ok, event, rest}

          :error ->
            {:ok, Input.special_key(:unknown), rest}
        end

      :incomplete ->
        :incomplete
    end
  end

  defp find_mouse_terminator(input) do
    find_mouse_terminator(input, <<>>)
  end

  defp find_mouse_terminator(<<>>, _acc), do: :incomplete

  defp find_mouse_terminator(<<"M", rest::binary>>, acc) do
    {:ok, acc, :press, rest}
  end

  defp find_mouse_terminator(<<"m", rest::binary>>, acc) do
    {:ok, acc, :release, rest}
  end

  defp find_mouse_terminator(<<char, rest::binary>>, acc)
       when char in ?0..?9 or char == ?; do
    find_mouse_terminator(rest, <<acc::binary, char>>)
  end

  defp find_mouse_terminator(_input, _acc), do: :incomplete

  defp parse_mouse_params(params) do
    case String.split(params, ";") do
      [cb_str, cx_str, cy_str] ->
        with {cb, ""} <- Integer.parse(cb_str),
             {cx, ""} <- Integer.parse(cx_str),
             {cy, ""} <- Integer.parse(cy_str),
             true <- cb >= 0 and cb <= 255,
             true <- cx >= 1 and cx <= @max_mouse_coordinate,
             true <- cy >= 1 and cy <= @max_mouse_coordinate do
          {:ok, cb, cx, cy}
        else
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp decode_mouse_event(cb, cx, cy, terminator) do
    button_code = cb &&& 0b11
    {action, button} = determine_mouse_action(cb, button_code, terminator)
    modifiers = extract_mouse_modifiers(cb)

    x = cx - 1
    y = cy - 1

    Event.mouse(action, button, x, y, modifiers: modifiers)
  end

  defp determine_mouse_action(cb, button_code, terminator) do
    cond do
      (cb &&& 64) != 0 -> scroll_action(button_code)
      (cb &&& 32) != 0 -> motion_action(button_code)
      true -> button_action(button_code, terminator)
    end
  end

  defp scroll_action(0), do: {:scroll_up, nil}
  defp scroll_action(1), do: {:scroll_down, nil}
  defp scroll_action(button_code), do: {:press, decode_button(button_code)}

  defp motion_action(3), do: {:move, nil}
  defp motion_action(button_code), do: {:drag, decode_button(button_code)}

  defp button_action(button_code, :release), do: {:release, decode_button(button_code)}
  defp button_action(3, :x10), do: {:release, nil}
  defp button_action(button_code, _terminator), do: {:press, decode_button(button_code)}

  defp extract_mouse_modifiers(cb) do
    []
    |> maybe_add_modifier(cb, 4, :shift)
    |> maybe_add_modifier(cb, 8, :alt)
    |> maybe_add_modifier(cb, 16, :ctrl)
  end

  defp maybe_add_modifier(modifiers, cb, bit, modifier) do
    if (cb &&& bit) != 0, do: [modifier | modifiers], else: modifiers
  end

  defp decode_button(0), do: :left
  defp decode_button(1), do: :middle
  defp decode_button(2), do: :right
  defp decode_button(_), do: nil

  defp partial_csi?(input), do: consume_unknown_csi(input) == :incomplete

  # Decode modifier byte (2=shift, 3=alt, 4=shift+alt, 5=ctrl, etc.)
  # Returns a list of modifiers like [:shift, :alt, :ctrl]
  defp decode_modifier(n) do
    # Modifier is 1-based
    n = n - 1
    modifiers = []
    modifiers = if (n &&& 1) != 0, do: [:shift | modifiers], else: modifiers
    modifiers = if (n &&& 2) != 0, do: [:alt | modifiers], else: modifiers
    modifiers = if (n &&& 4) != 0, do: [:ctrl | modifiers], else: modifiers
    modifiers
  end

  @doc """
  Checks if the given bytes might be a partial escape sequence.

  Used to determine if we should wait for more input or emit a lone ESC.
  """
  @spec partial_sequence?(binary()) :: boolean()
  def partial_sequence?(<<@escape>>), do: true
  def partial_sequence?(<<@escape, "[">>), do: true
  def partial_sequence?(<<@escape, "[M", rest::binary>>) when byte_size(rest) < 3, do: true
  def partial_sequence?(<<@escape, "[200~", _rest::binary>>), do: true
  def partial_sequence?(<<@escape, "[", rest::binary>>), do: partial_csi?(rest)
  def partial_sequence?(<<@escape, "O">>), do: true
  def partial_sequence?(_), do: false
end
