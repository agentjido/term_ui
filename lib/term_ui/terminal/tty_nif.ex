defmodule TermUI.Terminal.TtyNif do
  @moduledoc false

  @dialyzer {:nowarn_function, [loaded?: 0, disable_control_flags: 0, restore_control_flags: 1]}

  @type control_flags :: {non_neg_integer(), non_neg_integer()}
  @type error_reason :: :nif_not_loaded | {:posix | :win32, non_neg_integer()}
  @type load_error :: {:priv_dir_unavailable, term()} | {:load_failed, term(), String.t()}

  @doc false
  @spec ensure_loaded() :: :ok | {:error, load_error()}
  def ensure_loaded do
    if apply(__MODULE__, :loaded?, []), do: :ok, else: load_nif()
  end

  @doc false
  @spec load_nif() :: :ok | {:error, load_error()}
  def load_nif do
    case :code.priv_dir(:term_ui) do
      directory when is_list(directory) ->
        path = :filename.join(directory, ~c"term_ui_tty_nif")

        case :erlang.load_nif(path, 0) do
          :ok -> :ok
          {:error, {operation, _detail}} when operation in [:reload, :upgrade] -> :ok
          {:error, {reason, detail}} -> {:error, {:load_failed, reason, to_string(detail)}}
        end

      {:error, reason} ->
        {:error, {:priv_dir_unavailable, reason}}
    end
  end

  @doc false
  @spec loaded?() :: boolean()
  def loaded?, do: false

  @doc false
  @spec disable_control_flags() :: {:ok, control_flags()} | {:error, error_reason()}
  def disable_control_flags, do: {:error, :nif_not_loaded}

  @doc false
  @spec restore_control_flags(control_flags()) :: :ok | {:error, error_reason()}
  def restore_control_flags(_flags), do: {:error, :nif_not_loaded}
end
