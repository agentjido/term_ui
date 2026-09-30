defmodule IExCounter.MixProject do
  use Mix.Project

  def project do
    [
      app: :iex_counter,
      version: "0.1.0",
      elixir: ">= 1.18.4 and < 2.0.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:term_ui, path: "../.."}
    ]
  end
end
