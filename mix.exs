defmodule TermUI.MixProject do
  use Mix.Project

  @version "1.0.0-rc.1"
  @source_url "https://github.com/agentjido/term_ui"

  def project do
    [
      app: :term_ui,
      version: @version,
      elixir: ">= 1.18.4 and < 2.0.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
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
        ignore_warnings: ".dialyzer_ignore.exs",
        list_unused_filters: true,
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
        "coveralls.html": :test,
        spex: :test
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support", "mix/tasks"]
  defp elixirc_paths(_), do: ["lib", "mix/tasks"]

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

      # Testing
      {:excoveralls, "~> 0.18", only: :test},
      {:sexy_spex, "~> 0.2.1", only: :test, runtime: false},

      # LLM usage rules
      {:usage_rules, "~> 0.1", only: :dev, runtime: false},

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
        mix/tasks
        guides
        examples/showcase/README.md
        examples/showcase/lib
        examples/showcase/mix.exs
        examples/showcase/mix.lock
        examples/showcase/run.exs
        Makefile
        Makefile.win
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
        "guides/package-quality.md": [title: "Package Quality"],
        "guides/feature-parity.md": [title: "Feature Parity"],
        "guides/architecture.md": [title: "Architecture"],
        "guides/ui-context.md": [title: "UI Context Decision"],
        "guides/backend.md": [title: "Backend Contract"],
        "guides/widgets.md": [title: "Pure Widgets"],
        "guides/widget-parity.md": [title: "Widget Migration Parity"],
        "guides/showcase.md": [title: "Interactive Showcase"],
        "guides/interaction.md": [title: "Clipboard, Selection, and Mouse"],
        "guides/markdown-and-diffs.md": [title: "Markdown and Diffs"],
        "guides/removed-and-deferred.md": [title: "Removed and Deferred Features"],
        "guides/migration-1.0.md": [title: "Migration to 1.0"]
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
          TermUI.Test.DeterministicBackend
        ],
        Compatibility: [
          TermUI.Widgets.Sparkline
        ]
      ]
    ]
  end
end
