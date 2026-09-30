# Architecture

TermUI has three boundaries.

## Application

One runtime process owns one application state. It serializes terminal events,
application messages, command results, render timers, resize, and shutdown.

The application implements `TermUI.Elm`:

- `init/1` creates state.
- `event_to_msg/2` converts terminal input to an application message.
- `update/2` creates the next state and command data.
- `view/1` creates one complete `TermUI.Frame`.
- `handle_info/2` can convert an external process message to state and commands.
- `terminate/2` can release application resources.

The runtime does not store widget or component processes. It does not accept a
render tree, a buffer, or a list of backend cells from an application.

## Async commands

`Command.async/2` runs a zero-argument function outside the runtime process.
The function can return any term. The runtime, not the function, creates the
result tag that the mapper receives: a normal return becomes `{:ok, value}`;
a raise, throw, or exit becomes `{:error, reason}`. This creates exactly one
outer result tag. For example, a function return of `{:ok, value}` becomes
`{:ok, {:ok, value}}` for the mapper.

## Widgets

A widget is plain state plus `init/1`, `update/2`, and `view/2`. The parent
application stores that state. `view/2` returns a `TermUI.Frame`, which the
parent can place with `TermUI.Frame.overlay/4`.

The optional `mouse/3` widget callback receives local, zero-based coordinates.
The application creates pure mouse regions from its layout and owns hover,
drag, focus, and text selection state. Clipboard output is command data. The
runtime sends it through the same backend owner that draws frames.

Widgets that show processes, supervision trees, streams, or cluster nodes only
format snapshots. The parent application owns polling, subscriptions, RPC, and
other effects.

The optional `TermUI.Snapshot` provider modules perform one synchronous,
bounded collection only when the parent calls them. Their output separates
usable items from partial source errors. Remote cluster RPC needs an explicit
parent-supplied function. Providers do not monitor, retry, or schedule work.

An external stream can use `TermUI.Stream.ProducerAdapter`. This adapter is not
a widget owner. It bounds queued items and permits only one unacknowledged
batch in the application mailbox. The application remains the only owner of
the stream widget and applies each delivered batch in update order.

Themes, focus traversal, shortcut sequences, viewport drag, and pane collapse
are pure values stored by the application. TermUI does not register them or
start a service for them. The [UI context decision](ui-context.md) records why
TermUI keeps theme, focus, shortcut, and mouse values independent and shows the
preferred explicit wiring pattern.

## Data schemas

Zoi schemas define public data that can cross an application, runtime,
backend, or configuration boundary. The schema is the source of the struct
fields, defaults, and enforced keys for these boundary values.

`TermUI.Cell`, `TermUI.Style`, `TermUI.Frame`, `TermUI.Event`,
`TermUI.Command`, `TermUI.Clipboard.Operation`, `TermUI.Mouse.Region`,
`TermUI.Selection`, and `TermUI.Widget.Table.Column` expose `schema/0` for
explicit validation. Frame and command schemas also validate their nested
boundary data.

Private backend state, parser state, stream delivery state, and parent-owned
widget state use plain structs. They are not serialization or trust
boundaries, so a Zoi schema adds no useful contract. TermUI does not parse each
frame mutation or widget update through Zoi. Constructors and guards keep
these hot paths small. Applications must parse untrusted external data before
they use it as a boundary value.

## Frame

`TermUI.Frame` is a bounded, sparse cell map. Missing cells are blank. It clips
content to its dimensions and records the second column of wide graphemes. A
backend can compare the current frame with its last frame.

`TermUI.Frame.overlay/4` composes child frames without adding another render
representation. `TermUI.Frame.diff/2` remains the one backend cell comparison.

## Backend

A backend owns all terminal state. Setup is transactional. After successful
setup, every stop path calls `shutdown/2`. The backend normalizes input to
`TermUI.Event` values and accepts only `TermUI.Frame` for rendering.

One backend owner serializes input polling, size checks, drawing, flushing,
resize, and shutdown against one current backend state. Backend state stays
opaque to the runtime. An input failure stops the application after a final
meaningful render.

## Shutdown

Shutdown has three states: running, final render pending, and stopping. A
shutdown command or external shutdown request cancels a pending timer, renders
the newest dirty state, stops effect processes, calls the application terminate
callback, and closes the backend owner so that it restores the terminal.
