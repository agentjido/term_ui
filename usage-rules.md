# TermUI usage rules

Use one module with `use TermUI.Elm` as the root application.

- Store all durable UI state in the root application state.
- Convert `TermUI.Event` values to application messages in `event_to_msg/2`.
- Keep `update/2` pure. Return `TermUI.Command` values for effects.
- Return exactly one `TermUI.Frame` from `view/1`.
- Use `{columns, rows}` for application dimensions.
- Use `{column, row}` for a frame cursor.
- Treat backends as terminal owners. Do not parse terminal input in an application.
- Keep widget state in the parent. Do not start one process for each widget.
- Call widget `view/2` with `{columns, rows}` and compose the returned frame with
  `TermUI.Frame.overlay/4`.
- Route global mouse events with `TermUI.Mouse`. Call `TermUI.Widget.mouse/4`
  with local, zero-based coordinates.

Printable text is `TermUI.Event.Text`. Do not read printable characters from a
legacy `Key.char` field. Use `TermUI.Event.Key` for named or modified keys.

Use `TermUI.Style`, `TermUI.Cell`, and `TermUI.Frame`. The old renderer,
component, input, and `TermUI.Widgets` namespaces do not exist in 1.0.

Use `TermUI.Widget.MarkdownViewer` for MDEx Markdown. Use
`TermUI.Widget.DiffViewer` for unified or side-by-side text diffs. Supply
process, stream, supervision, and cluster snapshots from the parent application.
Use `TermUI.Stream.ProducerAdapter` only as a bounded bridge for an external
producer. Acknowledge each batch after the application applies it.

Store `TermUI.Theme`, `TermUI.Focus`, and `TermUI.Shortcut` values in the root
application state. Do not create a global theme, focus, or shortcut registry.

Use `TermUI.Selection` for Unicode grapheme ranges. Convert widget
`{:copy, text}` messages to `TermUI.Clipboard.copy/2` commands. Do not write
OSC 52 data directly from an application or widget.

Use the public Zoi schemas when untrusted data enters a TermUI boundary.
Boundary data types expose `schema/0`. Private runtime and widget structs do
not have schemas. Do not validate each cell mutation or widget update in a
render loop.

For tests, inject a module that implements `TermUI.Backend`. Assert on the
`TermUI.Frame` values passed to `draw/2`.
