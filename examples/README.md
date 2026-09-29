# TermUI Examples

This directory contains example applications demonstrating TermUI widgets and patterns.

See the [community guide](../guides/user/12-community.md) to share or contribute
an example. The [prompts](prompts) directory contains an optional v1 counter
request with verification checks.

## Examples Overview

| Example | Description | Key Features |
|---------|-------------|--------------|
| [dashboard](./dashboard/) | System monitoring dashboard | Multiple widgets, real-time updates, themes |
| [gauge](./gauge/) | Progress indicators | Color zones, bar/arc styles, labels |
| [sparkline](./sparkline/) | Time series visualization | Value-based colors, min/max tracking |
| [bar_chart](./bar_chart/) | Bar chart visualizations | Horizontal/vertical, colors, labels |
| [table](./table/) | Data tables | Columns, selection, scrolling, constraints |
| [line_chart](./line_chart/) | Line chart with Braille graphics | Multiple series, auto-scaling, legends |
| [menu](./menu/) | Hierarchical menus | Actions, submenus, checkboxes, radio groups |
| [tabs](./tabs/) | Tabbed interfaces | Tab switching, dynamic tabs, content panels |
| [dialog](./dialog/) | Modal dialogs | Confirmation, info, warning, error dialogs |
| [viewport](./viewport/) | Scrollable content areas | Keyboard/mouse scrolling, scrollbars |
| [canvas](./canvas/) | Custom drawing | Primitives, rectangles, Braille graphics |
| [alert_dialog](./alert_dialog/) | Standard confirmation alerts | Modal overlays, keyboard selection |
| [cluster_dashboard](./cluster_dashboard/) | Distributed Erlang status | Nodes, global names, process groups |
| [command_palette](./command_palette/) | Searchable commands | Substring filtering, shortcuts |
| [context_menu](./context_menu/) | Context actions | Keyboard and mouse alternatives |
| [form_builder](./form_builder/) | Validated forms | Multiple fields, submission |
| [iex_counter](./iex_counter/) | Minimal IEx counter | TTY/cooked input |
| [log_viewer](./log_viewer/) | Large log streams | Filtering, search, tail mode |
| [markdown_viewer](./markdown_viewer/) | Markdown content | Parsing and scrolling |
| [multi_renderer](./multi_renderer/) | Backend capabilities | Raw/TTY selection and degradation |
| [pick_list](./pick_list/) | Type-ahead selection | Filtering and modal navigation |
| [process_monitor](./process_monitor/) | BEAM process metrics | Sorting and refresh |
| [split_pane](./split_pane/) | Resizable panes | Constraints and keyboard resizing |
| [stream_widget](./stream_widget/) | GenStage streams | Consumer integration and bounded buffers |
| [supervision_tree_viewer](./supervision_tree_viewer/) | OTP supervision tree | Introspection and refresh |
| [text_input](./text_input/) | Text editing | Single/multiline input |
| [toast](./toast/) | Notifications | Timed stacking and dismissal |
| [tree_view](./tree_view/) | Hierarchical data | Expand/collapse navigation |

## Running Examples

Each example is a standalone Mix project. To run an example:

```bash
# Navigate to the example directory
cd examples/<example_name>

# Install dependencies
mix deps.get

# Run the example
mix termui.run
```

## Requirements

- Elixir 1.15+
- OTP 26+ for TTY mode; OTP 28+ for native Raw mode
- An ANSI-capable terminal; examples degrade to ASCII where supported

## Example Structure

Each example follows a consistent structure:

```
example_name/
├── mix.exs              # Mix project file
├── run.exs              # Script to run the example
├── README.md            # Example documentation
└── lib/
    └── example_name/
        ├── application.ex  # OTP application module
        └── app.ex          # Main component implementation
```

## The Elm Architecture

All examples use TermUI's Elm Architecture pattern with four callbacks:

```elixir
use TermUI.Elm

# Initialize component state
@impl true
def init(_opts), do: %{...}

# Convert events to messages
@impl true
def event_to_msg(event, state), do: {:msg, message} | :ignore

# Update state based on messages
@impl true
def update(message, state), do: {new_state, commands}

# Render state to UI tree
@impl true
def view(state), do: stack(:vertical, [...])
```

## Widget Categories

### Data Display
- **Gauge** - Show progress or values with visual feedback
- **Sparkline** - Compact time series visualization
- **BarChart** - Categorical data comparison
- **LineChart** - Trend visualization with multiple series
- **Table** - Structured data with selection

### Navigation
- **Menu** - Hierarchical command menus
- **Tabs** - Organize content into switchable panels

### Interaction
- **Dialog** - Modal prompts and confirmations
- **Viewport** - Scrollable content containers

### Drawing
- **Canvas** - Custom graphics with drawing primitives

## Learning Path

For beginners, we recommend exploring examples in this order:

1. **gauge** - Simple widget with basic event handling
2. **sparkline** - Working with data collections
3. **table** - Selection and navigation patterns
4. **menu** - Complex widget interactions
5. **dashboard** - Combining multiple widgets

## Contributing

When adding new examples:

1. Follow the existing directory structure
2. Include a comprehensive README.md
3. Add well-commented code explaining widget usage
4. Update this README with the new example
