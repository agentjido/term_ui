# TermUI

TermUI is a small terminal runtime for Elixir and the BEAM. It uses the Elm
architecture and has one render value: `TermUI.Frame`.

The runtime owns application state, command execution, frame timing, and
shutdown. A backend owns terminal setup, input, output, size, cursor state,
capabilities, and cleanup.

Jido Console uses TermUI as its terminal runtime. TermUI does not depend on
Jido, so it also remains useful as a general Elixir terminal package.

## Install

TermUI requires Elixir 1.18.4 or later and Erlang/OTP 28 or later. CI tests
Elixir 1.18.4, 1.19, and 1.20 on OTP 28, and Elixir 1.20 on OTP 29.

This branch contains TermUI `2.0.0`. Hex publication is managed separately
by the maintainer. Until 2.0 is published on Hex, use `main` in `mix.exs`:

```elixir
def deps do
  [
    {:term_ui, github: "agentjido/term_ui", branch: "main"}
  ]
end
```

V1 maintenance fixes are on `maint/1.x`. Use that branch for applications
that still use the v1 runtime contract. See the
[migration guide](guides/migration-2.0.md) before changing to v2.

TermUI uses MDEx to parse Markdown for terminal display. It uses Zoi schemas
for public data that crosses application, runtime, backend, or configuration
boundaries. Private runtime and widget state uses plain structs. TermUI has an
optional small C NIF for complete control-key input in the local raw backend
on OTP 28 and OTP 29. The TTY, SSH, and deterministic test backends do not
need this NIF or a source compiler.

## Application contract

```elixir
defmodule Counter do
  use TermUI.Elm

  alias TermUI.{Command, Event, Frame, Style}

  def init(opts) do
    %{count: 0, dimensions: Keyword.fetch!(opts, :dimensions)}
  end

  def event_to_msg(%Event.Key{key: :up}, _state), do: {:msg, :increment}
  def event_to_msg(%Event.Key{key: :down}, _state), do: {:msg, :decrement}
  def event_to_msg(%Event.Text{text: text}, _state) when text in ["q", "Q"],
    do: {:msg, :quit}

  def event_to_msg(%Event.Resize{width: width, height: height}, _state),
    do: {:msg, {:resize, width, height}}

  def event_to_msg(_event, _state), do: :ignore

  def update(:increment, state), do: %{state | count: state.count + 1}
  def update(:decrement, state), do: %{state | count: state.count - 1}
  def update(:quit, state), do: {state, [Command.shutdown()]}
  def update({:resize, width, height}, state), do: %{state | dimensions: {width, height}}

  def view(%{count: count, dimensions: {width, height}}) do
    heading = Style.new(fg: :cyan, attrs: [:bold])

    Frame.from_rows(
      [[{"Counter", heading}], "", "Count: #{count}", "", "Up/Down: change  Q: quit"],
      width,
      height
    )
  end
end

TermUI.run(Counter)
```

`init/1` receives `:dimensions` as `{columns, rows}`. Printable input arrives
as `Event.Text`. Named and modified keys arrive as `Event.Key`. Paste, mouse,
resize, and focus input have separate event types.

External input adapters can use `TermUI.Input` as one normalization boundary.
Its helpers keep printable text and committed composition in `Event.Text`,
paste in `Event.Paste`, and named or modified keys in `Event.Key`. It rejects
an unmodified printable value passed as a special key.

`view/1` must return one complete `TermUI.Frame`. A frame contains its size,
cells, and optional cursor. The cursor is `{column, row}` and is one-based.

## Effects

`update/2` returns new state or `{new_state, commands}`. Commands are data:

- `Command.message/1` queues an application message.
- `Command.send/2` sends data to another process.
- `Command.timer/2` queues a later application message.
- `Command.async/2` runs work outside the runtime process. The function can
  return any term. The runtime wraps a normal return as `{:ok, value}` and a
  raised, thrown, or exited function as `{:error, reason}`. Its mapper always
  receives this one runtime-produced result. For example, a function return of
  `{:ok, value}` reaches the mapper as `{:ok, {:ok, value}}`.
- `TermUI.Clipboard.copy/2` and `TermUI.Clipboard.clear/1` request bounded,
  serialized OSC 52 clipboard output.
- `Command.shutdown/1` requests one final render and cleanup.

## Pure widgets

A widget is not a process. The parent application owns widget state. It sends
events to the widget and composes the returned frame into its application frame.

```elixir
list = TermUI.Widget.List.init(items: ["one", "two"])
{list, messages} = TermUI.Widget.List.update(event, list)
list_frame = TermUI.Widget.List.view(list, {30, 10})
frame = TermUI.Frame.overlay(frame, list_frame, 2, 3)
```

Use `TermUI.Mouse` to route global events to local widget coordinates. Use
`TermUI.Widget.mouse/4` to apply the local event. `TextInput` and `TextArea`
support keyboard and mouse selection. Copy and cut return `{:copy, text}` to
the parent, which can return a `TermUI.Clipboard.copy/2` command.

The supplied pure widgets include:

- Text: label, single-line input, validated line input, multiline text area,
  Markdown viewer, log viewer, stream view, and diff viewer.
- Selection: button, checkbox, toggle, radio group, select, list, pick list,
  menu, context menu, command palette, tabs, table, tree view, and forms.
- Layout and feedback: block, breadcrumb, dialog, alert dialog, split pane,
  viewport, scrollbar, spinner, and toast.
- Data views: progress, gauge, sparkline, bar chart, line chart, canvas,
  process snapshots, supervision trees, and cluster snapshots.

System views accept data snapshots from the parent. They do not start polling
processes or perform RPC.

`TermUI.Layout` supplies pure row, column, and fixed-grid rectangle allocation.
The parent renders child frames and places them in these zero-based rectangles.

## Streaming and application UI state

`TermUI.Stream.ProducerAdapter` is an optional bounded bridge for external
token producers. It sends one batch at a time and waits for an explicit
acknowledgement. The application applies each batch with
`TermUI.Widget.Stream.push_many/2`. Stream state provides drop-oldest,
drop-newest, and whole-batch reject policies with visible counters.

`TermUI.Theme`, `TermUI.Focus`, and `TermUI.Shortcut` are pure values for
themes, focus traversal, and timestamp-bounded key sequences. They have no
registry or service process.

`TermUI.Widget.Viewport` can expose geometry and render draggable local
scrollbars. `TermUI.Widget.SplitPane` supports named multi-pane layouts,
collapse state, keyboard resize, and local separator drag.

## Markdown and diffs

`TermUI.Widget.MarkdownViewer` uses MDEx and supports CommonMark headings,
emphasis, links, quotes, lists, tasks, code blocks, rules, and tables.
Completed top-level blocks are parsed once. Only the unfinished streaming tail is
reparsed as new fragments arrive.

`TermUI.Widget.DiffViewer` accepts `:before` and `:after` text or a
`:unified_diff`. It supports unified and side-by-side terminal views.

## Backends

Use `:auto`, `:raw`, or `:tty` with the `:backend` option. Tests can use the
public deterministic backend or inject another module that implements
`TermUI.Backend`.

```elixir
TermUI.start_link(Counter,
  backend: {TermUI.Test.DeterministicBackend, owner: self(), size: {8, 40}}
)
```

`TermUI.Test.DeterministicBackend` captures complete frames and final shutdown
state. It supports normalized event and resize injection without a terminal or
TTY NIF. See the [backend guide](guides/backend.md).

Raw mode needs OTP 28 or later. TTY mode is the fallback when raw mode is not
available. `TermUI.Backend.SSH` runs one isolated v2 runtime for each remote
session. Applications that own an SSH server can use its direct session API.
OTP SSH daemons can use `TermUI.Backend.SSH.Channel` as their `:ssh_cli`
callback. The host keeps control of authentication and session limits.

### Optional local TTY NIF

`TERM_UI_TTY_NIF` controls the native build:

- `auto` is the default. It builds the NIF from source when `make` and a C
  compiler are available. If a tool is absent, it uses the pure BEAM TTY
  fallback.
- `source` requires a source build. A build error names each missing tool and
  identifies the non-native backend paths.
- `disabled` does not build the NIF. Use this mode for SSH servers, tests, and
  installations that use `backend: :tty`.

The NIF loads only when the local raw backend needs the native control-flag
fallback. It does not load when the runtime uses the TTY, SSH, deterministic,
or another custom backend. TermUI does not ship precompiled NIF artifacts.
This policy keeps platform binaries out of the package and uses the existing
pure BEAM TTY backend when a source build is not available.

## Documents

- [Share examples and ask for help](guides/community.md)
- [Architecture](guides/architecture.md)
- [UI context decision](guides/ui-context.md)
- [Backend contract](guides/backend.md)
- [Pure widgets](guides/widgets.md)
- [Widget migration parity](guides/widget-parity.md)
- [Clipboard, selection, and mouse](guides/interaction.md)
- [Markdown and diff viewers](guides/markdown-and-diffs.md)
- [Advanced feature parity](guides/feature-parity.md)
- [Package quality](guides/package-quality.md)
- [Publishing](guides/publishing.md)
- [Repository layout](guides/repository-layout.md)
- [Physical terminal checks](guides/terminal-checks.md)
- [Removed and deferred features](guides/removed-and-deferred.md)
- [Migration from 1.x to 2.0](guides/migration-2.0.md)
- [Interactive showcase](guides/showcase.md)
- [Runnable showcase application](https://github.com/agentjido/term_ui/blob/main/examples/showcase/README.md)
- [Counter example](https://github.com/agentjido/term_ui/tree/main/examples/iex_counter)
- [All examples](https://github.com/agentjido/term_ui/blob/main/examples/README.md)

## License

TermUI uses the MIT License. The repository includes the license text.
