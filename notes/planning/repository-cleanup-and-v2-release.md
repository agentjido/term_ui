# TermUI repository cleanup and v2 release plan

Prepared on 29 September 2026.

## Goal

Address all 12 open issues and all 3 open pull requests in
`agentjido/term_ui`. Repair confirmed defects on the correct version branch.
Verify the runtime in real terminals and in Jido Console. Clean up repository
documents, CI, branch rules, and release data. Prepare and ship TermUI 2.0.0
after the separate release decision required by `AGENTS.md`.

Issue #70 is part of this goal. The plan includes its web backend and optional
Ghostty sessions before the final 2.0.0 release. Moving that work to a later
release requires a scope decision. It is not a default closure reason.

An issue is addressed only when its acceptance checks pass, or when evidence
supports another clear resolution. Age and lack of recent comments are not
closure reasons. Preserve published tags and release history.

## Checked starting state

| Item | State |
| --- | --- |
| Authoritative repository | `agentjido/term_ui`; local remote `agentjido` |
| Local `origin` | `mikehostetler/term_ui`; a fork with different branch history |
| Local `upstream` | `pcharbon70/term_ui`; do not use it as the release target |
| Default branch | `develop`, commit `4c70486`; older v1 code |
| V1 release tag | `v1.0.0`, commit `560d992` |
| V1 maintenance branch | `maint/1.x`, commit `560d992`; three commits behind `main` |
| `main` | Commit `0e0e8e4`; v1 code with later dependency and CI fixes |
| V2 integration branch | `next/v2`, commit `048ae09` |
| V2 package version | Still `1.0.0-rc.1`; this must become a 2.0 version |
| Published Hex version | Stable `1.0.0` is listed on Hex |
| GitHub releases | The release list returned no entries; tags still exist |
| PR #67 | Draft from `next/v2` to `develop`; release review record |
| PR #69 | Targets `next/v2`; five failed checks in its latest run |
| PR #33 | V1 SSH contribution; targets `develop`; has merge conflicts |
| Branch protection | `develop` and `main` require old check names absent from the v2 workflow |
| Current working tree | Clean before this plan was added |

The last successful v2 branch CI run was on 1 September. It is historical
evidence. It does not establish the current release state.

PR #69 failed two Elixir 1.20 test jobs, two TTY jobs, and the dependency audit.
The run reports advisories for `igniter`, `mint`, and `usage_rules`. Read all
failure logs and run current checks before choosing dependency versions.

The v1 LogViewer now creates regexes in private functions. This suggests that
#7 is already fixed. V2 already has complete SSH session support. These are
code findings. Closure still needs verification.

## Branch rules

| Branch | Purpose and merge target |
| --- | --- |
| `maint/1.x` | Supported v1 fixes. Base all new v1 work on this branch. |
| `fix/v1-*`, `docs/v1-*`, `chore/v1-*` | Small v1 PRs into `maint/1.x`. |
| `next/v2` | V2 integration. Base all new v2 work on this branch. |
| `fix/v2-*`, `test/v2-*`, `feat/v2-*`, `docs/v2-*`, `chore/v2-*` | Small v2 PRs into `next/v2`. |
| `test/sexy-spex-acceptance-spec` | Existing head for PR #69. Update and verify it against the repaired v2 base. |
| `develop` | Keep its current release role until the separate v2 release decision. PR #67 is the only planned v2 entry. |
| `release/2.0.0` | Create after the release decision, from the verified v2 code on `develop`. Release changes only. |
| `main` | Stable release history. Merge the reviewed release branch here and tag its exact approved commit. |

Use `agentjido` explicitly for fetches, pushes, and repository checks. Do not
assume that `origin/develop` and `agentjido/develop` contain the same version.
Use separate worktrees for v1 and v2 work. Keep build output separate too.

Repair a defect on each version where it occurs. Port tests and behavior
between versions as needed. Do not copy the v2 runtime into v1. Do not merge
`next/v2` into `maint/1.x`.

Use Conventional Commits and focused, non-draft PRs for new work. Keep the
existing PR #67 draft until the release checks pass. Run `mix quality` and
`mix coveralls` before every commit. Terminal lifecycle changes also need a
real terminal check.

## Open issue work list

Branch names below are proposed. Create a fix branch only when a defect needs
a code change. Use a test or documentation branch for a verified old fix.

| Issue | Version and branch | Work and required evidence |
| --- | --- | --- |
| [#5: Windows control characters](https://github.com/agentjido/term_ui/issues/5) | Both; `fix/v1-windows-input` to `maint/1.x`, `fix/v2-windows-input` to `next/v2` | Reproduce in Windows Terminal and Command Prompt. Check Git Bash separately. Verify terminal setup, raw/TTY selection, escape output, size, and cleanup. Record supported terminals and test results. |
| [#6: Windows controls](https://github.com/agentjido/term_ui/issues/6) | Both; same Windows branches as #5 | Verify navigation, Enter, space, q, control keys, paste, and resize. Check the reported width problem with a full-width example. CI compilation alone does not prove that input works. |
| [#7: Regex attribute compile error](https://github.com/agentjido/term_ui/issues/7) | V1 report; `test/v1-log-viewer-compile` to `maint/1.x`; verify v2 LogViewer too | Confirm the existing fix in a clean Elixir 1.19 build. Verify LogViewer behavior. Record FreeBSD support from actual checks if available. Close as already fixed only with the fix commit and supported-version evidence. |
| [#9: Community examples and discussion](https://github.com/agentjido/term_ui/issues/9) | Documents; `docs/v2-community` to `next/v2`; add v1 guidance to `maint/1.x` where needed | Provide one clear route for discussion and contributed examples. Use existing project channels where possible. Record the decision on prompt examples. Close as an answered request after the guidance is available. |
| [#10: Oracle Linux release build](https://github.com/agentjido/term_ui/issues/10) | Both; `docs/v1-linux-release` to `maint/1.x`, `docs/v2-linux-release` to `next/v2` | Provide a repeatable release build for the target Linux environment. Check libc, BEAM, and native dependencies, including MDEx. Run the release on an Oracle Linux 8 compatible system. Test terminal use separately from the container build. Document any supported-platform limit. |
| [#11: Layout constraints disappear](https://github.com/agentjido/term_ui/issues/11) | V1 fix; `fix/v1-layout-constraints` to `maint/1.x`; `test/v2-layout-constraints` to `next/v2` | Run the exact nested constrained-stack example on v1. Repair tuple handling or correct the documented API. Verify the equivalent v2 fixed/fill layout, bounds, small sizes, and resize. Publish the migration example. |
| [#19: Full screen redraw](https://github.com/agentjido/term_ui/issues/19) | Both; `fix/v1-redraw-recovery` to `maint/1.x`, `fix/v2-redraw-recovery` to `next/v2` | Verify that forced redraw repairs terminal output, even when application state is unchanged. Check pane orientation changes, removed cells, and resize. An existing `force_render/1` function is not sufficient evidence. |
| [#25: Colors change after update](https://github.com/agentjido/term_ui/issues/25) | Both; `fix/v1-style-diff` to `maint/1.x`, `fix/v2-style-diff` to `next/v2` | Use a fixed sequence of matrix updates from the report. Check style-only changes, adjacent colors, ANSI reset state, and the final cell. Verify emitted terminal output as well as frame values. |
| [#35: macOS Option+Delete](https://github.com/agentjido/term_ui/issues/35) | Both; `fix/v1-option-delete` to `maint/1.x`, `fix/v2-option-delete` to `next/v2` | Capture the real key bytes. Test ESC+DEL, ESC+Backspace, split input chunks, and any observed CSI encoding. Check parser recovery and word deletion in text widgets. Verify Unicode, selections, and continued input after the key. Use a real macOS terminal. |
| [#36: Foreground/background recovery](https://github.com/agentjido/term_ui/issues/36) | Both; `fix/v1-resume-recovery` to `maint/1.x`, `fix/v2-resume-recovery` to `next/v2` | Check suspend, external terminal output, resume, and focus changes. Restore terminal modes and invalidate the last-output cache through the backend owner. Verify that a real full redraw repairs the screen without a state change. |
| [#68: SexySpex evaluation](https://github.com/agentjido/term_ui/issues/68) | V2; existing PR #69 to `next/v2` | Finish the PR checks. Verify state, frame output, cleanup, and the separate `mix spex` job. Record the adoption decision and test-only dependency use. |
| [#70: Web backend and Ghostty](https://github.com/agentjido/term_ui/issues/70) | V2; `feat/v2-web-protocol`, `feat/v2-web-backend`, `test/v2-web-browser`, and `feat/v2-ghostty-session`, all to `next/v2` | Complete the frame protocol, browser transport, renderer, browser tests, and optional terminal sessions. Use the detailed checks below. No v1 backport is planned. |

## Open pull request work list

| PR | Action |
| --- | --- |
| [#69: SexySpex](https://github.com/agentjido/term_ui/pull/69) | Repair shared CI and dependency failures on `next/v2` first. Update this PR to that base. Review its cleanup and dependency isolation. Run `mix quality`, `mix coveralls`, and `mix spex`. Merge only when all required checks pass. Then resolve #68 explicitly if it remains open. |
| [#33: SSH sessions](https://github.com/agentjido/term_ui/pull/33) | Compare every requested behavior with v2 and closed migration issue #48. Verify concurrent OTP SSH sessions, resize, shrinking rows, spaces, bottom-right output, backpressure, and disconnect cleanup. Add missing v2 behavior on `fix/v2-ssh-parity` to `next/v2`. The planned resolution is to close #33 as superseded after parity passes. Do not merge its old runtime changes into v2. If v1 users still require this new backend, use a separate `feat/v1-ssh-sessions` PR to `maint/1.x`; use a v1 minor release for a new public feature. |
| [#67: V2 release review](https://github.com/agentjido/term_ui/pull/67) | Keep it open and draft during cleanup. Update its description with the final scope, migration changes, test records, and release checks. Resolve review findings. Mark it ready after verification. Merge into `develop` only after the separate release decision. |

GitHub automatic issue closure depends on the default branch. A merge into
`maint/1.x` or `next/v2` may leave an issue open. Confirm the state and close it
with evidence when its work is complete.

## Work order

### 1. Establish reliable v1 and v2 checks

- Record fresh branch heads, tags, package versions, issue states, and CI runs.
- Compare the three v1 commits on `main` with `maint/1.x`. Run v1 checks, then
  include those fixes through a reviewed maintenance update. Keep `v1.0.0`
  unchanged.
- Use `chore/v1-maintenance-baseline` into `maint/1.x` for the v1 CI baseline.
  Add a `mix quality` alias if it is absent. Enable PR and push CI for
  `maint/1.x`. Preserve the supported v1 runtime range.
- Use `chore/v2-cleanup-baseline` into `next/v2` for current audit failures,
  warning failures, platform CI, and inconsistent branch instructions.
- Read the PR #69 failure logs in full. Capture expected warning output in
  tests where it is part of the contract. Repair unexpected warnings. Keep
  warnings-as-errors and the coverage threshold.
- Update vulnerable dependencies to verified compatible versions. Check
  transitive dependencies and each example lockfile. Run the current audit.
- Check the CI summary: it must fail when a required child job fails. PR #69
  had a successful summary despite failed child jobs.
- Add real platform checks for v2. Keep the declared v2 pairs: Elixir 1.18.4,
  1.19, and 1.20 on OTP 28; Elixir 1.20 on OTP 29.
- Align branch protection with checks that actually run. Keep review and test
  requirements. Stage the `develop` and `main` rule change with the release
  transition. Protect `maint/1.x` and `next/v2` with their own passing checks.

Exit check: clean v1 and v2 builds, passing current CI, and working merge checks
for maintenance PRs. Do not use historical green runs as the exit check.

### 2. Resolve the existing reports

- Verify #7 first. Record an existing fix where the report no longer occurs.
- Complete #35, #5, and #6. Input stalls and Windows input failures have high
  priority.
- Complete #19 and #36 together. Check actual output recovery.
- Complete #25 and #11 with reproductions from the issue bodies.
- Complete the deployment guide and target checks for #10.
- Complete the community guidance for #9.
- For each version, keep the fix, regression test, documents, and check record
  in the same focused PR where practical.

Exit check: each old report has a verified fix or an evidence-based resolution.
Do not close an unverified platform defect to make the open count zero.

### 3. Finish the pending contributions

- Finish and merge #69. Resolve #68.
- Verify SSH parity and resolve #33 as described above.
- Recheck the closed migration work in #47 and its child issues. Correct stale
  checklists where the underlying work is complete. Verify the actual API.

Exit check: #69 and #33 have final resolutions. #67 remains the release PR.

### 4. Complete issue #70

Use a transport-neutral frame protocol as the first design. Keep the server
transport optional. A normal TermUI application must not need Phoenix or
Ghostty to run.

- Define full frames, row changes, dimensions, styles, cursor state, protocol
  versions, and reconnect behavior. Confirm size order at each boundary.
- Keep the complete `TermUI.Frame` as the backend rendering contract. Apply
  wire changes against a known successful frame. Reconnect must start from a
  full frame.
- Implement a simple DOM renderer first. Normalize keyboard, mouse, paste,
  focus, and resize input to existing `TermUI.Event` values.
- Keep connection ownership, input validation, size, capabilities, and cleanup
  in the backend owner. Keep widgets pure. Bound queued output for slow clients.
- Add protocol tests and real browser tests for Unicode, wide cells, colors,
  attributes, cursor state, input, resize, disconnect, and shutdown.
- Measure full-frame and changed-row updates on a representative large frame.
  Use the results to decide if Canvas is needed. Avoid two permanent renderers.
- Check the current Ghostty APIs, dependency limits, and supported platforms
  before selecting the version.
- Add optional session support. One session owner manages the PTY and emulator.
  It converts emulator output to a TermUI frame region. It handles responses,
  input, resize, scrollback, output bounds, and shutdown.
- Test a shell and an alternate-screen application. Test two concurrent
  sessions. Confirm that no PTY process remains after shutdown.
- Test unsupported platforms and normal TermUI use without Ghostty. Report a
  clear unsupported result without breaking local, SSH, or browser backends.
- Demonstrate both ordinary frames and embedded terminal frames in the same
  browser renderer. Check every acceptance item in #70 before closure.

Exit check: #70 has a usable example, protocol tests, browser results, terminal
session results, and all acceptance items complete.

### 5. Clean up repository and release documents

Use `docs/v2-release-guide` and `chore/v2-repository-cleanup` into `next/v2`.

- Change the v2 package version, README dependency, and migration guide to the
  2.0 release series. Choose the next unused candidate version from current
  tags and Hex data. Do not publish another incompatible 1.0 candidate.
- Replace the current migration-to-1.0 guide with an accurate v1-to-v2 guide.
  Update module links, examples, package metadata, and usage rules.
- Preserve `TermUI` and the Jido Console runtime contract. Keep one state owner,
  complete frames, one backend owner, pure widgets, and commands as data.
- Mark v1 planning notes and the old 1.0 runbook as historical. Remove dead
  links and duplicate current instructions. Preserve useful design history.
- Check examples from a clean checkout. Remove local paths, build products,
  temporary files, and stale generated output from tracked files.
- Classify each old branch as active, merged, superseded, or unmerged. Preserve
  unmerged commits and release branches. Remove a branch only after its useful
  work has been preserved and its PR has a final resolution.
- Align default-branch contribution guidance, CI filters, Dependabot targets,
  labels, issue templates, and the v1 support statement with the chosen release
  topology. Future dependencies need to reach the maintained version branches.
- Check GitHub release records against tags and Hex. Repair missing records
  from verified release data. Never move or recreate a published tag.

Exit check: current documents describe v2 correctly, v1 guidance remains
available, and repository cleanup does not discard unmerged work.

### 6. Verify the release candidate

Record the commit SHA, toolchain, platform, command, and result for each check.

- Run `mix quality` and `mix coveralls` from clean checkouts. Keep v2 coverage
  at or above the current 90% threshold.
- Run `mix spex` and every declared CI pair. Test source and disabled NIF modes.
  Test automatic selection and missing-tool behavior too.
- Run dependency audit, unused-dependency checks, documentation build, package
  build, and Hex publication dry run.
- Inspect package contents. Install the built archive in a small clean consumer
  project and run it. The package must work without a repository checkout.
- Check local raw, local TTY/IEx, SSH, deterministic, and web backends.
- Check macOS, Linux, and Windows terminals. Add the target Linux release check
  from #10. Record any platform that remains unverified.
- Use real terminals for start, resize, paste, control keys, suspend/resume,
  normal exit, application error, backend error, and forced runtime exit. Check
  cursor, colors, input mode, mouse, paste, focus, and screen restoration.
- Run the counter and showcase. Run Jido Console with the candidate package.
  Verify commands, events, streaming output, resize, and shutdown.
- Run browser and Ghostty integration checks from #70.
- Review PR #67 at the final candidate SHA. Confirm that each open issue and
  PR has a final result or is the current release review itself.

Exit check: a complete release record with no known unresolved release defects.
An inaccessible terminal or consumer is an unverified check, not a pass.

### 7. Make the release decision and ship

`AGENTS.md` requires a separate decision before v2 enters `develop`. Prepare
the candidate and test record first. Obtain that decision at this stage.

- Mark #67 ready and satisfy its review requirements. Merge the approved v2
  code into `develop` after the release decision.
- Create `release/2.0.0` from the verified v2 code on `develop`.
- Use the existing release tooling for version and changelog preparation.
  Use an explicit 2.0 version. Inspect the dry run and the final package.
- Merge the reviewed release PR into `main`. Run required checks on the final
  release commit. Tag that exact commit as `v2.0.0`.
- Publish the same commit to Hex, HexDocs, and GitHub. Do not skip tests or
  publish from a dirty checkout. Confirm that publishing access is available.
- Install the published version in a clean consumer. Check the published docs
  and Jido Console once more.
- Align `develop` with the released code. Retire `next/v2` only after its work
  is merged and no active PR needs it. Keep `maint/1.x` for the v1 support line.

## Completion record

Maintain one table during execution with: issue or PR, version, branch, fix
commit, regression check, platform check, merged PR, and closure reason.

For bug fixes, closure needs a reproduction or a verified existing fix, passing
checks, and the version that contains the fix. For a duplicate or superseded
request, link the completed replacement. For an information request, link the
answer or published guide. Prepare a short evidence comment when closing an
item; the cleanup request authorizes these repository updates.

The goal is complete when all original issues and PRs have final resolutions,
needed v1 changes are on `maint/1.x`, v2 passes the release checks, TermUI 2.0.0
is published from its approved tag, and a clean consumer can use that release.
If release access or a required check is unavailable, keep the remaining work
explicit. Do not mark the release complete.

## Sources

- [Open issues](https://github.com/agentjido/term_ui/issues)
- [Open pull requests](https://github.com/agentjido/term_ui/pulls)
- [PR #69 failed CI run](https://github.com/agentjido/term_ui/actions/runs/34540585249)
- [Prior v2 CI run](https://github.com/agentjido/term_ui/actions/runs/33505073620)
- [Migration work #47](https://github.com/agentjido/term_ui/issues/47)
- [Published TermUI package](https://hex.pm/packages/term_ui)
- Repository files: `AGENTS.md`, `CONTRIBUTING.md`, `mix.exs`,
  `.github/workflows/ci.yml`, `.github/workflows/release.yml`,
  `release-1.0.0.md`, and the current backend and migration guides.

## Execution state

The v1 and v2 repairs, native Ghostty checks, Windows console checks, and candidate test repairs are merged. Physical terminal checks, the release decision, required review, and publication remain open. The original issue and PR scope is unchanged.

| Work | Branch or PR | Evidence and remaining work |
| --- | --- | --- |
| V1 maintenance baseline | [PR #71](https://github.com/agentjido/term_ui/pull/71), merged into `maint/1.x` at `4ecc460` | Includes the three v1 commits from `main`. Adds maintenance CI and `mix quality`. Replaces a fixed sleep with a completion message and uses the existing one-second async command timeout. Local quality and audit pass. Elixir 1.19.3 / OTP 28.1.1: 5,311 tests, 0 failures, 78.2% coverage. Elixir 1.15.8 / OTP 26.2.1: 5,324 tests, 0 failures, 78.1% coverage. All six remote CI jobs pass. `maint/1.x` now requires those six jobs with an up-to-date branch. |
| V2 CI and audit baseline | [PR #72](https://github.com/agentjido/term_ui/pull/72), merged into `next/v2` at `e195dfa` | Updates vulnerable development dependencies, adds platform and NIF checks, a final required-check job, and correct contribution targets. Verified setup-beam 1.24.1 supports the current Windows runner. Fixes the Windows linker `LIB` macro, CRLF diff parsing, and unused Unix test helpers. Local quality passes; 967 passed, 1 excluded, 90.2% coverage on Elixir 1.20.4 / OTP 28.5.0.5. All remote checks pass at `9cdb2fa` in run `36622829881`. `next/v2` now requires 22 current checks, including the final gate and explicit compile, matrix, quality, platform, NIF, and example jobs. |
| PR #69 and issue #68 | [PR #69](https://github.com/agentjido/term_ui/pull/69), merged into `next/v2` at `6c563db`; [resolution comment](https://github.com/agentjido/term_ui/issues/68#issuecomment-5897855739) | Adopted SexySpex for a small number of public acceptance workflows. Normal ExUnit remains the main suite. The spec requires normal runtime and backend shutdown. Discovery filters keep specs out of the normal suite. A Windows test now allows five seconds for external command startup while retaining the task-stop assertion. Local quality, 967 normal tests at 90.2% coverage, and one acceptance test pass. All remote checks pass at `7b25eac` in run `36623965332`. #68 is closed, with all seven acceptance items checked. `next/v2` now also requires the acceptance job: 23 required checks in total. |
| Issue #35 v2 input repair | [PR #73](https://github.com/agentjido/term_ui/pull/73), merged into `next/v2` at `a688700` | Restores ESC DEL and ESC BS parsing and word deletion in pure text widgets. Tests cover all chunk boundaries, continued input, Unicode, whitespace, selection, and multiline boundaries. Local quality passes; 975 passed, 1 excluded, 90.2% coverage. All remote checks pass at `9409f1e` in run `36624868117`. A macOS PTY with the real Raw backend receives both sequences, continues typing, and exits with restored terminal mode. Existing v1 tests pass (121); fix `d1104b3` is in published `v1.0.0`. The computer-use tool refused Terminal access for safety reasons. Physical Option+Delete input remains unverified; #35 remains open. |
| Issue #11 v1 regression | [PR #74](https://github.com/agentjido/term_ui/pull/74), merged into `maint/1.x` at `83fe794` | The exact nested constrained-stack example is already fixed in published `v1.0.0`, in commit `d1104b3`. Adds a regression check for all three rendered rows through public component helpers. Corrects two unstable async test fixtures while retaining their assertions. Local quality passes. Full v1 suite: 5,312 tests, 0 failures, 2 skipped, 13 excluded; 78.2% coverage. Focused renderer suite: 14 tests pass. All six remote checks pass at `f0fc233` in run `36625324989`. |
| Issue #11 v2 equivalent | [PR #75](https://github.com/agentjido/term_ui/pull/75), merged into `next/v2` at `09b0267`; [resolution comment](https://github.com/agentjido/term_ui/issues/11#issuecomment-5898296600) | Adds the nested-row migration example and checks complete frame output, small terminal sizes, clipping, and restoration after resize. Uses public Layout, Frame, and schema APIs. Local quality and 977 tests at 90.2% coverage pass. A macOS CI failure exposed a 100 ms logger-cleanup wait. The positive startup and normal-shutdown assertions now allow one second and still require logger restoration. All remote checks pass at final head `62f374c` in run `36626723748`. #11 is closed after both version checks merged. |
| Issues #19 and #36 | [PR #76](https://github.com/agentjido/term_ui/pull/76) merged into `maint/1.x` at `9632f8a`; [PR #77](https://github.com/agentjido/term_ui/pull/77) merged into `next/v2` at `ade4117`; [PR #78](https://github.com/agentjido/term_ui/pull/78) merged into `maint/1.x` at `b400c02` | Complete redraw now repairs both versions. Issue #19 is closed with evidence. V1 resume restores owned modes through its terminal owner and fixes parent-terminal access for child stty on macOS/BSD. Quality, 5,322 tests at 78.4% coverage, and all six required CI checks pass. The v2 resume branch restores modes through its backend owner and retains original native flags for shutdown. Real macOS Raw and TTY PTYs on each version pass SIGSTOP/SIGCONT, complete unchanged output, continued input, normal cleanup, and exact saved settings, including nondefault settings. Raw receives Ctrl+C/S/Q. [PR #79](https://github.com/agentjido/term_ui/pull/79) merged into `next/v2` at `b01c010`. V2 quality, 1,000 warning-strict tests at 90.3% coverage, one acceptance specification, and all 23 required CI checks pass. Issue #36 is closed with evidence. The fixes are not yet published on Hex. |
| Issue #25 color output | [PR #80](https://github.com/agentjido/term_ui/pull/80) merged into `maint/1.x` at `da1a932`; [PR #81](https://github.com/agentjido/term_ui/pull/81) merged into `next/v2` at `fb4d478`; [resolution comment](https://github.com/agentjido/term_ui/issues/25#issuecomment-5899397721) | The reported five-row matrix passes through both Raw runtimes. A v1 TTY update from `abcd` to `dbca` replaced unchanged middle cells with spaces; the repair writes separate contiguous runs. Fixed matrix permutations and style-only updates verify resulting ANSI characters and styles. V1 quality, 5,325 tests at 78.4% coverage, and all six required CI checks pass. V2 quality, 1,002 warning-strict tests at 90.3% coverage, one acceptance specification, and all 23 required CI checks pass. Real macOS PTYs pass all 26 matrix frames on Raw and TTY for both versions, with exact terminal settings restored. V2 TTY incremental output also passes the independent ANSI checks. #25 is closed after both PRs merged. The new v1 TTY repair is not yet published. |
| Issue #10 target build | [PR #82](https://github.com/agentjido/term_ui/pull/82), merged into `maint/1.x` at `ea26ce2`; [PR #84](https://github.com/agentjido/term_ui/pull/84), merged into `next/v2` at `bca8247`; Oracle Linux 8.5 x86_64 | A clean pinned builder uses OTP 28.5.0.5 with `--disable-jit`, Elixir 1.19.3, Rust 1.91.0, a root Rustler build dependency, and `MDEX_NATIVE_BUILD=1`. JIT bootstrap failed only in the tested x86_64 build under macOS ARM emulation; no native-host JIT defect is claimed. The downloaded MDExNative 0.2.9 GNU NIF requires glibc 2.29. Building it from source fixes its load on glibc 2.28. Both exact repository recipes produce copied releases with ERTS. MDEx HTML, TermUI styled Markdown, and the v2 TTY NIF pass on the pristine Oracle Linux 8.5 image without installed Mix, Elixir, Erlang, or a compiler. All four real Linux PTY checks pass Raw/TTY input, normal exit, and exact original settings. V1 archive SHA256: `9fd45ef9cebac148de8eaeeaf458ec20207825f0e08ca66170da3fe4a44f9ec7`; v2: `8792bf69dbf0c44539c600883e9436926228f630285d86dbf0ff8822bd17e09c`. V1 quality, coverage, and all six required checks pass. V2 quality, 1,003 warning-strict tests at 90.3% coverage, and one acceptance specification pass. All 23 required v2 checks pass at `560693b`. #10 is closed with the guides and target evidence. Production SSH profiles remain a separate release check. |
| Issue #9 community guidance | [PR #82](https://github.com/agentjido/term_ui/pull/82), merged into `maint/1.x` at `ea26ce2`; [PR #85](https://github.com/agentjido/term_ui/pull/85), merged into `next/v2` at `f25fc1f`; [resolution comment](https://github.com/agentjido/term_ui/issues/9#issuecomment-5900358135) | Guides use the existing Elixir Forum discussion and GitHub defect reports. They give v1/v2 branch targets, example requirements, and small optional prompt requests for each architecture. External andyl/zing examples are linked with an older-API warning. V1 quality, 5,325 tests at 78.4% coverage, and all six required checks pass. V2 quality, 1,003 warning-strict tests at 90.3% coverage, and all 23 required checks pass at `09f8d80`. #9 is closed after both guides merged. |
| PR #33 SSH parity | [PR #86](https://github.com/agentjido/term_ui/pull/86), merged into `maint/1.x` at `43cc2c2`; [PR #87](https://github.com/agentjido/term_ui/pull/87), merged into `next/v2` at `7bac815`; [resolution comment](https://github.com/agentjido/term_ui/pull/33#issuecomment-5900507817) | V1 tests its IO-device backend through real OTP SSH connections. Checks cover the final cell, removed cells, split arrow input, PTY resize, isolated buffers, and disconnect cleanup. Quality, 5,327 tests at 78.5% coverage, the minimum toolchain network tests, and all six required checks pass. Five v2 network tests also cover real SSH flow control, bounded output, the latest waiting frame, and background-only changes. Quality, 1,006 warning-strict tests at 90.4% coverage, one acceptance specification, and all 23 required checks pass at `9ae75f3`. Test cleanup stops only a live daemon on OTP 29. #33 is closed as superseded. Its original head is preserved in the local `archive/pr-33-ssh-proposal` branch and its source branch. The proposed runtime background APIs were not adopted; application views own styled background cells. |
| Issues #5 and #6 Windows console | [PR #88](https://github.com/agentjido/term_ui/pull/88), merged into `next/v2` at `5bf18a7` | Adds real ConPTY checks through Command Prompt and Git Bash, source and disabled NIF modes. Checks cover RGB cells, Unicode and wide text, space, resize, normal cleanup, raw controls, and native Ctrl+O/C/S/Q. The controller now reads UTF-8 JSON and waits for the separate backend record. A plain VM run identifies console flag changes that happen without a TermUI runtime; full mode values are compared with that baseline. A CI failure in an existing runtime test exposed a monitor started after its shutdown trigger. The monitor now starts first and keeps the exact exit-reason assertion. Local quality and 1,006 warning-strict tests at 90.4% coverage pass. All 23 required checks pass at `3c2b9e6` in run `36644034398`. Windows Raw/TTY checks pass through Command Prompt and Git Bash, including native controls. V1 verification and physical frontend profiles remain pending. Both issues stay open. |
| V1 console resize and worker cleanup | [PR #92](https://github.com/agentjido/term_ui/pull/92), merged into `maint/1.x` at `f8a3633` | Adds local size polling, stable unchanged TTY output, and normal shutdown of the private command executor, task supervisor, active tasks, timers, and input reader. Windows terminal detection reads native IO options correctly. One native acquisition and an owned control-flag NIF preserve raw controls and restore the saved flag. The package includes native source and build instructions; source links use agentjido. Windows stty calls return no POSIX terminal. Local quality, 5,329 tests, 10 doctests, 8 properties, and 78.8% coverage pass. Both real macOS Raw/TTY checks pass input, resize, cleanup, workers, and exact settings. All six real Command Prompt/Git Bash TTY/Raw/auto profiles pass, including raw arrows and native Ctrl+O/C/S/Q, exact full console modes, resize, and cleanup. All six required checks pass at `f739574` in run `36653865023`. Physical Windows Terminal and Mintty profiles remain pending. #5 and #6 stay open with new evidence comments. |
| Issue #70 browser protocol and session | [PR #89](https://github.com/agentjido/term_ui/pull/89), merged into `next/v2` at `51e0fb2` | Adds a transport-neutral backend, versioned cell and input maps, confirmed frame bases, one frame in flight plus one waiting frame, resync, limits, and isolated sessions. Eighteen focused tests cover protocol, output, input, resize, disconnect, owner exit, timeout, forced session exit, and shutdown. Local quality, 1,024 warning-strict tests at 90.5% coverage, and one acceptance specification pass. CI found the existing runtime monitor race recorded in #88. All 23 required checks pass at `cd92be5`, including the Windows console checks and monitor repair from #88. #70 stays open. |
| Issue #70 browser renderer and host | [PR #90](https://github.com/agentjido/term_ui/pull/90), merged into `next/v2` at `7d8e4d7` | Adds packaged DOM assets, a loopback Bandit/WebSock example with origin and input limits, and six real Chromium checks. Example audit and browser checks pass. Complete 200 by 100 updates have a measured 137.7 ms p95; one changed row has a 1.4 ms p95. These measurements exclude server, network, and paint. Local quality, 1,024 warning-strict tests at 90.5% coverage, docs, package content, example tests, audits, and six Chromium tests pass. The required Chromium CI job passes on Linux. A Windows result-file read hit a temporary permission error during atomic replacement; the bounded controller wait now also retries that condition. All 24 required checks pass at `b8a2dfd` in run `36645422724`. The exact head was merged by squash. `next/v2` now has 24 required checks, including Chromium. Ghostty 0.5.0 loads on macOS ARM64 and passes its audit. Pure frame-conversion tests pass; the optional session is in PR #91. |
| Issue #70 optional Ghostty session | [PR #91](https://github.com/agentjido/term_ui/pull/91), merged into `next/v2` at `a935813` | One session owns one emulator and real PTY. The parent stores complete Frames and returns input and confirmation commands. Output keeps one frame in flight and one latest waiting frame. Pure conversion covers Unicode, wide tails, styles, colors, and cursor. Missing SDK and unsupported platforms return structured errors. Local quality, 1,040 warning-strict tests at 90.3%, one specification, docs, and package checks pass. Four native tests on each supported platform cover real shell and Vim output, input, replies, paste, focus, mouse, resize, scrollback, separate state, and normal/owner/forced OS child cleanup. Two Chromium tests cover shell and Vim through the shared renderer, exact PTY resize, separate browsers, and child cleanup. Three ordinary host tests and all six ordinary browser checks pass. Native CI passes on GNU Linux x86_64, GNU Linux ARM64, and macOS ARM64. The upstream ARM64 archive contains x86_64 binaries. The verified ARM64 helper builds the exact SDK source with Zig 0.15.2; test dependencies compile first and the launcher sets the native library path. Stop handles the owner-exit race. All 27 required checks pass at `6e1b447` in run `36649711213`. #70 is closed with all ten acceptance items checked and evidence from PRs #89, #90, and #91. The changes are not yet published. |
| Jido Console source consumer | Clean copy of Console `8b7d988`, TermUI `6e1b447` | The existing explicit TermUI path option selects the current v2 code. Console keeps its approved immutable Jidoka reference. All 135 selected warning-strict console, TUI, editor, view, selection, and provider-free coding tests pass. The original Console checkout stays clean. Its Git Hooks build needed a Git repository, so the temporary source copy was initialized before compile. Console's existing lock file reports advisories in Ash and Mint; this does not change the passing TermUI dependency audit. This check uses source, not the final candidate package. The extracted 2.0.0-rc.1 archive also passes all 135 selected tests. Real macOS Raw and TTY Console checks now pass with the package. They cover Unicode, provider-free output, resize from 80 by 24 to 100 by 28, durable completed-turn data, normal exit, stopped backend and input reader, and exact saved terminal settings. Raw also checks slash completion, backspace, bracketed paste, and Ctrl+C. TTY uses line input and /cancel. No live provider is needed. |
| V1 release history | [TermUI 1.0.0](https://github.com/agentjido/term_ui/releases/tag/v1.0.0), existing tag `560d992` | Restores the missing GitHub record for the package published on 31 August 2026. All 171 files in the public Hex archive match the existing tag. The archive hash matches the public API: `79f4bd86751ce142c3ce0af2a7323840c72923f864d7ac6270e12218fdf1a9f3`. The tag is unchanged. Later maintenance fixes are not claimed as published. |
| V2 release candidate | [PR #93](https://github.com/agentjido/term_ui/pull/93), merged into `next/v2` at `063ed50` | Sets the unpublished version to 2.0.0-rc.1, corrects migration from 1.x to 2.0, updates current package and parity text, and adds a release record. The old 1.0 record remains as history. Local quality and 1,040 warning-strict tests at 90.3% pass. All 27 required CI checks pass at `0d7bcdd`. The built package has 156 files, current guides and browser assets, native source, and no native binaries. Archive SHA256 is `c89766cf5410b22202654feea1470a85c4859f6a41487eb1fae9e2fb284b8476`. The extracted package passes all 135 selected Jido Console tests. The package works in the real Raw/TTY Console consumer and a fresh Oracle Linux 8.5 consumer release. The copied release uses glibc 2.28, has no host Mix/Elixir/Erlang commands, loads native Markdown and the TTY NIF, accepts raw controls and normal quit, and restores exact flags in both Raw and TTY. The release preparation simulation selects 2.0.0 without a commit or tag. Its generated comparison base is the unpublished v2.0.0-rc.1 tag; the reviewed release changelog must use a verified published tag or exact commit and explain the breaking 2.0 changes. Hex package and docs simulation passes with a dry-run-only key; the public Hex list still has no 2.x release. Remote release dispatch is unavailable because release.yml is absent from the default branch. All 27 checks pass in the latest merged-SHA run `36651550758`; the parallel run `36651546599` exposed the blocked-window SSH test timeout. The fixture repair and explicit short-timeout test pass local quality, 13 focused SSH tests, and 1,041 warning-strict tests at 90.5%. In a temporary copy, a 120 ms delay per render makes the old fixture fail after 10.4 seconds; the new fixture passes all 100 renders in 12.5 seconds. Production timeouts remain unchanged. The fixture repair is merged in PR #94; the worker monitor repair is merged in PR #95. Physical frontend checks, issue resolutions, the release decision, and publication remain pending. |
| V2 SSH fixture timeout | [PR #94](https://github.com/agentjido/term_ui/pull/94), merged into `next/v2` at `2807625` | Allows 30 seconds for the blocked receive-window storage fixture. A separate one-second timeout test requires runtime failure and normal session cleanup. Queue capacity and latest-frame assertions remain exact. Production defaults remain unchanged. Local quality, all 13 focused SSH checks, and 1,041 warning-strict tests at 90.5% pass. The old fixture fails under controlled delay after 10.4 seconds; the new fixture passes all 100 delayed renders in 12.5 seconds. All 27 required checks pass at `c165d2c`. All 156 candidate package files match merged head `2807625`. A merged-SHA Windows run exposed a separate asynchronous worker monitor race, repaired in merged PR #95. |
| V2 async worker monitor | [PR #95](https://github.com/agentjido/term_ui/pull/95), merged into `next/v2` at `56c1d69` | The worker now acknowledges a message sent after monitor creation before the test triggers normal shutdown or forced runtime exit. Monitor and acknowledgment signals come from the same process, so the monitor is active first. Exact killed-reason assertions remain. Production code is unchanged. All 37 runtime contract tests, local quality, and 1,041 warning-strict tests at 90.6% pass. All 27 required checks pass at `2efba0e` in run `36654272959`. All 156 candidate archive files match merged code head `56c1d69`. Both merged-head runs pass: `36654920854` and `36654924669`. |
| V2 release record and migration review | [PR #96](https://github.com/agentjido/term_ui/pull/96), open into `next/v2` | Records the candidate, package, Console, Oracle Linux, Windows, browser, and Ghostty evidence. Adds final release CI triggers and separate v1/v2 dependency update targets for the approved default-branch transition. PR #67 now has the final scope and current tests. All 19 closed migration sub-issues are rechecked against current code, tests, docs, and ancestor commits; their checklists and parent #47 now state implementation results and pending release gates. No generic UI context is added. Its guide now uses the correct 2.0 version. A generated-doc link failure is repaired with a source URL. Strict docs, quality, and 1,041 tests at 90.6% pass locally. The rebuilt package also passes all 135 selected Console tests. Exact physical frontend commands are recorded. Required checks remain pending for the final updated head. |
| V2 signal-handler cleanup | [PR #83](https://github.com/agentjido/term_ui/pull/83), merged into `next/v2` at `9d59f03` | A close call could return before the supervised signal handler was removed. The backend owner now removes it synchronously before terminal cleanup. A delayed-output regression fails on the old implementation and passes after the fix. Real macOS Raw/TTY resume, continued input, and exact nondefault settings pass. Quality, 1,003 warning-strict tests at 90.3% coverage, one acceptance specification, and all 23 required CI checks pass at `f658d67`. |
| Issue #7 resolution | Published tag `v1.0.0`; [resolution comment](https://github.com/agentjido/term_ui/issues/7#issuecomment-5897486537) | Closed as fixed in 1.0.0. Commit `3b665ff` is an ancestor of the tag. The tag contains private `level_patterns/0` and `timestamp_pattern/0` functions. Clean Elixir 1.19 compilation and tests pass locally and in Linux CI. FreeBSD terminal behavior is not verified. |

Issues #5, #6, and #35 remain open. Final release branch rules, final
release checks, required review, and publication remain pending. PR #67 stays draft. No v2 code
has entered `develop`.

The release workflow has no `HEX_API_KEY` in this repository or its shared
organization secrets. Hex currently lists `pcharbon70` as the package owner.
Final publication needs a key with package publish permission. The user has
been asked to configure the key in GitHub, without sending its value in chat.
