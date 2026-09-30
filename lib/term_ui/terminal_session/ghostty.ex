# Dynamic calls keep this optional SDK out of the core dependency graph.
# credo:disable-for-this-file Credo.Check.Refactor.Apply
defmodule TermUI.TerminalSession.Ghostty do
  @moduledoc false

  alias TermUI.Event

  @terminal Module.concat(["Ghostty", "Terminal"])
  @pty Module.concat(["Ghostty", "PTY"])
  @key_event Module.concat(["Ghostty", "KeyEvent"])
  @mouse_event Module.concat(["Ghostty", "MouseEvent"])
  @native_modules [
    Module.concat(["Ghostty", "Terminal", "Nif"]),
    Module.concat(["Ghostty", "PTY", "Nif"])
  ]

  @keys %{
    up: :arrow_up,
    down: :arrow_down,
    left: :arrow_left,
    right: :arrow_right,
    enter: :enter,
    tab: :tab,
    backtab: :tab,
    backspace: :backspace,
    delete: :delete,
    escape: :escape,
    home: :home,
    end: :end,
    page_up: :page_up,
    page_down: :page_down,
    insert: :insert,
    space: :space,
    f1: :f1,
    f2: :f2,
    f3: :f3,
    f4: :f4,
    f5: :f5,
    f6: :f6,
    f7: :f7,
    f8: :f8,
    f9: :f9,
    f10: :f10,
    f11: :f11,
    f12: :f12
  }
  @characters Map.new(Enum.map(?a..?z, fn char -> {<<char>>, List.to_atom([char])} end))
              |> Map.merge(%{
                "0" => :digit_0,
                "1" => :digit_1,
                "2" => :digit_2,
                "3" => :digit_3,
                "4" => :digit_4,
                "5" => :digit_5,
                "6" => :digit_6,
                "7" => :digit_7,
                "8" => :digit_8,
                "9" => :digit_9,
                " " => :space,
                "-" => :minus,
                "=" => :equal,
                "[" => :bracket_left,
                "]" => :bracket_right,
                ";" => :semicolon,
                "'" => :quote,
                "," => :comma,
                "." => :period,
                "/" => :slash,
                "`" => :backquote,
                "\\" => :backslash
              })

  @doc false
  def available do
    with :ok <- platform(:os.type(), to_string(:erlang.system_info(:system_architecture))) do
      Enum.reduce_while(
        [@terminal, @pty, @key_event, @mouse_event | @native_modules],
        :ok,
        &load_module/2
      )
    end
  end

  @doc false
  def platform({:unix, :linux}, architecture) do
    if String.starts_with?(architecture, ["x86_64", "aarch64", "arm64"]) and
         not String.contains?(architecture, "musl"),
       do: :ok,
       else: {:error, {:unsupported_platform, :linux, architecture}}
  end

  @doc false
  def platform({:unix, :darwin}, architecture) do
    if String.starts_with?(architecture, ["aarch64", "arm64"]),
      do: :ok,
      else: {:error, {:unsupported_platform, :darwin, architecture}}
  end

  @doc false
  def platform(os, architecture), do: {:error, {:unsupported_platform, os, architecture}}

  @doc false
  def start_terminal(opts), do: apply(@terminal, :start_link, [opts])
  @doc false
  def start_pty(opts), do: apply(@pty, :start_link, [opts])
  @doc false
  def write_terminal(terminal, data), do: apply(@terminal, :write, [terminal, data])
  @doc false
  def write_pty(pty, data), do: apply(@pty, :write, [pty, data])
  @doc false
  def snapshot(terminal), do: apply(@terminal, :render_state, [terminal])

  @doc false
  def resize_terminal(terminal, columns, rows),
    do: apply(@terminal, :resize, [terminal, columns, rows])

  @doc false
  def resize_pty(pty, columns, rows), do: apply(@pty, :resize, [pty, columns, rows])
  @doc false
  def scroll(terminal, delta), do: apply(@terminal, :scroll, [terminal, delta])

  @doc false
  def key(terminal, event) do
    with {:ok, fields} <- key_fields(event) do
      apply(@terminal, :input_key, [terminal, struct(@key_event, fields)])
    end
  end

  @doc false
  def key_fields(%Event.Text{text: text}), do: {:ok, [key: :unidentified, utf8: text]}

  @doc false
  def key_fields(%Event.Key{key: key, modifiers: modifiers}) do
    with {:ok, key_code, text} <- key_code(key),
         {:ok, modifiers} <- modifiers(modifiers) do
      modifiers = if key == :backtab, do: Enum.uniq([:shift | modifiers]), else: modifiers
      {:ok, [key: key_code, utf8: text, mods: modifiers]}
    end
  end

  @doc false
  def mouse(terminal, event) do
    with {:ok, fields} <- mouse_fields(event) do
      apply(@terminal, :input_mouse, [terminal, struct(@mouse_event, fields)])
    end
  end

  @doc false
  def mouse_fields(%Event.Mouse{x: x, y: y} = event)
      when x >= 0 and y >= 0 and x < 80 and y < 30 do
    with {:ok, modifiers} <- modifiers(event.modifiers),
         {:ok, action} <- mouse_action(event.action) do
      {:ok,
       [
         action: action,
         button: event.button,
         mods: modifiers,
         x: (x + 0.5) * 10.0,
         y: (y + 0.5) * 20.0
       ]}
    end
  end

  @doc false
  def mouse_fields(_event), do: {:error, :ghostty_mouse_geometry_limit}

  @doc false
  def focus(terminal, %Event.Focus{action: action}) do
    if apply(@terminal, :focus_reporting?, [terminal]),
      do: apply(@terminal, :encode_focus, [action == :gained]),
      else: :none
  end

  @doc false
  def paste(terminal, pty, content) do
    forward_replies(pty)
    :ok = write_terminal(terminal, "\e[?2004$p")

    receive do
      {:pty_write, "\e[?2004;1$y"} ->
        {:ok, ["\e[200~", String.replace(content, "\e", ""), "\e[201~"]}

      {:pty_write, "\e[?2004;2$y"} ->
        {:ok, content}
    after
      100 -> {:error, :paste_mode_query_timeout}
    end
  end

  defp forward_replies(pty) do
    receive do
      {:pty_write, bytes} ->
        :ok = write_pty(pty, bytes)
        forward_replies(pty)
    after
      0 -> :ok
    end
  end

  @doc false
  def stop(process) when is_pid(process) do
    GenServer.stop(process, :normal)
  catch
    :exit, _reason -> :ok
  end

  defp load_module(module, :ok) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> {:cont, :ok}
      {:error, reason} -> {:halt, {:error, {:ghostty_unavailable, module, reason}}}
    end
  end

  defp key_code(key) when is_atom(key) do
    case Map.fetch(@keys, key) do
      {:ok, code} -> {:ok, code, nil}
      :error -> key_code(Atom.to_string(key))
    end
  end

  defp key_code(key) when is_binary(key) do
    case String.graphemes(key) do
      [_grapheme] -> {:ok, Map.get(@characters, String.downcase(key), :unidentified), key}
      _other -> {:error, :unsupported_key}
    end
  end

  defp key_code(_key), do: {:error, :unsupported_key}

  defp modifiers(values) do
    Enum.reduce_while(values, {:ok, []}, fn
      :meta, {:ok, result} -> {:cont, {:ok, [:super | result]}}
      value, {:ok, result} when value in [:shift, :ctrl, :alt] -> {:cont, {:ok, [value | result]}}
      _unknown, _result -> {:halt, {:error, :unsupported_modifier}}
    end)
  end

  defp mouse_action(:press), do: {:ok, :press}
  defp mouse_action(:release), do: {:ok, :release}
  defp mouse_action(action) when action in [:move, :drag], do: {:ok, :motion}
  defp mouse_action(_action), do: {:error, :unsupported_mouse_action}
end
