defmodule TermUI.MixProject do
  use Mix.Project

  @version "2.0.0-rc.2"
  @source_url "https://github.com/agentjido/term_ui"

  def project do
    [
      app: :term_ui,
      version: @version,
      elixir: ">= 1.18.4 and < 2.0.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [
        &String.ends_with?(&1, "_spex.exs"),
        ~r{^test/platform/support/.*_probe\.exs$}
      ],
      compilers: tty_nif_compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],

      # Hex package
      name: "TermUI",
      description: "A small Elm terminal runtime for Elixir and the BEAM",
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs(),
      aliases: aliases(),

      # Test coverage
      test_coverage: [tool: ExCoveralls, summary: [threshold: 90]],

      # Dialyzer
      dialyzer: [
        list_unused_filters: true,
        flags: [
          :error_handling,
          :underspecs,
          :unmatched_returns
        ],
        plt_add_apps: [:mix, :ex_unit, :lumis]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        spex: :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :ssh]
    ]
  end

  @doc false
  def tty_nif_compilers(
        mode \\ System.get_env("TERM_UI_TTY_NIF", "auto"),
        executable_finder \\ &System.find_executable/1,
        os_type \\ :os.type()
      ) do
    case String.downcase(mode) do
      "auto" ->
        if missing_tty_nif_tools(executable_finder, os_type) == [] do
          [:elixir_make | Mix.compilers()]
        else
          Mix.compilers()
        end

      "source" ->
        require_tty_nif_tools!(executable_finder, os_type)
        [:elixir_make | Mix.compilers()]

      "disabled" ->
        Mix.compilers()

      invalid ->
        Mix.raise(
          "TERM_UI_TTY_NIF must be auto, source, or disabled; received #{inspect(invalid)}"
        )
    end
  end

  defp require_tty_nif_tools!(executable_finder, os_type) do
    case missing_tty_nif_tools(executable_finder, os_type) do
      [] ->
        :ok

      missing ->
        Mix.raise("""
        TermUI cannot build its optional local TTY NIF because these tools are missing: \
        #{Enum.join(missing, ", ")}.

        Install the missing tools, or set TERM_UI_TTY_NIF=disabled. The :tty,
        TermUI.Backend.SSH, and TermUI.Test.DeterministicBackend paths do not need the NIF.
        """)
    end
  end

  defp missing_tty_nif_tools(executable_finder, os_type) do
    os_type
    |> tty_nif_tools()
    |> Enum.reject(fn {_label, executable} -> executable_finder.(executable) end)
    |> Enum.map(&elem(&1, 0))
  end

  defp tty_nif_tools({:win32, _name}),
    do: [{"nmake build tool", "nmake"}, {"Microsoft C/C++ compiler (cl)", "cl"}]

  defp tty_nif_tools(_os_type) do
    compiler = System.get_env("CC", "cc")
    [{"make build tool", "make"}, {"C compiler (#{compiler})", compiler}]
  end

  defp deps do
    [
      # Markdown parsing
      {:mdex, "~> 0.13.5"},

      # Public boundary data schemas and struct definitions
      {:zoi, "~> 0.18.7"},

      # Native terminal control for OTP 28 and OTP 29
      {:elixir_make, "~> 0.9", runtime: false},

      # Documentation
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:doctor, "~> 0.23", only: :dev, runtime: false},

      # Code quality
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      # MDEx exposes Lumis types even when its optional highlighter is absent.
      # Load those types for analysis without adding a runtime dependency.
      {:lumis, "~> 0.10", only: :dev, runtime: false},

      # Testing
      {:excoveralls, "~> 0.18", only: :test},
      {:sexy_spex, "~> 0.2.1", only: :test, runtime: false},

      # LLM usage rules
      {:usage_rules, "~> 1.2", only: :dev, runtime: false},

      # Release tooling
      {:git_ops, "~> 2.9", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "xref graph --format cycles --fail-above 0",
        "credo --strict",
        "dialyzer",
        "doctor --raise"
      ]
    ]
  end

  defp package do
    [
      name: "term_ui",
      maintainers: ["Pascal Charbonneau"],
      licenses: ["MIT"],
      links: %{
        "Changelog" => "https://hexdocs.pm/term_ui/changelog.html",
        "Documentation" => "https://hexdocs.pm/term_ui",
        "Discord" => "https://jido.run/discord",
        "GitHub" => @source_url,
        "Issues" => @source_url <> "/issues",
        "Website" => "https://jido.run"
      },
      files: ~w(
        c_src
        lib
        priv/web
        guides
        Makefile
        Makefile.win
        .formatter.exs
        mix.exs
        README.md
        LICENSE
        CHANGELOG.md
        CONTRIBUTING.md
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
        "CONTRIBUTING.md",
        "guides/README.md": [title: "Guide Index", filename: "guide-index"],
        "guides/getting-started.md": [title: "Getting Started"],
        "guides/examples.md": [title: "Example Lessons"],
        "guides/widget-recipes.md": [title: "Widget Recipes"],
        "guides/testing.md": [title: "Testing"],
        "guides/package-quality.md": [title: "Package Quality"],
        "guides/publishing.md": [title: "Publishing"],
        "guides/repository-layout.md": [title: "Repository Layout"],
        "guides/terminal-checks.md": [title: "Physical Terminal Checks"],
        "guides/terminal-session.md": [title: "Optional Terminal Sessions"],
        "guides/community.md": [title: "Community and Examples"],
        "guides/feature-parity.md": [title: "Feature Parity"],
        "guides/architecture.md": [title: "Architecture"],
        "guides/ui-context.md": [title: "UI Context Decision"],
        "guides/backend.md": [title: "Backend Contract"],
        "guides/web.md": [title: "Browser Backend"],
        "guides/linux-releases.md": [title: "Linux Releases"],
        "guides/widgets.md": [title: "Pure Widgets"],
        "guides/widget-parity.md": [title: "Widget Migration Parity"],
        "guides/showcase.md": [title: "Interactive Showcase"],
        "guides/interaction.md": [title: "Clipboard, Selection, and Mouse"],
        "guides/markdown-and-diffs.md": [title: "Markdown and Diffs"],
        "guides/removed-and-deferred.md": [title: "Removed and Deferred Features"],
        "guides/migration-2.0.md": [title: "Migration from 1.x to 2.0"]
      ],
      groups_for_extras: [
        "Start here": ["guides/README.md", "guides/getting-started.md", "guides/examples.md"],
        "Build an application": [
          "guides/architecture.md",
          "guides/widgets.md",
          "guides/widget-recipes.md",
          "guides/showcase.md",
          "guides/interaction.md",
          "guides/markdown-and-diffs.md",
          "guides/ui-context.md"
        ],
        "Choose a host": ["guides/backend.md", "guides/web.md", "guides/terminal-session.md"],
        "Test and maintain": [
          "CONTRIBUTING.md",
          "guides/testing.md",
          "guides/terminal-checks.md",
          "guides/package-quality.md",
          "guides/repository-layout.md",
          "guides/linux-releases.md",
          "guides/publishing.md"
        ],
        "Move from v1": [
          "guides/migration-2.0.md",
          "guides/widget-parity.md",
          "guides/feature-parity.md",
          "guides/removed-and-deferred.md"
        ]
      ],
      groups_for_modules: [
        Core: [
          TermUI,
          TermUI.App,
          TermUI.Config,
          TermUI.Elm,
          TermUI.Runtime,
          TermUI.Event,
          TermUI.Input,
          TermUI.Command,
          TermUI.Clipboard,
          TermUI.Clipboard.Operation,
          TermUI.Frame,
          TermUI.Cell,
          TermUI.Style,
          TermUI.Theme,
          TermUI.Focus,
          TermUI.Layout,
          TermUI.Shortcut,
          TermUI.DisplayWidth,
          TermUI.Markdown,
          TermUI.Markdown.Document,
          TermUI.Stream.ProducerAdapter,
          TermUI.Mouse,
          TermUI.Mouse.Region,
          TermUI.Mouse.Tracker,
          TermUI.Selection
        ],
        Widgets: [
          TermUI.Widget,
          TermUI.Widget.AlertDialog,
          TermUI.Widget.BarChart,
          TermUI.Widget.Block,
          TermUI.Widget.Breadcrumb,
          TermUI.Widget.Button,
          TermUI.Widget.Canvas,
          TermUI.Widget.ClusterDashboard,
          TermUI.Widget.Checkbox,
          TermUI.Widget.CommandPalette,
          TermUI.Widget.ContextMenu,
          TermUI.Widget.Dialog,
          TermUI.Widget.DiffViewer,
          TermUI.Widget.FormBuilder,
          TermUI.Widget.Gauge,
          TermUI.Widget.Label,
          TermUI.Widget.LineChart,
          TermUI.Widget.LineInput,
          TermUI.Widget.List,
          TermUI.Widget.LogViewer,
          TermUI.Widget.MarkdownViewer,
          TermUI.Widget.Menu,
          TermUI.Widget.PickList,
          TermUI.Widget.ProcessMonitor,
          TermUI.Widget.Progress,
          TermUI.Widget.RadioGroup,
          TermUI.Widget.Router,
          TermUI.Widget.ScrollBar,
          TermUI.Widget.Select,
          TermUI.Widget.Sparkline,
          TermUI.Widget.Spinner,
          TermUI.Widget.SplitPane,
          TermUI.Widget.Stream,
          TermUI.Widget.StreamWidget,
          TermUI.Widget.SupervisionTree,
          TermUI.Widget.SupervisionTreeViewer,
          TermUI.Widget.Table,
          TermUI.Widget.Table.Column,
          TermUI.Widget.Tabs,
          TermUI.Widget.TextArea,
          TermUI.Widget.TextInput,
          TermUI.Widget.TextInput.Line,
          TermUI.Widget.Toast,
          TermUI.Widget.Toast.Manager,
          TermUI.Widget.Toggle,
          TermUI.Widget.TreeView,
          TermUI.Widget.Viewport
        ],
        Backends: [
          TermUI.Backend,
          TermUI.Backend.SSH,
          TermUI.Backend.SSH.Channel,
          TermUI.WebBackend,
          TermUI.WebBackend.Protocol,
          TermUI.TerminalSession,
          TermUI.TerminalSession.Frame,
          TermUI.Test.DeterministicBackend
        ],
        Compatibility: [
          TermUI.Widgets.Sparkline
        ]
      ]
    ]
  end
end
