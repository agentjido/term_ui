defmodule Showcase.MixProject do
  use Mix.Project

  def project do
    [
      app: :term_ui_showcase,
      version: "0.1.0",
      elixir: ">= 1.18.4 and < 2.0.0",
      start_permanent: Mix.env() == :prod,
      deps: [{:term_ui, path: "../.."}]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end
end
