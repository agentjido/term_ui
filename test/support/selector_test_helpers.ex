defmodule TermUI.Backend.SelectorTestHelpers do
  @moduledoc """
  Test helpers for TermUI.Backend.Selector tests.

  Provides utilities for environment variable management and result validation
  to reduce duplication in selector tests.
  """

  import ExUnit.Assertions

  @doc """
  Executes a test function with temporary environment variable settings.

  Saves the original values of specified environment variables, sets new values
  for the duration of the test, and restores originals afterward.

  ## Parameters

  - `env_vars` - Map of environment variable names to values. Use `nil` to delete a variable.
  - `test_fn` - Zero-arity function containing the test logic.

  ## Examples

      with_env(%{"COLORTERM" => "truecolor"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.colors == :true_color
      end)

      with_env(%{"COLORTERM" => nil, "TERM" => "xterm-256color"}, fn ->
        caps = Selector.detect_capabilities()
        assert caps.colors == :color_256
      end)
  """
  @spec with_env(map(), (-> any())) :: any()
  def with_env(env_vars, test_fn) when is_map(env_vars) and is_function(test_fn, 0) do
    # Save original values
    original_values =
      Map.new(env_vars, fn {key, _val} ->
        {key, System.get_env(key)}
      end)

    try do
      # Set new values
      Enum.each(env_vars, fn {key, value} ->
        if value do
          System.put_env(key, value)
        else
          System.delete_env(key)
        end
      end)

      # Run test
      test_fn.()
    after
      # Restore original values
      Enum.each(original_values, fn {key, original} ->
        if original do
          System.put_env(key, original)
        else
          System.delete_env(key)
        end
      end)
    end
  end

  @doc """
  Asserts that a capabilities map has the expected structure and valid values.

  Validates that the map contains all required keys (`:colors`, `:unicode`,
  `:dimensions`, `:terminal`) with appropriate types.

  ## Examples

      caps = Selector.detect_capabilities()
      assert_valid_capabilities(caps)
  """
  @spec assert_valid_capabilities(map()) :: :ok
  def assert_valid_capabilities(caps) when is_map(caps) do
    assert Map.has_key?(caps, :colors), "capabilities should have :colors key"
    assert Map.has_key?(caps, :unicode), "capabilities should have :unicode key"
    assert Map.has_key?(caps, :dimensions), "capabilities should have :dimensions key"
    assert Map.has_key?(caps, :terminal), "capabilities should have :terminal key"

    assert caps.colors in [:true_color, :color_256, :color_16, :monochrome],
           "colors should be a valid color_depth atom"

    assert is_boolean(caps.unicode), "unicode should be a boolean"
    assert is_boolean(caps.terminal), "terminal should be a boolean"

    case caps.dimensions do
      nil ->
        :ok

      {rows, cols} ->
        assert is_integer(rows) and rows > 0, "rows should be a positive integer"
        assert is_integer(cols) and cols > 0, "cols should be a positive integer"

      other ->
        flunk("dimensions should be nil or {rows, cols}, got: #{inspect(other)}")
    end

    :ok
  end

  @doc """
  Asserts that a raw state map has the expected structure.

  Validates that the map contains the active raw-mode session.

  ## Examples

      {:raw, state} = Selector.select()
      assert_valid_raw_state(state)
  """
  @spec assert_valid_raw_state(map()) :: :ok
  def assert_valid_raw_state(state) when is_map(state) do
    assert Map.has_key?(state, :raw_mode_started),
           "raw state should have :raw_mode_started key"

    assert state.raw_mode_started == true,
           "raw_mode_started should be true"

    assert Map.has_key?(state, :raw_mode_session),
           "raw state should have :raw_mode_session key"

    :ok
  end

  @doc """
  Asserts that a selection result is valid (either raw or tty mode).

  Validates the result matches one of the expected patterns and delegates
  to the appropriate validation function.

  ## Examples

      result = Selector.select()
      assert_valid_selection_result(result)
  """
  @spec assert_valid_selection_result({atom(), map()}) :: :ok
  def assert_valid_selection_result(result) do
    assert is_tuple(result), "result should be a tuple"
    assert tuple_size(result) == 2, "result should be a 2-tuple"

    case result do
      {:raw, state} ->
        assert_valid_raw_state(state)

      {:tty, caps} ->
        assert_valid_capabilities(caps)

      other ->
        flunk("result should be {:raw, state} or {:tty, caps}, got: #{inspect(other)}")
    end
  end
end
