# TermUI User Guides

Welcome to the TermUI documentation. These guides cover everything you need to build terminal user interfaces with Elixir.

## Guides

1. **[Overview](01-overview.md)** - Introduction to TermUI and its architecture
2. **[Getting Started](02-getting-started.md)** - Build your first TermUI application
3. **[The Elm Architecture](03-elm-architecture.md)** - Understanding the component model
4. **[Events](04-events.md)** - Handling keyboard, mouse, and other input
5. **[Styling](05-styling.md)** - Colors, attributes, and themes
6. **[Layout](06-layout.md)** - Positioning and sizing components
7. **[Widgets](07-widgets.md)** - Using pre-built components
8. **[Terminal](08-terminal.md)** - Terminal modes and capabilities
9. **[Commands](09-commands.md)** - Side effects and async operations
10. **[Advanced Widgets](10-advanced-widgets.md)** - Navigation, visualization, data streaming, and BEAM introspection widgets
11. **[Linux Releases](11-linux-releases.md)** - Build and verify a release for an older Linux target.
12. **[Community and Examples](12-community.md)** - Share examples, ask for help, and contribute prompts.

## Quick Start

```elixir
defmodule MyApp do
  use TermUI.Elm

  alias TermUI.Event

  def init(_opts), do: %{count: 0}

  def event_to_msg(%Event.Key{key: :up}, _), do: {:msg, :inc}
  def event_to_msg(%Event.Key{key: :down}, _), do: {:msg, :dec}
  def event_to_msg(%Event.Key{key: "q"}, _), do: {:msg, :quit}
  def event_to_msg(_, _), do: :ignore

  def update(:inc, s), do: {%{s | count: s.count + 1}, []}
  def update(:dec, s), do: {%{s | count: s.count - 1}, []}
  def update(:quit, s), do: {s, [TermUI.Command.quit()]}

  def view(state), do: text("Count: #{state.count}")
end

# Run with: TermUI.Runtime.run(root: MyApp)
```

## Requirements

- Elixir 1.15+
- OTP 26+ for TTY mode; OTP 28+ for native raw mode
- Terminal with ANSI support

## Examples

See the `examples/` directory for complete applications:

- **dashboard** - System monitoring dashboard with gauges, sparklines, and tables
