# TermUI

[![Hex.pm](https://img.shields.io/hexpm/v/term_ui.svg)](https://hex.pm/packages/term_ui)
[![Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/term_ui)
[![License](https://img.shields.io/hexpm/l/term_ui.svg)](https://github.com/agentjido/term_ui/blob/maint/1.x/LICENSE)

A direct-mode Terminal UI framework for Elixir/BEAM, inspired by [BubbleTea](https://github.com/charmbracelet/bubbletea) (Go) and [Ratatui](https://github.com/ratatui-org/ratatui) (Rust).

TermUI combines The Elm Architecture with the BEAM process model and
supervision primitives to build robust terminal applications.

<p align="center">
  <img src="https://raw.githubusercontent.com/pcharbon70/term_ui/main/assets/dashboard_blue.jpg" width="45%" alt="Blue Theme">
  &nbsp;&nbsp;
  <img src="https://raw.githubusercontent.com/pcharbon70/term_ui/main/assets/dashboard_yellow.jpg" width="45%" alt="Yellow Theme">
</p>

## Features

- **Elm Architecture** - Predictable state management with `init/update/view`
- **Rich Widget Library** - Gauges, tables, menus, charts, dialogs, and more
- **Efficient Rendering** - A dirty render loop capped at roughly 60 FPS, with differential updates in Raw/custom backends and full-frame TTY redraws
- **Themable** - True color RGB support (16 million colors)
- **Terminal Backends** - Raw and TTY operation on Unix terminals, plus remote SSH sessions
- **OTP Integration** - A supervised runtime plus optional lower-level component lifecycle services
- **IEx Compatible** - Run TUI applications directly in IEx for interactive development

## Platform support

TermUI 1.0's local Raw and TTY backends target Unix-style terminals and are
supported on Linux and macOS. The SSH backend renders independent sessions to
OTP SSH channel devices.

Native Windows console support is experimental. ANSI output can work in a
terminal where virtual-terminal processing is already enabled, but TermUI does
not yet configure Win32 console modes or provide native raw input and resize
handling. On Windows, prefer WSL and verify keyboard, resize, paste, and cleanup
behavior for the terminal you deploy with. Mouse tracking is intentionally
disabled under WSL/ConPTY because disabling sequences are not handled reliably.

OTP 26's signal API does not expose `SIGWINCH` to application handlers. The
minimum-version TTY backend still supports size queries, but automatic local
resize events require a newer OTP; Raw mode already requires OTP 28 or later.

## IEx Compatibility

TermUI applications work directly in IEx with no code changes. This is perfect for:
- Interactive debugging and development
- Admin tools and dashboards in production IEx sessions
- Prototyping and testing TUI interfaces

### Running in IEx

```elixir
# In your IEx session
iex> TermUI.Runtime.run(root: MyApp.Counter)
# Use arrow keys, press Q to quit, returns to IEx prompt
```

### How It Works

TermUI keeps the active IEx shell in cooked mode and reads through its IO
server from a dedicated input process. This avoids replacing the shell while
still allowing TermUI to parse navigation keys and return cleanly to the IEx
prompt. Depending on the shell and terminal driver, cooked input may be
delivered immediately or buffered until Enter is pressed.

### Detection and Configuration

You can detect if your application is running in IEx:

```elixir
iex> TermUI.iex_mode?()
true

iex> TermUI.running_mode()
:iex
```

Force IEx-compatible mode via configuration:

```elixir
# config/config.exs
config :term_ui,
  iex_compatible: true
```

Or via environment variable:

```bash
export TERM_UI_IEX_MODE=true
```

### Important Notes

- **Navigation keys are supported** - Some cooked-mode terminals deliver them
  only after Enter is pressed
- **Keyboard shortcuts are parsed** - Including Tab, Enter, Escape, and
  function keys once the shell delivers their bytes
- **Clean shutdown** - Terminal state is restored when the app exits
- **Clean return to IEx** - Exiting the TUI restores the prompt for more commands

## Widgets

| Widget | Description |
|--------|-------------|
| **Gauge** | Progress bar with color zones |
| **Sparkline** | Compact inline trend graph |
| **Table** | Scrollable data table with selection and sorting |
| **Menu** | Hierarchical menu with submenus |
| **TextInput** | Single-line and multi-line text input |
| **Dialog** | Modal dialog with buttons |
| **PickList** | Modal selection with type-ahead filtering |
| **Tabs** | Tabbed interface for switchable panels |
| **AlertDialog** | Modal dialog for confirmations with standard button configurations |
| **ContextMenu** | Right-click context menu with keyboard and mouse support |
| **Toast** | Tick-driven notifications with stacking and dismissal |
| **Viewport** | Scrollable view with keyboard and mouse support |
| **SplitPane** | Resizable multi-pane layouts for IDE-style interfaces |
| **TreeView** | Hierarchical data display with expand/collapse |
| **FormBuilder** | Structured forms with validation and multiple field types |
| **CommandPalette** | Searchable command discovery with substring filtering |
| **BarChart** | Horizontal/vertical bar charts for categorical data |
| **LineChart** | Line charts using Braille characters for sub-character resolution |
| **Canvas** | Direct drawing surface for custom visualizations |
| **LogViewer** | High-performance log viewer with virtual scrolling and filtering |
| **StreamWidget** | Bounded stream widget with a GenStage consumer adapter |
| **ProcessMonitor** | Live BEAM process inspection with sorting and filtering |
| **SupervisionTreeViewer** | OTP supervision hierarchy visualization |
| **ClusterDashboard** | Distributed Erlang cluster monitoring |

## Installation

Add `term_ui` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:term_ui, "~> 1.0"}
  ]
end
```

## Quick Start

```elixir
defmodule Counter do
  use TermUI.Elm

  alias TermUI.Event
  alias TermUI.Renderer.Style

  def init(_opts), do: %{count: 0}

  def event_to_msg(%Event.Key{key: :up}, _state), do: {:msg, :increment}
  def event_to_msg(%Event.Key{key: :down}, _state), do: {:msg, :decrement}
  def event_to_msg(%Event.Key{key: "q"}, _state), do: {:msg, :quit}
  def event_to_msg(_, _), do: :ignore

  def update(:increment, state), do: {%{state | count: state.count + 1}, []}
  def update(:decrement, state), do: {%{state | count: state.count - 1}, []}
  def update(:quit, state), do: {state, [TermUI.Command.quit()]}

  def view(state) do
    stack(:vertical, [
      text("Counter Example", Style.new(fg: :cyan, attrs: [:bold])),
      text("", nil),
      text("Count: #{state.count}", nil),
      text("", nil),
      text("↑/↓ to change, Q to quit", Style.new(fg: :bright_black))
    ])
  end
end

# Run the application
TermUI.Runtime.run(root: Counter)
```

## Documentation

[Share examples and ask for help](guides/user/12-community.md).

### User Guides

| Guide | Description |
|-------|-------------|
| [Overview](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/user/01-overview.md) | Introduction to TermUI concepts |
| [Getting Started](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/user/02-getting-started.md) | First steps and setup |
| [Elm Architecture](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/user/03-elm-architecture.md) | Understanding init/update/view |
| [Events](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/user/04-events.md) | Handling keyboard and mouse input |
| [Styling](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/user/05-styling.md) | Colors, attributes, and themes |
| [Layout](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/user/06-layout.md) | Arranging components on screen |
| [Widgets](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/user/07-widgets.md) | Using built-in widgets |
| [Terminal](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/user/08-terminal.md) | Terminal capabilities and modes |
| [Commands](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/user/09-commands.md) | Side effects and async operations |
| [Linux Releases](guides/user/11-linux-releases.md) | Build and verify a release for an older Linux target |
| [Advanced Widgets](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/user/10-advanced-widgets.md) | Navigation, visualization, streaming, and BEAM introspection widgets |

### Developer Guides

| Guide | Description |
|-------|-------------|
| [Architecture Overview](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/developer/01-architecture-overview.md) | System layers and design |
| [Runtime Internals](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/developer/02-runtime-internals.md) | GenServer event loop and state |
| [Rendering Pipeline](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/developer/03-rendering-pipeline.md) | View to terminal output stages |
| [Event System](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/developer/04-event-system.md) | Input parsing and dispatch |
| [Buffer Management](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/developer/05-buffer-management.md) | ETS double buffering |
| [Terminal Layer](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/developer/06-terminal-layer.md) | Raw mode and ANSI sequences |
| [Elm Implementation](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/developer/07-elm-implementation.md) | Elm Architecture for OTP |
| [Creating Widgets](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/developer/08-creating-widgets.md) | How to build and contribute widgets |
| [Testing Framework](https://github.com/agentjido/term_ui/blob/maint/1.x/guides/developer/09-testing-framework.md) | Component and widget testing |

## Examples

The `examples/` directory contains standalone applications demonstrating each widget:

| Example | Description |
|---------|-------------|
| [alert_dialog](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/alert_dialog) | Confirmation dialogs with standard buttons |
| [bar_chart](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/bar_chart) | Horizontal and vertical bar charts |
| [canvas](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/canvas) | Free-form drawing with box/braille characters |
| [cluster_dashboard](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/cluster_dashboard) | Distributed Erlang cluster monitoring |
| [command_palette](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/command_palette) | VS Code-style command discovery |
| [context_menu](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/context_menu) | Right-click context menus |
| [dashboard](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/dashboard) | System monitoring dashboard with multiple widgets |
| [dialog](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/dialog) | Modal dialogs with buttons |
| [form_builder](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/form_builder) | Structured forms with validation |
| [gauge](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/gauge) | Progress bars and percentage indicators |
| [iex_counter](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/iex_counter) | Minimal counter designed for IEx/TTY mode |
| [line_chart](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/line_chart) | Braille-based line charts |
| [log_viewer](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/log_viewer) | Real-time log display with filtering |
| [markdown_viewer](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/markdown_viewer) | Scrollable Markdown rendering |
| [menu](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/menu) | Nested menus with keyboard navigation |
| [multi_renderer](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/multi_renderer) | Backend selection and capability degradation |
| [pick_list](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/pick_list) | Modal selection with type-ahead |
| [process_monitor](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/process_monitor) | Live BEAM process inspection |
| [sparkline](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/sparkline) | Inline data visualization |
| [split_pane](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/split_pane) | Resizable multi-pane layouts |
| [stream_widget](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/stream_widget) | GenStage consumer integration with a bounded display buffer |
| [supervision_tree_viewer](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/supervision_tree_viewer) | OTP supervision hierarchy |
| [table](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/table) | Scrollable data tables with selection |
| [tabs](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/tabs) | Tab-based navigation |
| [text_input](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/text_input) | Single and multi-line text input |
| [toast](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/toast) | Tick-driven notification dismissal |
| [tree_view](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/tree_view) | Hierarchical data with expand/collapse |
| [viewport](https://github.com/agentjido/term_ui/tree/maint/1.x/examples/viewport) | Scrollable content areas |

```bash
# Run any example
cd examples/dashboard
mix deps.get
mix termui.run
```

## Requirements

- Elixir 1.15+
- OTP 26+ for TTY mode; OTP 28+ for native Raw mode
- An ANSI-capable terminal; common widgets support ASCII fallback, while
  Braille charts and a few legacy/specialized renderers require Unicode (see
  the [compatibility guide](docs/widget-compatibility.md))

## License

MIT License - see [LICENSE](https://github.com/agentjido/term_ui/blob/maint/1.x/LICENSE) for details.
