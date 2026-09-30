defmodule TermUI.Test.BoundaryCases do
  @moduledoc false

  import ExUnit.Assertions

  @default_seed 30_092_026
  @cases 300

  def check(generator, property, opts \\ []) do
    seed =
      Keyword.get_lazy(opts, :seed, fn -> env_integer("TERM_UI_PROPERTY_SEED", @default_seed) end)

    only_case = env_integer("TERM_UI_PROPERTY_CASE", nil)
    cases = Keyword.get(opts, :cases, @cases)
    :rand.seed(:exsss, {seed, seed + 1, seed + 2})

    if only_case && only_case not in 1..cases do
      raise ArgumentError, "TERM_UI_PROPERTY_CASE must be within 1..#{cases}"
    end

    for index <- 1..cases do
      input = generator.()
      if is_nil(only_case) or only_case == index, do: verify(property, input, seed, index)
    end

    :ok
  end

  def choose(values), do: Enum.at(values, :rand.uniform(length(values)) - 1)
  def integer(minimum, maximum), do: minimum + :rand.uniform(maximum - minimum + 1) - 1

  def text(maximum \\ 24) do
    count = integer(0, maximum)
    alphabet = ["a", "Z", " ", "é", "界", "e\u0301", "👩‍💻", "\t", "\n", "\e"]
    for _index <- List.duplicate(nil, count), into: "", do: choose(alphabet)
  end

  def bytes(maximum \\ 128) do
    for _index <- List.duplicate(nil, integer(0, maximum)), into: <<>>, do: <<integer(0, 255)>>
  end

  def chunks(binary) do
    if binary == "" do
      []
    else
      count = integer(1, min(byte_size(binary), 7))
      <<chunk::binary-size(count), rest::binary>> = binary
      [chunk | chunks(rest)]
    end
  end

  defp verify(property, input, seed, index) do
    property.(input)
  rescue
    exception ->
      message = "#{Exception.message(exception)}\n#{replay(input, seed, index)}"
      reraise ExUnit.AssertionError, [message: message], __STACKTRACE__
  catch
    kind, reason -> flunk("#{inspect({kind, reason})}\n#{replay(input, seed, index)}")
  end

  defp replay(input, seed, index) do
    "TERM_UI_PROPERTY_SEED=#{seed} TERM_UI_PROPERTY_CASE=#{index}\n" <>
      "Replay input: #{inspect(input, limit: :infinity, printable_limit: :infinity)}"
  end

  defp env_integer(name, default) do
    case System.get_env(name) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {integer, ""} when integer >= 0 -> integer
          _invalid -> raise ArgumentError, "#{name} must be a non-negative integer"
        end
    end
  end
end
