---
title: Completed repository cleanup
type: maintenance
date: 2026-09-30
status: completed
---

> Historical plan. The current work is defined in [the RC1 plan](../2026-09-30-001-refactor-rc1-documentation-plan.md).

# Repository cleanup before further test work

Approved on 30 September 2026. Branch: `chore/v2-repository-layout`.
Base and pull request target: `main`. V1 remains on `maint/1.x`.

## Intended result

Keep a small library package with current guides, runnable consumer examples,
required native/browser assets, and a clear GitHub setup. Remove old local
tooling and duplicate source paths. Preserve history in Git and an external
backup.

```text
term_ui/
  .github/             workflows, dependency updates, issue and PR templates
  c_src/              optional local TTY NIF source
  config/config.exs   development release-tool configuration
  examples/           four existing applications and Linux release inputs
  guides/             current public documentation
  lib/
    mix/tasks/        existing consumer command
    term_ui/          runtime, widgets, backends, adapters
    term_ui.ex        public entry point
  notes/
    planning/         active plans
    releases/         source release and verification records
  priv/web/           required browser runtime assets
  test/               existing tests and platform tools
  mix.exs, mix.lock   package and dependency definitions
```

## Changes

- Remove `.claude`, `CLAUDE.md`, `.tool-versions`, old dashboard images, and
  optional editor prompt files.
- Keep one configuration file. Remove empty environment config files.
- Move the Mix task into `lib/mix/tasks`; preserve its public command.
- Remove `.dialyzer_ignore.exs`. Provide MDEx's optional Lumis types in the
  development analysis environment, with no new required runtime dependency.
- Keep browser assets in `priv/web` and native build source in `c_src`.
- Remove the duplicate local CI script. Document commands in `CONTRIBUTING.md`.
- Pin workflow callers. Keep required checks. Add issue/PR templates and
  dependency updates for existing examples. Enable automatic deletion of merged
  PR branches in GitHub settings.
- Index every example. Correct old v1 and release-candidate guidance.
- Reduce 464 tracked notes to active plans and relevant v2 release records.
  Move the physical terminal procedure into the guides.
- Move the root release record into `notes/releases` and fix references.
- Keep an explicit package allowlist, including the formatter config.
  Keep examples in the repository, outside the published package.

## Completion checks

- [x] Review final tracked folders and package files.
- [x] Check local documentation links and GitHub configuration syntax.
- [x] Run `mix quality` with no Dialyzer warning suppression.
- [x] Run `mix coveralls` and preserve the 90% minimum.
- [x] Run existing acceptance and affected example checks.
- [x] Build and inspect a package; compile its source and consumer Mix task.
- [ ] Pass all required GitHub CI checks.

No terminal lifecycle implementation changes are planned. If one becomes
necessary, add a real terminal check. Hex publication stays with the maintainer.
Do not add property tests, fuzz tests, new examples, or new example tests before
this cleanup is complete.

## Local validation record

Elixir 1.19.3 / OTP 28.1.1: `mix quality` passed; 1,041 tests passed, one
excluded, with 90.3% coverage. The existing acceptance specification and all
11 showcase tests passed. The counter compiled; it still has no standalone
tests. Strict docs, dependency audit, unused lock checks, YAML parsing, and
Actionlint passed. Local Markdown links were checked. The package contains
144 files, including native source, browser assets, the Mix task, and formatter
configuration. It excludes examples, notes, test tools, and repository config.

A fresh extracted package compiled in production mode with the source TTY NIF.
The consumer check passed for native loading, both browser assets, the moved
Mix command, input/state/frame output, and normal cleanup. Lumis was absent
from the production code path. The package SHA256 is
`ddd53a954f84e8743a91bb236b025f2fa2eac69046dd76433ec6d2120ed4b7a6`.
