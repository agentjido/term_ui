defmodule IExCounter.GuideSnippetsTest do
  use ExUnit.Case, async: true

  test "the published widget recipe snippets run against the consumer dependency" do
    guide = Path.expand("../../../guides/widget-recipes.md", __DIR__) |> File.read!()
    snippets = Regex.scan(~r/```elixir\n(.*?)\n```/s, guide, capture: :all_but_first)
    assert length(snippets) == 4

    results = Enum.map(snippets, fn [source] -> source |> Code.eval_string() |> elem(0) end)

    assert results == [
             {:city, "Zürich"},
             {"is required", %{}, [{:submit, %{name: "Ada"}}]},
             [%{id: 2, name: "Bea updated"}],
             {:async, ["beta", "gamma", "delta"], %{accepted: 4, dropped: 1, rejected: 0}}
           ]
  end
end
