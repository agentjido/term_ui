# Removed and deferred features

TermUI 2.0 has one runtime, one input path, one frame type, and
one widget namespace. Some old features did not fit this design.

## Intentional architecture removals

These systems will not return in their old form:

| Removed system | Replacement |
| --- | --- |
| Component server, registry, supervisor, containers, and state persistence | One Elm runtime and parent-owned pure widget state |
| Event router, event queue, message queue, and global focus manager | The Elm application serializes events and owns focus |
| Legacy raw, TTY, selector, and line-reader input modules | The selected backend owns one input path |
| Render nodes, renderer buffers, buffer managers, and renderer style/cell copies | `TermUI.Frame`, `TermUI.Cell`, and backend rendering |
| `TermUI.Widgets` and process-based widgets | `TermUI.Widget` pure state transitions |
| Global spatial index and mouse tracker | Pure `TermUI.Mouse.Region` lists and application-owned `TermUI.Mouse.Tracker` data |
| Global configuration and persistent-term caches | Runtime and widget options stored by their owner |

## Deferred optional features

These features are not in the new package:

- A global theme registry.
- A generic theme, focus, shortcut, and mouse context. The
  [UI context decision](ui-context.md) keeps these values in their smallest
  application-owned scopes.
- A constraint layout solver, layout cache, and alignment objects.
- A shared shortcut service and global focus traversal groups.
- Development hot reload, UI inspection, state inspection, and performance tools.
- The component test harness and mutable test renderer. Use
  `TermUI.Test.DeterministicBackend` for v2 runtime tests.
- Dedicated Unix and Windows platform adapter modules.
- The old set of one application for each widget. The counter and showcase are
  the general examples. Web and Ghostty examples show optional adapters.

SSH has returned as a normal backend that owns one complete remote session.
`TermUI.Backend.SSH.Channel` connects OTP SSH channel data and PTY changes to
that backend. It does not own daemon authentication or connection policy.
`TermUI.Theme`, `TermUI.Focus`, and `TermUI.Shortcut` now provide the safe pure
forms. The global service forms remain removed. These values keep the core
design unchanged.

Clipboard, selection, and mouse support have returned in refined forms.
Clipboard writes are bounded command data. Selection uses Unicode grapheme
positions. Mouse regions, hit testing, hover, and drag state are pure data.

## Widget behavior that became smaller

The widget names are present, but some old adapters and services are not:

| Widget area | Current behavior | Removed behavior |
| --- | --- | --- |
| Stream | Bounded batches, counters, overflow policies, and an optional acknowledged producer adapter | Widget-owned GenStage consumer |
| Process, supervision, and cluster views | Parent-supplied data or optional bounded one-shot providers | Widget-owned polling, implicit distributed RPC, and monitoring processes |
| Toast | Independent pure managers with explicit timer commands, safe expiry messages, and manual `tick/2` | Timer process and global stack service |
| Line input | Pure event-driven input | Blocking shell `IO.gets/1` adapter |
| Markdown code blocks | Emits copy data and supports bounded optional syntax-highlighter adapters | Direct clipboard writes and required Makeup integration |
| Menu and context menu | Nested data, pure open-path state, keyboard and mouse control, and edge-fitted overlay positions | Submenu processes and inline service variants |
| Table | Pure sorting, filtering, scrolling, columns, and identity-based row selection | Callback execution and a sorting service process |
| Form | Text, checkbox, select, and pure field, group, and submit validation | Field processes and callback execution |
| Split pane and viewport | Pure multi-pane state, versioned layout serialization, geometry, scrollbars, and local drag state | Global mouse routing and automatic persistence services |

Applications can add these effects in their Elm update function. A reusable
adapter belongs in TermUI only when it can stay pure or follow the backend and
command contracts.
