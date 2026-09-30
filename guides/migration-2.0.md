# Migration from TermUI 1.x to 2.0

TermUI 2.0 is a breaking change from published TermUI 1.0 and the `maint/1.x`
line. One runtime owns application state and update order. Each application
view returns one complete `TermUI.Frame`. The selected backend owns terminal
input, output, size, capabilities, and cleanup. Widgets are pure values, and
commands describe effects that the runtime executes.

The current candidate is `2.0.0`. It is not yet published on Hex. V1 fixes
go to `maint/1.x`; v2 changes go to `main`.
The public `TermUI` namespace remains. The v2 runtime contract used by Jido
Console remains supported.

## Public replacements

| TermUI 1.x | TermUI 2.0 |
| --- | --- |
| `TermUI.App` | `TermUI.run/2`, `TermUI.start_link/2`, or `TermUI.Runtime` |
| `TermUI.Component` and `TermUI.StatefulComponent` | One `TermUI.Elm` application or a pure `TermUI.Widget` |
| Component servers, registry, and supervisor | Parent-owned state in the root application |
| `TermUI.Component.RenderNode` | `TermUI.Frame` |
| Renderer buffers and tuple nodes | `TermUI.Frame` |
| `TermUI.Renderer.Cell` | `TermUI.Cell` |
| `TermUI.Renderer.Style` | `TermUI.Style` |
| `TermUI.Input.*` and terminal input readers | The `TermUI.Backend` input callback |
| External-input SSH adapter | `TermUI.Backend.SSH` complete session backend |
| Printable `Event.Key.char` input | `TermUI.Event.Text` |
| Component command tuples | `TermUI.Command` constructors |
| `TermUI.Widgets.Sparkline` | Deprecated facade for `TermUI.Widget.Sparkline` |
| Other `TermUI.Widgets.*` modules | Use the [widget parity table](widget-parity.md); no plural facade exists unless the row is `Direct` |
| `TermUI.Layout.Constraint` values and solver | Direct pure `TermUI.Layout` tracks |

The widget feature set is available under the singular namespace, but a name
match does not prove behavior parity. For example, the v2 table and Markdown
viewer have different state or effect contracts, so their plural names are
not available. Use the [widget parity table](widget-parity.md) to select the
documented replacement. Widgets now return `TermUI.Frame` and never require a
component PID.

`TermUI.Widgets.Sparkline` is the only deprecated plural facade. Its stateless
numeric mapping has a direct pure replacement. The facade returns a v2 frame,
not a v1 render node. All its deprecation messages name
`TermUI.Widget.Sparkline`.

`TermUI.App.start/2`, `TermUI.App.run/2`, and `TermUI.App.shutdown/1` remain as
deprecated v2 runtime delegates for all v2 releases. `TermUI.App.run/2` keeps
the v1 `{:ok, :exited_normally}` result. New code must use the replacements in
the table. The facade does not include the v1 global `backend_mode/0` and
`supports?/1` queries. Use `TermUI.Runtime.capabilities/1` for one runtime.

`TermUI.Command.quit/0` and `quit/1` are deprecated aliases for
`TermUI.Command.shutdown/0` and `shutdown/1`. The deprecated
`TermUI.Runtime.send_message/3` accepts only the old `:root` target and sends
the value through `send_message/2`. A component target returns a migration
error. Move that routing into the root application's `update/2` function.

## Layout constraint replacements

The v2 layout allocator covers the common v1 constraint inputs directly. It
does not use the v1 constraint structs, solver, or cache.

| v1 input | v2 track |
| --- | --- |
| `Constraint.length(20)` | `Layout.fixed(20)` or `20` |
| `Constraint.fill()` | `Layout.fill()` or `:fill` |
| `Constraint.percentage(30)` | `Layout.percentage(30)` |
| `Constraint.ratio(2)` | `Layout.ratio(2)` or `{:weight, 2}` |
| `constraint |> Constraint.with_min(10)` | `Layout.bounded(track, min: 10)` |
| `constraint |> Constraint.with_max(50)` | `Layout.bounded(track, max: 50)` |
| Measured content with bounds | `Layout.content(measured_size, min: 5, max: 50)` |

Use the tracks in `row/3` and `column/3`. A constrained grid accepts
`:column_tracks` and `:row_tracks`.

```elixir
root = TermUI.Layout.new({100, 30})
[header, body] = TermUI.Layout.column(root, [3, :fill])

[navigation, main] =
  TermUI.Layout.row(body, [
    TermUI.Layout.percentage(25),
    TermUI.Layout.bounded(:fill, min: 30)
  ])

cells =
  TermUI.Layout.grid(main, 4,
    column_tracks: [TermUI.Layout.content(label_width, max: 20), :fill],
    row_tracks: [TermUI.Layout.ratio(1), TermUI.Layout.ratio(1)]
  )
```

Minimum bounds apply when the parent has sufficient space. If all minimums
are larger than the parent, the allocator reduces them proportionally. Thus,
all rectangles stay inside the parent.

### Nested constrained rows

The v1 example in [issue #11](https://github.com/agentjido/term_ui/issues/11)
uses a horizontal constrained stack inside a vertical stack. In v2, allocate
the three rows first. Then allocate each row's children and place their frames
in one complete application frame.

Use the current dimensions from application state. Recalculate these
rectangles after a resize. `Layout.place/3` clips the children when the terminal
is small, including rectangles with zero width or height.

```elixir
alias TermUI.{DisplayWidth, Frame, Layout}

def view(%{dimensions: {width, height}}) do
  [top, middle, bottom] =
    Layout.column(Layout.new({width, height}), [1, 1, 1])

  [top_left, top_right] =
    Layout.row(top, [Layout.content(DisplayWidth.width("Visible 1")), Layout.fill()])

  [middle_left, middle_right] =
    Layout.row(middle, [Layout.fixed(15), Layout.fill()])

  children = [
    {top_left, "Visible 1"},
    {top_right, "Visible 2"},
    {middle_left, "Not visible"},
    {middle_right, "Also not visible"},
    {bottom, "Also visible"}
  ]

  Enum.reduce(children, Frame.new(width, height), fn {rect, text}, frame ->
    child = Frame.from_rows([text], DisplayWidth.width(text), 1)
    Layout.place(frame, child, rect)
  end)
end
```

At 50 columns and 3 rows, this view returns all three rows. The middle row
reserves 15 columns for `"Not visible"` and gives the remaining columns to
`"Also not visible"`.

## Temporary v1 configuration

The v2 entry points read these v1 application environment keys when the
matching explicit option is absent:

| v1 application environment key | Temporary v2 mapping |
| --- | --- |
| `:backend` | `:backend` runtime option |
| `:color_mode` | `:backend_opts` `:color_mode` preference |
| `:character_set` | `:backend_opts` `:character_set` preference |
| `:render_interval` | `:render_interval` runtime option |
| `:iex_compatible` | `:tty` for `true`; automatic backend selection for `false` or `:auto` |

Each used key emits one deprecation warning for the life of the VM. Explicit
v2 options take precedence. Built-in backends can reduce detected color and
Unicode support from these preferences. They do not increase reported
capabilities. Invalid old values return an `:invalid_legacy_config` error.

Public boundary structs derive their fields and defaults from Zoi schemas.
Private runtime and widget state uses plain structs. Direct struct update
syntax still works. Use the public `schema/0` functions when untrusted data
enters TermUI from an external source.

## Required application changes

1. Select one root module and use `TermUI.Elm`.
2. Move child process state into the root state or a normal domain process.
3. Convert terminal events in `event_to_msg/2`.
4. Return command structs from `update/2`.
5. Replace render nodes and buffers with `TermUI.Frame.from_rows/4` or cell writes.
6. Handle `Event.Resize` and store the new `{columns, rows}`.
7. Start with `TermUI.run(MyApp)` or `TermUI.start_link(MyApp)`.

## Backend changes

Replace cursor, clear, and cell-list render callbacks with `draw/2`. The value
passed to `draw/2` is the complete frame. Keep terminal input, output, size,
cursor, capability detection, setup, and cleanup inside the backend.

The old external-input SSH adapter becomes `TermUI.Backend.SSH`. Start one
session for each remote channel. The backend owns parsing, size, rendering,
output bounds, and cleanup. Use `TermUI.Backend.SSH.Channel` with OTP SSH, or
use the direct session API when the application already owns an SSH server.
