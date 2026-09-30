defmodule TermUI.Backend.CapabilityFilter do
  @moduledoc false

  @color_rank %{monochrome: 0, color_16: 1, color_256: 2, true_color: 3}

  @doc false
  @spec filter(map(), keyword()) :: map()
  def filter(capabilities, opts) when is_map(capabilities) and is_list(opts) do
    actual_color = normalize_color(Map.get(capabilities, :colors, :true_color))
    actual_unicode = Map.get(capabilities, :unicode, true) == true

    capabilities
    |> Map.put(:colors, effective_color(actual_color, Keyword.get(opts, :color_mode, :auto)))
    |> Map.put(
      :unicode,
      effective_unicode(actual_unicode, Keyword.get(opts, :character_set, :auto))
    )
  end

  def filter(capabilities, _invalid_opts) when is_map(capabilities), do: capabilities

  defp effective_color(actual, :auto), do: actual

  defp effective_color(actual, requested) when is_map_key(@color_rank, requested) do
    if @color_rank[requested] <= @color_rank[actual], do: requested, else: actual
  end

  defp effective_color(actual, _invalid), do: actual

  defp effective_unicode(actual, :auto), do: actual
  defp effective_unicode(_actual, :ascii), do: false
  defp effective_unicode(actual, :unicode), do: actual
  defp effective_unicode(actual, _invalid), do: actual

  defp normalize_color(:true_color), do: :true_color
  defp normalize_color(:color_256), do: :color_256
  defp normalize_color(:color_16), do: :color_16
  defp normalize_color(:monochrome), do: :monochrome
  defp normalize_color(count) when is_integer(count) and count >= 16_777_216, do: :true_color
  defp normalize_color(count) when is_integer(count) and count >= 256, do: :color_256
  defp normalize_color(count) when is_integer(count) and count >= 16, do: :color_16
  defp normalize_color(_other), do: :monochrome
end
