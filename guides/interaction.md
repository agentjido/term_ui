# Clipboard, selection, and mouse interaction

TermUI keeps interaction state in the Elm application. It does not use a
global mouse registry, a selection process, or direct clipboard writes.

## External input normalization

Use `TermUI.Input` when an external UI adapter sends input to TermUI. Keep
printable text, committed input-method composition, paste, and special keys
explicit:

```elixir
text = TermUI.Input.text("Jido 👩‍💻")
composition = TermUI.Input.composition("e\u0301")
paste = TermUI.Input.paste("first\nsecond")
enter = TermUI.Input.special_key("Return")
save = TermUI.Input.special_key("s", modifiers: [:control])
```

Pass `text`, `composition`, or `paste` to a focused text widget. `text/2` and
`composition/2` keep a Unicode or multi-codepoint string in one
`TermUI.Event.Text` value. Call `composition/2` only for committed text, not
for an input method's partial display value. Paste stays a
`TermUI.Event.Paste` value.

Pass `save` to `TermUI.Shortcut.route/2`. The key helper converts common names
such as `Return` and `ArrowUp`, and modifiers such as `control` and `option`.
It rejects unmodified printable input. Use `text/2` for that input. No helper
turns all printable text into legacy key-character values.

## Clipboard commands

`TermUI.Clipboard.copy/2` and `TermUI.Clipboard.clear/1` create command data.
The runtime sends each operation through the backend owner. Thus, clipboard
output is in sequence with frame output and terminal cleanup.

```elixir
def update({:copy, text}, state) do
  {state, [TermUI.Clipboard.copy(text, on_result: &{:clipboard_done, &1})]}
end

def update({:clipboard_done, :ok}, state), do: state
def update({:clipboard_done, {:error, reason}}, state), do: put_error(state, reason)
```

The result mapper receives `:ok` or `{:error, reason}`. A backend that does not
implement clipboard output returns an error. Clipboard data has a 100,000-byte
default limit. Use `:max_bytes` to set a smaller or larger positive limit.

The implementation uses OSC 52. The available targets are `:clipboard`,
`:primary`, and `:secondary`. `osc52_supported?/0` is only a terminal
heuristic. A terminal can still refuse the operation.

Bracketed paste is separate from clipboard output. A backend enables bracketed
paste and reports its content as `TermUI.Event.Paste`.

## Text selection

`TermUI.Selection` is pure data. Positions are zero-based Unicode grapheme
offsets. A range is half-open: `{start, finish}` includes `start` and excludes
`finish`.

```elixir
selection =
  TermUI.Selection.new()
  |> TermUI.Selection.start(1)
  |> TermUI.Selection.extend(3)

TermUI.Selection.extract(selection, "a界🙂z")
#=> "界🙂"
```

The module supports forward and backward ranges, replacement, select all,
word selection, and line selection. `TextInput` and `TextArea` support:

- Shift with Left, Right, Home, and End.
- Shift with Up and Down in `TextArea`.
- Ctrl+A, Ctrl+C, and Ctrl+X.
- Mouse press and drag selection.
- Paste or text replacement of the selected range.
- Selection removal with Backspace or Delete.

Copy and cut actions return `{:copy, text}` to the parent. The parent can
convert this message to `TermUI.Clipboard.copy/2`.

## Mouse routing

Terminal mouse coordinates are zero-based. Build regions from the same layout
that creates the frame. Then route the event before you call a child widget.

Raw terminals do not enable mouse reporting by default because it changes the
terminal's native text selection. Enable the smallest mode that your
application needs:

```elixir
TermUI.run(MyApp,
  backend: :raw,
  backend_opts: [mouse_tracking: :drag]
)
```

The modes are `:none`, `:click`, `:drag`, and `:all`. Use `:click` for press
and release events. Use `:drag` for button motion. Use `:all` only when hover
motion is necessary.

```elixir
regions = [
  TermUI.Mouse.region(:list, 2, 3, 30, 10),
  TermUI.Mouse.region(:dialog, 8, 5, 40, 12, z_index: 10)
]

case TermUI.Mouse.route(regions, event) do
  {:ok, :list, local_event} ->
    TermUI.Widget.mouse(TermUI.Widget.List, local_event, state.list, {30, 10})

  {:ok, :dialog, local_event} ->
    handle_dialog_mouse(local_event, state)

  :none ->
    {state, []}
end
```

The highest `:z_index` wins. The later region wins when two regions have the
same z-index. `route_all/2` returns all matches in front-to-back order.

`TermUI.Mouse.Tracker` gives pure hover and drag state. Its default drag
threshold is one terminal cell. Store the tracker in the application state.
Reset it when focus is lost.

Widgets can implement the optional `mouse/3` callback. Call it through
`TermUI.Widget.mouse/4`. The helper uses the widget's `mouse/3` callback when
it exists. Otherwise, it sends the event to `update/2`.

Interactive catalog widgets support local mouse input. This includes text
inputs, buttons, lists, menus, pick lists, command palettes, dialogs, forms,
tabs, tables, trees, scrollbars, and split panes. Scrollable content widgets
also accept mouse wheel events through `update/2`.
