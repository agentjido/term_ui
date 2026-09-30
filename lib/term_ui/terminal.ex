defmodule TermUI.Terminal do
  @moduledoc """
  Main terminal management GenServer for TermUI.

  Provides raw mode activation, alternate screen buffer management,
  terminal restoration, and size detection using OTP 28's native
  raw mode support.
  """

  use GenServer
  require Logger

  alias TermUI.ANSI
  alias TermUI.Platform
  alias TermUI.Terminal.NativeMode
  alias TermUI.Terminal.SignalHandler
  alias TermUI.Terminal.SizeDetector
  alias TermUI.Terminal.State
  alias TermUI.TerminalOutput
  alias TermUI.TermUtils

  # Dialyzer: unmatched_return, pattern_match_cov, guard_fail warnings
  @dialyzer {
    :nowarn_function,
    init: 1,
    handle_call: 3,
    handle_cast: 2,
    handle_info: 2,
    terminate: 2,
    do_restore: 1,
    io_has_terminal?: 0,
    check_tty: 0,
    apply_stty_raw_settings: 0,
    terminal?: 0,
    do_enable_raw_mode: 0
  }

  @ets_table :term_ui_terminal_state

  # Comprehensive mouse disable - disables ALL mouse modes defensively
  # This is kept as a constant for performance in cleanup paths
  @all_mouse_off "\e[?1006l\e[?1003l\e[?1002l\e[?1000l"

  # Client API

  @doc """
  Starts the Terminal GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns a child specification for starting the terminal in a supervisor.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @doc """
  Enables raw mode on the terminal.

  Calls OTP 28's `shell.start_interactive({:noshell, :raw})` and configures
  the terminal for TUI operation.

  Returns `{:ok, state}` on success or `{:error, reason}` on failure.
  """
  @spec enable_raw_mode() :: {:ok, State.t()} | {:error, term()}
  def enable_raw_mode do
    GenServer.call(__MODULE__, :enable_raw_mode)
  end

  @doc false
  @spec adopt_native_raw_mode() :: {:ok, State.t()}
  def adopt_native_raw_mode do
    GenServer.call(__MODULE__, :adopt_native_raw_mode)
  end

  @doc """
  Disables raw mode and restores original terminal settings.

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec disable_raw_mode() :: :ok | {:error, term()}
  def disable_raw_mode do
    GenServer.call(__MODULE__, :disable_raw_mode)
  end

  @doc """
  Enters the alternate screen buffer.

  The alternate screen preserves the user's shell history while the TUI runs.
  """
  @spec enter_alternate_screen() :: :ok | {:error, term()}
  def enter_alternate_screen do
    GenServer.call(__MODULE__, :enter_alternate_screen)
  end

  @doc """
  Leaves the alternate screen buffer and restores the original screen.
  """
  @spec leave_alternate_screen() :: :ok | {:error, term()}
  def leave_alternate_screen do
    GenServer.call(__MODULE__, :leave_alternate_screen)
  end

  @doc """
  Hides the cursor.
  """
  @spec hide_cursor() :: :ok
  def hide_cursor do
    GenServer.call(__MODULE__, :hide_cursor)
  end

  @doc """
  Shows the cursor.
  """
  @spec show_cursor() :: :ok
  def show_cursor do
    GenServer.call(__MODULE__, :show_cursor)
  end

  @doc """
  Gets the current terminal size.

  Returns `{:ok, {rows, cols}}` or `{:error, reason}`.
  """
  @spec get_terminal_size() :: {:ok, {pos_integer(), pos_integer()}} | {:error, term()}
  def get_terminal_size do
    GenServer.call(__MODULE__, :get_terminal_size)
  end

  @doc """
  Registers a process to receive terminal resize notifications.

  The registered process will receive `{:terminal_resize, {rows, cols}}` messages.
  """
  @spec register_resize_callback(pid()) :: :ok
  def register_resize_callback(pid \\ self()) do
    GenServer.call(__MODULE__, {:register_resize_callback, pid})
  end

  @doc """
  Unregisters a process from resize notifications.
  """
  @spec unregister_resize_callback(pid()) :: :ok
  def unregister_resize_callback(pid \\ self()) do
    GenServer.call(__MODULE__, {:unregister_resize_callback, pid})
  end

  @doc """
  Performs complete terminal restoration.

  This restores all terminal modifications in the correct sequence:
  1. Show cursor
  2. Leave alternate screen
  3. Disable raw mode
  4. Restore original settings
  """
  @spec restore() :: :ok | {:error, term()}
  def restore do
    GenServer.call(__MODULE__, :restore)
  end

  @doc """
  Checks if the terminal is currently in raw mode.
  """
  @spec raw_mode?() :: boolean()
  def raw_mode? do
    GenServer.call(__MODULE__, :raw_mode?)
  end

  @doc """
  Gets the current terminal state.
  """
  @spec get_state() :: State.t()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Enables mouse tracking with the specified mode.

  ## Modes

  - `:click` - Report button press and release only
  - `:drag` - Also report mouse motion while button is pressed
  - `:all` - Report all mouse motion (generates many events)

  Also enables SGR extended mode for accurate coordinates.
  """
  @spec enable_mouse_tracking(:click | :drag | :all) :: :ok
  def enable_mouse_tracking(mode \\ :click) when mode in [:click, :drag, :all] do
    GenServer.call(__MODULE__, {:enable_mouse_tracking, mode})
  end

  @doc """
  Disables mouse tracking.
  """
  @spec disable_mouse_tracking() :: :ok
  def disable_mouse_tracking do
    GenServer.call(__MODULE__, :disable_mouse_tracking)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    check_previous_crash()
    create_ets_table()
    register_signal_handler()

    {raw_mode_active, original_settings} = detect_prestarted_raw_mode()

    state =
      if raw_mode_active do
        %{
          State.new()
          | raw_mode_active: true,
            original_settings: original_settings
        }
      else
        State.new()
      end

    {:ok, state}
  end

  @impl true
  def handle_call(:enable_raw_mode, _from, state) do
    if state.raw_mode_active do
      {:reply, {:ok, state}, state}
    else
      case do_enable_raw_mode() do
        {:ok, original_settings} ->
          :ets.insert(@ets_table, {:raw_mode_active, true})

          new_state = %{state | raw_mode_active: true, original_settings: original_settings}
          {:reply, {:ok, new_state}, new_state}

        {:error, _reason} = error ->
          {:reply, error, state}
      end
    end
  end

  @impl true
  def handle_call(:adopt_native_raw_mode, _from, state) do
    :ets.insert(@ets_table, {:raw_mode_active, true})
    new_state = %{state | raw_mode_active: true}
    {:reply, {:ok, new_state}, new_state}
  end

  @impl true
  def handle_call(:disable_raw_mode, _from, state) do
    if state.raw_mode_active do
      do_disable_raw_mode(state.original_settings)
      :ets.insert(@ets_table, {:raw_mode_active, false})
      new_state = %{state | raw_mode_active: false, original_settings: nil}
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:enter_alternate_screen, _from, state) do
    if state.alternate_screen_active do
      {:reply, :ok, state}
    else
      write_to_terminal(ANSI.enter_alternate_screen())
      new_state = %{state | alternate_screen_active: true}
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:leave_alternate_screen, _from, state) do
    if state.alternate_screen_active do
      write_to_terminal(ANSI.leave_alternate_screen())
      new_state = %{state | alternate_screen_active: false}
      {:reply, :ok, new_state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:hide_cursor, _from, state) do
    write_to_terminal(ANSI.cursor_hide())
    new_state = %{state | cursor_visible: false}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:show_cursor, _from, state) do
    write_to_terminal(ANSI.cursor_show())
    new_state = %{state | cursor_visible: true}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_terminal_size, _from, state) do
    case do_get_terminal_size() do
      {:ok, {rows, cols}} = result ->
        new_state = %{state | size: {rows, cols}}
        {:reply, result, new_state}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:register_resize_callback, pid}, _from, state) do
    callbacks = [pid | state.resize_callbacks] |> Enum.uniq()
    new_state = %{state | resize_callbacks: callbacks}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:unregister_resize_callback, pid}, _from, state) do
    callbacks = Enum.reject(state.resize_callbacks, &(&1 == pid))
    new_state = %{state | resize_callbacks: callbacks}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:restore, _from, state) do
    new_state = do_restore(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:raw_mode?, _from, state) do
    {:reply, state.raw_mode_active, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:enable_mouse_tracking, mode}, _from, state) do
    # Skip mouse tracking on WSL/ConPTY -- mouse-off sequences are silently
    # ignored by ConPTY, so enabling mouse tracking leads to escape code leaks
    if TerminalOutput.needs_hard_reset?() do
      {:reply, :ok, state}
    else
      # First disable any existing tracking
      if state.mouse_tracking != :off do
        disable_current_mouse_mode(state.mouse_tracking)
      end

      # Enable new tracking mode with SGR
      # Map user-friendly mode names to ANSI protocol modes:
      # :click -> :normal (1000), :drag -> :button (1002), :all -> :all (1003)
      ansi_mode =
        case mode do
          :click -> :normal
          :drag -> :button
          :all -> :all
        end

      write_to_terminal(ANSI.enable_mouse_tracking(ansi_mode))
      write_to_terminal(ANSI.enable_sgr_mouse())

      new_state = %{state | mouse_tracking: mode}
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:disable_mouse_tracking, _from, state) do
    if state.mouse_tracking != :off do
      disable_current_mouse_mode(state.mouse_tracking)
      write_to_terminal(ANSI.disable_sgr_mouse())
    end

    new_state = %{state | mouse_tracking: :off}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info({:EXIT, _pid, :normal}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, :shutdown}, state) do
    Logger.debug("Terminal GenServer received shutdown, performing cleanup")
    do_restore(state)
    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.warning("Terminal GenServer received EXIT: #{inspect(reason)}, performing cleanup")
    do_restore(state)
    {:stop, reason, state}
  end

  @impl true
  def handle_info(:sigwinch, state) do
    case do_get_terminal_size() do
      {:ok, {rows, cols}} ->
        new_state = %{state | size: {rows, cols}}

        for pid <- new_state.resize_callbacks do
          send(pid, {:terminal_resize, {rows, cols}})
        end

        {:noreply, new_state}

      {:error, _reason} ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:sigcont, state) do
    case resume_raw_mode(state) do
      :ok ->
        restore_owned_output(state)
        Enum.each(state.resize_callbacks, &send(&1, :terminal_resume))
        {:noreply, state}

      {:error, reason} ->
        Enum.each(state.resize_callbacks, &send(&1, {:terminal_resume_failed, reason}))
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("Terminal GenServer terminating: #{inspect(reason)}")
    do_restore(state)
    :ok
  end

  # Private functions

  defp resume_raw_mode(%{raw_mode_active: false}), do: :ok

  defp resume_raw_mode(_state) do
    # The signal owner waits for OTP to process SIGCONT. Do not start another
    # shell here: it replaces the group that owns an outstanding IO.getn call.
    :ok = :gen_event.call(:erl_signal_server, {SignalHandler, self()}, :sync, 1_000)
    apply_stty_raw_settings()
  rescue
    exception -> {:error, {:resume_exception, exception}}
  catch
    kind, reason -> {:error, {:resume_failure, kind, reason}}
  end

  defp restore_owned_output(state) do
    if owns_terminal_output?(state) do
      write_to_terminal([
        ANSI.reset(),
        if(state.alternate_screen_active, do: ANSI.enter_alternate_screen(), else: []),
        if(state.cursor_visible, do: [], else: ANSI.cursor_hide()),
        resume_mouse_sequence(state.mouse_tracking),
        if(state.bracketed_paste, do: ANSI.enable_bracketed_paste(), else: []),
        if(state.focus_events, do: ANSI.enable_focus_events(), else: [])
      ])
    end
  end

  defp owns_terminal_output?(state) do
    Enum.any?([
      state.raw_mode_active,
      state.alternate_screen_active,
      not state.cursor_visible,
      state.mouse_tracking != :off,
      state.bracketed_paste,
      state.focus_events
    ])
  end

  defp resume_mouse_sequence(:off), do: []
  defp resume_mouse_sequence(:click), do: resume_mouse_sequence(:normal)
  defp resume_mouse_sequence(:drag), do: resume_mouse_sequence(:button)

  defp resume_mouse_sequence(mode),
    do: [ANSI.enable_mouse_tracking(mode), ANSI.enable_sgr_mouse()]

  defp register_signal_handler do
    case :os.type() do
      {:unix, _} ->
        handler = {SignalHandler, self()}

        case :gen_event.add_sup_handler(:erl_signal_server, handler, self()) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning("Unable to register terminal signal handler: #{inspect(reason)}")
        end

      _ ->
        :ok
    end
  rescue
    error ->
      Logger.warning("Unable to register terminal signal handler: #{Exception.message(error)}")
  catch
    kind, reason ->
      Logger.warning("Unable to register terminal signal handler: #{inspect({kind, reason})}")
  end

  # Backend.Selector may activate native raw mode before this process starts.
  # Pre-OTP 28 versions expose :shell.start_interactive/1 but do not implement
  # the native raw/cooked contract, so they must remain on the TTY path.
  defp detect_prestarted_raw_mode do
    # A Windows probe would acquire raw mode and then replace it with cooked
    # mode. Keep the first acquisition for enable_raw_mode or the selector.
    if Platform.native_raw_mode_supported?() and not match?({:win32, _}, :os.type()) do
      original_settings = save_terminal_settings()

      try do
        case start_native_raw_mode() do
          :ok ->
            do_disable_raw_mode(original_settings)
            :ets.insert(@ets_table, {:raw_mode_active, false})
            {false, nil}

          {:error, :already_started} ->
            # Selector may have activated OTP's raw shell before the Terminal
            # server started. Apply the OS-level flags as well: the native call
            # alone does not make `IO.getn/2` character-at-a-time in every
            # non-shell launch (for example `mix run` under a PTY).
            _ = apply_stty_raw_settings()
            :ets.insert(@ets_table, {:raw_mode_active, true})
            {true, original_settings}
        end
      rescue
        _ -> {false, nil}
      end
    else
      :ets.insert(@ets_table, {:raw_mode_active, false})
      {false, nil}
    end
  end

  defp do_enable_raw_mode do
    if terminal?() do
      # Save original terminal settings first
      original_settings = save_terminal_settings()

      try do
        if Platform.native_raw_mode_supported?() do
          # OTP 28 raw mode activation sets character-at-a-time mode with no echo.
          case start_native_raw_mode() do
            :ok ->
              apply_stty_raw_settings()
              {:ok, original_settings}

            {:error, reason} ->
              case apply_stty_raw_settings() do
                :ok -> {:ok, original_settings}
                {:error, _stty_reason} -> {:error, reason}
              end
          end
        else
          enable_raw_mode_with_stty(original_settings)
        end
      rescue
        _e in UndefinedFunctionError ->
          enable_raw_mode_with_stty(original_settings)

        e ->
          {:error, {:raw_mode_failed, Exception.message(e)}}
      catch
        kind, reason ->
          {:error, {kind, reason}}
      end
    else
      {:error, :not_a_terminal}
    end
  end

  defp enable_raw_mode_with_stty(original_settings) do
    case apply_stty_raw_settings() do
      :ok ->
        {:ok, original_settings}

      {:error, reason} ->
        {:error, {:otp_version, "OTP 28+ required and stty fallback failed: #{inspect(reason)}"}}
    end
  end

  defp start_native_raw_mode, do: NativeMode.enter()

  defp save_terminal_settings do
    case TermUtils.safe_stty(["-g"]) do
      {:ok, output} ->
        # Validate output format before storing
        case TermUtils.validate_stty_settings(output) do
          :ok -> output
          {:error, _} -> nil
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp apply_stty_raw_settings do
    # Apply comprehensive raw mode settings:
    # -echo: disable echoing of input characters
    # -icanon: disable canonical mode (line-at-a-time)
    # min 1: minimum number of characters for read
    # time 0: timeout in tenths of a second (0 = no timeout)
    # -isig: disable signal generation (Ctrl+C etc handled by app)
    # -ixon: disable XON/XOFF flow control
    case TermUtils.safe_stty(["raw", "-echo", "-isig", "-ixon", "min", "1", "time", "0"]) do
      {:ok, _output} ->
        :ok

      {:error, reason} ->
        {:error, {:stty_failed, reason}}
    end
  end

  defp do_disable_raw_mode(original_settings) do
    _ = ensure_cooked_mode()

    # First try to restore original settings if we have them
    if is_binary(original_settings) and original_settings != "" do
      restore_terminal_settings(original_settings)
    else
      # Fallback: use stty sane to restore reasonable defaults
      restore_stty_sane()
    end

    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp restore_terminal_settings(settings) do
    # Restore original settings - settings was validated when captured
    # We pass it as a single argument which stty accepts for restoration
    case TermUtils.safe_stty([settings]) do
      {:ok, _} -> :ok
      {:error, _} -> restore_stty_sane()
    end
  end

  defp restore_stty_sane do
    # Restore terminal to reasonable defaults
    case TermUtils.safe_stty(["sane"]) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  # Delegates to SizeDetector for consistent size detection across modules.
  defp do_get_terminal_size do
    SizeDetector.auto_detect()
  end

  defp do_restore(state) do
    # Phase 1: Direct-to-TTY write (most reliable, bypasses Erlang IO)
    TerminalOutput.write_to_tty(TerminalOutput.cleanup_sequence())

    # Phase 2: Erlang IO backup (in case /dev/tty write failed)
    write_to_terminal(@all_mouse_off)

    if not state.cursor_visible do
      write_to_terminal(ANSI.cursor_show())
    end

    # Reset terminal attributes before leaving alt screen
    write_to_terminal(ANSI.reset())

    if state.alternate_screen_active do
      write_to_terminal(ANSI.leave_alternate_screen())
    end

    # Phase 3: Cooked mode (before stty so stty gets final say)
    ensure_cooked_mode()

    # Phase 4: Restore original stty settings
    if state.raw_mode_active do
      do_disable_raw_mode(state.original_settings)
    end

    # Phase 5: Cleanup ONLCR persistent_term
    TerminalOutput.disable_onlcr()

    if :ets.whereis(@ets_table) != :undefined do
      :ets.insert(@ets_table, {:raw_mode_active, false})
    end

    State.new()
  end

  defp disable_current_mouse_mode(mode) do
    # Map user-friendly mode names to ANSI protocol modes
    ansi_mode =
      case mode do
        :click -> :normal
        :drag -> :button
        :all -> :all
        _ -> nil
      end

    if ansi_mode do
      write_to_terminal(ANSI.disable_mouse_tracking(ansi_mode))
    end
  end

  defp write_to_terminal(data) do
    TerminalOutput.write(data)
  rescue
    _ -> :ok
  end

  defp ensure_cooked_mode do
    if Platform.native_raw_mode_supported?() do
      :shell.start_interactive({:noshell, :cooked})
    end
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp terminal? do
    # Try multiple methods to detect if we have a terminal
    # This is important for SSH sessions where standard_io may not report terminal correctly
    cond do
      # Method 1: Check :io.getopts for terminal key
      io_has_terminal?() -> true
      # Method 2: Check if /dev/tty exists and is accessible (Unix/Linux/macOS)
      File.exists?("/dev/tty") -> true
      # Method 3: Check if stdout is a tty using test command
      check_tty() -> true
      # No terminal detected
      true -> false
    end
  end

  defp io_has_terminal? do
    case :io.getopts(:standard_io) do
      opts when is_list(opts) -> Keyword.get(opts, :terminal, false) == true
      {:ok, opts} -> Keyword.get(opts, :terminal, false) == true
      _ -> false
    end
  end

  defp check_tty do
    case TermUtils.safe_test(["-t", "0"]) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp create_ets_table do
    if :ets.whereis(@ets_table) == :undefined do
      :ets.new(@ets_table, [:named_table, :public, :set])
    end
  end

  defp check_previous_crash do
    if :ets.whereis(@ets_table) != :undefined do
      case :ets.lookup(@ets_table, :raw_mode_active) do
        [{:raw_mode_active, true}] ->
          Logger.warning("Detected unclean termination from previous run, resetting terminal")
          TerminalOutput.write_to_tty(TerminalOutput.cleanup_sequence())

        _ ->
          :ok
      end
    end
  end
end
