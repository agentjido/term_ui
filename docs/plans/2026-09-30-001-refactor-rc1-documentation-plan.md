---
title: RC1 documentation and test cleanup
type: refactor
date: 2026-09-30
status: active
---

# RC1 documentation and test cleanup

## Intended result

Prepare a clear package tree for `2.0.0-rc.1`. This is a release candidate,
not the final 2.0 release. Start from `main` at
`7aa844da56d51559a17bc7c9b2465032c334d626`. Use branch `release/2.0.0-rc.1`
and target `main`. V1 stays on `maint/1.x`.

## Scope and decisions

- Keep one state owner, one complete frame, one backend owner, pure widgets,
  command data, and the public `TermUI` namespace.
- Keep the four consumer projects. Follow Jido Core's ordered example catalog,
  linked source, tests, and expected results. TermUI keeps separate Mix projects
  because browser and native host dependencies are optional.
- Jido Action's current local checkout has no example catalog. Follow its
  package guides and `docs/plans` layout; do not claim to copy examples it lacks.
- Move maintainer material from `notes` to `docs`. Keep public guides under
  `guides` and generated ExDoc output under ignored `doc`.
- Move the Linux build recipe out of `examples`. Keep the recipe and its tested
  target; it resolves a real consumer build problem.
- Keep `priv/web` and the generated TTY NIF location. Ship native source,
  not a local compiled NIF.
- Keep SexySpex for short user workflows. Keep `test/spex`, which its CLI finds
  by default. Test the shipped counter rather than a copy inside a specification.
- Keep existing CI job names and required checks. Remove the contribution
  templates the maintainer deleted; retain Dependabot and workflow callers.

## Work order

| Phase | Work | Completion condition |
| --- | --- | --- |
| 1, complete in PR #102 | RC1 version, folder cleanup, guide index and first tutorial, example lessons, counter behavior tests, specification review | Links, quality, coverage, acceptance, affected examples, and required CI passed |
| 2, `docs/rc1-widget-recipes` | Small recipes for input/focus, forms, tables, and stream updates | Each recipe points to real source and a behavior test; copyable code uses the current API |
| 3, `test/rc1-acceptance-flows` | Add core user scenarios for text/paste, focus, row identity, resize, async failure, and normal cleanup | Scenarios assert visible frames and effects; they run without a physical terminal |
| 4, `test/rc1-property-boundaries` | Bounded parser, frame, and protocol properties, then regression fuzz inputs | Failures include a seed and a small replayable input; short checks run in PR CI |
| 5, `release/2.0.0-rc-validation` | Fresh package consumer and remaining terminal evidence | Record exact commits, toolchains, terminal profiles, known gaps, and maintainer release decision |

Finish the documentation and folder cleanup before phases 3 and 4. Do not add
a generator dependency or new demonstration applications in phase 1. Hex
publication and release tags require a separate maintainer instruction.

## Guide refinement

Organize guides around user tasks: start a counter, compose widgets, choose a
backend, test an application, migrate v1, and build or publish a release.
Keep API detail in module docs. Keep design evidence and completed checks in
`docs`. Avoid another guide that repeats the full widget catalog.

For each later guide change, check the source callback names, coordinate
conventions, command result shape, and stop behavior. Run copyable snippets in
a small consumer. Link the test that supports a claim and state its limits.

## Test review

The old SexySpex scenario checked one Up key in a private test counter. It
proved the deterministic input/state/frame path, but did not validate the
shipped example, quit, resize, or physical terminal behavior. RC1 links the
specification to the real counter and adds quit/cleanup checks. Focused ExUnit
tests cover its resize and control flow. Physical terminal and browser/native
checks remain separate because a deterministic backend cannot prove them.

The main suite already checks runtime failures, SSH sessions, clipboard output,
widgets, web protocol bounds, and native input. Keep these assertions and the
90% coverage minimum. Move files by purpose; do not remove tests to make the
tree smaller. The monitor registration race has a
[verified solution](../solutions/2026-09-30-terminal-session-monitor.md).

## Validation

- Run `mix quality`, `mix coveralls`, `mix spex`, strict ExDoc, dependency audit,
  unused lock checks, and a local Hex package build.
- Run tests for each affected example. Check the browser and Ghostty through
  their existing platform CI jobs.
- Check moved platform paths, Python syntax, relative links, workflow syntax,
  package exclusions, and RC1 version agreement.
- Do not describe Windows Terminal or Mintty as physically verified. Keep
  those checks linked from [the terminal guide](../../guides/terminal-checks.md).
- Commit with Conventional Commits after quality and coverage pass.

## Completion record

Local phase 1 checks passed on Elixir 1.19.3 / OTP 28.1.1: quality; 1,041
core tests with zero failures and one excluded test; 90.3% coverage; one
acceptance workflow; two counter tests; and 11 showcase tests. Strict HTML
docs, dependency audit, unused lock checks, YAML parsing, Windows probe path
checks, and all local Markdown links passed.

The RC1 package has 149 files. It contains the new guides, source NIF build
inputs, browser assets, and consumer Mix task. It excludes maintainer `docs`,
examples, tests, repository config, and compiled native libraries. Its SHA256
is `0eb939abcc3ff113bb8973150be738ce2a22f0d2ea7c6895dc7604fe6ef8ff2b`.

Phase 1 merged through [PR #102](https://github.com/agentjido/term_ui/pull/102)
at `72e9deae9994fb7886ef1172b917472451024712`. All required PR checks passed;
the [main CI run](https://github.com/agentjido/term_ui/actions/runs/36748762208)
also passed. Later phases remain active. This record does not authorize
publication.

The full suite also passed locally on Elixir 1.20.4 / OTP 29.1 with a fresh
build directory: 1,041 tests passed and one was excluded. Platform probe
filenames are explicitly excluded from test discovery and remain direct CI
commands. This addresses Elixir 1.20 unmatched-file warnings.

Phase 2 adds four small runnable widget applications to the existing counter
consumer, with six behavior tests and a test that runs all four guide code
blocks. The guide links each lesson to its source and tests. The terminal
procedure now gives separate v1 and v2 probe paths.

Phase 3 adds five runtime specifications against those same recipe sources.
Together with the counter specification, `mix spex` runs six user workflows.
Each verifies drawn frames and normal runtime/backend-owner cleanup. The
stream scenarios verify real async failure and recovery, bounded data loss,
pause rejection, and cancellation of a pending worker. The input scenario
checks a real backend clipboard command and its result. Local acceptance
checks passed; the required PR checks remain the merge condition.

Phase 4 adds eight generated boundary checks with 300 cases each and a fixed
regression corpus. Normal core CI jobs execute them on the supported toolchain
and native-policy matrices. Failures report a seed, case number, and bounded
input; the guide gives replay commands. Generation found malformed paste
bytes that raised an error and joined-grapheme width that disagreed with cells.
Both now have fixes and small permanent regressions. The
[solution record](../solutions/2026-09-30-generated-terminal-boundaries.md)
states their causes and scope.
