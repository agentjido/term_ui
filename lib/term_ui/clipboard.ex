defmodule TermUI.Clipboard do
  @moduledoc """
  Bounded OSC 52 clipboard commands.

  `copy/2` and `clear/1` return `TermUI.Command` data. The runtime sends the
  operation to its backend owner, so clipboard output cannot race with frame
  output. This module never writes directly to an IO device. The result mapper
  receives `:ok` or `{:error, reason}`.

  Clipboard content has a default 100,000-byte limit. Set `:max_bytes` to a
  positive integer to change the limit. Set `:target` to `:clipboard`,
  `:primary`, or `:secondary`.
  """

  alias TermUI.Clipboard.Operation
  alias TermUI.Command

  @osc52_prefix "\e]52;"
  @osc52_suffix "\e\\"
  @default_max_bytes 100_000
  @targets [:clipboard, :primary, :secondary]

  @doc "Creates a bounded clipboard write operation."
  @spec operation(term(), keyword()) :: Operation.t()
  def operation(content, opts \\ []) do
    %Operation{
      kind: :write,
      target: target!(opts),
      content: to_string(content),
      max_bytes: max_bytes!(opts)
    }
  end

  @doc "Creates a clipboard clear operation."
  @spec clear_operation(keyword()) :: Operation.t()
  def clear_operation(opts \\ []) do
    %Operation{
      kind: :clear,
      target: target!(opts),
      content: "",
      max_bytes: max_bytes!(opts)
    }
  end

  @doc "Creates a runtime command that copies text through the active backend."
  @spec copy(term(), keyword()) :: Command.clipboard_command()
  def copy(content, opts \\ []) do
    {mapper, operation_opts} = Keyword.pop(opts, :on_result, &{:clipboard_result, &1})
    Command.clipboard(operation(content, operation_opts), mapper)
  end

  @doc "Creates a runtime command that clears a terminal clipboard target."
  @spec clear(keyword()) :: Command.clipboard_command()
  def clear(opts \\ []) do
    {mapper, operation_opts} = Keyword.pop(opts, :on_result, &{:clipboard_result, &1})
    Command.clipboard(clear_operation(operation_opts), mapper)
  end

  @doc "Encodes an OSC 52 operation without performing IO."
  @spec sequence(Operation.t()) :: {:ok, String.t()} | {:error, term()}
  def sequence(%Operation{kind: kind, content: content, max_bytes: maximum} = operation) do
    size = byte_size(content)

    if size > maximum do
      {:error, {:clipboard_too_large, size, maximum}}
    else
      payload = if kind == :clear, do: "", else: Base.encode64(content)
      {:ok, @osc52_prefix <> target_code(operation.target) <> ";" <> payload <> @osc52_suffix}
    end
  end

  @doc "Returns true when the current terminal is likely to support OSC 52."
  @spec osc52_supported?() :: boolean()
  def osc52_supported? do
    term = System.get_env("TERM", "")
    program = System.get_env("TERM_PROGRAM", "")

    String.contains?(program, ["iTerm", "Alacritty", "WezTerm", "Apple_Terminal"]) or
      System.get_env("KITTY_WINDOW_ID") != nil or String.starts_with?(term, "xterm") or
      term in ["foot", "foot-extra"]
  end

  defp target!(opts) do
    target = Keyword.get(opts, :target, :clipboard)

    if target in @targets,
      do: target,
      else: raise(ArgumentError, "clipboard target must be :clipboard, :primary, or :secondary")
  end

  defp max_bytes!(opts) do
    case Keyword.get(opts, :max_bytes, @default_max_bytes) do
      maximum when is_integer(maximum) and maximum > 0 -> maximum
      other -> raise ArgumentError, "clipboard max_bytes must be positive, got: #{inspect(other)}"
    end
  end

  defp target_code(:clipboard), do: "c"
  defp target_code(:primary), do: "p"
  defp target_code(:secondary), do: "s"
end
