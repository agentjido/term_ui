# Run your first TermUI application

Use Elixir 1.18.4 or later and OTP 28 or later. The current source version is
`2.0.0-rc.1`. It has not been published by this preparation work. Start with
the counter from a source checkout:

```sh
git clone https://github.com/agentjido/term_ui.git
cd term_ui/examples/iex_counter
mix deps.get
mix run run.exs
```

The screen shows `TermUI counter` and `Count: 0`. Press Up to add one, Down
to subtract one, R to reset, and Q to quit. Change the terminal size; the frame
uses the new size. After quit, the shell prompt and normal input return.

For an IEx session, run `iex -S mix` in the same directory, then call:

```elixir
IExCounter.App.run(backend: :tty)
```

## Follow one event

Read [the counter source](https://github.com/agentjido/term_ui/blob/main/examples/iex_counter/lib/iex_counter/app.ex):

1. `init/1` stores the count and the supplied `{columns, rows}` dimensions.
2. `event_to_msg/2` converts Up to `:increment`. Printable R and Q arrive as
   `TermUI.Event.Text`, while Up arrives as `TermUI.Event.Key`.
3. `update/2` creates the next count. Quit returns `Command.shutdown()` as data.
4. `view/1` creates a complete `TermUI.Frame` from the current state.
5. The runtime gives the frame to its backend owner. That owner draws it and
   restores terminal state when the runtime stops.

The application owns state; the backend owns terminal I/O. A widget added
later must remain pure and must return messages to the parent for effects.

## Check it without a physical terminal

From `examples/iex_counter`, run:

```sh
mix test --warnings-as-errors
```

The tests run the actual application with `TermUI.Test.DeterministicBackend`.
They check the count, rendered output, reset, resize, and normal quit. From the
repository root, `mix spex` runs its readable acceptance workflow. These tests
do not prove physical keyboard encoding or terminal flag restoration; use
[the terminal procedure](terminal-checks.md) for those checks.

Next, use [the ordered examples](examples.md) to add widgets or a browser host.
