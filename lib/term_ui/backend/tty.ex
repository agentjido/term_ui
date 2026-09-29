defmodule TermUI.Backend.TTY do
  @moduledoc """
  TTY terminal backend for constrained environments.

  The TTY backend provides terminal rendering when raw mode is unavailable. This
  includes Nerves devices, shell-based SSH sessions, remote IEx consoles, and other scenarios
  where `:shell.start_interactive({:noshell, :raw})` returns `{:error, :already_started}`.

  ## When This Backend is Selected

  The `TermUI.Backend.Selector` chooses this backend when:
  1. Raw mode activation fails with `:already_started` (a shell is already running)
  2. The environment is detected as constrained (Nerves, remote IEx)
  3. Explicit TTY mode is requested via configuration

  ## Key Difference from Raw Backend

  **This backend remains event-capable, but delivery is terminal-dependent.**
  Without raw mode, it can:
  - Request characters and escape sequences using `IO.getn/2`; the shell or
    terminal driver may still buffer them until Enter
  - Process arrow keys, Tab, function keys, and control sequences
  - Position the cursor and render styled text

  The main differences from raw mode are:
  - **No terminal mode control** - Cannot switch terminal modes (shell already running)
  - **Potential interference** - The existing shell's line editing may occasionally interfere
  - **Capability uncertainty** - Must detect and adapt to available features
  - **Limited mouse support** - Mouse events may not be available or reliable

  ## Rendering Modes

  This backend supports two rendering modes via the `:line_mode` option:

  - **`:full_redraw`** (default) - Clears the screen and redraws everything on each
    frame. This is reliable but may cause visible flicker on slow connections.

  - **`:incremental`** - Only updates cells that changed since the last frame.
    This is faster and reduces flicker but may have artifacts if the terminal
    state becomes out of sync.

  ## Color Degradation

  The TTY backend automatically degrades colors based on detected capabilities:

  | Mode | Description | Escape Format |
  |------|-------------|---------------|
  | `:true_color` | Full 24-bit RGB | `ESC[38;2;r;g;bm` |
  | `:color_256` | 256-color palette | `ESC[38;5;nm` |
  | `:color_16` | Basic 16 colors | `ESC[31m` etc. |
  | `:monochrome` | No colors | Attributes only |

  ## Character Set Handling

  When Unicode is unavailable, box-drawing characters are automatically mapped
  to ASCII equivalents. The `:character_set` field tracks the current mode:

  - `:unicode` - Full Unicode box-drawing characters
  - `:ascii` - ASCII fallback (`+`, `-`, `|` for corners and lines)

  ## Configuration Options

  The `init/1` callback accepts these options:

  - `:capabilities` - Map of detected terminal capabilities (from Selector)
  - `:line_mode` - Rendering strategy (`:full_redraw` or `:incremental`)
  - `:alternate_screen` - Whether to use alternate screen buffer (default: `false`)

  ## Example

  This backend is typically used via the runtime, not directly:

      # Automatic backend selection (recommended)
      {:ok, runtime} = TermUI.Runtime.start_link(root: MyApp.Root)

      # The runtime handles backend selection based on environment

  ## See Also

  - `TermUI.Backend` - Behaviour definition
  - `TermUI.Backend.Selector` - Backend selection logic
  - `TermUI.Backend.Raw` - Full-featured backend for raw mode
  - `TermUI.CharacterSet` - Unicode/ASCII character mapping
  """

  @behaviour TermUI.Backend

  alias TermUI.Backend.InputBuffer
  alias TermUI.Color.Converter
  alias TermUI.Terminal.EscapeParser

  # Dialyzer: Functions return specific struct types
  @dialyzer {:nowarn_function, init: 1, map_character: 2, sanitize_char: 1}

  # ===========================================================================
  # ANSI Escape Sequence Constants
  # ===========================================================================

  # Cursor control sequences
  @cursor_hide "\e[?25l"
  @cursor_show "\e[?25h"

  # Screen control sequences
  @clear_screen "\e[2J"
  @cursor_home "\e[H"
  @alt_screen_enter "\e[?1049h"
  @alt_screen_leave "\e[?1049l"

  # Attribute control sequences
  @reset_attrs "\e[0m"

  # Input buffer management is handled by TermUI.Backend.InputBuffer module
  # which provides rate-limited logging and consistent behavior across backends.

  # ===========================================================================
  # Type Definitions and State Structure
  # ===========================================================================

  @typedoc """
  Color rendering mode based on terminal capabilities.

  Determines how colors are encoded in escape sequences:

  - `:true_color` - Full 24-bit RGB colors (`ESC[38;2;r;g;bm`)
  - `:color_256` - 256-color palette (`ESC[38;5;nm`)
  - `:color_16` - Basic 16 ANSI colors (`ESC[31m` etc.)
  - `:monochrome` - No color support, attributes only
  """
  @type color_mode :: :true_color | :color_256 | :color_16 | :monochrome

  @typedoc """
  Rendering strategy for frame updates.

  - `:full_redraw` - Clear and redraw entire screen each frame (reliable)
  - `:incremental` - Only update changed cells (faster but may have artifacts)
  """
  @type line_mode :: :full_redraw | :incremental

  @typedoc """
  Character set for box-drawing and special characters.

  - `:unicode` - Full Unicode box-drawing characters
  - `:ascii` - ASCII fallback characters
  """
  @type character_set :: :unicode | :ascii

  @typedoc """
  Internal state for the TTY backend.

  Tracks terminal configuration and rendering state.

  ## Fields

  - `:size` - Terminal dimensions as `{rows, cols}`
  - `:capabilities` - Map of detected terminal capabilities from Selector
  - `:line_mode` - Rendering strategy (`:full_redraw` or `:incremental`)
  - `:last_frame` - Previous frame for incremental rendering comparison
  - `:character_set` - Unicode or ASCII character set
  - `:color_mode` - Color capability level
  - `:alternate_screen` - Whether alternate screen buffer is active
  - `:cursor_visible` - Whether cursor is currently visible
  - `:cursor_position` - Current cursor position as `{row, col}` or `nil`
  - `:input_buffer` - Buffer for partial escape sequences between poll_event calls
  """
  @type t :: %__MODULE__{
          size: {pos_integer(), pos_integer()},
          capabilities: map(),
          line_mode: line_mode(),
          last_frame: map() | nil,
          character_set: character_set(),
          color_mode: color_mode(),
          alternate_screen: boolean(),
          cursor_visible: boolean(),
          cursor_position: {pos_integer(), pos_integer()} | nil,
          input_buffer: binary()
        }

  defstruct size: {24, 80},
            capabilities: %{},
            line_mode: :full_redraw,
            last_frame: nil,
            character_set: :unicode,
            color_mode: :true_color,
            alternate_screen: false,
            cursor_visible: true,
            cursor_position: nil,
            input_buffer: <<>>

  # ===========================================================================
  # Lifecycle Callbacks
  # ===========================================================================

  @impl true
  @doc """
  Initializes the TTY backend with detected capabilities.

  Accepts options from the Selector including terminal capabilities.

  ## Options

  - `:capabilities` - Map of detected terminal capabilities
  - `:line_mode` - Rendering strategy (default: `:full_redraw`)
  - `:alternate_screen` - Use alternate screen buffer (default: `false`)
  - `:size` - Explicit terminal dimensions (default: from capabilities or `{24, 80}`)

  ## Returns

  - `{:ok, state}` - Successfully initialized
  - `{:error, reason}` - Initialization failed
  """
  @spec init(keyword()) :: {:ok, t()}
  def init(opts \\ []) do
    capabilities = Keyword.get(opts, :capabilities, %{})
    line_mode = Keyword.get(opts, :line_mode, :full_redraw)
    alternate_screen = Keyword.get(opts, :alternate_screen, false)

    # Determine color mode from capabilities
    color_mode = determine_color_mode(capabilities)

    # Determine character set from capabilities
    character_set = determine_character_set(capabilities)

    # Get terminal size from capabilities or option or default
    size = determine_size(opts, capabilities)

    state = %__MODULE__{
      size: size,
      capabilities: capabilities,
      line_mode: line_mode,
      character_set: character_set,
      color_mode: color_mode,
      alternate_screen: alternate_screen
    }

    # Perform terminal setup
    state = setup_terminal(state)

    {:ok, state}
  end

  @impl true
  @doc """
  Shuts down the TTY backend and restores terminal state.

  Performs the following cleanup sequence:
  1. Reset all text attributes (colors, bold, underline, etc.)
  2. Show the cursor (in case it was hidden)
  3. Leave alternate screen buffer (if it was entered)

  ## Idempotent Behavior

  This function is safe to call multiple times. Each call will emit the same
  cleanup sequences, which is harmless since terminal state converges to the
  same result regardless of prior state.

  ## Error Handling

  All terminal writes use `safe_write/1` which catches and ignores errors.
  This ensures cleanup completes even if the terminal is in an error state
  or has been disconnected. We prioritize best-effort cleanup over failing
  on individual write errors.

  ## No Cooked Mode Restoration

  Unlike the Raw backend, the TTY backend never takes the terminal out of
  cooked mode (the shell is already running). Therefore, no mode restoration
  is needed during shutdown.

  ## Returns

  Always returns `:ok`.
  """
  @spec shutdown(t()) :: :ok
  def shutdown(%__MODULE__{} = state) do
    # Reset all attributes (colors, styles)
    safe_write(@reset_attrs)

    # Show cursor
    safe_write(@cursor_show)

    # Leave alternate screen if it was entered
    if state.alternate_screen do
      safe_write(@alt_screen_leave)
    end

    :ok
  end

  # ===========================================================================
  # Query Callbacks
  # ===========================================================================

  @impl true
  @doc """
  Returns the current terminal dimensions.

  ## Returns

  - `{:ok, {rows, cols}}` - Terminal size
  """
  @spec size(t()) :: {:ok, {pos_integer(), pos_integer()}}
  def size(%__MODULE__{size: size}) do
    {:ok, size}
  end

  @doc """
  Updates the terminal size and clears the frame buffer.

  When the terminal is resized, the previous frame is no longer valid since
  positions may now be out of bounds or content may need to be reflowed.
  This function updates the size and clears `last_frame` to force a full
  redraw on the next `draw_cells/2` call.

  ## Parameters

  - `state` - Current backend state
  - `new_size` - New terminal dimensions as `{rows, cols}`

  ## Returns

  `{:ok, updated_state}` with new size and cleared last_frame.
  """
  @spec set_size(t(), {pos_integer(), pos_integer()}) :: {:ok, t()}
  def set_size(%__MODULE__{} = state, {rows, cols} = new_size)
      when is_integer(rows) and rows > 0 and is_integer(cols) and cols > 0 do
    {:ok, %{state | size: new_size, last_frame: nil}}
  end

  @doc """
  Queries the terminal for its current size and updates state.

  Uses `:io.rows/0` and `:io.columns/0` to get the current terminal dimensions.
  If the query fails (e.g., not connected to a terminal), the current size is preserved.

  This function also clears `last_frame` to force a full redraw, since the
  terminal dimensions may have changed.

  Note: This is a TTY-specific extension function, not part of the Backend behaviour.
  The return signature matches `TermUI.Backend.Raw.refresh_size/1` for consistency.

  ## Returns

  `{:ok, {rows, cols}, updated_state}` with refreshed size and cleared last_frame.

  ## Example

      {:ok, {rows, cols}, state} = TTY.refresh_size(state)
  """
  @spec refresh_size(t()) :: {:ok, TermUI.Backend.size(), t()}
  def refresh_size(%__MODULE__{} = state) do
    new_size = query_terminal_size(state.size)
    new_state = %{state | size: new_size, last_frame: nil}
    {:ok, new_size, new_state}
  end

  # Queries the terminal for its current dimensions.
  # Falls back to the provided default if the query fails.
  @spec query_terminal_size({pos_integer(), pos_integer()}) :: {pos_integer(), pos_integer()}
  defp query_terminal_size(default) do
    rows =
      case :io.rows() do
        {:ok, r} when is_integer(r) and r > 0 -> r
        _ -> elem(default, 0)
      end

    cols =
      case :io.columns() do
        {:ok, c} when is_integer(c) and c > 0 -> c
        _ -> elem(default, 1)
      end

    {rows, cols}
  end

  # ===========================================================================
  # Cursor Callbacks
  # ===========================================================================

  @impl true
  @doc """
  Moves the cursor to the specified position.

  Position is 1-indexed: `{1, 1}` is the top-left corner.
  Outputs `\\e[row;colH` escape sequence.
  Position is clamped to terminal bounds.
  """
  @spec move_cursor(t(), {pos_integer(), pos_integer()}) :: {:ok, t()}
  def move_cursor(%__MODULE__{size: {max_rows, max_cols}} = state, {row, col}) do
    # Clamp position to terminal bounds
    clamped_row = max(1, min(row, max_rows))
    clamped_col = max(1, min(col, max_cols))

    # Output cursor positioning sequence
    safe_write("\e[#{clamped_row};#{clamped_col}H")

    {:ok, %{state | cursor_position: {clamped_row, clamped_col}}}
  end

  @impl true
  @doc """
  Hides the terminal cursor.

  Outputs `\\e[?25l` escape sequence.

  This operation is idempotent - if the cursor is already hidden,
  no escape sequence is written.
  """
  @spec hide_cursor(t()) :: {:ok, t()}
  def hide_cursor(%__MODULE__{cursor_visible: false} = state) do
    # Already hidden - idempotent no-op
    {:ok, state}
  end

  def hide_cursor(%__MODULE__{} = state) do
    safe_write(@cursor_hide)
    {:ok, %{state | cursor_visible: false}}
  end

  @impl true
  @doc """
  Shows the terminal cursor.

  Outputs `\\e[?25h` escape sequence.

  This operation is idempotent - if the cursor is already visible,
  no escape sequence is written.
  """
  @spec show_cursor(t()) :: {:ok, t()}
  def show_cursor(%__MODULE__{cursor_visible: true} = state) do
    # Already visible - idempotent no-op
    {:ok, state}
  end

  def show_cursor(%__MODULE__{} = state) do
    safe_write(@cursor_show)
    {:ok, %{state | cursor_visible: true}}
  end

  # ===========================================================================
  # Rendering Callbacks
  # ===========================================================================

  @impl true
  @doc """
  Clears the entire screen and moves cursor to home position.

  Outputs the following escape sequences:
  1. `\\e[2J` - Clear entire screen
  2. `\\e[H` - Move cursor to home position (1,1)

  Also clears `last_frame` in state, which forces a full redraw on the next
  `draw_cells/2` call when in incremental mode.

  ## Returns

  `{:ok, updated_state}` with cursor_position set to `{1, 1}` and last_frame cleared.
  """
  @spec clear(t()) :: {:ok, t()}
  def clear(state) do
    # Clear entire screen and move cursor to home position
    safe_write(@reset_attrs <> @clear_screen <> @cursor_home)

    # Update state: clear last_frame for incremental mode, reset cursor position
    {:ok, %{state | last_frame: nil, cursor_position: {1, 1}}}
  end

  @doc "Restores owned TTY output modes before a full redraw after resume."
  @spec resume(t()) :: {:ok, t()}
  def resume(state) do
    IO.write(TermUI.ANSI.reset())
    {:ok, setup_terminal(%{state | last_frame: nil})}
  end

  @impl true
  @doc """
  Draws cells to the terminal at specified positions.

  In `:full_redraw` mode (default), clears the screen first then renders all cells.
  In `:incremental` mode, only renders the provided cells without clearing.

  ## Cell Format

  Each cell is a tuple of `{position, cell_data}` where:
  - `position` is `{row, col}` (1-indexed)
  - `cell_data` is `{char, fg_color, bg_color, attrs}`

  ## Rendering Process

  1. In full_redraw mode, clear screen and home cursor
  2. Group cells by row for efficient rendering
  3. For each row, position cursor and output styled characters
  4. Apply color degradation based on `color_mode`

  ## Returns

  `{:ok, updated_state}` with `last_frame` updated for incremental mode.
  """
  @spec draw_cells(t(), [{TermUI.Backend.position(), TermUI.Backend.cell()}]) :: {:ok, t()}
  def draw_cells(%__MODULE__{} = state, cells) do
    case state.line_mode do
      :full_redraw ->
        # Always clear and redraw everything
        do_full_redraw(cells, state)

      :incremental ->
        if is_nil(state.last_frame) do
          # First frame in incremental mode - do full redraw to establish baseline
          do_full_redraw(cells, state)
        else
          # Subsequent frames - only render changes
          do_incremental_render(cells, state)
        end
    end
  end

  # Performs a full redraw: clears screen and renders all cells.
  @spec do_full_redraw(
          [{TermUI.Backend.position(), TermUI.Backend.cell()}],
          t()
        ) :: {:ok, t()}
  defp do_full_redraw(cells, state) do
    # Clear screen and home cursor
    safe_write(@clear_screen <> @cursor_home)

    # Group cells by row and render
    cells
    |> group_cells_by_row()
    |> render_rows(state)

    # Build frame map for incremental mode tracking
    frame =
      if state.line_mode == :incremental do
        build_frame_map(cells)
      else
        nil
      end

    {:ok, %{state | last_frame: frame, cursor_position: nil}}
  end

  # Performs incremental rendering: only updates changed/removed cells.
  #
  # Optimizations applied:
  # 1. Sort cells by position (row, then col) for sequential access
  # 2. Group adjacent cells on same row to minimize cursor moves
  # 3. Batch render grouped cells with single cursor positioning
  @spec do_incremental_render(
          [{TermUI.Backend.position(), TermUI.Backend.cell()}],
          t()
        ) :: {:ok, t()}
  defp do_incremental_render(cells, state) do
    # Compare current frame with last frame
    {changed, removed} = compare_frames(state.last_frame, cells)

    # Optimize: sort and group changed cells by row for efficient rendering
    # This reduces cursor positioning overhead
    changed
    |> sort_cells_by_position()
    |> group_cells_by_row()
    |> render_incremental_rows(state)

    # Clear removed cells (sorted for sequential access)
    removed
    |> Enum.sort()
    |> Enum.each(&clear_cell_at(&1, state))

    # Update last_frame with current frame
    frame = build_frame_map(cells)

    {:ok, %{state | last_frame: frame, cursor_position: nil}}
  end

  # Sorts cells by position (row first, then column) for optimal cursor movement.
  @spec sort_cells_by_position([{TermUI.Backend.position(), TermUI.Backend.cell()}]) ::
          [{TermUI.Backend.position(), TermUI.Backend.cell()}]
  defp sort_cells_by_position(cells) do
    Enum.sort_by(cells, fn {{row, col}, _cell} -> {row, col} end)
  end

  # Renders grouped cells for incremental mode with cursor optimization.
  #
  # For each row, positions cursor once at the first cell, then renders
  # cells in sequence. Adjacent cells benefit from implicit cursor advance.
  # Rows outside terminal bounds are skipped.
  @spec render_incremental_rows([{pos_integer(), [{pos_integer(), TermUI.Backend.cell()}]}], t()) ::
          :ok
  defp render_incremental_rows(grouped_rows, state) do
    {max_rows, _max_cols} = state.size

    Enum.each(grouped_rows, fn {row, row_cells} ->
      # Skip rows outside terminal bounds
      if row >= 1 and row <= max_rows do
        render_incremental_row(row, row_cells, state)
      end
    end)
  end

  # A gap contains unchanged cells. Move to the next changed run instead of
  # writing spaces over those cells with the preceding run's style.
  @spec render_incremental_row(pos_integer(), [{pos_integer(), TermUI.Backend.cell()}], t()) ::
          :ok
  defp render_incremental_row(row, row_cells, state) do
    row_cells
    |> Enum.with_index()
    |> Enum.chunk_by(fn {{column, _cell}, index} -> column - index end)
    |> Enum.each(fn entries ->
      cells = Enum.map(entries, &elem(&1, 0))
      [{start_column, _cell} | _] = cells
      render_row_at_column(row, start_column, cells, state)
    end)
  end

  # Clears a cell at a specific position by writing a space.
  #
  # Used for incremental rendering to clear cells that were in the
  # previous frame but not in the current frame. Positions outside
  # terminal bounds are silently skipped.
  @spec clear_cell_at(TermUI.Backend.position(), t()) :: :ok
  defp clear_cell_at({row, col}, state) do
    {max_rows, max_cols} = state.size

    # Validate position is within terminal bounds
    if row >= 1 and row <= max_rows and col >= 1 and col <= max_cols do
      cursor = "\e[#{row};#{col}H"
      safe_write([cursor, @reset_attrs, " "])
    end

    :ok
  end

  @impl true
  @doc """
  Flushes pending output to the terminal.

  For TTY mode, output is synchronous so this is largely a no-op.
  """
  @spec flush(t()) :: {:ok, t()}
  def flush(state) do
    {:ok, state}
  end

  # ===========================================================================
  # Input Callbacks
  # ===========================================================================

  @impl true
  @doc """
  Polls for input events with the specified timeout.

  Requests one character at a time with `IO.getn/2`. Because the terminal stays
  in cooked mode, the shell or terminal driver may buffer input until Enter.
  The timeout parameter may not be honored since `IO.getn/2` is blocking.

  Input is parsed using `TermUI.Terminal.EscapeParser` to handle escape
  sequences like arrow keys, function keys, and mouse events.

  Partial escape sequences are buffered in the state's `input_buffer` field
  and will be completed on subsequent calls.

  ## Returns

  - `{:ok, event, state}` - An input event was received
  - `{:timeout, state}` - No input available (rare with blocking IO)
  - `{:error, reason, state}` - An error occurred

  ## Note

  The timeout parameter is not honored due to the blocking nature of `IO.getn/2`.
  For non-blocking input, consider using the Raw backend when available.
  """
  @spec poll_event(t(), non_neg_integer()) ::
          {:ok, TermUI.Backend.event(), t()}
          | {:timeout, t()}
          | {:error, term(), t()}
  def poll_event(%__MODULE__{input_buffer: buffer} = state, _timeout) do
    # First check if we have buffered events from a previous partial parse
    case parse_buffered_input(buffer) do
      {:event, event, remaining} ->
        {:ok, event, %{state | input_buffer: remaining}}

      :need_more ->
        # Read a single character from input
        case read_input_char() do
          {:ok, char_data} ->
            # Combine with buffer (with size limit protection) and parse
            new_state = append_to_input_buffer(state, char_data)
            parse_and_return_event(new_state, new_state.input_buffer)

          :eof ->
            {:error, :eof, state}

          {:error, reason} ->
            {:error, reason, state}
        end
    end
  end

  # Attempts to parse an event from buffered input.
  @spec parse_buffered_input(binary()) :: {:event, TermUI.Backend.event(), binary()} | :need_more
  defp parse_buffered_input(<<>>) do
    :need_more
  end

  defp parse_buffered_input(buffer) do
    case EscapeParser.parse(buffer) do
      {[event | _rest_events], remaining} ->
        # Return first event, keep remaining in buffer
        # Note: We discard rest_events; they'll be re-parsed on next call
        {:event, event, remaining}

      {[], _remaining} ->
        # No complete events parsed - might be partial sequence
        :need_more
    end
  end

  # Reads a single character from standard input.
  @spec read_input_char() :: {:ok, binary()} | :eof | {:error, term()}
  defp read_input_char do
    case IO.getn("", 1) do
      :eof ->
        :eof

      {:error, reason} ->
        {:error, reason}

      char when is_binary(char) ->
        {:ok, char}

      # IO.getn can return a charlist in some contexts
      [char] when is_integer(char) ->
        {:ok, <<char>>}

      other ->
        # Unexpected return type - return error instead of masking it
        {:error, {:unexpected_io_return, other}}
    end
  end

  # Parses combined input and returns an event or timeout.
  @spec parse_and_return_event(t(), binary()) ::
          {:ok, TermUI.Backend.event(), t()}
          | {:timeout, t()}
  defp parse_and_return_event(state, input) do
    case EscapeParser.parse(input) do
      {[event | _rest], remaining} ->
        {:ok, event, %{state | input_buffer: remaining}}

      {[], remaining} ->
        # No complete event - buffer the input for next call
        # This happens with partial escape sequences
        # Apply buffer size limit to prevent memory exhaustion
        new_state = apply_buffer_limit(%{state | input_buffer: remaining})
        {:timeout, new_state}
    end
  end

  # Appends data to the input buffer with size limit protection.
  # Uses the shared InputBuffer module for rate-limited logging.
  @spec append_to_input_buffer(t(), binary()) :: t()
  defp append_to_input_buffer(state, data) do
    InputBuffer.append_with_limit(state, data, :input_buffer, source: __MODULE__)
  end

  # Applies buffer size limit, truncating if necessary.
  # Uses the shared InputBuffer module for rate-limited logging.
  @spec apply_buffer_limit(t()) :: t()
  defp apply_buffer_limit(%{input_buffer: buffer} = state) do
    {limited, _overflowed} = InputBuffer.apply_limit(buffer, source: __MODULE__)
    %{state | input_buffer: limited}
  end

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  # Determines color mode from capabilities map.
  @spec determine_color_mode(map()) :: color_mode()
  defp determine_color_mode(capabilities) do
    case Map.get(capabilities, :colors) do
      :true_color -> :true_color
      :color_256 -> :color_256
      :color_16 -> :color_16
      :monochrome -> :monochrome
      n when is_integer(n) -> color_mode_from_integer(n)
      _ -> :true_color
    end
  end

  defp color_mode_from_integer(n) when n >= 16_777_216, do: :true_color
  defp color_mode_from_integer(n) when n >= 256, do: :color_256
  defp color_mode_from_integer(n) when n >= 16, do: :color_16
  defp color_mode_from_integer(_), do: :true_color

  # Determines character set from capabilities map.
  @spec determine_character_set(map()) :: character_set()
  defp determine_character_set(capabilities) do
    case Map.get(capabilities, :unicode, true) do
      true -> :unicode
      false -> :ascii
      _ -> :unicode
    end
  end

  # Determines terminal size from options, capabilities, or defaults.
  @spec determine_size(keyword(), map()) :: {pos_integer(), pos_integer()}
  defp determine_size(opts, capabilities) do
    case Keyword.get(opts, :size) do
      {rows, cols} when is_integer(rows) and is_integer(cols) and rows > 0 and cols > 0 ->
        {rows, cols}

      nil ->
        size_from_capabilities_or_default(capabilities)

      _ ->
        {24, 80}
    end
  end

  defp size_from_capabilities_or_default(capabilities) do
    case Map.get(capabilities, :dimensions) do
      {rows, cols} when is_integer(rows) and is_integer(cols) and rows > 0 and cols > 0 ->
        {rows, cols}

      _ ->
        {24, 80}
    end
  end

  # Performs terminal setup during initialization.
  #
  # Outputs ANSI escape sequences to prepare the terminal for rendering:
  # - Optionally enters alternate screen buffer if configured
  # - Hides cursor for cleaner rendering
  # - Clears screen and moves cursor to home position
  #
  # Note: No raw mode activation - the shell is already running in TTY mode.
  @spec setup_terminal(t()) :: t()
  defp setup_terminal(state) do
    # Enter alternate screen if configured
    if state.alternate_screen do
      IO.write(@alt_screen_enter)
    end

    # Hide cursor for cleaner rendering
    IO.write(@cursor_hide)

    # Clear screen and move cursor to home position
    IO.write(@clear_screen <> @cursor_home)

    # Update state to reflect cursor is hidden
    %{state | cursor_visible: false, cursor_position: {1, 1}}
  end

  # ===========================================================================
  # Cell Rendering Helpers
  # ===========================================================================

  # Groups cells by row number and sorts by column within each row.
  @spec group_cells_by_row([{TermUI.Backend.position(), TermUI.Backend.cell()}]) ::
          [{pos_integer(), [{pos_integer(), TermUI.Backend.cell()}]}]
  defp group_cells_by_row(cells) do
    cells
    |> Enum.group_by(fn {{row, _col}, _cell} -> row end, fn {{_row, col}, cell} -> {col, cell} end)
    |> Enum.sort_by(fn {row, _cells} -> row end)
    |> Enum.map(fn {row, row_cells} ->
      {row, Enum.sort_by(row_cells, fn {col, _cell} -> col end)}
    end)
  end

  # Renders all rows to the terminal.
  @spec render_rows([{pos_integer(), [{pos_integer(), TermUI.Backend.cell()}]}], t()) :: :ok
  defp render_rows(rows, state) do
    Enum.each(rows, fn {row, row_cells} ->
      render_row_at_column(row, 1, row_cells, state)
    end)
  end

  # Shared row rendering function for both full redraw and incremental modes.
  #
  # Renders a row of cells starting at a specified column with style delta tracking.
  # Tracks the current style and only outputs SGR sequences when the style
  # changes between cells. Uses iolist append pattern (no reverse needed).
  #
  # Parameters:
  # - row: The row number (1-indexed)
  # - start_col: The column to position cursor at (1 for full redraw, first cell col for incremental)
  # - cells: List of {col, cell} tuples sorted by column
  # - state: Backend state with color_mode and character_set
  @spec render_row_at_column(
          pos_integer(),
          pos_integer(),
          [{pos_integer(), TermUI.Backend.cell()}],
          t()
        ) :: :ok
  defp render_row_at_column(row, start_col, cells, state) do
    # Track current column, current style, and accumulated iolist
    # Initial style is nil (no style set yet)
    initial_state = {start_col, nil, []}

    {_col, _style, iolist} =
      Enum.reduce(cells, initial_state, fn {col, cell}, {cur_col, cur_style, acc} ->
        # Fill gap with spaces if needed
        gap =
          if col > cur_col do
            String.duplicate(" ", col - cur_col)
          else
            ""
          end

        # Render the cell with style delta tracking
        {new_style, cell_io} = render_cell_with_delta(cell, cur_style, state)

        # Append to iolist (append pattern - no reverse needed for iolists)
        new_acc = [acc, gap, cell_io]

        # Return next column position and new style
        {col + 1, new_style, new_acc}
      end)

    # Build final iolist: cursor position + content + reset
    final_io = ["\e[#{row};#{start_col}H", iolist, @reset_attrs]

    # Single write for entire row
    safe_write(final_io)

    :ok
  end

  # Renders a single cell with style delta tracking.
  #
  # Only outputs SGR sequences when the style differs from the previous cell.
  # Returns the new style and the iodata for this cell.
  @spec render_cell_with_delta(
          TermUI.Backend.cell(),
          {TermUI.Backend.color(), TermUI.Backend.color(), [atom()]} | nil,
          t()
        ) :: {{TermUI.Backend.color(), TermUI.Backend.color(), [atom()]}, iodata()}
  defp render_cell_with_delta({char, fg, bg, attrs}, cur_style, state) do
    new_style = {fg, bg, attrs}

    # Only output SGR if style changed
    sgr =
      if new_style != cur_style do
        build_sgr_sequence(fg, bg, attrs, state.color_mode)
      else
        ""
      end

    # Map character (with potential character set mapping and sanitization)
    mapped_char = map_character(char, state.character_set)
    sanitized_char = sanitize_char(mapped_char)

    {new_style, [sgr, sanitized_char]}
  end

  # Builds SGR (Select Graphic Rendition) sequence for colors and attributes.
  #
  # Combines reset, attributes, foreground color, and background color into
  # a single efficient escape sequence string.
  @spec build_sgr_sequence(
          TermUI.Backend.color(),
          TermUI.Backend.color(),
          [atom()],
          color_mode()
        ) :: String.t()
  defp build_sgr_sequence(fg, bg, attrs, color_mode) do
    # Build each component
    reset_part = @reset_attrs
    attrs_part = build_attrs_sgr(attrs)
    fg_part = build_fg_sgr(fg, color_mode)
    bg_part = build_bg_sgr(bg, color_mode)

    # Combine non-empty parts
    [reset_part, attrs_part, fg_part, bg_part]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("")
  end

  # Builds SGR sequence for text attributes (bold, italic, etc.).
  @spec build_attrs_sgr([atom()]) :: String.t()
  defp build_attrs_sgr(attrs) do
    attrs
    |> Enum.map(&attr_to_sgr/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("")
  end

  # Builds SGR sequence for foreground color.
  @spec build_fg_sgr(TermUI.Backend.color(), color_mode()) :: String.t()
  defp build_fg_sgr(color, color_mode) do
    color_to_sgr(color, :fg, color_mode)
  end

  # Builds SGR sequence for background color.
  @spec build_bg_sgr(TermUI.Backend.color(), color_mode()) :: String.t()
  defp build_bg_sgr(color, color_mode) do
    color_to_sgr(color, :bg, color_mode)
  end

  # Converts an attribute to its SGR sequence.
  @spec attr_to_sgr(atom()) :: String.t() | nil
  defp attr_to_sgr(:bold), do: "\e[1m"
  defp attr_to_sgr(:dim), do: "\e[2m"
  defp attr_to_sgr(:italic), do: "\e[3m"
  defp attr_to_sgr(:underline), do: "\e[4m"
  defp attr_to_sgr(:blink), do: "\e[5m"
  defp attr_to_sgr(:reverse), do: "\e[7m"
  defp attr_to_sgr(:strikethrough), do: "\e[9m"
  defp attr_to_sgr(_), do: nil

  # Converts a color to its SGR sequence based on color mode.
  @spec color_to_sgr(TermUI.Backend.color(), :fg | :bg, color_mode()) :: String.t()
  defp color_to_sgr(:default, :fg, _mode), do: "\e[39m"
  defp color_to_sgr(:default, :bg, _mode), do: "\e[49m"
  defp color_to_sgr(nil, _type, _mode), do: ""

  # True color mode - output RGB directly (with validation)
  defp color_to_sgr({r, g, b}, :fg, :true_color)
       when is_integer(r) and r >= 0 and r <= 255 and
              is_integer(g) and g >= 0 and g <= 255 and
              is_integer(b) and b >= 0 and b <= 255 do
    "\e[38;2;#{r};#{g};#{b}m"
  end

  defp color_to_sgr({r, g, b}, :bg, :true_color)
       when is_integer(r) and r >= 0 and r <= 255 and
              is_integer(g) and g >= 0 and g <= 255 and
              is_integer(b) and b >= 0 and b <= 255 do
    "\e[48;2;#{r};#{g};#{b}m"
  end

  # 256-color mode - convert RGB to palette index (with validation)
  defp color_to_sgr({r, g, b}, :fg, :color_256)
       when is_integer(r) and r >= 0 and r <= 255 and
              is_integer(g) and g >= 0 and g <= 255 and
              is_integer(b) and b >= 0 and b <= 255 do
    "\e[38;5;#{Converter.rgb_to_256({r, g, b})}m"
  end

  defp color_to_sgr({r, g, b}, :bg, :color_256)
       when is_integer(r) and r >= 0 and r <= 255 and
              is_integer(g) and g >= 0 and g <= 255 and
              is_integer(b) and b >= 0 and b <= 255 do
    "\e[48;5;#{Converter.rgb_to_256({r, g, b})}m"
  end

  # 16-color mode - convert RGB to basic color (with validation)
  defp color_to_sgr({r, g, b}, :fg, :color_16)
       when is_integer(r) and r >= 0 and r <= 255 and
              is_integer(g) and g >= 0 and g <= 255 and
              is_integer(b) and b >= 0 and b <= 255 do
    "\e[#{Converter.rgb_to_16({r, g, b}, :fg)}m"
  end

  defp color_to_sgr({r, g, b}, :bg, :color_16)
       when is_integer(r) and r >= 0 and r <= 255 and
              is_integer(g) and g >= 0 and g <= 255 and
              is_integer(b) and b >= 0 and b <= 255 do
    "\e[#{Converter.rgb_to_16({r, g, b}, :bg)}m"
  end

  # Monochrome mode - skip colors entirely
  defp color_to_sgr({_r, _g, _b}, _type, :monochrome), do: ""

  # Invalid RGB values fall through to catch-all clause (returns "")

  # Monochrome mode - skip all colors (named and palette)
  defp color_to_sgr(name, _type, :monochrome) when is_atom(name), do: ""
  defp color_to_sgr(n, _type, :monochrome) when is_integer(n), do: ""

  # Named colors (for all other modes)
  defp color_to_sgr(name, :fg, _mode) when is_atom(name), do: named_color_to_sgr(name, :fg)
  defp color_to_sgr(name, :bg, _mode) when is_atom(name), do: named_color_to_sgr(name, :bg)

  # Palette index (0-255)
  defp color_to_sgr(n, :fg, _mode) when is_integer(n) and n >= 0 and n <= 255,
    do: "\e[38;5;#{n}m"

  defp color_to_sgr(n, :bg, _mode) when is_integer(n) and n >= 0 and n <= 255,
    do: "\e[48;5;#{n}m"

  defp color_to_sgr(_, _, _), do: ""

  # Named color SGR code mappings (foreground base codes)
  @named_color_codes %{
    black: 30,
    red: 31,
    green: 32,
    yellow: 33,
    blue: 34,
    magenta: 35,
    cyan: 36,
    white: 37,
    bright_black: 90,
    bright_red: 91,
    bright_green: 92,
    bright_yellow: 93,
    bright_blue: 94,
    bright_magenta: 95,
    bright_cyan: 96,
    bright_white: 97
  }

  # Named color to SGR sequence using map lookup
  @spec named_color_to_sgr(atom(), :fg | :bg) :: String.t()
  defp named_color_to_sgr(name, type) do
    case Map.get(@named_color_codes, name) do
      nil ->
        ""

      code when type == :fg ->
        "\e[#{code}m"

      code when type == :bg ->
        # Background codes are foreground + 10
        bg_code = code + 10
        "\e[#{bg_code}m"
    end
  end

  # ===========================================================================
  # Character Set Mapping (Unicode to ASCII)
  # ===========================================================================

  # Compile-time mapping from Unicode box-drawing characters to ASCII equivalents.
  # Built from CharacterSet definitions to ensure consistency and automatic adaptation
  # when new character keys are added.
  @unicode_chars TermUI.CharacterSet.get(:unicode)
  @ascii_chars TermUI.CharacterSet.get(:ascii)

  # Build the mapping in a single expression:
  # 1. Map all single-character keys (excluding bar_levels) from unicode to ascii
  # 2. Add bar_levels mapping (Unicode has 8 levels, ASCII has 5 - cycle ASCII to match)
  # 3. Override bar_full to ensure it maps correctly (it appears in both bar_levels and standalone)
  @unicode_to_ascii_map (
                          # Single-character keys (all keys except bar_levels)
                          single_keys = TermUI.CharacterSet.keys() -- [:bar_levels]

                          base =
                            Map.new(single_keys, fn key ->
                              {@unicode_chars[key], @ascii_chars[key]}
                            end)

                          # Add bar_levels with cycling (8 Unicode levels → 5 ASCII levels cycled)
                          bar_map =
                            @unicode_chars.bar_levels
                            |> Enum.zip(Stream.cycle(@ascii_chars.bar_levels))
                            |> Map.new()

                          # Merge bar_map first, then base - this ensures bar_full gets the standalone value
                          # since it appears last in single_keys and overwrites the cycled bar_levels value
                          Map.merge(bar_map, base)
                        )

  # Maps characters based on character set.
  #
  # When character_set is :unicode, passes through unchanged.
  # When character_set is :ascii, replaces Unicode box-drawing and special
  # characters with their ASCII equivalents for terminals that don't support Unicode.
  @spec map_character(String.t(), character_set()) :: String.t()
  defp map_character(char, :unicode), do: char

  defp map_character(char, :ascii) do
    Map.get(@unicode_to_ascii_map, char, char)
  end

  # Sanitizes characters to prevent escape sequence injection (defense-in-depth).
  #
  # This is the last line of defense against terminal escape injection.
  # Cells should be pre-sanitized by TermUI.Renderer.Cell which provides
  # comprehensive sanitization (CSI sequences, OSC sequences, control chars).
  # This function provides minimal ESC removal as a safety net in case
  # unsanitized content somehow reaches the rendering layer.
  #
  # For comprehensive sanitization, see TermUI.Sanitize.sanitize/1.
  @spec sanitize_char(String.t()) :: String.t()
  defp sanitize_char(char) when is_binary(char) do
    String.replace(char, "\e", "")
  end

  defp sanitize_char(char), do: char

  # Builds a frame map from cells for incremental mode tracking.
  @spec build_frame_map([{TermUI.Backend.position(), TermUI.Backend.cell()}]) :: map()
  defp build_frame_map(cells) do
    Map.new(cells, fn {pos, cell} -> {pos, cell} end)
  end

  # ===========================================================================
  # Frame Comparison for Incremental Rendering
  # ===========================================================================

  # Compares the current frame with the previous frame to identify changes.
  #
  # Core diffing algorithm for incremental rendering. Identifies which cells
  # need to be updated (new or changed) and which positions need to be cleared.
  #
  @doc """
  Compares two frames to find changed and removed cells.

  This is a testing helper function exposed for unit testing the incremental
  rendering logic. It is not part of the Backend behaviour API.

  Uses MapSet for efficient position lookup when finding removed cells,
  avoiding the need to build a full frame map just for membership testing.

  ## Parameters

  - `last_frame` - Map of `{row, col}` => `{char, fg, bg, attrs}` from previous frame
  - `current_cells` - List of `{{row, col}, {char, fg, bg, attrs}}` tuples for current frame

  ## Returns

  Tuple of `{changed_cells, removed_positions}`:
  - `changed_cells` - Cells that are new or different from last frame
  - `removed_positions` - Positions that were in last frame but not in current
  """
  @spec compare_frames(
          map(),
          [{TermUI.Backend.position(), TermUI.Backend.cell()}]
        ) :: {[{TermUI.Backend.position(), TermUI.Backend.cell()}], [TermUI.Backend.position()]}
  def compare_frames(last_frame, current_cells) do
    # Find changed cells: new or different from last frame
    changed =
      Enum.filter(current_cells, fn {pos, cell} ->
        case Map.get(last_frame, pos) do
          nil -> true
          ^cell -> false
          _different -> true
        end
      end)

    # Build position set for efficient membership testing (cheaper than full frame map)
    current_positions = MapSet.new(current_cells, fn {pos, _cell} -> pos end)

    # Find removed positions: in last frame but not in current
    removed =
      last_frame
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(current_positions, &1))

    {changed, removed}
  end

  # ===========================================================================
  # Terminal I/O Helpers
  # ===========================================================================

  # Writes data to the terminal, ignoring any errors.
  #
  # This provides bulletproof writes for shutdown sequences where we want
  # to attempt terminal cleanup even if the terminal is in an error state.
  # Errors are silently ignored since we're cleaning up anyway.
  @spec safe_write(iodata()) :: :ok
  defp safe_write(data) do
    try do
      IO.write(data)
    rescue
      _ -> :ok
    end

    :ok
  end
end
