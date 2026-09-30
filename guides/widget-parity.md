# Widget migration parity

This table compares the public plural widget modules in `term_ui 1.0.0-rc`
with the pure widgets in the v2 architecture. A direct facade is safe only
when one old value can map to one pure v2 value without a process, callback,
selection change, or hidden effect.

The status terms have these meanings:

- **Direct**: The v2 state and user behavior match. A deprecated plural
  facade is available.
- **Reduced**: The main view exists, but some options, state, events, or
  results differ. Use the singular module directly.
- **Deferred**: A known behavior gap must close before a facade can be safe.
- **Application-owned**: The parent application now owns polling, routing, or
  another effect.
- **Removed**: The old helper or process has no public v2 replacement.

## Public table

| v1 plural module | Direct v2 replacement | Status | Facade and migration note |
| --- | --- | --- | --- |
| `TermUI.Widgets.AlertDialog` | `TermUI.Widget.AlertDialog` | Reduced | No facade. Alert types, callback results, and focus state differ. |
| `TermUI.Widgets.BarChart` | `TermUI.Widget.BarChart` | Reduced | No facade. V2 is a pure horizontal chart and does not claim old vertical-chart parity. |
| `TermUI.Widgets.Canvas` | `TermUI.Widget.Canvas` | Reduced | No facade. Core character, line, rectangle, and Braille drawing remain, but the old read, fill, and render-node helpers do not. |
| `TermUI.Widgets.ClusterDashboard` | `TermUI.Widget.ClusterDashboard`, `TermUI.Snapshot.ClusterProvider`, and application commands | Application-owned | No facade. The parent selects nodes, enables RPC, handles refresh requests, and applies stable provider items. |
| `TermUI.Widgets.CommandPalette` | `TermUI.Widget.CommandPalette` | Reduced | No facade. Selection returns parent messages and uses pure pick-list state. |
| `TermUI.Widgets.ContextMenu` | `TermUI.Widget.ContextMenu` | Reduced | No facade. V2 has nested parent-owned menu data and pure edge placement, but no process variants. |
| `TermUI.Widgets.ContextMenu.Behavior`, `TermUI.Widgets.ContextMenu.Factory`, and `TermUI.Widgets.ContextMenu.Inline` | `TermUI.Widget.ContextMenu` and `TermUI.Widget.Menu` | Removed | No facade. The process and factory variants are not part of v2. |
| `TermUI.Widgets.Dialog` | `TermUI.Widget.Dialog` | Reduced | No facade. V2 returns messages instead of calling close and confirm callbacks. |
| `TermUI.Widgets.FormBuilder` | `TermUI.Widget.FormBuilder` | Reduced | No facade. Pure field, group, and submit validation restore the error flow, but field types and callback results do not match. |
| `TermUI.Widgets.Gauge` | `TermUI.Widget.Gauge` | Reduced | No facade. V2 uses horizontal or vertical bars and does not claim old arc or traffic-light parity. |
| `TermUI.Widgets.LineChart` | `TermUI.Widget.LineChart` | Reduced | No facade. V2 keeps the pure series view but has a smaller option set. |
| `TermUI.Widgets.LogViewer` | `TermUI.Widget.LogViewer` | Reduced | No facade. Search, bookmark, selection, and callback state differ. |
| `TermUI.Widgets.MarkdownViewer` | `TermUI.Widget.MarkdownViewer` | Reduced | No facade. V2 uses bounded documents, parent-owned copy messages, and an optional bounded syntax-highlighter adapter. The old process API does not match. |
| `TermUI.Widgets.Menu` | `TermUI.Widget.Menu` | Reduced | No facade. Nested open-path behavior is pure, but v1 checkbox items and callback results do not match. |
| `TermUI.Widgets.ProcessMonitor` | `TermUI.Widget.ProcessMonitor`, `TermUI.Snapshot.ProcessProvider`, and application commands | Application-owned | No facade. The parent selects processes, invokes bounded collection, and owns actions and polling. |
| `TermUI.Widgets.ScrollBar` | `TermUI.Widget.ScrollBar` | Reduced | No facade. Size fields and callback results changed to pure state and messages. |
| `TermUI.Widgets.Sparkline` | `TermUI.Widget.Sparkline` | Direct | Deprecated facade available. Both paths use the same pure state, scaling, character mapping, and frame view. |
| `TermUI.Widgets.SplitPane` | `TermUI.Widget.SplitPane` | Reduced | No facade. V2 has explicit versioned layout serialization and safe restore, but it does not restore the process API or automatic file persistence. |
| `TermUI.Widgets.StreamWidget` | `TermUI.Widget.Stream` and `TermUI.Stream.ProducerAdapter` | Application-owned | No facade. The parent owns the pure buffer and connects producers through bounded batches. |
| `TermUI.Widgets.StreamWidget.Consumer` | `TermUI.Stream.ProducerAdapter` | Removed | No facade. The hidden GenStage consumer process is not restored. |
| `TermUI.Widgets.SupervisionTreeViewer` | `TermUI.Widget.SupervisionTree`, `TermUI.Snapshot.SupervisionTreeProvider`, and application commands | Application-owned | No facade. The parent selects the root, invokes collection, and owns process actions and failure policy. |
| `TermUI.Widgets.Table` and `TermUI.Widgets.Table.Column` | `TermUI.Widget.Table` and `TermUI.Widget.Table.Column` | Reduced | No facade. Sorting, filtering, and identity-based multi-selection are pure. V1 callbacks and constraint values do not match the v2 state and message API. |
| `TermUI.Widgets.Tabs` | `TermUI.Widget.Tabs` | Reduced | No facade. Dynamic tab callbacks and state do not match the pure v2 selection contract. |
| `TermUI.Widgets.TextInput` | `TermUI.Widget.TextInput` and `TermUI.Widget.TextArea` | Reduced | No facade. V2 separates single-line and multiline state and uses normalized text events. |
| `TermUI.Widgets.TextInput.Line` | `TermUI.Widget.LineInput` | Reduced | No facade. Validation returns parent messages and no blocking read occurs inside the widget. |
| `TermUI.Widgets.Toast` | `TermUI.Widget.Toast` | Reduced | No facade. Position and callback state do not match. |
| `TermUI.Widgets.ToastManager` | `TermUI.Widget.Toast.Manager` | Reduced | No facade. V2 returns explicit token-safe timer commands and supports independent pure areas, but it does not restore a named global service. |
| `TermUI.Widgets.TreeView` | `TermUI.Widget.TreeView` | Reduced | No facade. Lazy loading, filtering, and multi-selection state differ. |
| `TermUI.Widgets.Viewport` | `TermUI.Widget.Viewport` | Reduced | No facade. The scrolling capability remains, but v2 measures frame rows and owns local scrollbar drag state. |
| `TermUI.Widgets.VisualizationHelper` and `TermUI.Widgets.WidgetHelpers` | Direct `TermUI.Frame`, `TermUI.Style`, and widget functions | Removed | No facade. These implementation helpers are not a compatibility boundary. |

## Direct sparkline migration

The deprecated plural facade returns a v2 `TermUI.Frame`. It does not create a
v1 render node.

```elixir
# Temporary source bridge
frame = TermUI.Widgets.Sparkline.render(values: [1, 3, 2], width: 3)

# Direct v2 replacement
state = TermUI.Widget.Sparkline.init(values: [1, 3, 2])
frame = TermUI.Widget.Sparkline.view(state, {3, 1})
```

The facade also delegates `value_to_bar/3`, `bar_characters/0`,
`to_sparkline/2`, and `push/3` to the singular module. Each deprecated
function names its direct replacement. No plural facade starts a process or
returns a render node.
