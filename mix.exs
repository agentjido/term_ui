defmodule TermUI.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/pcharbon70/term_ui"

  def project do
    [
      app: :term_ui,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex package
      name: "TermUI",
      description: "A direct-mode Terminal UI framework for Elixir/BEAM",
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      aliases: aliases(),

      # Test coverage
      test_coverage: [tool: ExCoveralls],

      # Dialyzer
      # Note: call_without_opaque warnings suppressed with :no_opaque in widget modules
      # due to MapSet nested in opaque Style type
      dialyzer: [
        flags: [
          :error_handling,
          :underspecs,
          :unmatched_returns
        ],
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "mix/tasks"]
  defp elixirc_paths(_), do: ["lib", "mix/tasks"]

  defp aliases do
    [
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "dialyzer",
        "docs --warnings-as-errors"
      ]
    ]
  end

  def application do
    [
      extra_applications: if(Mix.env() == :test, do: [:logger, :ssh], else: [:logger])
    ]
  end

  defp deps do
    [
      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},

      # Code quality
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: :dev, runtime: false},

      # Testing
      {:castore, "~> 1.0", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:stream_data, "~> 1.0", only: :test},

      # Streaming
      {:gen_stage, "~> 1.2"},

      # Markdown processing
      {:mdex, "~> 0.14"},

      # Syntax highlighting for code blocks
      {:makeup, "~> 1.1"},
      {:makeup_elixir, "~> 1.0"}
    ]
  end

  defp package do
    [
      name: "term_ui",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(
        lib
        mix/tasks
        guides
        docs/widget-compatibility.md
        mix.exs
        README.md
        LICENSE
        CHANGELOG.md
        usage-rules.md
      )
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "guides/api_reference.md": [title: "TermUI 1.0 API Map"],
        "guides/component_system.md": [title: "Component Systems"],
        "docs/widget-compatibility.md": [title: "Widget Compatibility"],
        "guides/user/README.md": [filename: "user-guides", title: "User Guides"],
        "guides/user/01-overview.md": [title: "Overview"],
        "guides/user/02-getting-started.md": [title: "Getting Started"],
        "guides/user/03-elm-architecture.md": [title: "The Elm Architecture"],
        "guides/user/04-events.md": [title: "Events"],
        "guides/user/05-styling.md": [title: "Styling"],
        "guides/user/06-layout.md": [title: "Layout"],
        "guides/user/07-widgets.md": [title: "Widgets"],
        "guides/user/08-terminal.md": [title: "Terminal"],
        "guides/user/09-commands.md": [title: "Commands"],
        "guides/user/10-advanced-widgets.md": [title: "Advanced Widgets"],
        "guides/user/11-linux-releases.md": [title: "Linux Releases"],
        "guides/user/12-community.md": [title: "Community and Examples"],
        "guides/developer/README.md": [filename: "developer-guides", title: "Developer Guides"],
        "guides/developer/01-architecture-overview.md": [title: "Architecture Overview"],
        "guides/developer/02-runtime-internals.md": [title: "Runtime Internals"],
        "guides/developer/03-rendering-pipeline.md": [title: "Rendering Pipeline"],
        "guides/developer/04-event-system.md": [title: "Event System"],
        "guides/developer/05-buffer-management.md": [title: "Buffer Management"],
        "guides/developer/06-terminal-layer.md": [title: "Terminal Layer"],
        "guides/developer/07-elm-implementation.md": [title: "Elm Implementation"],
        "guides/developer/08-creating-widgets.md": [title: "Creating Widgets"],
        "guides/developer/09-testing-framework.md": [title: "Testing Framework"]
      ],
      groups_for_extras: [
        "Reference Guides":
          ~r/(guides\/(api_reference|component_system)|docs\/widget-compatibility)\.md/,
        "User Guides": ~r/guides\/user\/.*/,
        "Developer Guides": ~r/guides\/developer\/.*/
      ],
      groups_for_modules: [
        Core: [
          TermUI,
          TermUI.App,
          TermUI.Config,
          TermUI.Elm,
          TermUI.Runtime,
          TermUI.Command,
          TermUI.Event,
          TermUI.Message
        ],
        "Component APIs": [
          TermUI.Component,
          TermUI.StatefulComponent,
          TermUI.Container
        ],
        "Standalone component services": [
          TermUI.ComponentServer,
          TermUI.ComponentSupervisor,
          TermUI.ComponentRegistry,
          TermUI.Component.StatePersistence,
          TermUI.Component.Introspection,
          TermUI.EventRouter,
          TermUI.Event.Propagation,
          TermUI.Event.Transformation,
          TermUI.FocusManager,
          TermUI.Focus.Tracker,
          TermUI.Focus.Indicator,
          TermUI.Focus.Traversal,
          TermUI.SpatialIndex
        ],
        "Standalone compatibility APIs": ~r/TermUI\.(?:(?:Style|Parser)(?:\..*)?|Widget\..*)/,
        Widgets: ~r/TermUI\.Widgets\..*/,
        Rendering: [
          TermUI.Renderer.Style,
          TermUI.Renderer.Cell,
          TermUI.Renderer.Buffer,
          TermUI.Renderer.BufferManager,
          TermUI.Runtime.NodeRenderer,
          TermUI.Component.RenderNode
        ],
        Layout: ~r/TermUI\.Layout\..*/,
        Backends: ~r/TermUI\.Backend(\..*)?/,
        Terminal: ~r/TermUI\.(Terminal|Input)(\..*)?/,
        Testing: ~r/TermUI\.Test\..*/
      ],
      before_closing_body_tag: %{
        html: """
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <script>
          document.addEventListener("DOMContentLoaded", function () {
            mermaid.initialize({ startOnLoad: false, theme: "default" });
            let id = 0;
            for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
              const preEl = codeEl.parentElement;
              const graphDefinition = codeEl.textContent;
              const graphEl = document.createElement("div");
              const graphId = "mermaid-graph-" + id++;
              mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
                graphEl.innerHTML = svg;
                bindFunctions?.(graphEl);
                preEl.insertAdjacentElement("afterend", graphEl);
                preEl.remove();
              });
            }
          });
        </script>
        """
      }
    ]
  end
end
