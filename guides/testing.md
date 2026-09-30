# Test an application and the package

Use tests to state observable behavior. Check input, resulting state, rendered
frames, command effects, and cleanup as separate results. A test that only
starts a runtime does not establish that input or shutdown works.

## Test groups

| Path | Purpose | Command from the repository root |
| --- | --- | --- |
| `test/term_ui` | Focused public API, widget, parser, frame, and backend tests | `mix test test/term_ui` |
| `test/integration` | Runtime ordering, effects, failure, redraw, color, and SSH contracts | `mix test test/integration` |
| `test/spex` | Readable user acceptance workflow against the real counter | `mix spex` |
| `test/platform` | Real Unix PTY checks and native-policy or Windows console tools | `mix test test/platform` for the Unix PTY case |
| `test/mix` | Consumer Mix command behavior | `mix test test/mix` |
| `test/support` | Compiled private helpers such as the ANSI screen reader | Loaded by the test build |
| `examples/*/test` | The actual consumer applications and browser/native hosts | Run `mix test --warnings-as-errors` in that example |

Run `mix quality` and `mix coveralls` before a commit. Coverage must remain at
least 90%. Run `mix spex` separately; `_spex.exs` files are excluded from the
normal ExUnit test search. The SexySpex CLI uses `test/spex` by default, so keep
that directory unless the caller is also changed.

Platform `*_probe.exs` files are command-line tools. The package excludes that
exact filename pattern under `test/platform/support` from test discovery.
Elixir 1.20 otherwise reports those files as unmatched tests. Actual
`*_test.exs` files remain part of the normal suite.

## SexySpex review

SexySpex supplies Given-When-Then steps on top of ExUnit. Its original TermUI
scenario exercised one Up key in a test-only counter. That was a valid check
of input, state, and frame output, but a narrow specification of TermUI.

The RC1 scenario loads the real `IExCounter.App` source and checks startup,
increment, output, quit, backend cleanup, and normal process exit. It uses an
ExUnit test supervisor to stop the runtime after a failed assertion. The
standalone counter tests add decrement, reset, uppercase quit, and resize.

Keep SexySpex for a few readable user workflows. Use ordinary ExUnit for edge
cases and internal contracts. Neither framework can turn simulated events
into proof of physical keyboard or terminal mode behavior. The next acceptance
work is recorded in the RC1 plan under `docs/plans`; property and fuzz tests
come after this folder and guide cleanup.

## Reliable completion checks

Wait for a drawn frame before you assert visible output. `Runtime.sync/1`
confirms message order from its caller; it does not confirm drawing or backend
cleanup. Use explicit backend messages and process monitors with bounded
timeouts. Install a monitor before an action that can stop the child.

Use fixed data for documentation and repeatable tests. The showcase provides
`data_mode: :snapshot`. Keep live collection checks separate so changes in
process data do not change an expected frame.

## Physical and optional host checks

`TERM_UI_TTY_NIF=disabled mix test` selects the non-native path and excludes
NIF-dependent tests. `TERM_UI_TTY_NIF=source mix test` requires a source build
and includes the Unix PTY control-byte check. Tests tagged `:requires_terminal`
remain excluded unless `TERMUI_INCLUDE_TERMINAL_TESTS=1` is set.

Windows CI checks Command Prompt and Git Bash through ConPTY. It does not prove
the physical Windows Terminal or Mintty profiles. Follow
[physical terminal checks](terminal-checks.md) and keep their recorded gaps.
Use the web and Ghostty READMEs for their Chromium and real native checks.
