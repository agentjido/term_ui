# Package quality

TermUI follows the [Jido package quality standard](https://jido.run/docs/contributors/package-quality-standards)
where it does not conflict with the public TermUI contract. The shared
[`agentjido/github-actions`](https://github.com/agentjido/github-actions)
repository is the source of truth for workflow versions. TermUI uses the v5
callers because v5 is the current stable workflow contract. The standards page
still contains some older v4 examples.

## Compliance record

| Area | TermUI decision |
| --- | --- |
| Package identity | README, Hex metadata, guides, and module docs describe the Elm runtime and its use by Jido Console. |
| Repository files | `AGENTS.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `LICENSE`, `usage-rules.md`, examples, guides, and environment config files are present. |
| Public data | Public boundary values use Zoi schemas. Private runtime and widget state uses plain structs. |
| Quality command | `mix quality` runs format, warning-free compile, xref cycle checks, strict Credo, Dialyzer, and Doctor. |
| Tests and coverage | `mix coveralls` runs deterministic tests and enforces at least 90% line coverage without excluding production modules. |
| CI | The v5 shared CI caller tests each declared Elixir and OTP pair. The native-policy jobs also test the source NIF on the minimum pair. CI checks audit, docs, package content, and unused dependencies. |
| Dependency updates | Dependabot checks Mix and GitHub Actions dependencies each week with Conventional Commit titles. |
| Releases | The v5 shared release caller uses `git_ops` for release preparation and Hex publication. |
| Review | The v5 shared advisory review caller checks pull requests to `develop` and `next/v2`. |
| Examples | The runnable counter and showcase examples are outside `lib/` and have their own Mix projects. |
| Worktree safety | The package does not auto-install Git hooks and does not store local worktree paths. |

## Documented exceptions

- The public namespace stays `TermUI`, not `Jido.TermUI`. This preserves the
  upstream API and the Jido Console contract.
- TermUI keeps small tagged error tuples at backend and runtime boundaries. It
  does not add Splode during the release candidate because that would change
  the public failure contract.
- TermUI has no installer. It needs no project files, configuration, database
  changes, or generated code, so an Igniter installer would have no work to do.
- `develop` remains the default stable integration branch. The v2 work stays
  on `next/v2`, so CI push and review filters include both branches.

Review these exceptions before the stable 2.0 release. Do not remove them by
changing the runtime or public namespace in a quality-only change.

## Supported runtime matrix

The package requires Elixir `>= 1.18.4 and < 2.0.0`. TermUI declares these CI
pairs:

| Erlang/OTP | Elixir | Purpose |
| --- | --- | --- |
| 28 | 1.18.4 | Minimum supported pair and minimum source-NIF test |
| 28 | 1.19 | Supported Elixir line |
| 28 | 1.20 | Supported Elixir line on the minimum OTP release |
| 29 | 1.20 | Newest supported OTP release and source/disabled NIF policies |

The minimum is the intersection of two technical limits:

- OTP 28 is required by the raw terminal contract. The real PTY test must
  receive Ctrl+O, Ctrl+C, Ctrl+S, and Ctrl+Q as data. OTP 26 and OTP 27 compile
  the source NIF and pass the non-terminal suite, but the PTY probe does not
  receive those bytes. TermUI does not claim support for a runtime that loses
  input bytes.
- Elixir 1.18.4 is the first Elixir 1.18 patch with initial OTP 28 support. The
  [Elixir 1.18 changelog](https://elixir.hexdocs.pm/1.18/changelog.html#v1-18-4-2025-05-21)
  documents that compatibility. Older Elixir lines can compile much of TermUI,
  but their supported OTP ranges end before OTP 28.

The CI matrix and the package requirement must change together. A new minimum
must pass the complete suite and the source-NIF PTY test. A compile-only result
or a run with `TERM_UI_TTY_NIF=disabled` is not enough.
