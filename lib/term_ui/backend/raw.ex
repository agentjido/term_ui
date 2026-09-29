defmodule TermUI.Backend.Raw do
  @moduledoc """
  Raw terminal backend providing full terminal control.

  The Raw backend is the primary high-fidelity rendering path in TermUI. It provides
  direct terminal control with immediate keystroke detection, true color support,
  mouse tracking, and all advanced terminal features.

  ## Requirements

  - **OTP 28+**: Raw mode is activated via `:shell.start_interactive({:noshell, :raw})`
  - **Terminal access**: Requires a real terminal (not pipes or redirected I/O)

  ## How It Works

  The Raw backend assumes raw mode has already been activated by `TermUI.Backend.Selector`
  before `init/1` is called. The selector uses `:shell.start_interactive({:noshell, :raw})`
  to enter raw mode, and on success, routes to this backend.

  **Important**: The `init/1` callback does NOT activate raw mode itself. It only performs
  terminal setup (alternate screen, cursor hiding, etc.) assuming raw mode is already active.

  ## Features

  When raw mode is active, this backend provides:

  - **Alternate screen buffer**: Preserves original terminal content, restored on exit
  - **Cursor control**: Hide/show cursor, precise positioning
  - **True color rendering**: Full 24-bit RGB color support (`{r, g, b}` tuples)
  - **256-color palette**: Extended color support (0-255 indices)
  - **Mouse tracking**: Click, drag, and movement detection
  - **Immediate input**: Character-by-character keystroke detection
  - **Escape sequence handling**: Function keys, arrow keys, modifiers

  ## Initialization Flow

  ```
  1. Selector calls :shell.start_interactive({:noshell, :raw})
     └── Returns :ok (raw mode active)

  2. Runtime creates Raw backend state
     └── Calls Raw.init(opts)

  3. Raw.init/1 performs terminal setup:
     ├── Enter alternate screen buffer (optional)
     ├── Hide cursor
     ├── Enable mouse tracking (optional)
     └── Clear screen
  ```

  ## Configuration Options

  The `init/1` callback accepts these options:

  - `:alternate_screen` - Use alternate screen buffer (default: `true`)
  - `:hide_cursor` - Hide cursor during rendering (default: `true`)
  - `:mouse_tracking` - Mouse tracking mode (default: `:none`)
    - `:none` - No mouse tracking
    - `:click` - Track button clicks only
    - `:drag` - Track clicks and drag events
    - `:all` - Track all mouse movement
  - `:size` - Explicit terminal dimensions `{rows, cols}` (default: auto-detect)

  ## Shutdown Behavior

  The `shutdown/1` callback restores the terminal to its pre-init state:

  1. Disable mouse tracking (if enabled)
  2. Show cursor
  3. Reset all text attributes
  4. Leave alternate screen (if entered)
  5. Return to cooked mode via `:shell.start_interactive({:noshell, :cooked})`

  Shutdown is designed to be error-safe - individual failures don't prevent
  subsequent cleanup steps from running.

  ## Usage Example

  This backend is typically used via the runtime, not directly:

      # Automatic backend selection (recommended)
      {:ok, runtime} = TermUI.Runtime.start_link(root: MyApp.Root)

      # The runtime handles:
      # 1. Backend selection via Selector
      # 2. Backend initialization
      # 3. Rendering via draw_cells/2
      # 4. Input polling via poll_event/2
      # 5. Clean shutdown

  ## Mouse Tracking Modes

  The Raw backend uses intuitive mode names that map to underlying ANSI protocol modes:

  | Raw Backend | ANSI Protocol | Escape Sequence | Description |
  |-------------|---------------|-----------------|-------------|
  | `:none`     | (disabled)    | -               | No mouse tracking |
  | `:click`    | Normal (1000) | `ESC[?1000h`    | Button press/release only |
  | `:drag`     | Button (1002) | `ESC[?1002h`    | Press/release + motion while pressed |
  | `:all`      | Any (1003)    | `ESC[?1003h`    | All mouse motion events |

  When mouse tracking is enabled, SGR extended mode (`ESC[?1006h`) is also activated
  for accurate coordinate encoding beyond column 223.

  Note: The `TermUI.ANSI` module uses protocol names (`:normal`, `:button`, `:all`),
  while this backend uses user-friendly names (`:click`, `:drag`, `:all`). The mapping
  is handled internally when emitting sequences.

  ## Style Delta Optimization

  The `current_style` field in the backend state tracks the last-emitted SGR (Select
  Graphic Rendition) attributes. This enables **style delta optimization** in
  `draw_cells/2`:

  Instead of emitting full style sequences for every cell:
  ```
  ESC[0;38;2;255;0;0;48;2;0;0;0mA  <- 25 bytes per cell
  ESC[0;38;2;255;0;0;48;2;0;0;0mB
  ```

  We only emit changes from the previous style:
  ```
  ESC[38;2;255;0;0;48;2;0;0;0mA   <- Full style for first cell
  B                                <- No escape needed, same style!
  ESC[38;2;0;255;0mC              <- Only foreground changed
  ```

  This optimization can reduce escape sequence output by 80-90% for typical UIs
  where adjacent cells share styles (text blocks, borders, backgrounds).

  The `current_style` map tracks:
  - `:fg` - Current foreground color
  - `:bg` - Current background color
  - `:attrs` - Current text attributes (`:bold`, `:underline`, `:reverse`, etc.)

  ## See Also

  - `TermUI.Backend` - Behaviour definition
  - `TermUI.Backend.Selector` - Backend selection logic
  - `TermUI.Backend.TTY` - Fallback backend for non-raw environments
  - `TermUI.ANSI` - Escape sequence generation
  """

  @behaviour TermUI.Backend

  alias TermUI.ANSI
  alias TermUI.Backend.InputBuffer
  alias TermUI.Platform
  alias TermUI.Renderer.CursorOptimizer
  alias TermUI.Terminal.SizeDetector
  alias TermUI.TerminalOutput
  alias TermUI.TermUtils
  require Logger

  # Dialyzer: Functions with unmatched return values
  @dialyzer {:nowarn_function, shutdown: 1, safe_write: 1, safe_cooked_mode: 0}

  # Comprehensive mouse disable sequence - disables ALL mouse modes defensively
  # This ensures cleanup even if state is inconsistent
  @all_mouse_off "\e[?1006l\e[?1003l\e[?1002l\e[?1000l"

  # Input buffer management is handled by TermUI.Backend.InputBuffer module
  # which provides rate-limited logging and consistent behavior across backends.

  # Maximum event queue size to prevent memory exhaustion when events
  # are parsed faster than they're consumed.
  @max_event_queue_size 100

  # ===========================================================================
  # Type Definitions and State Structure
  # ===========================================================================

  @typedoc """
  Mouse tracking mode for the terminal.

  These are user-friendly names that map to ANSI protocol modes internally:

  - `:none` - No mouse tracking (disabled)
  - `:click` - Track button press/release only (ANSI "normal" mode, 1000)
  - `:drag` - Track clicks and motion while button pressed (ANSI "button" mode, 1002)
  - `:all` - Track all mouse movement (ANSI "any" mode, 1003)

  See the "Mouse Tracking Modes" section in the module documentation for details.
  """
  @type mouse_mode :: :none | :click | :drag | :all

  @typedoc """
  Current SGR (Select Graphic Rendition) style state.

  Tracks the current foreground color, background color, and text attributes
  to enable style delta optimization - only emitting escape sequences for
  changed attributes.

  ## Fields

  - `:fg` - Current foreground color (see `TermUI.Backend.color()`)
  - `:bg` - Current background color (see `TermUI.Backend.color()`)
  - `:attrs` - List of active text attributes:
    - `:bold` - Bold/bright text
    - `:dim` - Dimmed text
    - `:italic` - Italic text
    - `:underline` - Underlined text
    - `:blink` - Blinking text
    - `:reverse` - Swapped foreground/background
    - `:hidden` - Hidden text
    - `:strikethrough` - Struck-through text

  See the "Style Delta Optimization" section in the module documentation for
  how this enables efficient rendering.
  """
  @type style_state :: %{
          fg: TermUI.Backend.color(),
          bg: TermUI.Backend.color(),
          attrs: [atom()]
        }

  @typedoc """
  Internal state for the Raw backend.

  Tracks all terminal state needed for rendering and input handling.

  ## Fields

  - `:size` - Terminal dimensions as `{rows, cols}`
  - `:cursor_visible` - Whether cursor is currently visible (default: `false`)
  - `:cursor_position` - Current cursor position as `{row, col}` or `nil`
  - `:alternate_screen` - Whether alternate screen buffer is active
  - `:mouse_mode` - Current mouse tracking mode
  - `:current_style` - Current SGR state for style delta tracking
  - `:optimize_cursor` - Whether to use cursor movement optimization (default: `true`)
  - `:input_buffer` - Buffer for partial escape sequences during input parsing
  - `:event_queue` - Queue of parsed events waiting to be returned
  """
  @type t :: %__MODULE__{
          size: {pos_integer(), pos_integer()},
          cursor_visible: boolean(),
          cursor_position: {pos_integer(), pos_integer()} | nil,
          alternate_screen: boolean(),
          mouse_mode: mouse_mode(),
          current_style: style_state() | nil,
          optimize_cursor: boolean(),
          input_buffer: binary(),
          event_queue: [TermUI.Backend.event()],
          events_dropped: non_neg_integer()
        }

  defstruct size: {24, 80},
            cursor_visible: false,
            cursor_position: nil,
            alternate_screen: false,
            mouse_mode: :none,
            current_style: nil,
            optimize_cursor: true,
            input_buffer: <<>>,
            event_queue: [],
            events_dropped: 0

  # ===========================================================================
  # Behaviour Callbacks - Lifecycle, Queries, Cursor, Rendering, Input
  # ===========================================================================
  @impl true
  @doc """
  Initializes the Raw backend with terminal setup.

  Assumes raw mode is already active (started by Selector). Performs terminal
  configuration including alternate screen, cursor hiding, and mouse tracking.

  ## Options

  - `:alternate_screen` - Use alternate screen buffer (default: `true`)
  - `:hide_cursor` - Hide cursor during rendering (default: `true`)
  - `:mouse_tracking` - Mouse tracking mode (default: `:none`)
  - `:size` - Explicit dimensions `{rows, cols}` (default: auto-detect)
  - `:optimize_cursor` - Use cursor movement optimization (default: `true`)

  ## Returns

  - `{:ok, state}` on success
  - `{:error, :invalid_size}` if size option is malformed
  - `{:error, :terminal_setup_failed}` if terminal configuration fails
  - `{:error, :size_detection_failed}` if auto-detect fails and no size provided

  ## Examples

      # Default initialization
      {:ok, state} = Raw.init([])

      # With explicit options
      {:ok, state} = Raw.init(
        alternate_screen: true,
        hide_cursor: true,
        mouse_tracking: :click,
        size: {24, 80}
      )
  """
  @spec init(keyword()) :: {:ok, t()} | {:error, term()}
  def init(opts \\ []) do
    # Parse options with defaults
    alternate_screen = Keyword.get(opts, :alternate_screen, true)
    hide_cursor = Keyword.get(opts, :hide_cursor, true)
    mouse_tracking = Keyword.get(opts, :mouse_tracking, :none)
    size_opt = Keyword.get(opts, :size, nil)
    optimize_cursor = Keyword.get(opts, :optimize_cursor, true)

    # Validate and get terminal size
    with {:ok, size} <- get_terminal_size(size_opt) do
      # Perform terminal setup sequence
      # Order: alternate screen -> hide cursor -> mouse tracking -> clear
      if alternate_screen do
        write_to_terminal(ANSI.enter_alternate_screen())
      end

      if hide_cursor do
        write_to_terminal(ANSI.cursor_hide())
      end

      # Skip mouse tracking on WSL/ConPTY -- mouse-off sequences are silently
      # ignored, so enabling mouse tracking leads to escape code leaks
      enable_mouse_tracking(mouse_tracking)

      # Clear screen and home cursor
      write_to_terminal(ANSI.clear_screen())
      write_to_terminal(ANSI.cursor_position(1, 1))

      # Build initial state
      state = %__MODULE__{
        size: size,
        cursor_visible: not hide_cursor,
        cursor_position: {1, 1},
        alternate_screen: alternate_screen,
        mouse_mode: mouse_tracking,
        current_style: nil,
        optimize_cursor: optimize_cursor
      }

      {:ok, state}
    end
  end

  defp enable_mouse_tracking(mouse_tracking) do
    if mouse_tracking != :none and not TerminalOutput.needs_hard_reset?() do
      ansi_mode = mouse_mode_to_ansi(mouse_tracking)

      if ansi_mode do
        write_to_terminal(ANSI.enable_mouse_tracking(ansi_mode))
        write_to_terminal(ANSI.enable_sgr_mouse())
      end
    end
  end

  @impl true
  @doc """
  Shuts down the backend and restores terminal state.

  Performs cleanup in order: disable mouse, show cursor, reset attributes,
  leave alternate screen, return to cooked mode.

  ## Error Safety

  This function is designed to be error-safe:
  - Each cleanup step is wrapped in try/rescue
  - Individual failures are logged but don't prevent subsequent steps
  - Always returns `:ok` regardless of individual step failures
  - Idempotent: safe to call multiple times

  ## Cleanup Sequence

  1. Disable mouse tracking (if enabled)
  2. Show cursor (ANSI: `ESC[?25h`)
  3. Reset all text attributes (ANSI: `ESC[0m`)
  4. Leave alternate screen (ANSI: `ESC[?1049l`)
  5. Return to cooked mode via `:shell.start_interactive({:noshell, :cooked})`
  """
  @spec shutdown(t()) :: :ok
  def shutdown(state) do
    # Phase 1: Direct-to-TTY write (most reliable, bypasses Erlang IO)
    TerminalOutput.write_to_tty(TerminalOutput.cleanup_sequence())

    # Phase 2: Erlang IO backup (in case /dev/tty write failed)
    safe_write(@all_mouse_off)
    safe_write(ANSI.cursor_show())
    safe_write(ANSI.reset())

    if state.alternate_screen do
      safe_write(ANSI.leave_alternate_screen())
    end

    # Phase 3: Drain pending input (mouse events buffered during shutdown)
    drain_pending_input()

    # Phase 4: Return to cooked mode
    safe_cooked_mode()

    :ok
  end

  @impl true
  @doc """
  Returns the current terminal dimensions.

  Returns the cached size from state as `{rows, cols}`. This does not
  re-query the terminal - it returns the dimensions captured at `init/1`
  or last updated by `refresh_size/1`.

  ## Return Value

  - `{:ok, {rows, cols}}` - Terminal dimensions (rows first, then columns)

  ## Examples

      {:ok, {24, 80}} = Raw.size(state)  # Standard 80x24 terminal
      {:ok, {50, 120}} = Raw.size(state) # Larger terminal

  ## See Also

  - `refresh_size/1` - Re-query terminal dimensions (call after SIGWINCH)
  - `init/1` - Initial size detection
  """
  # Note: The error case `{:error, :enotsup}` is included in the typespec for future-proofing
  # and consistency with the Backend behaviour, even though this implementation always returns
  # the cached size. A future backend might need to report unsupported size queries.
  @spec size(t()) :: {:ok, TermUI.Backend.size()}
  def size(state) do
    {:ok, state.size}
  end

  @doc """
  Re-queries terminal dimensions and updates state.

  This function queries the terminal for its current size using `:io.rows/0`
  and `:io.columns/0`, then updates the cached size in state. It should be
  called after receiving a SIGWINCH signal to handle terminal resize events.

  ## Return Value

  - `{:ok, {rows, cols}, updated_state}` - New dimensions and updated state
  - `{:error, :size_detection_failed}` - Failed to query terminal dimensions

  ## SIGWINCH Handling

  Terminal resize events are delivered via SIGWINCH. Your application should:

  1. Register a signal handler for SIGWINCH
  2. Call `refresh_size/1` when the signal is received
  3. Trigger a re-render with the new dimensions

  Example integration:

      def handle_info({:signal, :sigwinch}, state) do
        case Raw.refresh_size(state.backend_state) do
          {:ok, new_size, new_backend_state} ->
            # Update state and trigger re-render
            {:noreply, %{state | backend_state: new_backend_state, size: new_size}}
          {:error, _reason} ->
            # Keep existing size
            {:noreply, state}
        end
      end

  ## Size Detection

  Uses the same detection logic as `init/1`:
  1. Query `:io.rows/0` and `:io.columns/0`
  2. Fall back to LINES and COLUMNS environment variables
  3. Return error if all methods fail

  ## See Also

  - `size/1` - Return cached dimensions without re-querying
  - `init/1` - Initial size detection during initialization
  """
  @spec refresh_size(t()) :: {:ok, TermUI.Backend.size(), t()} | {:error, :size_detection_failed}
  def refresh_size(state) do
    case get_terminal_size(nil) do
      {:ok, new_size} ->
        {:ok, new_size, %{state | size: new_size}}

      {:error, _reason} ->
        {:error, :size_detection_failed}
    end
  end

  @impl true
  @doc """
  Moves the cursor to the specified position.

  Position is 1-indexed: `{1, 1}` is the top-left corner.

  ## Cursor Optimization

  When `optimize_cursor: true` (default), this function uses `CursorOptimizer`
  to select the cheapest movement sequence. This can reduce cursor movement
  overhead by 40%+ compared to always using absolute positioning.

  Movement options considered:
  - Absolute positioning: `ESC[{row};{col}H` (6-10 bytes)
  - Relative moves: up/down/left/right (3-6 bytes)
  - Carriage return + vertical (1 + 3-6 bytes)
  - Home position: `ESC[H` (3 bytes)
  - Literal spaces for small rightward moves (1 byte each)

  ## Position Validation

  Positions must have positive integer coordinates. This function does NOT
  validate positions against terminal bounds - positions beyond the terminal
  dimensions are accepted and recorded in state. Most terminals silently clamp
  out-of-bounds positions, which may cause state-reality divergence.

  **Callers should validate positions before calling** using `valid_position?/2`:

      if Raw.valid_position?(state, position) do
        Raw.move_cursor(state, position)
      else
        {:error, :out_of_bounds}
      end

  This design allows the renderer layer to handle bounds checking appropriately
  for its use case (e.g., scrolling, wrapping, or clamping).

  ## See Also

  - `hide_cursor/1` - Hide cursor during rendering
  - `show_cursor/1` - Show cursor after rendering
  - `valid_position?/2` - Check if position is within terminal bounds

  ## Examples

      {:ok, state} = Raw.move_cursor(state, {1, 1})   # Top-left
      {:ok, state} = Raw.move_cursor(state, {24, 80}) # Bottom-right (80x24)
  """
  @spec move_cursor(t(), TermUI.Backend.position()) :: {:ok, t()}
  def move_cursor(state, {row, col} = position)
      when is_integer(row) and is_integer(col) and row > 0 and col > 0 do
    # Generate movement sequence (optimized or absolute based on state)
    sequence = generate_cursor_sequence(state, row, col)
    write_to_terminal(sequence)

    # Update state with new cursor position
    updated_state = %{state | cursor_position: position}

    {:ok, updated_state}
  end

  # Generates cursor movement sequence, using optimization when enabled.
  # Clauses ordered from most specific to general:
  # 1. Optimization disabled - always absolute (most restrictive)
  # 2. No previous position - absolute (can't optimize without from position)
  # 3. Optimization enabled with position - use optimizer
  @spec generate_cursor_sequence(t(), pos_integer(), pos_integer()) :: iodata()
  defp generate_cursor_sequence(%__MODULE__{optimize_cursor: false}, row, col) do
    # Optimization disabled - always use absolute positioning
    ANSI.cursor_position(row, col)
  end

  defp generate_cursor_sequence(%__MODULE__{cursor_position: nil}, row, col) do
    # No previous position known - use absolute positioning
    # (applies regardless of optimize_cursor setting)
    ANSI.cursor_position(row, col)
  end

  defp generate_cursor_sequence(
         %__MODULE__{optimize_cursor: true, cursor_position: {from_row, from_col}},
         to_row,
         to_col
       ) do
    # Use optimizer to find cheapest movement, with error recovery
    # Only catch expected exceptions, not system-level errors
    {sequence, _cost} = CursorOptimizer.optimal_move(from_row, from_col, to_row, to_col)
    sequence
  rescue
    e in [ArgumentError, ArithmeticError, FunctionClauseError] ->
      # Fall back to absolute positioning if optimizer fails
      Logger.warning(
        "CursorOptimizer failed (#{Exception.message(e)}), falling back to absolute positioning: from #{inspect({from_row, from_col})} to #{inspect({to_row, to_col})}"
      )

      ANSI.cursor_position(to_row, to_col)
  end

  @impl true
  @doc """
  Hides the terminal cursor.

  Uses ANSI sequence `ESC[?25l` (DECTCEM off).

  ## Idempotent Behavior

  This operation is idempotent. When the cursor is already hidden:
  - No escape sequence is written to the terminal
  - The exact same state object is returned unchanged
  - Callers cannot distinguish a no-op from an actual state change

  This design prevents redundant ANSI writes and allows callers to call
  without tracking current visibility state.

  ## See Also

  - `show_cursor/1` - Show the cursor
  - `move_cursor/2` - Move cursor to position
  """
  @spec hide_cursor(t()) :: {:ok, t()}
  def hide_cursor(%__MODULE__{cursor_visible: false} = state) do
    # Already hidden - idempotent no-op
    {:ok, state}
  end

  def hide_cursor(state) do
    # Write hide cursor sequence
    write_to_terminal(ANSI.cursor_hide())

    # Update state
    updated_state = %{state | cursor_visible: false}

    {:ok, updated_state}
  end

  @impl true
  @doc """
  Shows the terminal cursor.

  Uses ANSI sequence `ESC[?25h` (DECTCEM on).

  ## Idempotent Behavior

  This operation is idempotent. When the cursor is already visible:
  - No escape sequence is written to the terminal
  - The exact same state object is returned unchanged
  - Callers cannot distinguish a no-op from an actual state change

  This design prevents redundant ANSI writes and allows callers to call
  without tracking current visibility state.

  ## See Also

  - `hide_cursor/1` - Hide the cursor
  - `move_cursor/2` - Move cursor to position
  """
  @spec show_cursor(t()) :: {:ok, t()}
  def show_cursor(%__MODULE__{cursor_visible: true} = state) do
    # Already visible - idempotent no-op
    {:ok, state}
  end

  def show_cursor(state) do
    # Write show cursor sequence
    write_to_terminal(ANSI.cursor_show())

    # Update state
    updated_state = %{state | cursor_visible: true}

    {:ok, updated_state}
  end

  @impl true
  @doc """
  Clears the entire screen and moves cursor to home position.

  Uses ANSI sequences:
  - `ESC[2J` - ED (Erase Display) parameter 2: clear entire screen
  - `ESC[1;1H` - CUP (Cursor Position): move to row 1, column 1

  ## State Changes

  After clear:
  - `cursor_position` is set to `{1, 1}` (home position)
  - `current_style` is reset to `nil` (terminal style state is unknown after clear)

  All other state fields are preserved.

  ## Idempotency

  This operation is idempotent - calling `clear/1` multiple times in succession
  is safe and will result in the same state each time.

  ## Examples

      {:ok, state} = Raw.init(size: {24, 80})
      {:ok, moved} = Raw.move_cursor(state, {10, 20})
      {:ok, cleared} = Raw.clear(moved)

      cleared.cursor_position  # => {1, 1}
      cleared.current_style    # => nil

  ## See Also

  - `move_cursor/2` - Move cursor to specific position
  - `draw_cells/2` - Draw content to screen
  """
  @spec clear(t()) :: {:ok, t()}
  def clear(state) do
    # Write clear screen sequence followed by cursor home
    write_to_terminal([ANSI.clear_screen(), ANSI.cursor_position(1, 1)])

    # Reset style state (unknown after clear) and set cursor to home
    updated_state = %{state | current_style: nil, cursor_position: {1, 1}}

    {:ok, updated_state}
  end

  @impl true
  @doc """
  Draws cells to the terminal at specified positions.

  Cells are rendered with optimized cursor movement and style delta tracking
  to minimize escape sequence output. See the "Style Delta Optimization" section
  in the module documentation for details on how this works.

  ## Cell Format

  Each cell is a tuple `{position, cell_data}` where:
  - `position` is `{row, col}` (1-indexed)
  - `cell_data` is `{char, fg, bg, attrs}`

  ## Performance

  This function uses several optimizations:
  - Style delta tracking (only emit changed attributes)
  - Relative cursor movement when cheaper than absolute
  - Batched I/O writes

  ## Examples

      # Draw a single red "A" at position {1, 1}
      cells = [{{1, 1}, {"A", :red, :default, []}}]
      {:ok, state} = Raw.draw_cells(state, cells)

      # Draw multiple cells with different styles
      cells = [
        {{1, 1}, {"H", :green, :default, [:bold]}},
        {{1, 2}, {"i", :green, :default, [:bold]}},
        {{2, 1}, {"!", :yellow, :blue, []}}
      ]
      {:ok, state} = Raw.draw_cells(state, cells)
  """
  @spec draw_cells(t(), [{TermUI.Backend.position(), TermUI.Backend.cell()}]) :: {:ok, t()}
  def draw_cells(state, []) do
    # Empty list - no-op
    {:ok, state}
  end

  def draw_cells(state, cells) when is_list(cells) do
    # Sort cells in row-major order, then by column within each row
    sorted_cells =
      Enum.sort_by(cells, fn {{row, col}, _cell} -> {row, col} end)

    # Split into contiguous runs and render each with a single cursor position
    runs = detect_runs(sorted_cells)

    {output, final_pos, final_style} =
      render_runs(runs, state.cursor_position, state.current_style)

    # Write batched output to terminal
    write_to_terminal(output)

    # Update state with final cursor position and style
    updated_state = %{state | cursor_position: final_pos, current_style: final_style}

    {:ok, updated_state}
  end

  # Detects contiguous runs of cells: same row with consecutive columns.
  # Returns a list of runs, where each run is a non-empty list of cells
  # that can be rendered with a single cursor positioning.
  defp detect_runs([]), do: []

  defp detect_runs([first | rest]) do
    {current_run, runs} =
      Enum.reduce(rest, {[first], []}, fn {{row, col}, _cell_data} = cell,
                                          {current_run, completed_runs} ->
        # Get the last cell in the current run to check adjacency
        [{{prev_row, prev_col}, _} | _] = current_run

        if row == prev_row and col == prev_col + 1 do
          # Adjacent: extend current run (prepend for efficiency, reversed later)
          {[cell | current_run], completed_runs}
        else
          # Gap or new row: finalize current run, start new one
          {[cell], [Enum.reverse(current_run) | completed_runs]}
        end
      end)

    # Don't forget the final run
    Enum.reverse([Enum.reverse(current_run) | runs])
  end

  # Renders a list of runs into an iolist. Each run gets one cursor position
  # at its start, then streams characters with inline style deltas only when
  # the style changes. Style state is tracked continuously across runs (no
  # per-row resets).
  defp render_runs(runs, initial_pos, initial_style) do
    Enum.reduce(runs, {[], initial_pos, initial_style}, fn run, {output_acc, cursor_pos, style} ->
      {run_output, run_end_pos, run_end_style} =
        render_single_run(run, cursor_pos, style)

      {[output_acc, run_output], run_end_pos, run_end_style}
    end)
  end

  # Renders a single contiguous run. Emits one cursor position at the start,
  # then for each cell: style delta (if changed) + character.
  defp render_single_run([{{row, col}, _} | _] = run, cursor_pos, style) do
    # Position cursor at run start
    cursor_output = cursor_move_output(cursor_pos, {row, col})

    # Stream characters with inline style changes
    {chars_output, end_col, end_style} =
      Enum.reduce(run, {[], col, style}, fn {{_row, _col}, {char, fg, bg, attrs}},
                                            {out_acc, cur_col, cur_style} ->
        new_style = %{fg: fg, bg: bg, attrs: normalize_attrs(attrs)}
        style_output = style_delta_output(cur_style, new_style)

        {[out_acc, style_output, char], cur_col + 1, new_style}
      end)

    {[cursor_output, chars_output], {row, end_col}, end_style}
  end

  # Normalizes attributes to a sorted list for consistent comparison.
  #
  # Accepts both list and MapSet input formats to support:
  # - Direct cell tuples from Backend.cell() which use lists
  # - Internal Cell struct which uses MapSet for attributes
  #
  # Sorting ensures consistent comparison regardless of input order,
  # enabling reliable style delta detection.
  @spec normalize_attrs([atom()] | MapSet.t()) :: [atom()]
  defp normalize_attrs(attrs) when is_list(attrs), do: Enum.sort(attrs)
  defp normalize_attrs(%MapSet{} = attrs), do: attrs |> MapSet.to_list() |> Enum.sort()

  # Generates cursor movement escape sequence if position has changed.
  #
  # Returns empty iolist if no move needed (cursor already at target position).
  # Uses absolute positioning for all moves.
  #
  # Note on cursor advancement: After writing a character, the cursor automatically
  # advances one column. This function assumes single-width characters. Multi-width
  # characters (CJK, emoji) would require grapheme width tracking - a future enhancement.
  #
  # Note: Using CursorOptimizer could provide ~40% byte savings on cursor movement.
  # Current absolute positioning is simple and correct but not optimal.
  # See move_cursor/2 for example of CursorOptimizer integration.
  @spec cursor_move_output({pos_integer(), pos_integer()} | nil, {pos_integer(), pos_integer()}) ::
          iolist()
  defp cursor_move_output(nil, {row, col}) do
    # No previous position known - must use absolute
    ANSI.cursor_position(row, col)
  end

  defp cursor_move_output({cur_row, cur_col}, {target_row, target_col})
       when cur_row == target_row and cur_col == target_col do
    # Already at target position - no move needed
    []
  end

  defp cursor_move_output({_cur_row, _cur_col}, {target_row, target_col}) do
    # Need to move cursor - use absolute positioning
    ANSI.cursor_position(target_row, target_col)
  end

  # Generates style delta escape sequences - only emits what has changed.
  #
  # Style delta optimization reduces escape sequence output by 80-90% for typical
  # UIs where adjacent cells share styles. Instead of emitting full style for every
  # cell, we only emit changes from the previous style.
  #
  # When attributes are removed (e.g., transitioning from [:bold, :italic] to [:bold]),
  # we must reset with ESC[0m and rebuild the full style, since ANSI doesn't have
  # efficient individual attribute removal for all attributes.
  #
  # Note: This uses ANSI module for sequence generation. For parameter-level SGR
  # operations (e.g., combining into single sequence), see TermUI.SGR module.
  @spec style_delta_output(style_state() | nil, style_state()) :: iolist()
  defp style_delta_output(nil, new_style) do
    # No previous style - emit full style
    build_full_style(new_style)
  end

  defp style_delta_output(current_style, new_style) when current_style == new_style do
    # Styles are identical - no output needed
    []
  end

  defp style_delta_output(current_style, new_style) do
    # Check if we need a full reset (removing attributes is complex)
    # Strategy: if new style has fewer or different attrs, reset and rebuild
    current_attrs = MapSet.new(current_style.attrs)
    new_attrs = MapSet.new(new_style.attrs)

    # Attributes being removed require a reset
    removed_attrs = MapSet.difference(current_attrs, new_attrs)

    if MapSet.size(removed_attrs) > 0 do
      # Reset and apply full new style
      [ANSI.reset(), build_full_style(new_style)]
    else
      # Build delta - only add new attributes and changed colors
      build_style_delta(current_style, new_style)
    end
  end

  # Builds a complete style sequence from scratch.
  #
  # Used when:
  # 1. First cell being rendered (no previous style)
  # 2. After a style reset when attributes were removed
  #
  # Generates escape sequences for foreground color, background color, and all
  # text attributes in that order.
  @spec build_full_style(style_state()) :: iolist()
  defp build_full_style(%{fg: fg, bg: bg, attrs: attrs}) do
    [
      color_sequence(:fg, fg),
      color_sequence(:bg, bg),
      attr_sequences(attrs)
    ]
  end

  # Builds style delta - only emits escape sequences for changes.
  #
  # Compares current and new styles, emitting only:
  # - Foreground color sequence if fg changed
  # - Background color sequence if bg changed
  # - Attribute sequences for newly added attributes
  #
  # Note: This function is only called when no attributes were removed
  # (removal requires full reset, handled by style_delta_output/2).
  @spec build_style_delta(style_state(), style_state()) :: iolist()
  defp build_style_delta(current, new) do
    fg_output = if current.fg != new.fg, do: color_sequence(:fg, new.fg), else: []
    bg_output = if current.bg != new.bg, do: color_sequence(:bg, new.bg), else: []

    # New attributes that weren't in current
    new_attr_set = MapSet.new(new.attrs)
    current_attr_set = MapSet.new(current.attrs)
    added_attrs = MapSet.difference(new_attr_set, current_attr_set) |> MapSet.to_list()
    attr_output = attr_sequences(added_attrs)

    [fg_output, bg_output, attr_output]
  end

  # Generate color sequence for foreground or background
  defp color_sequence(:fg, :default), do: ["\e[39m"]
  defp color_sequence(:bg, :default), do: ["\e[49m"]

  defp color_sequence(:fg, {r, g, b}) when is_integer(r) and is_integer(g) and is_integer(b) do
    ANSI.foreground_rgb(r, g, b)
  end

  defp color_sequence(:bg, {r, g, b}) when is_integer(r) and is_integer(g) and is_integer(b) do
    ANSI.background_rgb(r, g, b)
  end

  defp color_sequence(:fg, index) when is_integer(index) and index >= 0 and index <= 255 do
    ANSI.foreground_256(index)
  end

  defp color_sequence(:bg, index) when is_integer(index) and index >= 0 and index <= 255 do
    ANSI.background_256(index)
  end

  defp color_sequence(:fg, color) when is_atom(color) do
    ANSI.foreground(color)
  end

  defp color_sequence(:bg, color) when is_atom(color) do
    ANSI.background(color)
  end

  # Catch-all for invalid colors - log warning and return empty sequence
  defp color_sequence(:fg, unknown) do
    Logger.warning("Unknown foreground color: #{inspect(unknown)}")
    []
  end

  defp color_sequence(:bg, unknown) do
    Logger.warning("Unknown background color: #{inspect(unknown)}")
    []
  end

  # Generate attribute sequences
  defp attr_sequences([]), do: []

  defp attr_sequences(attrs) when is_list(attrs) do
    Enum.map(attrs, &attr_sequence/1)
  end

  defp attr_sequence(:bold), do: ANSI.bold()
  defp attr_sequence(:dim), do: ANSI.dim()
  defp attr_sequence(:italic), do: ANSI.italic()
  defp attr_sequence(:underline), do: ANSI.underline()
  defp attr_sequence(:blink), do: ANSI.blink()
  defp attr_sequence(:reverse), do: ANSI.reverse()
  defp attr_sequence(:hidden), do: ANSI.hidden()
  defp attr_sequence(:strikethrough), do: ANSI.strikethrough()
  defp attr_sequence(_unknown), do: []

  @impl true
  @doc """
  Flushes pending output to the terminal.

  For the Raw backend, this is a no-op because `IO.write/1` is synchronous -
  output is written directly to the terminal without buffering. The callback
  exists for API completeness and compatibility with backends that may use
  buffered I/O.

  This function is idempotent and safe to call multiple times.

  ## Returns

  - `{:ok, state}` - Always succeeds, returning state unchanged
  """
  @spec flush(t()) :: {:ok, t()}
  def flush(state) do
    # IO.write/1 is synchronous in Erlang/OTP - no buffering to flush.
    # For backends with buffered output, this would call :erlang.port_command/3
    # with the :nosuspend option or similar synchronization mechanism.
    {:ok, state}
  end

  # ===========================================================================
  # Mouse Tracking
  # ===========================================================================

  @doc """
  Enables mouse tracking with the specified mode.

  Changes the mouse tracking mode, enabling detection of mouse events.
  This function can be called after initialization to change the tracking mode.

  ## Parameters

  - `state` - Current backend state
  - `mode` - Mouse tracking mode:
    - `:click` - Track button press/release only (ANSI "normal" mode, 1000)
    - `:drag` - Track clicks and motion while button pressed (ANSI "button" mode, 1002)
    - `:all` - Track all mouse movement (ANSI "any" mode, 1003)

  ## Escape Sequences

  This function emits:
  1. The appropriate mouse tracking mode sequence:
     - `:click` → `ESC[?1000h`
     - `:drag` → `ESC[?1002h`
     - `:all` → `ESC[?1003h`
  2. SGR extended mode (`ESC[?1006h`) for accurate coordinate encoding

  ## Idempotent Behavior

  If the requested mode matches the current mode, no escape sequences are
  written and the same state is returned.

  ## Returns

  - `{:ok, updated_state}` with `mouse_mode` set to the new mode

  ## Examples

      # Enable click tracking
      {:ok, state} = Raw.enable_mouse(state, :click)

      # Enable all movement tracking
      {:ok, state} = Raw.enable_mouse(state, :all)

  ## See Also

  - `disable_mouse/1` - Disable mouse tracking
  - `init/1` - Can set initial mouse tracking mode via `:mouse_tracking` option
  """
  @spec enable_mouse(t(), :click | :drag | :all) :: {:ok, t()}
  def enable_mouse(%__MODULE__{mouse_mode: mode} = state, mode) do
    # Already in requested mode - idempotent no-op
    {:ok, state}
  end

  def enable_mouse(state, mode) when mode in [:click, :drag, :all] do
    # Skip mouse tracking on WSL/ConPTY
    if TerminalOutput.needs_hard_reset?() do
      {:ok, state}
    else
      # Disable current mode if active (to avoid stacking modes)
      if state.mouse_mode != :none do
        disable_current_mouse_mode(state.mouse_mode)
      end

      # Enable new mode
      ansi_mode = mouse_mode_to_ansi(mode)
      write_to_terminal(ANSI.enable_mouse_tracking(ansi_mode))
      write_to_terminal(ANSI.enable_sgr_mouse())

      {:ok, %{state | mouse_mode: mode}}
    end
  end

  @doc """
  Disables mouse tracking.

  Turns off mouse event reporting, returning the terminal to normal operation
  where mouse actions are not reported to the application.

  ## Escape Sequences

  This function emits:
  1. Disable SGR extended mode (`ESC[?1006l`)
  2. Disable the current tracking mode:
     - `:click` → `ESC[?1000l`
     - `:drag` → `ESC[?1002l`
     - `:all` → `ESC[?1003l`

  ## Idempotent Behavior

  If mouse tracking is already disabled (`:none`), no escape sequences are
  written and the same state is returned.

  ## Returns

  - `{:ok, updated_state}` with `mouse_mode` set to `:none`

  ## Examples

      # Disable after enabling
      {:ok, state} = Raw.enable_mouse(state, :click)
      {:ok, state} = Raw.disable_mouse(state)
      state.mouse_mode  # => :none

      # Idempotent - safe to call when already disabled
      {:ok, same_state} = Raw.disable_mouse(state)

  ## See Also

  - `enable_mouse/2` - Enable mouse tracking
  - `shutdown/1` - Automatically disables mouse tracking during cleanup
  """
  @spec disable_mouse(t()) :: {:ok, t()}
  def disable_mouse(%__MODULE__{mouse_mode: :none} = state) do
    # Already disabled - idempotent no-op
    {:ok, state}
  end

  def disable_mouse(state) do
    # Disable SGR mode first
    write_to_terminal(ANSI.disable_sgr_mouse())

    # Disable the current tracking mode
    ansi_mode = mouse_mode_to_ansi(state.mouse_mode)

    if ansi_mode do
      write_to_terminal(ANSI.disable_mouse_tracking(ansi_mode))
    end

    {:ok, %{state | mouse_mode: :none}}
  end

  @impl true
  @doc """
  Polls for input events with the specified timeout.

  In raw mode, input arrives character-by-character enabling real-time
  keyboard and mouse event handling. This function uses the `EscapeParser`
  module to parse escape sequences into `TermUI.Event` structs.

  ## Parameters

  - `state` - Current backend state
  - `timeout` - Milliseconds to wait (0 for non-blocking)

  ## Returns

  - `{:ok, event, state}` - Event received and parsed
  - `{:timeout, state}` - No input within timeout period
  - `{:error, reason, state}` - Terminal I/O error occurred

  ## Escape Sequence Handling

  Some sequences are ambiguous (ESC alone vs ESC followed by another key).
  The function buffers partial sequences and uses the timeout to disambiguate.
  If the buffer contains a partial escape sequence and the timeout expires,
  the escape key is emitted and remaining bytes are re-parsed.

  ## Examples

      # Non-blocking poll (timeout = 0)
      {:timeout, state} = Raw.poll_event(state, 0)

      # Block up to 100ms for input
      case Raw.poll_event(state, 100) do
        {:ok, %Event.Key{key: :enter}, state} -> handle_enter(state)
        {:ok, %Event.Mouse{action: :click}, state} -> handle_click(state)
        {:timeout, state} -> handle_idle(state)
      end
  """
  @spec poll_event(t(), non_neg_integer()) ::
          {:ok, TermUI.Backend.event(), t()}
          | {:timeout, t()}
          | {:error, term(), t()}
  def poll_event(state, timeout) do
    # First, try to parse any buffered input
    case try_parse_buffer(state) do
      {:ok, event, new_state} ->
        {:ok, event, new_state}

      {:need_more, state} ->
        # Try to read more input with timeout
        read_input_with_timeout(state, timeout)
    end
  end

  # Attempts to parse an event from the current buffer or event queue.
  # Returns {:ok, event, state} if a complete event is available,
  # or {:need_more, state} if more input is needed.
  @spec try_parse_buffer(t()) :: {:ok, TermUI.Backend.event(), t()} | {:need_more, t()}
  defp try_parse_buffer(%{event_queue: [event | rest]} = state) do
    # Return queued event first
    {:ok, event, %{state | event_queue: rest}}
  end

  defp try_parse_buffer(%{input_buffer: <<>>, event_queue: []} = state) do
    {:need_more, state}
  end

  defp try_parse_buffer(%{input_buffer: buffer, event_queue: []} = state) do
    alias TermUI.Terminal.EscapeParser

    case EscapeParser.parse(buffer) do
      {[event], remaining} ->
        # Single event - simple case
        {:ok, event, %{state | input_buffer: remaining}}

      {[event | rest_events], remaining} ->
        # Multiple events parsed - return first, queue the rest (with size limit)
        new_state = queue_events(%{state | input_buffer: remaining}, rest_events)
        {:ok, event, new_state}

      {[], remaining} when remaining != <<>> ->
        # Partial sequence - check if it's a potential escape sequence
        if EscapeParser.partial_sequence?(remaining) do
          {:need_more, %{state | input_buffer: remaining}}
        else
          # Unknown data - clear buffer
          {:need_more, %{state | input_buffer: <<>>}}
        end

      {[], <<>>} ->
        {:need_more, state}
    end
  end

  # Reads input from the terminal with a timeout.
  # Uses a Task to avoid blocking indefinitely on IO.getn/2.
  @spec read_input_with_timeout(t(), non_neg_integer()) ::
          {:ok, TermUI.Backend.event(), t()} | {:timeout, t()} | {:error, term(), t()}
  defp read_input_with_timeout(state, timeout) do
    alias TermUI.Event
    alias TermUI.Terminal.EscapeParser

    # For zero timeout, just check if there's input ready
    # Unfortunately, IO.getn blocks, so we use a Task with timeout
    task = Task.async(fn -> read_one_byte() end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, data}} ->
        # Got input - add to buffer and try to parse (with size limit)
        new_state = append_to_input_buffer(state, data)
        try_parse_or_continue(new_state, timeout)

      {:ok, :eof} ->
        {:error, :eof, state}

      {:ok, {:error, reason}} ->
        {:error, reason, state}

      nil ->
        # Timeout - if we have a partial escape sequence, handle it
        handle_timeout(state)
    end
  end

  # After reading new input, try to parse it. If we get a partial sequence,
  # continue reading with remaining timeout (simplified: just try once more).
  @spec try_parse_or_continue(t(), non_neg_integer()) ::
          {:ok, TermUI.Backend.event(), t()} | {:timeout, t()} | {:error, term(), t()}
  defp try_parse_or_continue(state, _timeout) do
    alias TermUI.Event
    alias TermUI.Terminal.EscapeParser

    buffer = state.input_buffer

    case EscapeParser.parse(buffer) do
      {[event | _rest], remaining} ->
        {:ok, event, %{state | input_buffer: remaining}}

      {[], remaining} when remaining != <<>> ->
        # Partial sequence - for escape sequences, use a short timeout
        if EscapeParser.partial_sequence?(remaining) do
          # Wait a bit more for the rest of the escape sequence
          wait_for_escape_completion(state, remaining)
        else
          {:timeout, %{state | input_buffer: remaining}}
        end

      {[], <<>>} ->
        {:timeout, state}
    end
  end

  # Short timeout to wait for escape sequence completion.
  @escape_timeout 50

  @spec wait_for_escape_completion(t(), binary()) ::
          {:ok, TermUI.Backend.event(), t()} | {:timeout, t()} | {:error, term(), t()}
  defp wait_for_escape_completion(state, buffer) do
    alias TermUI.Event
    alias TermUI.Terminal.EscapeParser

    task = Task.async(fn -> read_one_byte() end)

    case Task.yield(task, @escape_timeout) || Task.shutdown(task) do
      {:ok, {:ok, data}} ->
        # Got more data - try to parse again
        new_buffer = buffer <> data
        handle_parse_result(EscapeParser.parse(new_buffer), state, new_buffer)

      {:ok, :eof} ->
        # EOF during escape sequence - emit what we have
        emit_partial_escape(state, buffer)

      {:ok, {:error, _reason}} ->
        emit_partial_escape(state, buffer)

      nil ->
        # Timeout - emit partial escape sequence
        emit_partial_escape(state, buffer)
    end
  end

  # Handles the result of parsing escape sequence data.
  defp handle_parse_result({[event | _], remaining}, state, _buffer) do
    {:ok, event, %{state | input_buffer: remaining}}
  end

  defp handle_parse_result({[], remaining}, state, _buffer) do
    alias TermUI.Terminal.EscapeParser

    if EscapeParser.partial_sequence?(remaining) do
      wait_for_escape_completion(state, remaining)
    else
      {:timeout, %{state | input_buffer: remaining}}
    end
  end

  # Handles timeout when we have a partial escape sequence.
  @spec handle_timeout(t()) :: {:timeout, t()} | {:ok, TermUI.Backend.event(), t()}
  defp handle_timeout(%{input_buffer: <<>>} = state) do
    {:timeout, state}
  end

  defp handle_timeout(%{input_buffer: buffer} = state) do
    alias TermUI.Terminal.EscapeParser

    if EscapeParser.partial_sequence?(buffer) do
      emit_partial_escape(state, buffer)
    else
      {:timeout, state}
    end
  end

  # Emits events from a partial escape sequence (timeout disambiguation).
  @spec emit_partial_escape(t(), binary()) :: {:ok, TermUI.Backend.event(), t()}
  defp emit_partial_escape(state, buffer) do
    alias TermUI.Event

    # Handle known partial sequences
    case buffer do
      # Lone ESC
      <<0x1B>> ->
        {:ok, Event.key(:escape), %{state | input_buffer: <<>>}}

      # ESC[ without terminator - emit ESC, keep [ for next parse
      <<0x1B, ?[>> ->
        {:ok, Event.key(:escape), %{state | input_buffer: "["}}

      # ESC O without terminator
      <<0x1B, ?O>> ->
        {:ok, Event.key(:escape), %{state | input_buffer: "O"}}

      # Other partial sequences starting with ESC
      <<0x1B, rest::binary>> ->
        {:ok, Event.key(:escape), %{state | input_buffer: rest}}

      # Non-escape partial - just clear buffer
      _ ->
        {:timeout, %{state | input_buffer: <<>>}}
    end
  end

  # Reads one byte from stdin.
  @spec read_one_byte() :: {:ok, binary()} | :eof | {:error, term()}
  defp read_one_byte do
    case IO.getn("", 1) do
      :eof -> :eof
      {:error, reason} -> {:error, reason}
      data when is_binary(data) -> {:ok, data}
    end
  end

  # ===========================================================================
  # Helper Functions
  # ===========================================================================

  @doc """
  Checks if a position is valid within the terminal bounds.

  Returns `true` if the position has positive coordinates and is within
  the terminal dimensions stored in state.

  ## Examples

      iex> state = %Raw{size: {24, 80}}
      iex> Raw.valid_position?(state, {1, 1})
      true
      iex> Raw.valid_position?(state, {24, 80})
      true
      iex> Raw.valid_position?(state, {25, 1})
      false
      iex> Raw.valid_position?(state, {0, 1})
      false
  """
  @spec valid_position?(t(), {integer(), integer()}) :: boolean()
  def valid_position?(%__MODULE__{size: {max_rows, max_cols}}, {row, col})
      when is_integer(row) and is_integer(col) do
    row > 0 and col > 0 and row <= max_rows and col <= max_cols
  end

  def valid_position?(_state, _position), do: false

  @doc """
  Maps a Raw backend mouse mode to the corresponding ANSI protocol mode.

  This is used internally when emitting mouse tracking escape sequences.

  ## Examples

      iex> Raw.mouse_mode_to_ansi(:click)
      :normal
      iex> Raw.mouse_mode_to_ansi(:drag)
      :button
      iex> Raw.mouse_mode_to_ansi(:all)
      :all
  """
  @spec mouse_mode_to_ansi(mouse_mode()) :: :normal | :button | :all | nil
  def mouse_mode_to_ansi(:none), do: nil
  def mouse_mode_to_ansi(:click), do: :normal
  def mouse_mode_to_ansi(:drag), do: :button
  def mouse_mode_to_ansi(:all), do: :all

  # Provides access to the ANSI module for escape sequence generation
  @doc false
  def ansi_module, do: ANSI

  # ===========================================================================
  # Private Functions
  # ===========================================================================

  # Gets terminal size from explicit option or auto-detection.
  # Delegates to SizeDetector for consistent detection across backends.
  @spec get_terminal_size({pos_integer(), pos_integer()} | nil) ::
          {:ok, {pos_integer(), pos_integer()}} | {:error, term()}
  defp get_terminal_size(size_opt) do
    SizeDetector.detect(size: size_opt)
  end

  # Appends data to the input buffer with size limit protection.
  # Uses the shared InputBuffer module for rate-limited logging.
  @spec append_to_input_buffer(t(), binary()) :: t()
  defp append_to_input_buffer(state, data) do
    InputBuffer.append_with_limit(state, data, :input_buffer, source: __MODULE__)
  end

  # Queues events with size limit protection.
  # If the queue exceeds @max_event_queue_size, drops oldest events.
  # This prevents memory exhaustion when events are parsed faster than consumed.
  # Dropped events are counted in the events_dropped field for monitoring.
  @spec queue_events(t(), [TermUI.Backend.event()]) :: t()
  defp queue_events(state, []), do: state

  defp queue_events(state, new_events) do
    combined = state.event_queue ++ new_events
    queue_size = length(combined)

    if queue_size > @max_event_queue_size do
      # Keep newest events, drop oldest
      to_drop = queue_size - @max_event_queue_size
      new_total_dropped = state.events_dropped + to_drop

      # Only log on first drop to prevent log flooding
      if state.events_dropped == 0 do
        Logger.warning(
          "Event queue overflow (#{queue_size} events), dropping #{to_drop} oldest events"
        )
      end

      %{state | event_queue: Enum.drop(combined, to_drop), events_dropped: new_total_dropped}
    else
      %{state | event_queue: combined}
    end
  end

  # Writes data to the terminal via TerminalOutput (ONLCR-aware).
  defp write_to_terminal(data) do
    TerminalOutput.write(data)
  rescue
    e ->
      Logger.debug("Terminal write failed: #{Exception.message(e)}")
      :ok
  end

  # Error-safe write for shutdown - logs errors but continues
  defp safe_write(data) do
    TerminalOutput.write(data)
  rescue
    _ -> :ok
  end

  # Drains pending input bytes (e.g. mouse events buffered during shutdown).
  # Sets /dev/tty to non-blocking, reads and discards pending bytes, then
  # restores it. Reading :stdio here can block under pre-OTP 28 I/O servers
  # when stdin is captured or redirected, even after stty fails.
  defp drain_pending_input do
    case TermUtils.safe_stty(["min", "0", "time", "1"]) do
      {:ok, _output} ->
        try do
          drain_tty_input()
        after
          _ = TermUtils.safe_stty(["min", "1", "time", "0"])
        end

      {:error, _reason} ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp drain_tty_input do
    case File.open("/dev/tty", [:read, :binary]) do
      {:ok, tty} ->
        try do
          drain_input_loop(tty, 0, 20)
        after
          File.close(tty)
        end

      {:error, _reason} ->
        :ok
    end
  end

  defp drain_input_loop(_tty, iteration, max) when iteration >= max, do: :ok

  defp drain_input_loop(tty, iteration, max) do
    case IO.binread(tty, 64) do
      data when is_binary(data) and byte_size(data) > 0 ->
        drain_input_loop(tty, iteration + 1, max)

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  # Disables the current mouse tracking mode
  defp disable_current_mouse_mode(mode) do
    ansi_mode = mouse_mode_to_ansi(mode)

    if ansi_mode do
      write_to_terminal(ANSI.disable_mouse_tracking(ansi_mode))
    end
  end

  # Error-safe cooked mode restoration
  defp safe_cooked_mode do
    if Platform.native_raw_mode_supported?() do
      :shell.start_interactive({:noshell, :cooked})
    end
  rescue
    e in UndefinedFunctionError ->
      Logger.warning(
        "Cooked mode restoration not available (OTP 28+ required): #{Exception.message(e)}"
      )

      :ok

    e ->
      Logger.warning("Failed to restore cooked mode: #{Exception.message(e)}")
      :ok
  catch
    kind, reason ->
      Logger.warning("Failed to restore cooked mode: #{kind} - #{inspect(reason)}")
      :ok
  end
end
