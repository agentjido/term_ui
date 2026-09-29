defmodule TermUIWebExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :term_ui_web_example,
      version: "0.1.0",
      elixir: ">= 1.18.4 and < 2.0.0",
      deps: [
        {:term_ui, path: "../.."},
        {:bandit, "~> 1.12.5"},
        {:websock_adapter, "~> 0.6.0"},
        {:jason, "~> 1.4.4"}
      ]
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {TermUIWebExample.Application, []}]
  end
end
