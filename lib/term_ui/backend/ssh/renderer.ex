defmodule TermUI.Backend.SSH.Renderer do
  @moduledoc false

  alias TermUI.{ANSI, Frame}
  alias TermUI.Backend.Renderer, as: CellRenderer

  @doc false
  @spec setup_sequence(keyword(), map()) :: binary()
  def setup_sequence(opts, capabilities) do
    mouse_mode = supported_mouse_mode(opts, capabilities)

    [
      if(Keyword.get(opts, :alternate_screen, true), do: ANSI.enter_alternate_screen(), else: []),
      if(Keyword.get(opts, :hide_cursor, true), do: ANSI.cursor_hide(), else: []),
      mouse_setup(mouse_mode),
      if(Keyword.get(opts, :bracketed_paste, true), do: ANSI.enable_bracketed_paste(), else: []),
      if(Keyword.get(opts, :focus_events, true), do: ANSI.enable_focus_events(), else: []),
      ANSI.clear_screen(),
      ANSI.cursor_position(1, 1)
    ]
    |> IO.iodata_to_binary()
  end

  @doc false
  @spec cleanup_sequence(keyword(), map()) :: binary()
  def cleanup_sequence(opts, capabilities) do
    mouse_mode = supported_mouse_mode(opts, capabilities)

    [
      mouse_cleanup(mouse_mode),
      if(Keyword.get(opts, :bracketed_paste, true), do: ANSI.disable_bracketed_paste(), else: []),
      if(Keyword.get(opts, :focus_events, true), do: ANSI.disable_focus_events(), else: []),
      ANSI.cursor_show(),
      ANSI.reset(),
      if(Keyword.get(opts, :alternate_screen, true), do: ANSI.leave_alternate_screen(), else: [])
    ]
    |> IO.iodata_to_binary()
  end

  @doc false
  @spec frame_sequence(Frame.t() | nil, Frame.t(), map()) :: binary()
  def frame_sequence(previous, %Frame{} = current, capabilities) do
    full? = is_nil(previous) or dimensions_changed?(previous, current)
    changes = if full?, do: Frame.cells(current), else: Frame.diff(previous, current)

    [
      ANSI.cursor_hide(),
      if(full?, do: [ANSI.reset(), ANSI.clear_screen(), ANSI.cursor_position(1, 1)], else: []),
      CellRenderer.render(changes, color_mode(capabilities), character_set(capabilities)),
      cursor_sequence(current.cursor)
    ]
    |> IO.iodata_to_binary()
  end

  defp supported_mouse_mode(opts, capabilities) do
    requested = Keyword.get(opts, :mouse_tracking, :none)
    if Map.get(capabilities, :mouse, true), do: requested, else: :none
  end

  defp mouse_setup(:none), do: []
  defp mouse_setup(:click), do: [ANSI.enable_mouse_tracking(:normal), ANSI.enable_sgr_mouse()]
  defp mouse_setup(:drag), do: [ANSI.enable_mouse_tracking(:button), ANSI.enable_sgr_mouse()]
  defp mouse_setup(:all), do: [ANSI.enable_mouse_tracking(:all), ANSI.enable_sgr_mouse()]

  defp mouse_cleanup(:none), do: []
  defp mouse_cleanup(_mode), do: "\e[?1006l\e[?1003l\e[?1002l\e[?1000l"

  defp cursor_sequence(nil), do: ANSI.cursor_hide()
  defp cursor_sequence({column, row}), do: [ANSI.cursor_position(row, column), ANSI.cursor_show()]

  defp dimensions_changed?(previous, current) do
    previous.width != current.width or previous.height != current.height
  end

  defp character_set(capabilities) do
    if Map.get(capabilities, :unicode, true), do: :unicode, else: :ascii
  end

  defp color_mode(capabilities) do
    capabilities
    |> Map.get(:colors, :true_color)
    |> normalize_color_mode()
  end

  defp normalize_color_mode(:true_color), do: :true_color
  defp normalize_color_mode(:color_256), do: :color_256
  defp normalize_color_mode(:color_16), do: :color_16
  defp normalize_color_mode(:monochrome), do: :monochrome
  defp normalize_color_mode(count) when is_integer(count) and count >= 16_777_216, do: :true_color
  defp normalize_color_mode(count) when is_integer(count) and count >= 256, do: :color_256
  defp normalize_color_mode(count) when is_integer(count) and count >= 16, do: :color_16
  defp normalize_color_mode(_other), do: :monochrome
end
