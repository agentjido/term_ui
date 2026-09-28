defmodule TermUI.Widgets.VisualizationHelper do
  @moduledoc """
  Shared utilities for visualization widgets (charts, gauges, sparklines).

  Provides common functions for:
  - Value normalization and scaling
  - Number formatting
  - Color/zone threshold mapping
  - Min/max range calculation
  - Input validation
  - Style application

  ## Usage

      alias TermUI.Widgets.VisualizationHelper, as: VizHelper

      # Normalize a value to 0-1 range
      VizHelper.normalize(75, 0, 100)
      #=> 0.75

      # Format numbers for display
      VizHelper.format_number(3.14159)
      #=> "3.1"

      # Find style based on threshold zones
      zones = [{0, :green}, {60, :yellow}, {80, :red}]
      VizHelper.find_zone(85, zones)
      #=> :red
  """

  # Maximum dimensions to prevent memory exhaustion
  @max_width 1000
  @max_height 500

  # Dialyzer: Functions return specific types or constants
  @dialyzer {:nowarn_function, max_width: 0, max_height: 0, maybe_style: 2}

  @doc """
  Returns the maximum allowed width for visualization widgets.
  """
  @spec max_width() :: pos_integer()
  def max_width, do: @max_width

  @doc """
  Returns the maximum allowed height for visualization widgets.
  """
  @spec max_height() :: pos_integer()
  def max_height, do: @max_height

  @doc """
  Clamps width to safe bounds.

  ## Examples

      iex> VisualizationHelper.clamp_width(50)
      50

      iex> VisualizationHelper.clamp_width(2000)
      1000

      iex> VisualizationHelper.clamp_width(-5)
      1
  """
  @spec clamp_width(integer()) :: pos_integer()
  def clamp_width(width) when is_integer(width) do
    width |> max(1) |> min(@max_width)
  end

  def clamp_width(_), do: 40

  @doc """
  Clamps height to safe bounds.

  ## Examples

      iex> VisualizationHelper.clamp_height(20)
      20

      iex> VisualizationHelper.clamp_height(1000)
      500

      iex> VisualizationHelper.clamp_height(-5)
      1
  """
  @spec clamp_height(integer()) :: pos_integer()
  def clamp_height(height) when is_integer(height) do
    height |> max(1) |> min(@max_height)
  end

  def clamp_height(_), do: 10

  @doc """
  Normalizes a value to 0-1 range based on min/max bounds.
  Clamps result to [0, 1].

  Returns 0.5 when min equals max to avoid division by zero.

  ## Examples

      iex> VisualizationHelper.normalize(50, 0, 100)
      0.5

      iex> VisualizationHelper.normalize(75, 0, 100)
      0.75

      iex> VisualizationHelper.normalize(150, 0, 100)
      1.0

      iex> VisualizationHelper.normalize(-10, 0, 100)
      0.0

      iex> VisualizationHelper.normalize(50, 50, 50)
      0.5
  """
  @spec normalize(number(), number(), number()) :: float()
  def normalize(value, min, max) when is_number(value) and is_number(min) and is_number(max) do
    if max > min do
      normalized = (value - min) / (max - min)
      normalized |> max(0.0) |> min(1.0)
    else
      0.5
    end
  end

  def normalize(_, _, _), do: 0.5

  @doc """
  Scales a normalized value (0-1) to a target size.

  ## Examples

      iex> VisualizationHelper.scale(0.5, 100)
      50

      iex> VisualizationHelper.scale(0.75, 20)
      15
  """
  @spec scale(float(), number()) :: integer()
  def scale(normalized, target_size) when is_number(normalized) and is_number(target_size) do
    round(normalized * target_size)
  end

  @doc """
  Normalizes and scales a value in one step.

  ## Examples

      iex> VisualizationHelper.normalize_and_scale(50, 0, 100, 20)
      10

      iex> VisualizationHelper.normalize_and_scale(75, 0, 100, 40)
      30
  """
  @spec normalize_and_scale(number(), number(), number(), number()) :: integer()
  def normalize_and_scale(value, min, max, target_size) do
    value
    |> normalize(min, max)
    |> scale(target_size)
  end

  @doc """
  Formats a numeric value for display.

  - Floats are formatted to 1 decimal place
  - Integers are converted to string
  - Other values return "???"

  ## Examples

      iex> VisualizationHelper.format_number(42)
      "42"

      iex> VisualizationHelper.format_number(3.14159)
      "3.1"

      iex> VisualizationHelper.format_number(:not_a_number)
      "???"
  """
  @spec format_number(any()) :: String.t()
  def format_number(value) when is_float(value) do
    :erlang.float_to_binary(value, decimals: 1)
  end

  def format_number(value) when is_integer(value) do
    Integer.to_string(value)
  end

  def format_number(_value), do: "???"

  @doc """
  Finds the appropriate style/color for a value based on threshold zones.

  Zones should be a list of `{threshold, style}` tuples. The function returns
  the style associated with the highest threshold that is <= the value.

  ## Examples

      iex> zones = [{0, :green}, {60, :yellow}, {80, :red}]
      iex> VisualizationHelper.find_zone(50, zones)
      :green

      iex> zones = [{0, :green}, {60, :yellow}, {80, :red}]
      iex> VisualizationHelper.find_zone(75, zones)
      :yellow

      iex> zones = [{0, :green}, {60, :yellow}, {80, :red}]
      iex> VisualizationHelper.find_zone(90, zones)
      :red

      iex> VisualizationHelper.find_zone(50, [])
      nil
  """
  @spec find_zone(number(), [{number(), any()}]) :: any() | nil
  def find_zone(_value, []), do: nil

  def find_zone(value, zones) when is_number(value) and is_list(zones) do
    zones
    |> Enum.sort_by(fn {threshold, _} -> -threshold end)
    |> Enum.find_value(fn {threshold, style} ->
      if value >= threshold, do: style
    end)
  end

  def find_zone(_, _), do: nil

  @doc """
  Calculates min/max range from data, with optional overrides.

  ## Examples

      iex> VisualizationHelper.calculate_range([1, 5, 3, 9, 2])
      {1, 9}

      iex> VisualizationHelper.calculate_range([1, 5, 3], min: 0)
      {0, 5}

      iex> VisualizationHelper.calculate_range([1, 5, 3], min: 0, max: 10)
      {0, 10}

      iex> VisualizationHelper.calculate_range([])
      {0, 1}
  """
  @spec calculate_range([number()], keyword()) :: {number(), number()}
  def calculate_range(values, opts \\ [])
  def calculate_range([], _opts), do: {0, 1}

  def calculate_range(values, opts) when is_list(values) and values != [] do
    min_val = Keyword.get_lazy(opts, :min, fn -> Enum.min(values) end)
    max_val = Keyword.get_lazy(opts, :max, fn -> Enum.max(values) end)
    {min_val, max_val}
  end

  def calculate_range(_, _), do: {0, 1}

  @doc """
  Applies style conditionally to a render node.

  Returns the node unchanged if style is nil.

  ## Examples

      iex> node = %{type: :text, content: "hello"}
      iex> VisualizationHelper.maybe_style(node, nil)
      %{type: :text, content: "hello"}
  """
  @spec maybe_style(any(), any()) :: any()
  def maybe_style(node, nil), do: node

  def maybe_style(node, style) do
    import TermUI.Component.RenderNode
    styled(node, style)
  end

  @doc """
  Gets a color from a list by cycling through indices.

  ## Examples

      iex> colors = [:red, :blue, :green]
      iex> VisualizationHelper.cycle_color(colors, 0)
      :red

      iex> colors = [:red, :blue, :green]
      iex> VisualizationHelper.cycle_color(colors, 4)
      :blue

      iex> VisualizationHelper.cycle_color([], 0)
      nil
  """
  @spec cycle_color([any()], non_neg_integer()) :: any() | nil
  def cycle_color([], _index), do: nil

  def cycle_color(colors, index) when is_list(colors) and is_integer(index) do
    Enum.at(colors, rem(index, length(colors)))
  end

  # =============================================================================
  # Input Validation
  # =============================================================================

  @doc """
  Validates that a value is a number.

  ## Examples

      iex> VisualizationHelper.validate_number(42)
      :ok

      iex> VisualizationHelper.validate_number(3.14)
      :ok

      iex> VisualizationHelper.validate_number("not a number")
      {:error, "expected a number, got: \\"not a number\\""}
  """
  @spec validate_number(any()) :: :ok | {:error, String.t()}
  def validate_number(value) when is_number(value), do: :ok
  def validate_number(value), do: {:error, "expected a number, got: #{inspect(value)}"}

  @doc """
  Validates that all values in a list are numbers.

  ## Examples

      iex> VisualizationHelper.validate_number_list([1, 2, 3])
      :ok

      iex> VisualizationHelper.validate_number_list([1, "two", 3])
      {:error, "all values must be numbers, found non-number at index 1"}

      iex> VisualizationHelper.validate_number_list("not a list")
      {:error, "expected a list of numbers"}
  """
  @spec validate_number_list(any()) :: :ok | {:error, String.t()}
  def validate_number_list(values) when is_list(values) do
    case Enum.find_index(values, fn v -> not is_number(v) end) do
      nil -> :ok
      index -> {:error, "all values must be numbers, found non-number at index #{index}"}
    end
  end

  def validate_number_list(_), do: {:error, "expected a list of numbers"}

  @doc """
  Validates bar chart data structure.

  Each item must be a map with :label (string) and :value (number) keys.

  ## Examples

      iex> data = [%{label: "A", value: 10}, %{label: "B", value: 20}]
      iex> VisualizationHelper.validate_bar_data(data)
      :ok

      iex> VisualizationHelper.validate_bar_data([%{label: "A"}])
      {:error, "bar data item at index 0 missing :value key"}

      iex> VisualizationHelper.validate_bar_data("not a list")
      {:error, "expected a list of bar data items"}
  """
  @spec validate_bar_data(any()) :: :ok | {:error, String.t()}
  def validate_bar_data(data) when is_list(data) do
    data
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, _acc ->
      case validate_bar_item(item, index) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def validate_bar_data(_), do: {:error, "expected a list of bar data items"}

  defp validate_bar_item(item, index) when is_map(item) do
    cond do
      not Map.has_key?(item, :label) ->
        {:error, "bar data item at index #{index} missing :label key"}

      not Map.has_key?(item, :value) ->
        {:error, "bar data item at index #{index} missing :value key"}

      not is_binary(item.label) ->
        {:error, "bar data item at index #{index} :label must be a string"}

      not is_number(item.value) ->
        {:error, "bar data item at index #{index} :value must be a number"}

      true ->
        :ok
    end
  end

  defp validate_bar_item(_, index) do
    {:error, "bar data item at index #{index} must be a map with :label and :value"}
  end

  @doc """
  Validates line chart series data structure.

  Each series must be a map with `:data` containing a list of numbers. Extra
  keys are allowed but are not interpreted by this validator or `LineChart`.

  ## Examples

      iex> series = [%{data: [1, 2, 3]}, %{data: [4, 5, 6]}]
      iex> VisualizationHelper.validate_series_data(series)
      :ok

      iex> VisualizationHelper.validate_series_data([%{data: "not a list"}])
      {:error, "series at index 0 :data must be a list of numbers"}
  """
  @spec validate_series_data(any()) :: :ok | {:error, String.t()}
  def validate_series_data(series) when is_list(series) do
    series
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {item, index}, _acc ->
      case validate_series_item(item, index) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  def validate_series_data(_), do: {:error, "expected a list of series"}

  defp validate_series_item(item, index) when is_map(item) do
    cond do
      not Map.has_key?(item, :data) ->
        {:error, "series at index #{index} missing :data key"}

      not is_list(item.data) ->
        {:error, "series at index #{index} :data must be a list of numbers"}

      not Enum.all?(item.data, &is_number/1) ->
        {:error, "series at index #{index} :data must contain only numbers"}

      true ->
        :ok
    end
  end

  defp validate_series_item(_, index) do
    {:error, "series at index #{index} must be a map with :data key"}
  end

  @doc """
  Validates that a character is a single printable character.

  ## Examples

      iex> VisualizationHelper.validate_char("█")
      :ok

      iex> VisualizationHelper.validate_char("ab")
      {:error, "expected a single character, got 2 characters"}

      iex> VisualizationHelper.validate_char("")
      {:error, "expected a single character, got empty string"}
  """
  @spec validate_char(any()) :: :ok | {:error, String.t()}
  def validate_char(char) when is_binary(char) do
    graphemes = String.graphemes(char)

    case length(graphemes) do
      1 -> :ok
      0 -> {:error, "expected a single character, got empty string"}
      n -> {:error, "expected a single character, got #{n} characters"}
    end
  end

  def validate_char(_), do: {:error, "expected a string character"}

  @doc """
  Safely duplicates a string with bounds checking.

  Prevents memory exhaustion by clamping count to reasonable bounds.

  ## Examples

      iex> VisualizationHelper.safe_duplicate("█", 5)
      "█████"

      iex> VisualizationHelper.safe_duplicate("█", -5)
      ""

      iex> VisualizationHelper.safe_duplicate("█", 10000)
      # Returns string with max_width characters
  """
  @spec safe_duplicate(String.t(), integer()) :: String.t()
  def safe_duplicate(string, count) when is_binary(string) and is_integer(count) do
    safe_count = count |> max(0) |> min(@max_width)
    String.duplicate(string, safe_count)
  end

  def safe_duplicate(_, _), do: ""
end
