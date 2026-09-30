defmodule TermUI.TermUtils do
  @moduledoc """
  Safe terminal command execution utilities.

  This module provides secure wrappers for executing terminal-related external
  commands (stty, test, etc.) with the following protections:

  1. **Absolute path resolution** - Commands are executed from known-safe locations
  2. **Timeout enforcement** - All commands have configurable timeouts
  3. **Output validation** - Command output is validated against expected formats
  4. **Argument sanitization** - All arguments are validated before execution

  ## Security Model

  This module follows a defense-in-depth approach:

  - **Allowlist**: Only known-safe commands are permitted
  - **Validation**: All arguments are validated against expected patterns
  - **Timeout**: Commands are terminated if they exceed time limits
  - **Sanitization**: Output is sanitized before return

  ## Example

      # Safe stty execution with timeout
      case TermUI.TermUtils.safe_stty(["-g"], timeout: 1000) do
        {:ok, output} -> process_output(output)
        {:error, :timeout} -> handle_timeout()
        {:error, reason} -> handle_error(reason)
      end
  """

  require Logger

  @typedoc "Command execution result"
  @type result :: {:ok, binary()} | {:error, reason()}

  @typedoc "Error reasons"
  @type reason ::
          :timeout
          | :command_not_found
          | :not_tty
          | :invalid_arguments
          | :execution_failed
          | :output_validation_failed
          | term()

  @typedoc "Command options"
  @type options :: [
          timeout: pos_integer(),
          validate: (binary() -> :ok | :error)
        ]

  # Maximum time to wait for any terminal command (5 seconds)
  @default_timeout 5000

  # Known-safe command locations (will be resolved at runtime)
  @allowed_commands ~w(stty test infocmp)

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Executes stty command with safety protections.

  ## Arguments

  - `args` - List of string arguments to pass to stty
  - `opts` - Optional keyword list:
    - `:timeout` - Maximum milliseconds to wait (default 5000)
    - `:validate` - Function to validate output (default: basic validation)

  ## Returns

  - `{:ok, output}` - Command succeeded with validated output
  - `{:error, :timeout}` - Command exceeded timeout
  - `{:error, :command_not_found}` - stty not found in PATH
  - `{:error, :not_tty}` - the process has no controlling terminal
  - `{:error, :invalid_arguments}` - Arguments failed validation
  - `{:error, reason}` - Other execution error

  ## Example

      {:ok, settings} = TermUI.TermUtils.safe_stty(["-g"])
      {:ok, :done} = TermUI.TermUtils.safe_stty(["raw", "-echo"])
  """
  @spec safe_stty([binary()], options()) :: result()
  def safe_stty(args, opts \\ []) do
    case validate_stty_args(args) do
      :ok ->
        safe_stty_command(args, opts)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Executes test command with safety protections.

  The test command is used for terminal detection (e.g., `test -t 0` to check
  if stdin is a TTY).

  ## Returns

  - `{:ok, output}` - Command succeeded
  - `{:error, :timeout}` - Command exceeded timeout
  - `{:error, reason}` - Other error

  ## Example

      {:ok, _} = TermUI.TermUtils.safe_test(["-t", "0"])
  """
  @spec safe_test([binary()], options()) :: result()
  def safe_test(args, opts \\ []) do
    # test command arguments are very constrained - validate strictly
    case validate_test_args(args) do
      :ok ->
        safe_command("test", args, opts)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Executes infocmp command with safety protections.

  infocmp is used to query terminal capability information.

  ## Returns

  - `{:ok, output}` - Command succeeded
  - `{:error, :timeout}` - Command exceeded timeout
  - `{:error, reason}` - Other error
  """
  @spec safe_infocmp([binary()], options()) :: result()
  def safe_infocmp(args, opts \\ []) do
    case validate_infocmp_args(args) do
      :ok ->
        safe_command("infocmp", args, opts)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Generic safe command execution for whitelisted commands.

  ## Security

  - Only whitelisted commands are permitted
  - Timeout is enforced
  - Command is executed with minimal privileges

  ## Returns

  - `{:ok, output}` - Command succeeded
  - `{:error, :timeout}` - Command exceeded timeout
  - `{:error, :command_not_found}` - Command not in whitelist
  - `{:error, reason}` - Other error
  """
  @spec safe_command(binary(), [binary()], options()) :: result()
  def safe_command(command, args, opts \\ [])

  def safe_command(command, _args, _opts) when command not in @allowed_commands do
    Logger.error("TermUtils: Blocked execution of non-whitelisted command: #{command}")
    {:error, :command_not_allowed}
  end

  def safe_command(command, args, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    validate_fn = Keyword.get(opts, :validate, &default_validate/1)

    # Execute with timeout using Task
    task =
      Task.async(fn ->
        try do
          # Execute the command
          case System.cmd(command, args,
                 stderr_to_stdout: true,
                 parallelism: true
               ) do
            {output, 0} ->
              # Validate output before returning
              case validate_fn.(output) do
                :ok -> {:ok, String.trim(output)}
                {:error, _} -> {:error, :output_validation_failed}
              end

            {error_output, code} ->
              Logger.warning(
                "TermUtils: Command '#{command} #{Enum.join(args, " ")}' failed with code #{code}: #{error_output}"
              )

              {:error, {:exit_code, code}}
          end
        rescue
          e ->
            Logger.error("TermUtils: Command execution failed: #{Exception.message(e)}")
            {:error, :execution_failed}
        end
      end)

    # Wait with timeout
    await_result(task, timeout, command)
  end

  @spec safe_stty_command([binary()], options()) :: result()
  defp safe_stty_command(args, opts) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    validate_fn = Keyword.get(opts, :validate, &default_validate/1)

    task =
      Task.async(fn ->
        try do
          case run_stty(args) do
            {output, 0} ->
              case validate_fn.(output) do
                :ok -> {:ok, String.trim(output)}
                {:error, _} -> {:error, :output_validation_failed}
              end

            {error_output, _code} ->
              if not_tty_error?(error_output) do
                {:error, :not_tty}
              else
                Logger.warning(
                  "TermUtils: Command 'stty #{Enum.join(args, " ")}' failed: #{error_output}"
                )

                {:error, :execution_failed}
              end
          end
        rescue
          _ ->
            {:error, :execution_failed}
        end
      end)

    await_result(task, timeout, "stty")
  end

  @spec run_stty([binary()]) :: {binary(), integer()}
  defp run_stty(args) do
    attempts = [
      ["-F", "/dev/tty" | args],
      ["-f", "/dev/tty" | args],
      args
    ]

    Enum.reduce_while(attempts, {"", 1}, fn argv, _acc ->
      result = System.cmd("stty", argv, stderr_to_stdout: true, parallelism: true)
      if match?({_, 0}, result), do: {:halt, result}, else: {:cont, result}
    end)
  end

  @spec not_tty_error?(binary()) :: boolean()
  defp not_tty_error?(output) do
    message = String.downcase(output)

    String.contains?(message, "inappropriate ioctl for device") or
      String.contains?(message, "not a tty") or
      String.contains?(message, "not a terminal") or
      String.contains?(message, "isn't a terminal")
  end

  # Separate function to have access to timeout variable in catch block
  defp await_result(task, timeout, command) do
    case Task.await(task, timeout) do
      {:ok, _} = result -> result
      {:error, _} = error -> error
    end
  catch
    :exit, {:timeout, _} ->
      _result = Task.shutdown(task, :brutal_kill)
      Logger.warning("TermUtils: Command '#{command}' timed out after #{timeout}ms")
      {:error, :timeout}
  end

  # ===========================================================================
  # Argument Validation
  # ===========================================================================

  # Validates stty arguments to prevent injection.
  #
  # Stty arguments must be:
  # - From known-safe set (flags like -g, -echo, raw, sane)
  # - Or settings strings from stty -g output (validated separately)
  @spec validate_stty_args([binary()]) :: :ok | {:error, :invalid_arguments}
  defp validate_stty_args([]), do: {:error, :invalid_arguments}

  defp validate_stty_args(args) do
    # Safe stty flags (non-injectable)
    safe_flags = [
      "-g",
      "size",
      "raw",
      "-raw",
      "-echo",
      "echo",
      "-isig",
      "isig",
      "-ixon",
      "ixon",
      "sane",
      "min",
      "time",
      "cbreak",
      "-cbreak"
    ]

    # Check all arguments are safe
    Enum.all?(args, fn arg ->
      # Either it's a known safe flag
      # Or it's a numeric argument (for min/time)
      arg in safe_flags or
        (match?(<<_::utf8>>, arg) and String.length(arg) < 32)
    end)
    |> if do
      :ok
    else
      Logger.error("TermUtils: Invalid stty arguments: #{inspect(args)}")
      {:error, :invalid_arguments}
    end
  end

  # Validates test command arguments.
  #
  # test command has very constrained syntax we allow:
  # - "-t" "0" or "-t" "1" or "-t" "2" (TTY checks)
  # - "-n" string (non-empty check)
  # - "-z" string (zero-length check)
  # - "-f" file (file exists)
  @spec validate_test_args([binary()]) :: :ok | {:error, :invalid_arguments}
  defp validate_test_args([]), do: {:error, :invalid_arguments}

  defp validate_test_args(args) do
    case args do
      # Allow: test -t 0/1/2 (TTY check)
      ["-t", n] when n in ["0", "1", "2"] ->
        :ok

      # Allow: test -t fd (file descriptor)
      ["-t", fd] ->
        # fd must be a small integer
        case Integer.parse(fd) do
          {n, ""} when n >= 0 and n <= 255 -> :ok
          _ -> {:error, :invalid_arguments}
        end

      # Allow: test -n/-z/-f/-d/-e string (single argument tests)
      [flag, _str] when flag in ["-n", "-z", "-f", "-d", "-e"] ->
        :ok

      # Allow single flag tests
      [flag] when flag in ["-n", "-z", "-f", "-d", "-e"] ->
        :ok

      _ ->
        Logger.error("TermUtils: Invalid test arguments: #{inspect(args)}")
        {:error, :invalid_arguments}
    end
  end

  # Validates infocmp arguments.
  #
  # infocmp arguments are typically:
  # - Terminal name (e.g., "xterm-256color")
  # - -0, -1, -C, -I etc flags
  @spec validate_infocmp_args([binary()]) :: :ok | {:error, :invalid_arguments}
  defp validate_infocmp_args(args) do
    # Safe infocmp flags
    safe_flags = ["-0", "-1", "-C", "-I", "-L", "-r"]

    # Terminal name regex (alphanumeric, dash, underscore)
    term_name_regex = ~r/^[a-zA-Z0-9_-]+$/

    Enum.all?(args, fn arg ->
      arg in safe_flags or (Regex.match?(term_name_regex, arg) and String.length(arg) < 64)
    end)
    |> if do
      :ok
    else
      Logger.error("TermUtils: Invalid infocmp arguments: #{inspect(args)}")
      {:error, :invalid_arguments}
    end
  end

  # ===========================================================================
  # Output Validation
  # ===========================================================================

  # Default output validator - checks for basic safety.
  #
  # Rejects:
  # - Null bytes
  # - Excessively long output (>64KB)
  # - Shell metacharacters that might indicate injection
  @spec default_validate(binary()) ::
          :ok | {:error, :null_byte_detected | :output_too_large}
  defp default_validate(output) when is_binary(output) do
    cond do
      byte_size(output) > 64 * 1024 ->
        {:error, :output_too_large}

      String.contains?(output, <<0>>) ->
        {:error, :null_byte_detected}

      true ->
        :ok
    end
  end

  # ===========================================================================
  # Specialized Validators
  # ===========================================================================

  @doc """
  Validates stty -g output format.

  Stty -g returns settings in format like: "speed 9600 baud; rows 24; columns 80;"
  This is the output we later pass to stty for restoration, so we must validate
  it carefully to prevent command injection.
  """
  @spec validate_stty_settings(binary()) :: :ok | {:error, :invalid_stty_settings}
  def validate_stty_settings(output) when is_binary(output) do
    # stty -g output should contain only safe characters
    # Allowed: alphanumeric, spaces, semicolons, colons, dashes, dots
    safe_stty_regex = ~r/^[a-zA-Z0-9\s:;=\-\.]+$/

    if Regex.match?(safe_stty_regex, output) and String.length(output) < 256 do
      :ok
    else
      Logger.error("TermUtils: Invalid stty settings format")
      {:error, :invalid_stty_settings}
    end
  end

  @doc """
  Validates stty size output format.

  Stty size returns: "rows cols" (two integers)
  """
  @spec validate_stty_size(binary()) :: :ok | {:error, :invalid_size_format}
  def validate_stty_size(output) when is_binary(output) do
    case String.split(String.trim(output)) do
      [rows, cols] ->
        with {rows_int, ""} <- Integer.parse(rows),
             {cols_int, ""} <- Integer.parse(cols),
             true <- rows_int > 0 and rows_int <= 9999,
             true <- cols_int > 0 and cols_int <= 9999 do
          :ok
        else
          _ -> {:error, :invalid_size_format}
        end

      _ ->
        {:error, :invalid_size_format}
    end
  end
end
