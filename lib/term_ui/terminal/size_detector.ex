defmodule TermUI.Terminal.SizeDetector do
  @moduledoc false
  alias TermUI.TermUtils

  # Maximum terminal dimension (rows or columns).
  # No production terminal exceeds this size. This provides defense against
  # malicious environment variables or terminal responses.
  @max_terminal_dimension 9999

  @type dimension :: 1..9999
  @type size :: {dimension(), dimension()}

  @doc """
  Returns the maximum valid terminal dimension.
  """
  @spec max_dimension() :: 9999
  def max_dimension, do: @max_terminal_dimension

  @doc """
  Detects terminal size, optionally accepting an explicit size.

  When an explicit size tuple is provided, it's validated and returned.
  Otherwise, auto-detection is attempted.

  ## Options

    * `:size` - Explicit `{rows, cols}` tuple to use instead of detection

  ## Returns

    * `{:ok, {rows, cols}}` - Successfully detected or validated size
    * `{:error, reason}` - Failed to detect size

  ## Examples

      # Auto-detect
      {:ok, {24, 80}} = SizeDetector.detect()

      # Use explicit size
      {:ok, {40, 120}} = SizeDetector.detect(size: {40, 120})
  """
  @spec detect(keyword()) ::
          {:ok, size()} | {:error, :invalid_size | :size_detection_failed}
  def detect(opts \\ []) do
    case Keyword.get(opts, :size) do
      nil -> auto_detect()
      {rows, cols} -> validate_size(rows, cols)
      _invalid -> {:error, :invalid_size}
    end
  end

  @doc """
  Auto-detects terminal size using all available methods.

  Tries methods in order:
  1. `:io.rows/0` and `:io.columns/0`
  2. LINES and COLUMNS environment variables
  3. `stty size` command

  ## Returns

    * `{:ok, {rows, cols}}` - Successfully detected size
    * `{:error, :size_detection_failed}` - All methods failed
  """
  @spec auto_detect() :: {:ok, size()} | {:error, :size_detection_failed}
  def auto_detect do
    # Return the first success
    with {:error, _} <- detect_from_io(),
         {:error, _} <- detect_from_env(),
         {:error, _} <- detect_from_stty() do
      {:error, :size_detection_failed}
    else
      {:ok, _size} = ok -> ok
    end
  end

  @doc """
  Detects terminal size from Erlang's `:io` module.

  Uses `:io.rows/0` and `:io.columns/0` which query the terminal directly.
  This is the most reliable method when running in a real terminal.
  """
  @spec detect_from_io() ::
          {:ok, size()}
          | {:error, :invalid_size | :io_detection_failed | :io_not_available}
  def detect_from_io do
    if function_exported?(:io, :rows, 0) and function_exported?(:io, :columns, 0) do
      case {:io.rows(), :io.columns()} do
        {{:ok, rows}, {:ok, cols}} ->
          validate_size(rows, cols)

        _ ->
          {:error, :io_detection_failed}
      end
    else
      {:error, :io_not_available}
    end
  end

  @doc """
  Detects terminal size from LINES and COLUMNS environment variables.

  These are standard environment variables set by many shells and terminal
  emulators. Values are validated against practical bounds.
  """
  @spec detect_from_env() :: {:ok, size()} | {:error, :env_detection_failed}
  def detect_from_env do
    with {:ok, lines} <- get_env_int("LINES"),
         {:ok, columns} <- get_env_int("COLUMNS") do
      {:ok, {lines, columns}}
    else
      _ -> {:error, :env_detection_failed}
    end
  end

  @doc """
  Detects terminal size from the `stty size` command.

  This is a fallback method that works on most Unix-like systems.
  It spawns a subprocess to run `stty size` with safety protections.
  """
  @spec detect_from_stty() ::
          {:ok, size()}
          | {:error, :invalid_size | :stty_failed | :stty_parse_failed | :stty_timeout}
  def detect_from_stty do
    case TermUtils.safe_stty(["size"]) do
      {:ok, output} ->
        parse_stty_output(output)

      {:error, :timeout} ->
        {:error, :stty_timeout}

      {:error, _} ->
        {:error, :stty_failed}
    end
  end

  @doc """
  Validates that the given dimensions are within practical bounds.

  ## Returns

    * `{:ok, {rows, cols}}` - Valid dimensions
    * `{:error, :invalid_size}` - Invalid dimensions
  """
  @spec validate_size(term(), term()) ::
          {:ok, size()} | {:error, :invalid_size}
  def validate_size(rows, cols)
      when is_integer(rows) and is_integer(cols) and
             rows > 0 and rows <= @max_terminal_dimension and
             cols > 0 and cols <= @max_terminal_dimension do
    {:ok, {rows, cols}}
  end

  def validate_size(_rows, _cols), do: {:error, :invalid_size}

  # Private functions

  # Parses an environment variable as a positive integer within bounds.
  defp get_env_int(var) do
    with value when not is_nil(value) <- System.get_env(var),
         {int, ""} <- Integer.parse(value),
         true <- int > 0 and int <= @max_terminal_dimension do
      {:ok, int}
    else
      nil -> {:error, :not_set}
      {_int, _remainder} -> {:error, :invalid}
      false -> {:error, :out_of_bounds}
      _ -> {:error, :invalid}
    end
  end

  # Parses stty output format "rows cols"
  defp parse_stty_output(output) do
    case String.split(String.trim(output)) do
      [rows_str, cols_str] ->
        with {rows, ""} <- Integer.parse(rows_str),
             {cols, ""} <- Integer.parse(cols_str) do
          validate_size(rows, cols)
        else
          _ -> {:error, :stty_parse_failed}
        end

      _ ->
        {:error, :stty_parse_failed}
    end
  end
end
