# Interactive showcase

The TermUI showcase is a representative executable demo of the public
application, widget, frame, event, command, and clipboard contracts. It also
explains the ownership rules from inside a running terminal application.

## Run the application

Use a terminal of at least 80 columns by 24 rows when possible.

```sh
git clone https://github.com/agentjido/term_ui.git
cd term_ui
git switch main
cd examples/showcase
mix deps.get
mix run run.exs
```

See the [showcase source and full control
list](https://github.com/agentjido/term_ui/tree/main/examples/showcase).

Press Escape and then 1 through 6 to select a page. This command menu does not
depend on terminal function-key settings.

## What it demonstrates

- The Overview page composes live BEAM gauges, progress, a sparkline, bars, and
  a process table.
- The Inputs page routes events to parent-owned text, list, and button state.
- The Content page shows Markdown, diff, a live refresh stream, and clipboard
  command output.
- The BEAM page renders live parent-supplied process, runtime-link, and cluster
  snapshots.
- The Architecture page explains the active application, frame, and backend
  seams.
- The Controls page shows checkbox, toggle, radio group, select, spinner, and
  breadcrumb widgets with parent-owned state.

## Application structure

`Showcase.App` is the only Elm application. It owns global state, all page and
widget state, timers, asynchronous collection commands, clipboard commands,
terminal dimensions, and final frame composition.

Each page is a pure adapter:

```elixir
{page_state, messages} = Page.update(event, page_state)
frame = Page.view(page_state, dimensions, theme)
```

A page does not start a process or nested runtime. `Showcase.LiveData` collects
VM metrics, process details, runtime links, and connected-node data in a
runtime-managed asynchronous command. The command result updates parent-owned
widget state. The widgets do not perform process inspection or RPC.

Use `Showcase.App.run(data_mode: :snapshot)` when deterministic output is
required. The showcase tests use this mode. CI renders every page at normal and
compact sizes and checks live collection, input routing, timers, and clipboard
command output.
