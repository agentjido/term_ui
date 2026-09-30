# Add input, forms, tables, and streams

These four recipes use the existing counter consumer. Each application owns
its widget state and returns one complete frame. Run from
`examples/iex_counter` after `mix deps.get`:

```sh
mix run -e 'TermUI.run(IExCounter.Recipes.InputFocus)'
mix run -e 'TermUI.run(IExCounter.Recipes.Form)'
mix run -e 'TermUI.run(IExCounter.Recipes.Table)'
mix run -e 'TermUI.run(IExCounter.Recipes.Stream)'
```

Run one command at a time. Press Esc to quit. Run `mix test --warnings-as-errors`
in that directory to check the recipes and the code blocks below. The complete
applications also handle resize; frame dimensions use `{columns, rows}`.

## Route input to the focused widget

In the input recipe, type a name, press Tab, then type a city. Shift+Tab returns
to the name. Text and paste go only to the focused input. The parent routes
Tab through `TermUI.Focus`; Home and End stay with the text editor. Only the
focused child retains a cursor when the parent overlays the two frames.

```elixir
focus = TermUI.Focus.new([:name, :city])
{focus, _messages} = TermUI.Focus.route(TermUI.Event.key(:tab), focus)
input = TermUI.Widget.TextInput.init(max_length: 20)
{input, _messages} = TermUI.Widget.TextInput.update(TermUI.Event.paste("Zürich\n"), input)
{focus.current, input.value}
```

This returns `{:city, "Zürich"}`. The newline is removed because this is a
single-line input. Ctrl+A selects all text; Ctrl+C and Ctrl+X return copy
messages. The parent converts those messages to `TermUI.Clipboard.copy/1`
commands. Clipboard output is a backend effect.

Read [InputFocus](https://github.com/agentjido/term_ui/blob/main/examples/iex_counter/lib/iex_counter/recipes/input_focus.ex)
and its [behavior tests](https://github.com/agentjido/term_ui/blob/main/examples/iex_counter/test/recipes_test.exs).

## Validate a form before use

Press Enter with an empty name to show the required-field error. Type a name,
use Tab to select Role, and use Left or Right to change the choice. Tab moves
to Alerts; Space changes the checkbox. Enter shows the accepted values.
The recipe displays a confirmation; it does not write to a service.

```elixir
form = TermUI.Widget.FormBuilder.init(fields: [%{id: :name, label: "Name", required: true}])
{invalid, _messages} = TermUI.Widget.FormBuilder.update(TermUI.Event.key(:enter), form)
{edited, _messages} = TermUI.Widget.FormBuilder.update(TermUI.Event.paste("Ada"), invalid)
{valid, messages} = TermUI.Widget.FormBuilder.update(TermUI.Event.key(:enter), edited)
{invalid.errors.name, valid.errors, messages}
```

This returns `{"is required", %{}, [{:submit, %{name: "Ada"}}]}`. Field and
group validators stay pure. Convert a valid submit message into a command
when the application must save externally. A widget must not do that effect.

Read [Form](https://github.com/agentjido/term_ui/blob/main/examples/iex_counter/lib/iex_counter/recipes/form.ex)
and its [behavior tests](https://github.com/agentjido/term_ui/blob/main/examples/iex_counter/test/recipes_test.exs).

## Preserve row identity when data changes

Press Down and Enter to select Bea. R refreshes and reorders the rows; S cycles
the name sort. H hides or shows Bea. The footer keeps selected ID `2` while
the row is hidden. The selection refers to an ID, not a visible row number.

```elixir
table = TermUI.Widget.Table.init(rows: [%{id: 1, name: "Ada"}, %{id: 2, name: "Bea"}], row_id: :id)
table = TermUI.Widget.Table.set_selection(table, [2])
table = TermUI.Widget.Table.set_rows(table, [%{id: 2, name: "Bea updated"}, %{id: 1, name: "Ada"}])
TermUI.Widget.Table.selected_rows(table)
```

This returns `[%{id: 2, name: "Bea updated"}]`. Each ID must be unique and
stable. A refresh removes selected IDs that are no longer present. A filter
keeps selected IDs for rows that still exist.

Read [Table](https://github.com/agentjido/term_ui/blob/main/examples/iex_counter/lib/iex_counter/recipes/table.ex)
and its [behavior tests](https://github.com/agentjido/term_ui/blob/main/examples/iex_counter/test/recipes_test.exs).

## Feed a bounded stream through commands

Press L to load four fixed items. The buffer holds three, so the screen shows
beta, gamma, and delta and reports one dropped item. Space pauses the view.
L while paused rejects the incoming batch. F runs a failed load; the existing
items remain visible and the status gives a retry action. L retries.

```elixir
command = TermUI.Command.async(fn -> ["alpha", "beta", "gamma", "delta"] end, &{:loaded, &1})
stream = TermUI.Widget.Stream.init(limit: 3, overflow: :drop_oldest)
{stream, result} = TermUI.Widget.Stream.offer_many(stream, ["alpha", "beta", "gamma", "delta"])
{command.kind, stream.items, result}
```

This returns `{:async, ["beta", "gamma", "delta"], %{accepted: 4, dropped: 1,
rejected: 0}}`. Creating a command does not run its function. The runtime runs
it and supplies one outer result tag to the mapper: `{:ok, items}` or
`{:error, reason}`. The parent handles `{:loaded, result}`, changes stream
state, and renders. No stream widget process owns data or effects.

This small recipe loads finite batches. For continuous external producers,
use `TermUI.Stream.ProducerAdapter` and acknowledge each delivered batch through
an application-owned effect. Its delivery bound and the widget display bound
serve separate purposes. See [architecture](architecture.md).

Read [Stream](https://github.com/agentjido/term_ui/blob/main/examples/iex_counter/lib/iex_counter/recipes/stream.ex)
and its [behavior tests](https://github.com/agentjido/term_ui/blob/main/examples/iex_counter/test/recipes_test.exs).

## Know the test limits

The consumer tests check editing, validation, row identity, buffer loss, frame
bounds, and shutdown command data. Runtime acceptance scenarios in `test/spex`
check drawn frames, actual command results, and normal backend cleanup. Follow
[testing](testing.md) for the full commands and the separate physical terminal
checks. Neither group proves a physical keyboard or a terminal frontend.
