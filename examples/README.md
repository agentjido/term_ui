# Example lessons

Read these four consumer projects in order. Each teaches a public contract
through runnable source, expected behavior, and tests. Use Elixir 1.18.4 or
later with OTP 28 or later. Run the commands from a source checkout.

| Order | Example | Learn | Source | Checks |
| --- | --- | --- | --- | --- |
| 1 | [Counter](iex_counter/README.md) | Input, application state, complete frames, resize, and quit | [App](iex_counter/lib/iex_counter/app.ex) | [Application tests](iex_counter/test/app_test.exs), [acceptance workflow](../test/spex/counter_spex.exs) |
| 2 | [Showcase](showcase/README.md) | Pure widgets, parent composition, data snapshots, and command effects | [App](showcase/lib/showcase/app.ex), [pages](showcase/lib/showcase/pages) | [Application tests](showcase/test/showcase/app_test.exs) |
| 3 | [Browser host](web/README.md) | Host-owned transport and isolated application sessions | [App](web/lib/app.ex), [socket](web/lib/socket.ex), [router](web/lib/router.ex) | [Application tests](web/test/app_test.exs), [Chromium tests](web/test/browser/web.spec.js) |
| 4 | [Ghostty shell host](ghostty/README.md) | Optional real shell frames, command-owned input, and child cleanup | [App](ghostty/lib/app.ex), [host](ghostty/lib/application.ex) | [Native sessions](ghostty/test/session_test.exs), [Chromium shell](ghostty/test/browser/session.spec.js) |

The existing project names stay stable. `iex_counter` runs through both Mix
and IEx. `ghostty` uses a native terminal emulator and PTY; it is separate from
TermUI's local TTY input NIF. Its README lists supported systems and native
build requirements.

Each project has its own Mix dependencies. Web hosts and Ghostty remain
optional consumers, outside the core Hex package. CI runs their current
application, browser, and native checks.

The Linux Docker files moved to
[docs/recipes/linux-release](../docs/recipes/linux-release/README.md). They are
build inputs for an older glibc target, not an interactive application. Use
[the Linux release guide](../guides/linux-releases.md) when that target is needed.

## Add or refine a lesson

State the user's task, required tools, run command, expected screen or output,
and exit command. Point to the source that owns each behavior and its test.
Keep data fixtures local where possible. Add a consumer test and its CI check
with a new example. Keep package API detail in module docs and link the relevant
[guide](../guides/README.md).
