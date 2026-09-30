# Advanced feature parity

This comparison uses the source archive published to Hex as `term_ui
1.0.0-rc` for the before state. A feature in that archive is not proof that the
feature was correct in a real terminal. The rewrite removed shared processes
and global services that could break state ownership and terminal cleanup.

The after state is the `2.0.0-rc.1` candidate on `main`. `Retained` means that the
user capability remains. `Replaced` means that the capability has a new API.
`Partial` means that useful behavior remains, but an advanced function is
missing. `Deferred` means that the old form is not safe to restore.

## Before and after

| Feature | Before: published `1.0.0-rc` | After: TermUI 2.0 | Status and gap |
| --- | --- | --- | --- |
| Runtime and widget ownership | Component servers, registries, queues, routers, and process-owned widgets | One Elm runtime with parent-owned pure widgets and command data | Replaced. Do not restore the old ownership model. |
| Streaming input | `StreamWidget` accepted messages through a GenStage consumer and tracked demand | `ProducerAdapter` bounds queued data and sends one acknowledged batch at a time; the parent applies it to the pure widget | Replaced. Slow consumers cannot receive an unbounded series of adapter batches. |
| Stream buffer controls | Four overflow modes, pause, clear, rate display, callbacks, and a render-rate setting | Batch push, clear, lifetime counters, drop-oldest, drop-newest, whole-batch reject, pause, follow, scroll, and formatting | Replaced with pure state. Rate calculation belongs in application data. |
| Streaming Markdown | The viewer replaced its full content through a GenServer call | A bounded incremental document parses completed top-level blocks once and retains the last extensible block as a pending tail | Improved and retained without a viewer process. |
| Markdown grammar | MDEx headings, emphasis, links, quotes, lists, code blocks, and rules | MDEx plus strike-through, task lists, autolinks, images, tables, and terminal-safe raw HTML | Improved and retained. |
| Code syntax highlighting | Makeup highlighted Elixir and Erlang fenced code | A bounded library-neutral adapter maps tokens to terminal styles; the optional Makeup adapter supports Elixir and Erlang | Replaced. Plain code has no Makeup dependency, and unknown or failed tokens fall back safely. |
| Code block copy | The widget callback wrote through caller code from a component process | The pure widget returns `{:copy, code}` and the parent can issue a bounded clipboard command | Replaced with safer effect ownership. |
| Diff viewing | No dedicated diff viewer | Unified and side-by-side views, Myers line comparison, input bounds, and mode switching | Added in the rewrite. |
| Tables | Sorting, single or multi-selection, callbacks, and constraint widths | Pure stable sorting and filtering, identity-based single or multiple selection, vertical scrolling, mouse or keyboard selection, and row replacement | Replaced for data interaction. Callbacks are parent messages, and v2 uses direct column widths. |
| Menus | Actions, checkboxes, separators, and nested submenus | Actions, separators, disabled items, nested submenu data, pure open-path state, keyboard and mouse control, and edge-fitted context positions | Replaced for nested navigation. Checkbox items remain reduced, and no submenu process exists. |
| Forms | Six field types, custom validators, groups, visibility rules, reset, and submit callbacks | Text, checkbox, select, pure field, group, and submit validators, field errors, first-error focus, paste cleaning, mouse focus, and submit messages | Replaced for validation flow. Some field types and conditional visibility remain reduced. |
| Viewports | Scroll bars, drag control, `scroll_into_view/3`, content dimensions, and visible fractions | Pure geometry, visible ranges, `scroll_into_view/3`, optional local scrollbars, keyboard and wheel scroll, and drag state | Retained through a pure replacement. |
| Split panes | Multiple panes, collapse, keyboard resize, persistence, and mouse drag | Named multi-pane weights, collapse state, measured layout, keyboard resize, local separator drag, and versioned pure layout serialization | Retained. The parent selects storage and persistence time. TermUI performs no layout file IO. |
| Toasts | Timed toast collection with callback-style control | Pure bounded independent managers support add, replace, dismiss, count limits, manual ticks, and token-safe timer commands | Retained through a pure replacement with application-owned timing. |
| Process and cluster views | Widgets performed process inspection, polling, node monitoring, and distributed RPC | Pure widgets accept stable output from optional one-shot process, supervision, and cluster providers | Replaced. The parent selects sources, RPC, authorization, polling, and failure policy. |
| Themes and capability fallback | Global theme registry and semantic component styles | `TermUI.Theme` stores named styles, variants, values, merge data, and a capability-limited copy | Replaced. The global registry remains removed. |
| Focus and shortcuts | Global focus manager, traversal groups, and shortcut sequence service | `TermUI.Focus` routes enabled traversal order; `TermUI.Shortcut` routes chords and timestamp-bounded sequences | Replaced with application-owned pure values. |
| Layout solver | Constraint solver, alignment values, and a layout cache | Direct frame composition and pure row, column, and grid tracks for fixed, fill, percentage, ratio, bounds, and measured content | Replaced for common constraints. The general solver and global cache remain removed. |
| Developer tools | Hot reload, UI and state inspectors, and a performance monitor | Deterministic backend tests and runtime instrumentation through normal application state | Partial. Add optional inspection data APIs before any live tool. |
| Test toolkit | Component harness, event simulator, and test renderer shipped in `lib/` | Public deterministic v2 backend with event injection, complete frames, and shutdown snapshots | Replaced. Tests use the runtime, event, command, and frame contracts without component processes. |
| Platform and SSH adapters | Unix and Windows adapter modules; the published Hex archive did not contain an SSH backend | Raw, TTY, and SSH backends own complete sessions | Replaced. SSH has a direct host API and an OTP SSH channel callback with isolated runtimes and bounded frame output. |
| Browser delivery | No browser backend | A transport-neutral WebSocket session, complete or changed Frame rows, normalized events, and shared DOM assets | Added. Protocol and Chromium tests check input, Unicode, wide cells, styles, resize, confirmation, and cleanup. Dense full updates have a measured cost; see the web guide. |
| Embedded terminal content | No owned embedded emulator and PTY | An optional Ghostty session emits complete Frames and accepts command-owned input | Added. Real shell and Vim tests pass on GNU Linux x86_64/ARM64 and macOS ARM64. Other platforms return an explicit error. Ghostty is a consumer dependency. |

## Recommended order

1. Add richer form field data when an application use case needs it.
2. Add optional inspection data APIs before any live developer tool.

Bounded assistant output and rich Markdown no longer need the old component
ownership model. Optional syntax highlighting also keeps pure widget state.
