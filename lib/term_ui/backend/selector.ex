defmodule TermUI.Backend.Selector do
  @moduledoc """
  Determines which terminal backend to use at runtime.

  The Selector module implements a "try raw mode first" strategy for backend
  selection. After the platform/version guard, attempting acquisition is the
  authoritative check for whether native Raw mode is available.

  ## Why Not Use Heuristics?

  Environment-based detection (checking `$TERM`, current I/O device options, etc.) cannot
  reliably detect all cases where raw mode is unavailable:

  - **Nerves devices**: The erlinit process may have already started a shell,
    making raw mode unavailable even though `$TERM` suggests a capable terminal

  - **SSH sessions**: Remote SSH connections often have a shell already running
    in the PTY, preventing raw mode activation

  - **Remote IEx**: Connecting to a running node via `--remsh` or distributed
    Erlang inherits the remote node's terminal state

  - **Docker containers**: Terminal allocation varies by configuration; a TTY
    may be allocated but a shell may already be running

  - **IDE terminals**: Integrated terminals may report capabilities they don't
    fully support in raw mode

  ## The Selection Strategy

  The selector attempts to start raw mode using OTP 28's
  `:shell.start_interactive({:noshell, :raw})`:

  1. **If raw mode succeeds** (returns `:ok`):
     - The terminal is now in raw mode
     - Return `{:raw, state}` for the Raw backend

  2. **If raw mode fails** with `{:error, :already_started}`:
     - A shell is already running, raw mode unavailable
     - Detect terminal capabilities for graceful degradation
     - Return `{:tty, capabilities}` for the TTY backend

  3. **If the function is undefined** (pre-OTP 28):
     - Fall back to TTY mode
     - Return `{:tty, capabilities}` with detected capabilities

  ## Return Values

  The `select/0` function returns one of:

  - `{:raw, state}` - Raw mode is active. The `state` map contains:
    - `:raw_mode_started` - `true` indicating raw mode was activated

  - `{:tty, capabilities}` - TTY mode should be used. The `capabilities` map contains:
    - `:colors` - Color depth (`:true_color`, `:color_256`, `:color_16`, `:monochrome`)
    - `:unicode` - Boolean indicating Unicode support
    - `:dimensions` - `{rows, cols}` tuple or `nil` if unknown
    - `:terminal` - Boolean indicating terminal presence

  ## Explicit Selection

  For testing or configuration override, use `select/1`:

      # Select a module explicitly (initialization is performed by Runtime)
      {:explicit, TermUI.Backend.TTY, []} = Selector.select(TermUI.Backend.TTY)

      {:explicit, TermUI.Backend.Raw, []} = Selector.select(TermUI.Backend.Raw)

      # Auto-detect (same as select/0)
      result = Selector.select(:auto)

  ## Examples

      # Inspect the selected local mode. Runtime owns backend initialization.
      case TermUI.Backend.Selector.select() do
        {:raw, _state} -> :raw
        {:tty, _capabilities} -> :tty
      end

  ## OTP Version Requirements

  - **OTP 28+ on a supported Unix platform**: Native Raw selection with
    `:shell.start_interactive/1`
  - **OTP 27 and earlier**: Automatic fallback to TTY mode
  """

  require Logger

  alias TermUI.Platform
  alias TermUI.Terminal.NativeMode

  @typedoc """
  Result of backend selection.

  - `{:raw, state}` - Raw mode active, use Raw backend
  - `{:tty, capabilities}` - TTY mode, use TTY backend with capabilities
  - `{:explicit, module, opts}` - Explicit backend selection (bypasses detection)
  """
  @type selection_result ::
          {:raw, raw_state()}
          | {:tty, capabilities()}
          | {:explicit, module(), keyword()}

  @typedoc """
  State returned when raw mode is successfully activated.
  """
  @type raw_state :: %{raw_mode_started: boolean()}

  @typedoc """
  Detected terminal capabilities for TTY mode.
  """
  @type capabilities :: %{
          colors: color_depth(),
          unicode: boolean(),
          dimensions: {pos_integer(), pos_integer()} | nil,
          terminal: boolean()
        }

  @typedoc """
  Detected color depth for TTY mode.
  """
  @type color_depth :: :true_color | :color_256 | :color_16 | :monochrome

  # Terminal types that support at least 16 colors.
  # Used by basic_terminal?/1 to detect color support when COLORTERM is not set.
  @basic_terminals ~w(xterm screen tmux vt100 vt220 linux rxvt ansi cygwin putty konsole gnome eterm)

  @doc """
  Selects the appropriate backend by attempting raw mode first.

  Returns `{:raw, state}` if raw mode succeeds, or `{:tty, capabilities}`
  if raw mode is unavailable.

  ## Examples

      iex> case TermUI.Backend.Selector.select() do
      ...>   {:raw, _state} -> :raw_mode
      ...>   {:tty, _caps} -> :tty_mode
      ...> end
      # Returns :raw_mode or :tty_mode depending on environment
  """
  @spec select() :: {:raw, raw_state()} | {:tty, capabilities()}
  def select do
    try_raw_mode()
  end

  @doc """
  Selects a backend with explicit mode or module specification.

  ## Arguments

  - `:auto` - Same as `select/0`, auto-detect backend
  - `module` - Use specific backend module (e.g., `TermUI.Backend.TTY`)
  - `{module, opts}` - Use specific backend with options

  ## Examples

      # Auto-detect
      Selector.select(:auto)

      # Force TTY mode
      Selector.select(TermUI.Backend.TTY)

      # Force with options
      Selector.select({TermUI.Backend.TTY, line_mode: :full_redraw})
  """
  @spec select(:auto | module() | {module(), keyword()}) :: selection_result()
  def select(:auto), do: select()

  def select({module, opts}) when is_atom(module) and is_list(opts) do
    Logger.info("TermUI: Using forced backend: #{inspect(module)}")
    {:explicit, module, opts}
  end

  def select(module) when is_atom(module) do
    Logger.info("TermUI: Using forced backend: #{inspect(module)}")
    {:explicit, module, []}
  end

  # Private implementation functions

  @doc false
  @spec try_raw_mode() :: {:raw, raw_state()} | {:tty, capabilities()}
  def try_raw_mode do
    attempt_raw_mode()
  rescue
    # Handle pre-OTP 28 systems where :shell.start_interactive/1 doesn't exist
    UndefinedFunctionError ->
      {:tty, detect_capabilities()}
  end

  # Attempts to start raw mode using OTP 28's shell.start_interactive/1
  # This is separated to allow testing the rescue path
  @doc false
  @spec attempt_raw_mode() :: {:raw, raw_state()} | {:tty, capabilities()}
  def attempt_raw_mode do
    if Platform.native_raw_mode_supported?() do
      case NativeMode.enter() do
        :ok ->
          # Raw mode successfully activated
          {:raw, %{raw_mode_started: true}}

        {:error, :already_started} ->
          # A shell is already running, fall back to TTY mode
          {:tty, detect_capabilities()}

        {:error, reason} ->
          # Preserve unexpected failures in the capabilities map for debugging.
          {:tty, Map.put(detect_capabilities(), :raw_mode_error, reason)}
      end
    else
      {:tty, detect_capabilities()}
    end
  end

  @doc false
  @spec detect_capabilities() :: capabilities()
  def detect_capabilities do
    %{
      colors: detect_color_depth(),
      unicode: detect_unicode_support(),
      dimensions: detect_dimensions(),
      terminal: detect_terminal_presence()
    }
  end

  # Detects color depth from environment variables
  # Priority: $COLORTERM > $TERM patterns > monochrome fallback
  @spec detect_color_depth() :: color_depth()
  defp detect_color_depth do
    colorterm = System.get_env("COLORTERM") || ""
    term = System.get_env("TERM") || ""

    cond do
      true_color_colorterm?(colorterm) ->
        :true_color

      true_color_term?(term) ->
        :true_color

      color_256_term?(term) ->
        :color_256

      basic_16_color_term?(term) ->
        :color_16

      true ->
        :monochrome
    end
  end

  defp true_color_colorterm?(colorterm) do
    colorterm in ["truecolor", "24bit"]
  end

  defp true_color_term?(term) do
    String.contains?(term, "-direct")
  end

  defp color_256_term?(term) do
    String.contains?(term, "-256color") or String.contains?(term, "256color")
  end

  defp basic_16_color_term?(term) do
    term != "" and basic_terminal?(term)
  end

  # Checks if TERM indicates a basic terminal with at least 16 colors.
  # Uses @basic_terminals module attribute for the list of supported terminal types.
  @spec basic_terminal?(String.t()) :: boolean()
  defp basic_terminal?(term) do
    Enum.any?(@basic_terminals, fn basic ->
      String.starts_with?(term, basic) or String.contains?(term, basic)
    end)
  end

  # Detects Unicode support from $LANG environment variable
  @spec detect_unicode_support() :: boolean()
  defp detect_unicode_support do
    lang = System.get_env("LANG") || ""
    lc_all = System.get_env("LC_ALL") || ""
    lc_ctype = System.get_env("LC_CTYPE") || ""

    # Check all locale variables, prioritizing LC_ALL > LC_CTYPE > LANG
    locale =
      cond do
        lc_all != "" -> lc_all
        lc_ctype != "" -> lc_ctype
        true -> lang
      end

    locale_upper = String.upcase(locale)

    String.contains?(locale_upper, "UTF-8") or String.contains?(locale_upper, "UTF8")
  end

  # Detects terminal dimensions using :io module
  @spec detect_dimensions() :: {pos_integer(), pos_integer()} | nil
  defp detect_dimensions do
    with {:ok, cols} <- :io.columns(),
         {:ok, rows} <- :io.rows() do
      {rows, cols}
    else
      _ -> nil
    end
  end

  # Detects if we're connected to a terminal
  @dialyzer {:nowarn_function,
             detect_terminal_presence: 0,
             select: 0,
             select: 1,
             try_raw_mode: 0,
             attempt_raw_mode: 0,
             detect_capabilities: 0}
  @spec detect_terminal_presence() :: term()
  defp detect_terminal_presence do
    case :io.getopts() do
      {:ok, opts} ->
        Keyword.get(opts, :terminal, false)

      _ ->
        false
    end
  end
end
