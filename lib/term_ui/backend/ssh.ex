defmodule TermUI.Backend.SSH do
  @moduledoc """
  SSH terminal backend for remote terminal sessions.

  The SSH backend renders to an Erlang SSH channel IO device, enabling TermUI
  applications to run over SSH connections via OTP's `:ssh` application.

  ## How It Works

  When an SSH client connects and requests a PTY, the `:ssh` application creates
  an IO device (the channel's group leader) that implements the Erlang IO protocol.
  This backend writes ANSI escape sequences to that device and reads input from it.

  SSH channels are already in raw mode from the client side — no `stty` or
  `:shell.start_interactive` is needed.

  ## Usage

  Start a TermUI Runtime with an explicit SSH backend:

      device = Process.group_leader()  # SSH channel's IO device
      {rows, cols} = get_pty_size(device)

      {:ok, runtime} = TermUI.Runtime.start_link(
        root: MyApp.Root,
        backend: {TermUI.Backend.SSH, device: device, size: {rows, cols}}
      )

  ## Input Handling

  SSH input is delivered externally. The host process reads bytes from the SSH
  device, parses escape sequences, and sends events to the Runtime:

      send(runtime, {:ssh_input, %TermUI.Event.Key{key: :enter}})

  The `poll_event/2` callback returns `{:timeout, state}` since input is external.

  ## Resize Events

  Terminal size changes arrive as SSH `window_change` channel requests. Forward
  them to the Runtime:

      send(runtime, {:ssh_resize, new_rows, new_cols})

  ## Multiple Sessions

  Each SSH connection gets its own Backend.SSH instance with its own device.
  There is no global state — multiple concurrent sessions work independently.

  ## See Also

  - `TermUI.Backend` — Behaviour definition
  - `TermUI.Backend.Raw` — Local terminal backend (raw mode)
  - `TermUI.Backend.TTY` — Local terminal backend (cooked mode)
  """

  @behaviour TermUI.Backend

  alias TermUI.ANSI
  alias TermUI.Renderer.DisplayWidth

  # ANSI escape sequence constants
  @cursor_hide "\e[?25l"
  @cursor_show "\e[?25h"
  @clear_screen "\e[2J"
  @cursor_home "\e[H"
  @alt_screen_enter "\e[?1049h"
  @alt_screen_leave "\e[?1049l"
  @autowrap_off "\e[?7l"
  @autowrap_on "\e[?7h"
  @reset_attrs "\e[0m"

  # Mouse tracking sequences
  @mouse_sgr_on "\e[?1006h"
  @mouse_normal_on "\e[?1000h"
  @mouse_button_on "\e[?1002h"
  @mouse_any_on "\e[?1003h"
  @all_mouse_off "\e[?1006l\e[?1003l\e[?1002l\e[?1000l"

  @typedoc """
  Mouse tracking mode.

  - `:none` — No mouse tracking
  - `:click` — Button press/release only (mode 1000)
  - `:drag` — Press/release + motion while pressed (mode 1002)
  - `:all` — All mouse movement (mode 1003)
  """
  @type mouse_mode :: :none | :click | :drag | :all

  @typedoc """
  Current SGR style state for delta optimization.
  """
  @type style_state :: %{
          fg: TermUI.Backend.color(),
          bg: TermUI.Backend.color(),
          attrs: [atom()]
        }

  @typedoc """
  Internal state for the SSH backend.

  ## Fields

  - `:device` — SSH channel IO device PID
  - `:size` — Terminal dimensions as `{rows, cols}`
  - `:cursor_visible` — Whether cursor is currently visible
  - `:cursor_position` — Current cursor position as `{row, col}` or `nil`
  - `:alternate_screen` — Whether alternate screen buffer is active
  - `:mouse_mode` — Current mouse tracking mode
  - `:current_style` — Current SGR state for style delta tracking
  """
  @type t :: %__MODULE__{
          device: IO.device(),
          size: {pos_integer(), pos_integer()},
          cursor_visible: boolean(),
          cursor_position: {pos_integer(), pos_integer()} | nil,
          alternate_screen: boolean(),
          mouse_mode: mouse_mode(),
          current_style: style_state() | nil
        }

  defstruct device: nil,
            size: {24, 80},
            cursor_visible: false,
            cursor_position: nil,
            alternate_screen: false,
            mouse_mode: :none,
            current_style: nil

  # ===========================================================================
  # Lifecycle Callbacks
  # ===========================================================================

  @impl true
  @doc """
  Initializes the SSH backend with the given device and terminal size.

  ## Options

  - `:device` (required) — SSH channel IO device (from `Process.group_leader()` in SSH shell)
  - `:size` — Terminal dimensions as `{rows, cols}` from PTY negotiation (default: `{24, 80}`)
  - `:alternate_screen` — Use alternate screen buffer (default: `true`)
  - `:hide_cursor` — Hide cursor during rendering (default: `true`)
  - `:mouse_tracking` — Mouse tracking mode (default: `:none`)
  """
  @spec init(keyword()) :: {:ok, t()}
  def init(opts) do
    device = Keyword.fetch!(opts, :device)
    size = Keyword.get(opts, :size, {24, 80})
    alternate_screen = Keyword.get(opts, :alternate_screen, true)
    hide_cursor = Keyword.get(opts, :hide_cursor, true)
    mouse_tracking = Keyword.get(opts, :mouse_tracking, :none)

    state = %__MODULE__{
      device: device,
      size: size,
      cursor_visible: not hide_cursor
    }

    # Enter alternate screen buffer
    state =
      if alternate_screen do
        device_write(device, @alt_screen_enter)
        %{state | alternate_screen: true}
      else
        state
      end

    # Hide cursor
    if hide_cursor do
      device_write(device, @cursor_hide)
    end

    # Prevent a write to the bottom-right cell from scrolling the screen.
    device_write(device, @autowrap_off)

    # Enable mouse tracking
    state = enable_mouse(state, mouse_tracking)

    # Clear screen
    device_write(device, @clear_screen <> @cursor_home)

    {:ok, state}
  end

  @impl true
  @doc """
  Shuts down the SSH backend and restores terminal state.

  Writes cleanup sequences to the SSH device. Silently handles errors
  since the SSH channel may already be closed on disconnect.
  """
  @spec shutdown(t()) :: :ok
  def shutdown(%__MODULE__{device: device} = state) do
    # Disable mouse tracking
    device_write(device, @all_mouse_off)

    # Reset attributes
    device_write(device, @reset_attrs)

    # Show cursor
    device_write(device, @cursor_show)

    # Restore the channel's terminal settings before returning control.
    device_write(device, @autowrap_on)

    # Leave alternate screen
    if state.alternate_screen do
      device_write(device, @alt_screen_leave)
    end

    :ok
  end

  # ===========================================================================
  # Query Callbacks
  # ===========================================================================

  @impl true
  @doc """
  Returns the cached terminal dimensions.

  SSH terminal size is provided at init from PTY negotiation and updated
  externally via `update_size/3` when window_change events arrive.
  """
  @spec size(t()) :: {:ok, {pos_integer(), pos_integer()}}
  def size(%__MODULE__{size: size}) do
    {:ok, size}
  end

  @doc """
  Updates the cached terminal size.

  Called when an SSH `window_change` event arrives with new dimensions.
  Returns the updated state.
  """
  @spec update_size(t(), pos_integer(), pos_integer()) :: {:ok, t()}
  def update_size(%__MODULE__{} = state, rows, cols)
      when is_integer(rows) and rows > 0 and is_integer(cols) and cols > 0 do
    {:ok, %{state | size: {rows, cols}}}
  end

  # ===========================================================================
  # Cursor Callbacks
  # ===========================================================================

  @impl true
  @spec move_cursor(t(), {pos_integer(), pos_integer()}) :: {:ok, t()}
  def move_cursor(%__MODULE__{device: device, size: {max_rows, max_cols}} = state, {row, col}) do
    clamped_row = max(1, min(row, max_rows))
    clamped_col = max(1, min(col, max_cols))
    device_write(device, "\e[#{clamped_row};#{clamped_col}H")
    {:ok, %{state | cursor_position: {clamped_row, clamped_col}}}
  end

  @impl true
  @spec hide_cursor(t()) :: {:ok, t()}
  def hide_cursor(%__MODULE__{cursor_visible: false} = state), do: {:ok, state}

  def hide_cursor(%__MODULE__{device: device} = state) do
    device_write(device, @cursor_hide)
    {:ok, %{state | cursor_visible: false}}
  end

  @impl true
  @spec show_cursor(t()) :: {:ok, t()}
  def show_cursor(%__MODULE__{cursor_visible: true} = state), do: {:ok, state}

  def show_cursor(%__MODULE__{device: device} = state) do
    device_write(device, @cursor_show)
    {:ok, %{state | cursor_visible: true}}
  end

  # ===========================================================================
  # Rendering Callbacks
  # ===========================================================================

  @impl true
  @spec clear(t()) :: {:ok, t()}
  def clear(%__MODULE__{device: device} = state) do
    device_write(device, [ANSI.reset(), @clear_screen, @cursor_home])
    {:ok, %{state | cursor_position: {1, 1}, current_style: nil}}
  end

  @impl true
  @doc """
  Draws cells to the SSH terminal at specified positions.

  Uses style delta optimization — only emits SGR escape sequences when
  the style changes from the previous cell. Cells should be sorted by
  position (row-major) for efficient cursor movement.
  """
  @spec draw_cells(t(), [{TermUI.Backend.position(), TermUI.Backend.cell()}]) :: {:ok, t()}
  def draw_cells(%__MODULE__{} = state, []), do: {:ok, state}

  def draw_cells(%__MODULE__{device: device} = state, cells) when is_list(cells) do
    # Sort cells by position for sequential rendering
    sorted = Enum.sort_by(cells, fn {{row, col}, _cell} -> {row, col} end)

    # Render with style delta tracking
    {iodata, new_style, last_pos} =
      Enum.reduce(sorted, {[], state.current_style, state.cursor_position}, fn
        {{row, col}, {char, fg, bg, attrs}}, {acc, prev_style, prev_pos} ->
          # Cursor movement — skip if already at the right position
          move_seq = cursor_move_sequence(prev_pos, {row, col})

          # Style delta — only emit changes
          {style_seq, new_style} = style_delta_sequence(prev_style, fg, bg, attrs)

          # Sanitize character
          safe_char = sanitize_char(char)

          new_acc = [acc, move_seq, style_seq, safe_char]
          {new_acc, new_style, {row, col + max(1, DisplayWidth.width(safe_char))}}
      end)

    # Flush all accumulated output in a single write
    device_write(device, iodata)

    {:ok, %{state | current_style: new_style, cursor_position: last_pos}}
  end

  @impl true
  @spec flush(t()) :: {:ok, t()}
  def flush(%__MODULE__{} = state) do
    # Output is written immediately in draw_cells — nothing to flush
    {:ok, state}
  end

  # ===========================================================================
  # Input Callback
  # ===========================================================================

  @impl true
  @doc """
  Returns timeout — SSH input is delivered externally.

  The host process reads from the SSH device and sends parsed events
  to the Runtime via `send(runtime, {:ssh_input, event})`.
  """
  @spec poll_event(t(), non_neg_integer()) :: {:timeout, t()}
  def poll_event(%__MODULE__{} = state, _timeout) do
    {:timeout, state}
  end

  # ===========================================================================
  # Private — Device IO
  # ===========================================================================

  @spec device_write(IO.device(), iodata()) :: :ok
  defp device_write(device, data) do
    IO.write(device, data)
  rescue
    _ -> :ok
  end

  # ===========================================================================
  # Private — Mouse Tracking
  # ===========================================================================

  @spec enable_mouse(t(), mouse_mode()) :: t()
  defp enable_mouse(state, :none), do: %{state | mouse_mode: :none}

  defp enable_mouse(%__MODULE__{device: device} = state, mode) do
    seq =
      case mode do
        :click -> @mouse_normal_on <> @mouse_sgr_on
        :drag -> @mouse_button_on <> @mouse_sgr_on
        :all -> @mouse_any_on <> @mouse_sgr_on
      end

    device_write(device, seq)
    %{state | mouse_mode: mode}
  end

  # ===========================================================================
  # Private — Cursor Movement
  # ===========================================================================

  # Generate minimal cursor movement sequence
  @spec cursor_move_sequence(
          {pos_integer(), pos_integer()} | nil,
          {pos_integer(), pos_integer()}
        ) :: iodata()
  defp cursor_move_sequence(nil, {row, col}) do
    "\e[#{row};#{col}H"
  end

  defp cursor_move_sequence({cur_row, cur_col}, {row, col}) do
    cond do
      cur_row == row and cur_col == col ->
        []

      cur_row == row ->
        # Same row, different column
        "\e[#{row};#{col}H"

      true ->
        # Different row
        "\e[#{row};#{col}H"
    end
  end

  # ===========================================================================
  # Private — Style Delta
  # ===========================================================================

  # Compute minimal SGR sequence for style change
  @spec style_delta_sequence(
          style_state() | nil,
          TermUI.Backend.color(),
          TermUI.Backend.color(),
          [atom()]
        ) ::
          {iodata(), style_state()}
  defp style_delta_sequence(nil, fg, bg, attrs) do
    # No previous style — emit full style
    new_style = %{fg: fg, bg: bg, attrs: attrs}
    seq = build_full_style(fg, bg, attrs)
    {seq, new_style}
  end

  defp style_delta_sequence(%{fg: fg, bg: bg, attrs: attrs} = prev, fg, bg, attrs) do
    # Same style — no sequence needed
    {[], prev}
  end

  defp style_delta_sequence(prev, fg, bg, attrs) do
    new_style = %{fg: fg, bg: bg, attrs: attrs}

    # Check if attributes changed (requires full reset)
    if prev.attrs != attrs do
      seq = build_full_style(fg, bg, attrs)
      {seq, new_style}
    else
      # Only colors changed — emit delta
      parts = []
      parts = if prev.fg != fg, do: [parts | fg_sequence(fg)], else: parts
      parts = if prev.bg != bg, do: [parts | bg_sequence(bg)], else: parts
      {parts, new_style}
    end
  end

  defp build_full_style(fg, bg, attrs) do
    parts = [@reset_attrs]
    parts = parts ++ attr_sequences(attrs)
    parts = parts ++ [fg_sequence(fg)]
    parts = parts ++ [bg_sequence(bg)]
    parts
  end

  @spec fg_sequence(TermUI.Backend.color()) :: iodata()
  defp fg_sequence(:default), do: "\e[39m"

  defp fg_sequence({r, g, b}) when is_integer(r) and is_integer(g) and is_integer(b) do
    "\e[38;2;#{r};#{g};#{b}m"
  end

  defp fg_sequence(index) when is_integer(index) and index in 0..255 do
    "\e[38;5;#{index}m"
  end

  defp fg_sequence(name) when is_atom(name) do
    ANSI.foreground(name)
  end

  @spec bg_sequence(TermUI.Backend.color()) :: iodata()
  defp bg_sequence(:default), do: "\e[49m"

  defp bg_sequence({r, g, b}) when is_integer(r) and is_integer(g) and is_integer(b) do
    "\e[48;2;#{r};#{g};#{b}m"
  end

  defp bg_sequence(index) when is_integer(index) and index in 0..255 do
    "\e[48;5;#{index}m"
  end

  defp bg_sequence(name) when is_atom(name) do
    ANSI.background(name)
  end

  @spec attr_sequences([atom()]) :: [iodata()]
  defp attr_sequences(attrs) do
    Enum.map(attrs, fn
      :bold -> "\e[1m"
      :dim -> "\e[2m"
      :italic -> "\e[3m"
      :underline -> "\e[4m"
      :blink -> "\e[5m"
      :reverse -> "\e[7m"
      :hidden -> "\e[8m"
      :strikethrough -> "\e[9m"
      _ -> []
    end)
  end

  # ===========================================================================
  # Private — Character Sanitization
  # ===========================================================================

  @spec sanitize_char(String.t()) :: String.t()
  defp sanitize_char(""), do: " "

  defp sanitize_char(char) when is_binary(char) do
    char
    |> String.graphemes()
    |> List.first()
    |> case do
      nil -> " "
      grapheme -> if Regex.match?(~r/[\x00-\x1F\x7F]/u, grapheme), do: " ", else: grapheme
    end
  end
end
