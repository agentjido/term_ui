# TermUI 2.0.0 source release record

On 30 September 2026, the maintainer approved merging PR #67 into `main`
and keeping a separate clean v1 branch. The maintainer will handle Hex
publication separately. This decision replaces the earlier route through
`develop` and the requirement for publication access during repository cleanup.

## Branches and publication

- PR #67 targets `main`. Its final source uses version `2.0.0`.
- `maint/1.x` stays at `f8a363301830ab0bf5ed21088bd0b85680597874` and keeps
  the v1 runtime, fixes, and six required v1 CI checks.
- `main` will receive the v2 runtime and its 27 required checks.
- `develop` is a historical v1 integration branch. New work targets the two
  supported version branches.
- Dependabot sends v1 changes to `maint/1.x` and v2 changes to `main`.
- Keep the required approving review and conversation resolution on `main`.
- Do not publish to Hex, push a release tag, or run a publication workflow
  during this cleanup. The maintainer owns the separate publication step.

The preparation branch keeps the tested v2 source and joins the existing
`main` history. The three later v1 changes on `main` were already reconciled
on `maint/1.x`; their v2 replacements are in the tested runtime. Old v1
runtime files are not copied into v2. PR #67 can then use a normal squash
merge into `main` without the old modify/delete conflicts. Published tags
and the v1 branch stay unchanged.

## Verified source baseline

The tested source baseline is `0b1e38245711069dd576393049d3922ff1dd97f9`,
after PR #97. Both merged-head CI runs, `36712303944` and `36712295717`, pass
all 27 required checks. Local quality, 1,041 core tests at 90.5% coverage,
all 11 showcase tests, strict docs, package checks, real macOS and Linux
PTYs, Windows ConPTY, SSH sessions, Chromium, and native Ghostty checks pass.

The baseline archive has 156 files and SHA256
`cb318609993b4040b9f435416cd76f131e77e1375010fb15fc23f2bee4d6fa49`.
The fresh extracted package passes the Raw showcase PTY check. The earlier
package passes 135 selected Jido Console tests and real Raw/TTY Console
checks. Core runtime, native, and build files are identical between those
packages. Final release metadata needs a rebuilt package and its own checks.

The copied Oracle Linux 8.5 release runs on glibc 2.28 without host build
tools. Native Markdown, the TTY NIF, Raw and TTY input, and cleanup pass.
Optional Ghostty checks pass on GNU Linux x86_64, GNU Linux ARM64, and macOS
ARM64. Windows and Intel macOS Ghostty are unsupported by the tested SDK.
The Linux ARM64 SDK needs the documented pinned source build.

## Physical terminal results

Issue #35 is closed. The maintainer repeated the physical macOS Raw Inputs
page test and reported success. The application returned to the shell, and
the saved terminal settings compare equal. The terminal app name and version
were not supplied. No separate physical v1 profile pass is claimed.

Issues #5 and #6 remain open for physical Windows Terminal and Mintty
checks. Their v1 and v2 repairs are merged, and Windows Command Prompt and
Git Bash ConPTY checks pass. The maintainer has accepted the missing physical
Windows checks as follow-up work. They do not block this source release.

## Final merge and cleanup

1. Run `mix quality`, warning-strict `mix coveralls`, docs, package, showcase,
   and consumer checks on the final source.
2. Run all 27 required CI checks on the exact final PR #67 head.
3. Obtain the required approving GitHub review and resolve any findings.
4. Squash merge PR #67 into `main` at its exact tested head.
5. Make `main` the default branch after the merge.
6. Remove only exact closed-PR branch heads after a fresh reference check and
   a verified local Git backup. Keep active worktrees, unmatched work, v1
   maintenance, release history, and all published tags.
7. Leave package publication and release tags to the maintainer.

The full evidence and execution record are in
`notes/planning/repository-cleanup-and-v2-release.md`.
