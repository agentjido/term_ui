# Interactive showcase

This application is a representative executable demo of TermUI widgets and architecture.
It uses only the public Elm application, widget, frame, event, command, and
clipboard contracts.

## Run it

Use a terminal of at least 80 columns by 24 rows when possible.

```sh
cd examples/showcase
mix deps.get
mix run run.exs
```

The application also works from IEx:

```elixir
Showcase.App.run()
```

Live mode is the default. For fixed output in a test or documentation session,
use:

```elixir
Showcase.App.run(data_mode: :snapshot)
```

## Controls

- Escape opens the command menu. Press 1 through 6 to select a page.
- In the command menu, N and P select the next or previous page, R refreshes
  data, T changes the theme, and Q stops the application.
- Ctrl+N and Ctrl+P select the next or previous page without opening the menu.
- Ctrl+Left and Ctrl+Right also select pages when the terminal sends those
  key combinations.
- Ctrl+R requests an immediate live refresh.
- Ctrl+T changes the showcase theme.
- Ctrl+Q stops the application and restores the terminal without opening the
  menu.
- Tab changes focus on pages with multiple controls.
- The footer and page status show local controls.

## Pages

### Overview

Shows gauges, progress, sparklines, bars, and a selectable table driven by live
BEAM memory, process, scheduler, and run-queue values. Rendering does not
collect data or perform effects.

### Inputs

Shows single-line and multiline text input, multiple selection, keyboard focus,
button output, and copy messages. The parent routes each event to one focused
widget.

### Content

Shows Markdown, diff, and bounded stream widgets. Use `[` and `]` to change the
active widget. The stream records each live BEAM refresh. The Markdown sample
includes a copyable code block. The parent converts its copy message to
serialized clipboard command data.

### BEAM

Shows process, runtime-tree, and cluster widgets. `Showcase.LiveData` collects
local process details, runtime links, and local or connected-node values. The
parent supplies each result to the pure widgets. The widgets do not inspect
processes, monitor nodes, or perform RPC.

### Architecture

Explains the application, widget, frame, and backend ownership seams inside the
running TermUI application.

### Controls

Shows checkbox, toggle, radio group, select, spinner, and breadcrumb widgets.
The application owns all Controls page state. Its existing refresh timer
advances the pure spinner state.

## Structure

`Showcase.App` is the only Elm application. It owns global state, every page
state, timers, asynchronous collection commands, clipboard commands, terminal
dimensions, and final frame composition.

Each module in `Showcase.Pages` is a pure page adapter:

```elixir
{page_state, messages} = Page.update(event, page_state)
frame = Page.view(page_state, dimensions, theme)
```

A page does not start a process or a nested runtime. `Showcase.LiveData`
collects external values inside a runtime-managed asynchronous command.
`Showcase.Layout` contains only frame composition helpers.

## Tests

```sh
mix test
```

The tests use explicit snapshot mode and render every page at normal and compact
terminal sizes. They also check live collection, state ownership, input routing,
timers, and clipboard command output. CI compiles and tests this standalone Mix
application so the documentation cannot silently drift from the public API.
