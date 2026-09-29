# V2 counter request

Use a checkout of `agentjido/term_ui` on `next/v2`. Read `AGENTS.md`,
`CONTRIBUTING.md`, the README application contract, and `examples/iex_counter`
before you write code.

Create a small counter in the namespace `Demo.Counter`:

- Start at zero. Up increases the count. Down decreases it. Lowercase or
  uppercase q requests shutdown. Ignore other input.
- Show the count and a help line. Handle resize with the new width and height.
- Use `TermUI.Elm`. Return one complete `TermUI.Frame` from `view/1`.
- Use `TermUI.Event.Text` for printable q and `TermUI.Event.Key` for Up and
  Down. Use `TermUI.Command.shutdown/0` to request cleanup.
- Keep state and update order in the runtime. Do not write terminal output,
  change terminal modes, or start a process from `view/1` or a widget.
- Add a documented start command and checks for count changes, frame output,
  resize, and shutdown. Use `TermUI.Test.DeterministicBackend` for runtime
  checks. Read its API on this branch before use.
- Run `mix quality` and `mix coveralls`. Run the application in a real terminal
  and check Up, Down, q, resize, and restored settings after quit.

Report the source commit, toolchain, checks, and terminal used. State any check
that you could not complete.
