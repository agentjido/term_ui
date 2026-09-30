defmodule TermUI.Backend.Selector do
  @moduledoc false

  require Logger

  alias TermUI.Terminal.RawMode

  # OTP types start_interactive/1 as :ok, but it also returns runtime errors
  # such as :already_started. This function must handle those results.
  @dialyzer {:nowarn_function, attempt_raw_mode: 0}

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
  @type raw_state :: %{
          raw_mode_started: true,
          raw_mode_session: RawMode.session()
        }

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
    # Implementation in task 1.2.2
    # Placeholder: attempt raw mode, fall back to TTY with capabilities
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
    case RawMode.enter() do
      {:ok, session} ->
        {:raw, %{raw_mode_started: true, raw_mode_session: session}}

      {:error, :already_started} ->
        {:tty, detect_capabilities()}

      {:error, reason} ->
        {:tty, Map.put(detect_capabilities(), :raw_mode_error, reason)}
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
  @spec detect_terminal_presence() :: boolean()
  defp detect_terminal_presence do
    case :io.getopts() do
      opts when is_list(opts) ->
        Keyword.get(opts, :terminal, false) == true

      {:error, _reason} ->
        false
    end
  end
end
