defmodule TermUI.Config do
  @moduledoc """
  Adapts known v1 application environment values to v2 runtime options.

  Explicit runtime and backend options always take precedence. Each v1 key
  emits one deprecation warning for the life of the VM when TermUI uses it.
  """

  require Logger

  @warning_key {__MODULE__, :deprecated_warnings}
  @backend_values [:auto, :raw, :tty]
  @color_values [:auto, :true_color, :color_256, :color_16, :monochrome]
  @character_values [:auto, :unicode, :ascii]
  @iex_values [:auto, true, false]

  @type error :: {:invalid_legacy_config, atom(), term(), String.t()}

  @doc "Merges supported v1 application environment values into v2 runtime options."
  @spec merge_runtime_options(keyword()) :: {:ok, keyword()} | {:error, error()}
  def merge_runtime_options(opts) when is_list(opts) do
    with {:ok, opts} <- merge_backend(opts),
         {:ok, opts} <- merge_color_mode(opts),
         {:ok, opts} <- merge_character_set(opts),
         {:ok, opts} <- merge_render_interval(opts) do
      merge_iex_mode(opts)
    end
  end

  @doc false
  @spec reset_deprecation_warnings() :: :ok
  def reset_deprecation_warnings do
    :persistent_term.erase(@warning_key)
    :ok
  end

  defp merge_backend(opts) do
    merge_runtime_option(opts, :backend, :backend, @backend_values, & &1)
  end

  defp merge_color_mode(opts) do
    merge_backend_option(opts, :color_mode, :color_mode, @color_values)
  end

  defp merge_character_set(opts) do
    merge_backend_option(opts, :character_set, :character_set, @character_values)
  end

  defp merge_render_interval(opts) do
    if Keyword.has_key?(opts, :render_interval) do
      {:ok, opts}
    else
      case Application.fetch_env(:term_ui, :render_interval) do
        {:ok, interval} when is_integer(interval) and interval > 0 ->
          warn_once(:render_interval, ":render_interval runtime option")
          {:ok, Keyword.put(opts, :render_interval, interval)}

        {:ok, invalid} ->
          invalid(:render_interval, invalid, "expected a positive integer")

        :error ->
          {:ok, opts}
      end
    end
  end

  defp merge_iex_mode(opts) do
    if Keyword.has_key?(opts, :backend) do
      {:ok, opts}
    else
      case Application.fetch_env(:term_ui, :iex_compatible) do
        {:ok, value} ->
          merge_iex_value(opts, value)

        :error ->
          {:ok, opts}
      end
    end
  end

  defp merge_runtime_option(opts, new_key, old_key, valid_values, mapper) do
    if Keyword.has_key?(opts, new_key) do
      {:ok, opts}
    else
      case Application.fetch_env(:term_ui, old_key) do
        {:ok, value} ->
          merge_validated_runtime_option(opts, new_key, old_key, value, valid_values, mapper)

        :error ->
          {:ok, opts}
      end
    end
  end

  defp merge_backend_option(opts, old_key, new_key, valid_values) do
    if backend_option_present?(opts, new_key) do
      {:ok, opts}
    else
      case Application.fetch_env(:term_ui, old_key) do
        {:ok, value} ->
          merge_validated_backend_option(opts, old_key, new_key, value, valid_values)

        :error ->
          {:ok, opts}
      end
    end
  end

  defp merge_iex_value(opts, value) when value in @iex_values do
    warn_once(:iex_compatible, ":backend runtime option")
    backend = if value == true, do: :tty, else: :auto
    {:ok, Keyword.put(opts, :backend, backend)}
  end

  defp merge_iex_value(_opts, invalid) do
    invalid(:iex_compatible, invalid, "expected :auto, true, or false")
  end

  defp merge_validated_runtime_option(opts, new_key, old_key, value, valid_values, mapper) do
    if value in valid_values do
      warn_once(old_key, ":#{new_key} runtime option")
      {:ok, Keyword.put(opts, new_key, mapper.(value))}
    else
      invalid_value(old_key, value, valid_values)
    end
  end

  defp merge_validated_backend_option(opts, old_key, new_key, value, valid_values) do
    if value in valid_values do
      warn_once(old_key, ":backend_opts option :#{new_key}")
      {:ok, put_backend_option(opts, new_key, value)}
    else
      invalid_value(old_key, value, valid_values)
    end
  end

  defp invalid_value(key, value, valid_values) do
    expected = Enum.map_join(valid_values, ", ", &inspect/1)
    invalid(key, value, "expected one of #{expected}")
  end

  defp backend_option_present?(opts, key) do
    explicit_backend_opts?(Keyword.fetch(opts, :backend_opts), key) or
      explicit_backend_spec_opts?(Keyword.get(opts, :backend), key)
  end

  defp explicit_backend_opts?({:ok, opts}, key) when is_list(opts),
    do: Keyword.has_key?(opts, key)

  defp explicit_backend_opts?({:ok, _invalid}, _key), do: true
  defp explicit_backend_opts?(:error, _key), do: false

  defp explicit_backend_spec_opts?({_module, opts}, key) when is_list(opts),
    do: Keyword.has_key?(opts, key)

  defp explicit_backend_spec_opts?(_backend, _key), do: false

  defp put_backend_option(opts, key, value) do
    Keyword.update(opts, :backend_opts, [{key, value}], &Keyword.put_new(&1, key, value))
  end

  defp invalid(key, value, expectation) do
    warn_once(key, "the matching v2 runtime or backend option")
    {:error, {:invalid_legacy_config, key, value, expectation}}
  end

  defp warn_once(key, replacement) do
    lock = {{__MODULE__, key}, self()}

    _result =
      :global.trans(lock, fn ->
        warned = :persistent_term.get(@warning_key, MapSet.new())

        unless MapSet.member?(warned, key) do
          Logger.warning(
            "config :term_ui, #{inspect(key)} is deprecated; use the #{replacement} instead"
          )

          :persistent_term.put(@warning_key, MapSet.put(warned, key))
        end
      end)

    :ok
  end
end
