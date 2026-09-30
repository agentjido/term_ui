# Counter example

This is the smallest supported TermUI example. It uses one Elm application, typed
events, data commands, and one `TermUI.Frame` render value.

Run it with:

```sh
cd examples/iex_counter
mix deps.get
mix run run.exs
```

Use Up and Down to change the value. Use R to reset it. Use Q to stop it.

The initial screen shows `TermUI counter` and `Count: 0`. Resize the terminal
to see a complete frame with the new dimensions. After Q, the shell returns.

For IEx, run `iex -S mix` in this directory and call
`IExCounter.App.run(backend: :tty)`.

## Read the source

Follow [App](lib/iex_counter/app.ex) in callback order: `init/1`,
`event_to_msg/2`, `update/2`, then `view/1`. Up and Down are named key events;
R and Q are text events. Resize updates the stored dimensions. Quit returns
`Command.shutdown()` as data. The runtime owns execution and backend cleanup.

## Verify the lesson

```sh
mix test --warnings-as-errors
```

[The tests](test/app_test.exs) run the actual app with the deterministic backend.
They check visible count changes, decrement below zero, reset, uppercase quit,
normal cleanup, and resize clipping. From the repository root, `mix spex`
runs [the readable acceptance workflow](../../test/spex/counter_spex.exs).
These checks need no physical terminal and do not verify its OS flags.

Next: [compose widgets in the showcase](../showcase/README.md).
