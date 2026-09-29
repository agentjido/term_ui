defmodule TermUIGhosttyExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :term_ui_ghostty_example,
      version: "0.1.0",
      elixir: ">= 1.18.4 and < 2.0.0",
      deps: [
        {:term_ui, path: "../.."},
        {:term_ui_web_example, path: "../web", runtime: false},
        {:ghostty, "== 0.5.0", runtime: false}
      ]
    ]
  end

  def application,
    do: [extra_applications: [:logger], mod: {TermUIGhosttyExample.Application, []}]
end
