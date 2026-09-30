defmodule TermUI.Backend.InputBuffer do
  @moduledoc false

  require Logger

  # Maximum buffer size before truncation (1KB)
  @max_buffer_size 1024

  # Number of bytes to keep when truncating (preserves partial sequences)
  @keep_size 256
  @paste_start "\e[200~"
  @paste_end "\e[201~"
  @max_paste_size 8 * 1024 * 1024

  # Minimum time between overflow warnings (5 seconds in milliseconds)
  @warning_interval_ms 5_000

  # ETS table for tracking last warning times (created on first use)
  @warning_table :term_ui_input_buffer_warnings

  @doc """
  Returns the maximum buffer size allowed.

  ## Examples

      iex> TermUI.Backend.InputBuffer.max_size()
      1024
  """
  @spec max_size() :: 1024
  def max_size, do: @max_buffer_size

  @doc """
  Returns the number of bytes kept when truncating.

  ## Examples

      iex> TermUI.Backend.InputBuffer.keep_size()
      256
  """
  @spec keep_size() :: 256
  def keep_size, do: @keep_size

  @doc """
  Appends data to a buffer and returns the new buffer.

  This is a simple append without limit checking. Use `apply_limit/2`
  or `append_with_limit/4` for protected appending.

  ## Parameters

  - `buffer` - The existing buffer (binary)
  - `data` - Data to append (binary)

  ## Returns

  The combined buffer.

  ## Examples

      iex> TermUI.Backend.InputBuffer.append("hello", " world")
      "hello world"
  """
  @spec append(binary(), binary()) :: binary()
  def append(buffer, data) when is_binary(buffer) and is_binary(data) do
    buffer <> data
  end

  @doc """
  Applies the buffer size limit, truncating if necessary.

  If the buffer exceeds the maximum size, it is truncated to keep only
  the most recent bytes (to preserve potential partial escape sequences).

  ## Parameters

  - `buffer` - The buffer to check (binary)
  - `opts` - Options:
    - `:source` - Identifier for rate-limited logging (default: `:unknown`)
    - `:log` - Whether to log overflow (default: `true`)

  ## Returns

  Tuple of `{limited_buffer, overflowed?}`.

  ## Examples

      iex> {buffer, false} = TermUI.Backend.InputBuffer.apply_limit("short")
      iex> buffer
      "short"

      iex> long = String.duplicate("x", 2000)
      iex> {buffer, true} = TermUI.Backend.InputBuffer.apply_limit(long, source: :test)
      iex> byte_size(buffer)
      256
  """
  @spec apply_limit(binary(), keyword()) :: {binary(), boolean()}
  def apply_limit(buffer, opts \\ []) when is_binary(buffer) do
    buffer_size = byte_size(buffer)

    if buffer_size > @max_buffer_size do
      # Keep only the most recent bytes
      actual_keep = min(@keep_size, buffer_size)
      truncated = binary_part(buffer, buffer_size - actual_keep, actual_keep)

      # Rate-limited logging
      source = Keyword.get(opts, :source, :unknown)
      should_log = Keyword.get(opts, :log, true)

      if should_log do
        maybe_log_overflow(source, buffer_size, actual_keep)
      end

      {truncated, true}
    else
      {buffer, false}
    end
  end

  @doc """
  Appends data to a state's buffer field with limit protection.

  This is a convenience function that:
  1. Appends data to the specified buffer field
  2. Applies the size limit
  3. Returns the updated state

  ## Parameters

  - `state` - Map or struct containing the buffer
  - `data` - Data to append (binary)
  - `field` - The field name containing the buffer (atom)
  - `opts` - Options passed to `apply_limit/2`

  ## Returns

  The updated state with the new buffer value.

  ## Examples

      iex> state = %{input_buffer: "partial"}
      iex> new_state = TermUI.Backend.InputBuffer.append_with_limit(state, "[A", :input_buffer)
      iex> new_state.input_buffer
      "partial[A"
  """
  @spec append_with_limit(map(), binary(), atom(), keyword()) :: map()
  def append_with_limit(state, data, field, opts \\ []) when is_map(state) and is_atom(field) do
    if Keyword.get(opts, :paste_aware, false) do
      append_terminal_input(state, data, field, opts)
    else
      current = Map.get(state, field, "")
      new_buffer = append(current, data)
      {limited, _overflowed} = apply_limit(new_buffer, opts)
      Map.put(state, field, limited)
    end
  end

  defp append_terminal_input(state, data, field, opts) do
    case Map.get(state, :paste_state) do
      %{mode: :collecting} = paste -> append_paste_data(state, paste, data, field, opts)
      %{mode: :discarding} = paste -> discard_paste_data(state, paste, data, field, opts)
      _ -> append_regular_terminal_input(state, data, field, opts)
    end
  end

  defp append_regular_terminal_input(state, data, field, opts) do
    buffer = append(Map.get(state, field, ""), data)

    cond do
      String.starts_with?(buffer, @paste_start) ->
        body =
          binary_part(
            buffer,
            byte_size(@paste_start),
            byte_size(buffer) - byte_size(@paste_start)
          )

        state
        |> Map.put(field, @paste_start)
        |> Map.put(:paste_state, %{mode: :collecting, chunks: [], size: 0, end_buffer: ""})
        |> append_terminal_input(body, field, opts)

      byte_size(buffer) > @max_buffer_size ->
        maybe_log_terminal_overflow(opts, byte_size(buffer))
        Map.put(state, field, "")

      true ->
        Map.put(state, field, buffer)
    end
  end

  defp append_paste_data(state, paste, data, field, opts) do
    data = paste.end_buffer <> data

    case :binary.match(data, @paste_end) do
      {position, marker_size} ->
        body = binary_part(data, 0, position)

        trailing =
          binary_part(data, position + marker_size, byte_size(data) - position - marker_size)

        complete_paste(state, paste, body, trailing, field, opts)

      :nomatch ->
        {body, end_buffer} = split_end_marker_prefix(data)
        body_size = paste.size + byte_size(body)

        if body_size > @max_paste_size do
          discard_paste(state, body_size, end_buffer, field, opts)
        else
          state
          |> Map.put(field, @paste_start)
          |> Map.put(:paste_state, %{
            paste
            | chunks: prepend_chunk(paste.chunks, body),
              size: body_size,
              end_buffer: end_buffer
          })
        end
    end
  end

  defp complete_paste(state, paste, body, trailing, field, opts) do
    body_size = paste.size + byte_size(body)

    if body_size > @max_paste_size do
      discard_paste(state, body_size, "", field, opts, @paste_end <> trailing)
    else
      content =
        paste.chunks
        |> prepend_chunk(body)
        |> Enum.reverse()
        |> IO.iodata_to_binary()

      {trailing, _overflowed} = apply_limit(trailing, opts)

      state
      |> Map.put(field, @paste_start <> content <> @paste_end <> trailing)
      |> Map.put(:paste_state, nil)
    end
  end

  defp discard_paste(state, body_size, end_buffer, field, opts, remaining \\ "") do
    maybe_log_terminal_overflow(opts, body_size)

    state =
      state
      |> Map.put(field, "")
      |> Map.put(:paste_state, %{mode: :discarding, end_buffer: end_buffer})

    if remaining == "" do
      state
    else
      discard_paste_data(state, state.paste_state, remaining, field, opts)
    end
  end

  defp discard_paste_data(state, paste, data, field, opts) do
    data = paste.end_buffer <> data

    case :binary.match(data, @paste_end) do
      {position, marker_size} ->
        trailing =
          binary_part(data, position + marker_size, byte_size(data) - position - marker_size)

        state
        |> Map.put(field, "")
        |> Map.put(:paste_state, nil)
        |> append_terminal_input(trailing, field, opts)

      :nomatch ->
        {_discarded, end_buffer} = split_end_marker_prefix(data)

        state
        |> Map.put(field, "")
        |> Map.put(:paste_state, %{mode: :discarding, end_buffer: end_buffer})
    end
  end

  defp split_end_marker_prefix(data) do
    max_prefix_size = min(byte_size(data), byte_size(@paste_end) - 1)

    prefix_size =
      if max_prefix_size == 0 do
        0
      else
        Enum.find(Range.new(max_prefix_size, 1, -1), 0, fn size ->
          suffix = binary_part(data, byte_size(data) - size, size)
          String.starts_with?(@paste_end, suffix)
        end)
      end

    body_size = byte_size(data) - prefix_size
    {binary_part(data, 0, body_size), binary_part(data, body_size, prefix_size)}
  end

  defp prepend_chunk(chunks, ""), do: chunks
  defp prepend_chunk(chunks, chunk), do: [chunk | chunks]

  defp maybe_log_terminal_overflow(opts, size) do
    if Keyword.get(opts, :log, true) do
      maybe_log_overflow(Keyword.get(opts, :source, :unknown), size, 0)
    end
  end

  # ===========================================================================
  # Rate-Limited Logging
  # ===========================================================================

  # Logs a warning if enough time has passed since the last warning.
  @spec maybe_log_overflow(term(), pos_integer(), non_neg_integer()) :: :ok
  defp maybe_log_overflow(source, original_size, keep_size) do
    now = System.monotonic_time(:millisecond)

    case get_last_warning_time(source) do
      nil ->
        # First overflow for this source
        set_last_warning_time(source, now)
        do_log_overflow(source, original_size, keep_size)

      last_time when now - last_time >= @warning_interval_ms ->
        # Enough time has passed
        set_last_warning_time(source, now)
        do_log_overflow(source, original_size, keep_size)

      _last_time ->
        # Too soon, skip logging
        :ok
    end
  end

  defp do_log_overflow(source, original_size, keep_size) do
    Logger.warning(
      "Input buffer overflow (#{original_size} bytes) in #{inspect(source)}, " <>
        "truncating to #{keep_size} bytes"
    )
  end

  # Gets the last warning time for a source from ETS.
  @spec get_last_warning_time(term()) :: integer() | nil
  defp get_last_warning_time(source) do
    ensure_table_exists()

    case :ets.lookup(@warning_table, source) do
      [{^source, time}] -> time
      [] -> nil
    end
  end

  # Sets the last warning time for a source in ETS.
  @spec set_last_warning_time(term(), integer()) :: true
  defp set_last_warning_time(source, time) do
    ensure_table_exists()
    :ets.insert(@warning_table, {source, time})
  end

  # Ensures the ETS table exists.
  @spec ensure_table_exists() :: :ok
  defp ensure_table_exists do
    case :ets.whereis(@warning_table) do
      :undefined ->
        # Create the table - it might race with another process
        try do
          _table = :ets.new(@warning_table, [:set, :public, :named_table])
          :ok
        rescue
          ArgumentError ->
            # Table already exists (race condition), that's fine
            :ok
        end

      _tid ->
        :ok
    end

    :ok
  end

  @doc """
  Clears the rate limit state (useful for testing).

  ## Examples

      iex> TermUI.Backend.InputBuffer.clear_rate_limits()
      :ok
  """
  @spec clear_rate_limits() :: :ok
  def clear_rate_limits do
    case :ets.whereis(@warning_table) do
      :undefined -> :ok
      _tid -> :ets.delete_all_objects(@warning_table)
    end

    :ok
  end
end
