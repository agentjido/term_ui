# UI context decision

TermUI does not provide a generic `TermUI.Context` value in TermUI 2.0.
The v2 examples do not show repeated root wiring across theme,
focus, shortcuts, and mouse state.

## Evidence from the v2 examples

The review used both runnable applications and every showcase page.

| Scope | Theme state | Focus or active state | Shortcut state | Mouse tracker state |
| --- | ---: | ---: | ---: | ---: |
| `IExCounter.App` root | 0 | 0 | 0 | 0 |
| `Showcase.App` root | 1 | 0 | 0 | 0 |
| Showcase page states | 0 | 4 local values | 0 | 0 |

The showcase passes its theme through one root-to-page boundary,
`Showcase.Page.view/3`. Six page modules implement that boundary. The root does
not pass focus, shortcut, or mouse state through it.

The Inputs and Controls pages each own a small focus order. The Content and
BEAM pages each own an active view selector. These four values have different
lifetimes and meanings. Moving them to the application root would make the
root know details that belong to each page.

The showcase has two command-key mapping groups with five common keys. It does
not store shortcut sequence state. An application that needs chords or key
sequences can store a `TermUI.Shortcut` value directly. A generic context does
not remove those mappings.

Neither example uses mouse tracker state. Widgets receive local mouse events
only when the parent that owns their layout routes those events.

## Decision

A library context would not reduce the measured boundary count. It would
replace the one theme argument with a larger value that has unused fields. It
would also invite the root application to own page-local focus and mouse data.

TermUI keeps the four pure values independent:

- Store `TermUI.Theme` at the highest parent that shares the theme.
- Store `TermUI.Focus` at the parent that owns that focus order.
- Store `TermUI.Shortcut` at the scope that owns the bindings.
- Store `TermUI.Mouse.Tracker` at the parent that draws and routes the matching
  regions.

This decision can change when a real v2 application must pass at least three
of these values together through several of the same boundaries. A future
proposal must include that application evidence and must remain a pure,
application-owned value.

## Preferred explicit wiring

Update each value with its own pure function and put the returned value back in
the owning model:

```elixir
{focus, focus_messages} = TermUI.Focus.route(event, state.focus)
{shortcuts, shortcut_messages} = TermUI.Shortcut.route(event, state.shortcuts)

state = %{state | focus: focus, shortcuts: shortcuts}
messages = focus_messages ++ shortcut_messages
```

Query only the value that a child needs:

```elixir
focused? = TermUI.Focus.focused?(state.focus, :editor)
panel_style = TermUI.Theme.style(state.theme, :panel)

child_frame = Editor.view(state.editor, dimensions,
  focused: focused?,
  panel_style: panel_style
)
```

For mouse input, build regions from the same layout that creates the frame.
Keep the tracker beside that layout state:

```elixir
{mouse, drag_messages} = TermUI.Mouse.Tracker.update(state.mouse, event)

case TermUI.Mouse.route(regions, event) do
  {:ok, id, local_event} -> route_child_mouse(id, local_event, %{state | mouse: mouse})
  :none -> {%{state | mouse: mouse}, drag_messages}
end
```

An application can define its own struct when its values always move together.
TermUI does not standardize that application-specific shape and does not store
it in a process, registry, application environment, or persistent term.
