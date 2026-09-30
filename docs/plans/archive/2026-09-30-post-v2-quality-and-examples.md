---
title: Earlier quality and examples proposal
type: maintenance
date: 2026-09-30
status: superseded
---

> Historical plan. The current work is defined in [the RC1 plan](../2026-09-30-001-refactor-rc1-documentation-plan.md).

# TermUI: quality and examples after v2

Date: 30 September 2026

Baseline: `main` at `1002f3fc85dc7ed103cf55de243877e4b19c3bac`.

Status: deferred plan. First complete
[repository cleanup](2026-09-30-repository-cleanup.md), as requested on 30 September 2026.
Do not add property tests, fuzz tests, or new example tests before that cleanup
is complete. This plan does not create a tracked goal.

## Objective

Make TermUI v2 easier to use, test, and maintain. Add practical examples with
tests. Add acceptance tests, property tests, and fuzz tests at the input
boundaries. Keep the public `TermUI` API and the Jido Console runtime contract.

Use small pull requests. Find defects through the new tests, then fix each
defect with a test that shows the failure. Keep Hex publication under the
maintainer's separate control.

## Current evidence

- PR #67 is merged. `main` contains v2. The latest main CI run passed.
- There are no open pull requests. Issues #5 and #6 remain open for physical
  Windows terminal checks. Their labels state that fixes are present.
- The last full local run had 1,041 passing tests, one excluded test, and 90.6%
  coverage. The configured coverage minimum is 90%.
- CI already checks several Elixir/OTP versions, native and non-native modes,
  macOS, Windows, acceptance specifications, examples, Chromium, and Ghostty.
  Keep those checks as the starting point.
- There is one acceptance file: `test/spex/counter_spex.exs`. It tests a small
  application defined inside the test.
- There is no current StreamData dependency or property test suite. Old notes
  describe v1 property tests that are no longer in the source tree.
- The runnable examples are `iex_counter`, `showcase`, `web`, and `ghostty`.
  The example index omits the web and Ghostty examples. The counter example has
  no standalone tests.
- A recent macOS CI run failed while it waited 500 ms for normal backend
  shutdown in the resize contract test. The rerun passed. The cause needs an
  investigation; the pass does not resolve the test reliability problem.
- Some current guidance still refers to v1, old tool versions, or the v2
  release candidate. There are 464 tracked files under `notes`; much of that
  material records earlier designs.

These findings support test reliability and current documentation as the first
work. More examples are useful when they also test real user tasks.

## Branch rules

- Start each v2 branch from current `main`. Target its pull request at `main`.
- Use `maint/1.x` only for a defect that also affects v1. Make a separate fix
  and pull request there. Do not merge a v2 branch into the v1 line.
- Use `next/v2` and `develop` as historical references. They are not targets for
  this work.
- Keep each change small enough to review and test. Split a table entry into
  smaller pull requests if it changes several unrelated contracts.
- Use Conventional Commits. Run `mix quality` and `mix coveralls` before each
  commit. Also run the acceptance, example, or platform checks affected by the
  change.

## Work order

Each branch name below is proposed. The first cycle ends after steps 1–10.
Step 11 can proceed in small parts during that cycle.

| Step | Branch from `main` | Work and completion condition |
| --- | --- | --- |
| 1 | `docs/v2-current-guidance` | Correct current version and tool guidance. Index every example. Mark old v1 test notes as historical. Current instructions and links agree with the source. |
| 2 | `test/v2-lifecycle-determinism` | Investigate the macOS shutdown failure. Use explicit acknowledgements and process monitors where needed. The affected tests pass across recorded seeds and native modes, with useful failure output. |
| 3 | `test/v2-acceptance-flows` | Add shared test helpers, tests for the actual counter example, and eight core user scenarios. A contributor can run the suite without a terminal or external service. |
| 4 | `test/v2-property-contracts` | Add a test-only generator library. Test parser, frame, protocol, and widget contracts in bounded groups. A failing seed can be replayed and reduced to a small case. |
| 5 | `feat/examples-form-workflow` | Add a form example with validation, focus, paste, confirmation, resize, and cancel tests. |
| 6 | `feat/examples-data-table` | Add a table example with stable row identity, sort, filter, selection, refresh, and empty/error states. Test the actual application. |
| 7 | `feat/examples-stream-monitor` | Add a stream example with bounded log retention, pause/resume, filtering, async batches, and clean shutdown. Test overload and cancellation. |
| 8 | `test/v2-fuzz-boundaries` | Add malformed-input tests and a stored regression corpus. Add a separate runtime model test branch if that work is too large for this pull request. |
| 9 | `ci/v2-quality-profiles` | Add longer generated-test runs, failure artifacts, and test profiles. Measure run time. Keep fast pull request checks and the existing platform checks. |
| 10 | `test/v2-package-consumer` | Turn the package and Jido Console checks into repeatable repository tests. Test a fresh package in a separate consumer build. |
| 11 | `chore/v2-history-cleanup` | Add an index for historical notes. Check remaining branches for unique work. Archive or remove only material with a clear replacement or saved recovery path. |

Add each new example to CI in the same pull request as the example. Add short
property checks to CI when the properties are added. Step 9 extends those
checks; it is not the first point at which they run.

## Test reliability and acceptance

First inspect the known shutdown failure and similar fixtures. Distinguish
application state updates, frame output, backend cleanup, and process exit.
`Runtime.sync` can confirm application update order. It does not prove that a
frame was drawn or that the backend stopped.

Use actual messages and monitors to wait for completion. Keep bounded timeouts
with failure output that identifies the pending operation. Measure expensive
cases before setting their deadlines. Do not add sleeps or increase every test
timeout to hide the failure.

Build small helpers under `test/support` around
`TermUI.Test.DeterministicBackend`. Helpers should send events, wait for a frame
that meets a condition, inspect command effects, and confirm cleanup. Avoid a
new public test API until these helpers show a stable need.

The first acceptance scenarios should cover:

1. Start an application, draw its initial frame, and quit normally.
2. Enter Unicode text and bracketed paste, then submit or cancel.
3. Move focus with the keyboard and activate the intended control.
4. Select a table row, then filter or reorder data without changing its identity.
5. Resize from a large view to a compact view and back.
6. Complete, fail, and cancel an async command without accepting stale results.
7. Handle clipboard and log commands under the selected backend capabilities.
8. Report a backend failure and release owned resources as the runtime contract
   requires.

Core scenarios can use small shared fixture applications. Example tests must
use the example application itself. Check the visible result, state change,
effect, and cleanup that matter to each task. Do not require every intermediate
state to produce a frame; the runtime can combine draw requests.

## Property and fuzz tests

An acceptance test checks a specific user task. A property test checks a rule
across many generated inputs. A fuzz test sends malformed or unusual input to
a defined boundary.

Use [StreamData](https://stream-data.hexdocs.pm/ExUnitProperties.html) as a
test-only dependency. It supports generated cases, shrinking, and seed replay.
Check it on the minimum supported Elixir version before adoption. Start with
100 cases per property, small frames, event sequences of up to 50 events, and
typical byte inputs of up to 4 KiB. Use separate fixed cases for large limits.
Adjust these starting values from measured run time.

| Boundary | Rules to test |
| --- | --- |
| Escape parser | Valid sequences give the same semantic result across supported byte splits. Compare reconstructed text and key/mouse actions. Partial UTF-8 and escape sequences retain the correct remainder. Invalid bytes follow the documented recovery rule. Account for Escape-key ambiguity and normalize event timestamps. |
| Input buffer | Ordinary overflow follows its size and retention rules. Paste-aware buffering follows its separate paste limit. Do not assume that the ordinary 1 KiB limit applies inside a paste. |
| Frame and display width | Cells and cursor stay within the frame. Wide characters and placeholders remain valid through clipping, overlay, resize, and diff. Include combining characters, CJK text, and emoji. |
| Web protocol | Valid payloads give typed events. Invalid shapes, UTF-8, sizes, versions, modifiers, and coordinates are rejected at the documented boundary. Test JSON decoding separately from the core protocol map. |
| Pure widgets | Editing keeps the cursor and selection in range. Tables preserve explicit row identity. Retained logs stay within limits. Invalid values are rejected where the public contract requires it. |
| Runtime model | Generated valid messages preserve state order and match a small independent model. Test async completion, cancellation, resize, and shutdown. Owned processes stop, and backend shutdown occurs once. |

Build the expected result from a simple independent model or fixed known
fixtures. A test that only checks for no exception is insufficient for valid
input. The current ANSI screen helper is an ASCII fixture tool; do not use it
as evidence for Unicode display correctness.

Store minimized failure inputs in the repository. Mutate those inputs for
longer runs. Print the seed, input, backend, and tool versions on failure. Keep
memory, event count, and execution time bounded. Send arbitrary terminal bytes
to the parser test boundary, rather than to a person's active terminal.

This first cycle uses generated and mutated inputs. Native coverage-guided
fuzzing is later work if the initial tests show a need.

## Practical examples

Each example should have a standalone Mix project, local fixtures, a clear run
command, expected controls, and tests. The default path must work without
credentials or a network service. Keep widget state in the application and
effects in command data.

- **Form workflow:** use `FormBuilder`, text input, and selection controls.
  Show validation errors, keyboard focus, Unicode paste, confirmation, and
  cancellation at compact terminal sizes.
- **Data table:** use bundled data. Show sort/filter, stable row selection,
  bounded async refresh, loading, empty results, and a recoverable error.
- **Stream monitor:** use a local producer. Show a bounded `LogViewer`, a
  Markdown detail view, pause/resume, batch updates, and cancellation.

Document backend capabilities for each example. Raw input, TTY line input,
SSH, and web input have different controls. Share application code where the
contracts permit it; specify supported controls for each adapter.

After these examples are tested, consider a workbench with `SplitPane`, fixture
files, Markdown, and diff views. Also consider an SSH example with loopback
sessions, resize, and disconnect tests. These are follow-up options, rather
than conditions for finishing the first cycle.

## CI, package checks, and cleanup

Keep short tests on pull requests. Run longer generated cases on a manual or
scheduled GitHub Actions job. Use both saved seeds and fresh seeds. Upload the
seed and reduced input on failure. Longer tests should have explicit resource
and time limits.

Keep the existing native, non-native, browser, macOS, and Windows checks. Add
new jobs to the required summary and branch settings only after they work
reliably. Do not remove protection or weaken a check to obtain a pass.

Add a testing guide with commands for unit, acceptance, property, fuzz,
terminal, browser, and consumer tests. Label new commands as proposed until
they exist. Make CI reject an example entry that has no meaningful tests.

Make the earlier release evidence repeatable: build the package locally, unpack
it, and run a pinned Jido Console consumer contract suite in a fresh build.
Use fixtures that need no provider credentials. Keep the Oracle Linux source
build check reproducible if it remains a supported package target. These checks
must not publish a package or create a release tag.

Use coverage to find missing failure paths. Give attention to SSH, raw backend
cleanup, stream limits, optional terminal adapters, and log ownership. Keep the
90% minimum. Do not add tests for declarations or duplicate implementation
logic just to raise the percentage.

For old notes, first add an index that separates current guidance from design
history. Mark obsolete instructions at their source. Move files only after
checking links. For old branches, compare unique commits and preserve useful
work before deletion. Keep the clean `maint/1.x` branch and needed local native
builds. Do not delete tags as part of this work.

## Validation and completion

The first cycle is complete when:

- Current instructions, example lists, and testing commands agree with v2.
- The known test failure has a documented cause and fix, or a bounded wait
  supported by measured evidence. A rerun alone does not satisfy this condition.
- Eight core acceptance scenarios and the actual counter example run in CI.
- The three new examples compile, have meaningful tests, and run from a clean
  checkout with documented commands.
- Property and fuzz failures can be replayed. Saved regression inputs run in CI.
- Short and extended test profiles have measured costs and useful failure output.
- A fresh package passes the pinned consumer contract checks.
- `mix quality`, `mix coveralls`, and all required checks pass for each change.
- Coverage stays at or above 90%. Public API and runtime ownership remain intact.

For terminal lifecycle changes, also make a real macOS terminal check. Keep
Windows ConPTY checks in CI. Record the remaining physical Windows checks on
issues #5 and #6; they do not block this cycle. A macOS result does not prove a
physical Windows terminal result.

Start with steps 1 and 2, then steps 3 and 4. Add the form example first. Review
the helper API and CI cost after that example, before adding the table and
stream examples. This gives early evidence before the larger test suite grows.
