# Repository layout

TermUI is a library package. Keep runtime code and required assets separate
from examples, tests, development tools, and release records. This layout
follows the same package structure as Jido Action and Jido v3, with the native
and browser files that TermUI needs.

| Path | Purpose | In the Hex package |
| --- | --- | --- |
| `lib/term_ui.ex`, `lib/term_ui/` | Public API, runtime, frames, pure widgets, backends, and adapters | Yes |
| `lib/mix/tasks/termui.run.ex` | Existing `mix termui.run` consumer command | Yes |
| `c_src/`, `Makefile`, `Makefile.win` | Optional TTY NIF source and build rules | Yes |
| `priv/web/` | JavaScript and CSS used by browser consumers | Yes |
| `guides/` | Current user, architecture, migration, and contributor guides | Yes |
| `examples/` | Separate applications and optional host dependencies | No |
| `test/` | Unit, integration, acceptance, and platform test tools | No |
| `.github/` | Workflows and dependency updates | No |
| `config/config.exs` | Development-only `git_ops` release configuration | No |
| `docs/plans/` | Current maintenance plans | No |
| `docs/solutions/`, `docs/releases/` | Verified fixes and source verification records | No |
| `docs/recipes/` | Optional consumer build inputs | No |
| `AGENTS.md` | Repository work rules | No |

The explicit package file list in `mix.exs` also includes `.formatter.exs`,
metadata, the license, changelog, contribution guidance, and usage rules.
Local tool versions, editor settings, generated docs, coverage files, package
archives, and compiled native libraries are not release inputs.

## Runtime files

`priv` is the OTP application directory for runtime files that are not BEAM
modules. Consumers find it with `:code.priv_dir(:term_ui)`.

Keep `priv/web/term_ui.js` and `priv/web/term_ui.css`. Browser hosts serve these
files from that directory. The optional TTY NIF also uses `priv` for its
compiled library, such as `term_ui_tty_nif.so` on macOS. Source builds generate
it from `c_src`. Git ignores the binary and the Hex file list includes only
`priv/web`, so a local platform binary cannot enter the package. Deleting the
generated NIF would remove the current source build output; deleting the whole
folder would also remove the required browser assets.

Keep `mix termui.run` under `lib/mix/tasks`. This puts compiled Elixir source
under `lib` and preserves the existing consumer command. It runs an
application's `run/0` function; it does not add a second runtime.

Examples stay in the repository. The runtime does not load their source, so
they are excluded from the package. Use the linked source checkout to run the
showcase. The library has no built-in demo command.

## Configuration and CI

The library needs no application-wide configuration. Its repository config
sets up `git_ops` in the development environment. Empty environment config
files are not needed. Consumers select options when they start an application.

The shared Jido v5 CI, review, and release callers use pinned commit references.
CI retains the declared toolchain and platform checks. The separate web job
needs Node.js and Chromium. Ghostty checks need a native SDK. These dependencies
stay outside the core library.

Dependabot covers core and example Mix projects, the web npm project, and
GitHub Actions. V1 updates target `maint/1.x`; v2 updates target `main`.

Hex publication belongs to the maintainer. The manual release caller publishes
an existing annotated tag with an explicitly passed `HEX_API_KEY`. Version
changes go through PR checks. See [publishing](publishing.md) for the flow.
Normal cleanup builds and checks a package locally.

## Historical material

Use [docs](https://github.com/agentjido/term_ui/blob/main/docs/README.md) for
active plans, verified solutions, recipes, and concise source records. This
replaces `notes`. Current API guidance belongs in `guides`. Generated ExDoc
output is in ignored `doc`. Old feature plans, reviews, agent commands, screenshots,
and research remain in Git history at
`1002f3fc85dc7ed103cf55de243877e4b19c3bac`.

Do not restore obsolete runtime instructions to the working tree. Use the v1
branch for the v1 API. See [physical terminal checks](terminal-checks.md) for
the remaining Windows checks.
