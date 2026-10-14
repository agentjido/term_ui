defmodule TermUIWebExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :term_ui_web_example,
      version: "0.1.0",
      elixir: ">= 1.18.4 and < 2.0.0",
      deps: [
        {:term_ui, path: "../.."},
        # Replace this pin when Hex includes GHSA-69m6-wcv4-rwcf.
        {:bandit,
         github: "mtrudel/bandit", ref: "d88b21953c65061f21136ea76a89a4f95a2ac7a1", override: true},
        {:websock_adapter, "~> 0.6.0"},
        {:jason, "~> 1.4.4"}
      ]
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {TermUIWebExample.Application, []}]
  end
end
