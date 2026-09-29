# V1 counter request

Use a checkout of `agentjido/term_ui` on `maint/1.x`. Read `AGENTS.md`,
`guides/user/03-elm-architecture.md`, `guides/user/04-events.md`,
`guides/user/09-commands.md`, and `examples/iex_counter` before you write code.

Create a small counter in the namespace `Demo.Counter`:

- Start at zero. Up increases the count. Down decreases it. Lowercase or
  uppercase q requests shutdown. Ignore other input.
- Show the count and a help line. Check output after terminal resize.
- Use `TermUI.Elm` and the v1 text and stack helpers in `view/1`. Keep state
  and update order in the runtime.
- Use `TermUI.Event.Key` with string keys for printable q and Q, and named
  keys for Up and Down. Require no modifiers for q and Q.
- Return a `TermUI.Command.quit/0` value from `update/2` to request cleanup.
  Do not write terminal output or change terminal modes from `view/1`.
- Add a documented start command and checks for state changes and output.
- Run `mix quality` and `mix coveralls`. Run the application in a real terminal
  and check Up, Down, q, resize, and restored settings after quit.

Report the source commit, toolchain, checks, and terminal used. State any check
that you could not complete.
