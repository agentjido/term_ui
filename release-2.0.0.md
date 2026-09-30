# TermUI 2.0.0 release record

The working candidate is `2.0.0-rc.1` on `next/v2`. Hex currently has no 2.0
release. This candidate is not tagged or published. Complete the checks below
before the separate release decision required by `AGENTS.md`.

## Branches

- `maint/1.x` receives v1 fixes. It includes the reconciled published fixes and
  the maintenance repairs from this cleanup.
- `next/v2` receives v2 fixes and candidate preparation.
- PR #67 remains draft during verification. It targets `develop`.
- After the release decision and required review, merge #67 into `develop`.
- Create `release/2.0.0` from that verified code. Set the final version to
  `2.0.0`, prepare the changelog, and open the release PR against `main`.
- Merge only the reviewed release. Tag its exact approved commit as `v2.0.0`.
  Publish that same commit to Hex, HexDocs, and GitHub.

Use squash merges and Conventional Commits. Do not bypass the review or CI
rules on `main` or `develop`. Keep published tags and unmerged work.

## Candidate checks

Code candidate: `56c1d69caf3f3b8264bf4e1ba968d9a360de70ae`, after PR #95.
All 27 required checks passed before its merge, at
`2efba0ec95cb9558a23a42b5582ac8ac71c8a982` in
[run 36654272959](https://github.com/agentjido/term_ui/actions/runs/36654272959).
All 27 also pass at the merged code commit in
[run 36654920854](https://github.com/agentjido/term_ui/actions/runs/36654920854).
This release-record update needs its own CI result.

- [ ] All 27 required checks pass at the final candidate SHA.
- [x] `mix quality` and warning-strict `mix coveralls` pass.
- [x] All declared toolchain pairs pass, with coverage at or above 90%.
- [x] Raw, TTY, SSH, deterministic, browser, and optional Ghostty checks pass.
- [x] Real macOS, Linux, and Windows input, resize, and cleanup checks pass
      in the tested PTY and ConPTY profiles.
- [ ] Physical Option+Delete and Windows frontend profiles are verified.
- [x] The copied Oracle Linux 8.5 release works without host build tools.
- [x] Counter, showcase, browser, and Ghostty examples pass their checks.
- [x] The package contains the guides, browser assets, and required source.
- [x] The package excludes test output, credentials, and native build output.
- [x] A clean consumer installs and uses the built package.
- [x] Jido Console passes its runtime, editor, stream, resize, and shutdown
      checks with that package and through a real PTY.
- [x] Migration, parity, installation, source links, and package version agree.
- [ ] Original issues and PRs have evidence-based final results, apart from
      the current release review itself.
- [x] PR #67 has the final scope, migration summary, and current verification
      record. Update its exact head and CI result after final changes.

The optional Ghostty 0.5 Linux ARM64 archive contains x86_64 binaries. Its
verified source build uses the SDK-pinned Ghostty commit, Zig 0.15.2, and the
native library search path set by `examples/ghostty/run_native.sh`.
Normal backends do not need Ghostty or Zigler.

### Test and package evidence

- Core checks: 1,041 passed, one excluded, 90.6% coverage. All 37 runtime
  contract tests pass. PR #95 confirms monitor registration before shutdown;
  its exact process-exit checks stay in place.
- SSH: 13 focused tests pass, including real network sessions, bounded output,
  resize, and cleanup. PR #94 gives the slow-client fixture 30 seconds. A
  separate one-second test checks output-timeout failure and cleanup.
  Production timeouts remain unchanged.
- Windows v2: real Command Prompt and Git Bash ConPTY profiles pass Raw and
  TTY input, Unicode, wide cells, native control keys, resize, and cleanup
  with the source NIF and with the NIF disabled.
- Windows v1: all six TTY, Raw, and automatic-selection profiles pass in
  [PR #92](https://github.com/agentjido/term_ui/pull/92). All six maintenance
  CI checks pass; local coverage is 78.8%. This work is on `maint/1.x`.
- Browser: six Chromium checks pass. The optional Ghostty host adds two
  browser checks and four native checks on each of GNU Linux x86_64,
  GNU Linux ARM64, and macOS ARM64. Windows and Intel macOS Ghostty are
  unsupported by the tested SDK.
- The `2.0.0-rc.1` archive built for PR #93 contains 156 files. Its SHA256 is
  `c89766cf5410b22202654feea1470a85c4859f6a41487eb1fae9e2fb284b8476`.
  All 156 files match code candidate `56c1d69`; PRs #94 and #95 change tests
  and planning records. Rebuild the final archive after document updates.
- A clean copy of Jido Console `8b7d988` passes all 135 selected warning-strict
  tests with that extracted archive. Real macOS Raw and TTY runs also pass
  Unicode input, provider-free output, resize from 80 by 24 to 100 by 28,
  durable completed-turn data, normal shutdown, and exact terminal settings.
  Raw checks completion, backspace, bracketed paste, and Ctrl+C. TTY checks
  line input and `/cancel`. The original Console checkout stays unchanged.
- A fresh consumer of the extracted archive builds on Oracle Linux 8.5
  x86_64 with glibc 2.28, OTP 28.5.0.5, Elixir 1.19.3, and Rust 1.91.0.
  Native Markdown is built from source. The copied release loads Markdown
  and the TTY NIF with no host Mix, Elixir, Erlang, or compiler. Real Raw and
  TTY PTYs pass input, normal exit, and exact saved flags. Copied release
  SHA256: `829796f3958f7f864b4f0940212364683f84413c29f8b9e24b3113b9f85634fa`.
- Local release preparation in dry-run mode selects `2.0.0` and creates no
  commit or tag. Hex package and docs dry runs pass. No 2.x package is
  published. Remote release dispatch is unavailable until the workflow
  enters the default branch through the reviewed v2 transition.

### Open checks and access

Issues [#5](https://github.com/agentjido/term_ui/issues/5),
[#6](https://github.com/agentjido/term_ui/issues/6), and
[#35](https://github.com/agentjido/term_ui/issues/35) remain open. Physical
Windows Terminal and Mintty profiles, and the physical macOS Option+Delete
key, need results. Injected key bytes and ConPTY results do not establish
those frontend settings. Keep the issues open until those results are known.
Use the exact commands and result fields in
`notes/planning/physical-terminal-checks.md` for both version branches.

The existing Jido Console lock has Ash and Mint advisories. Its selected
tests pass with the approved Jidoka reference. The TermUI audit passes.
This release work does not update the separate Console dependency contract.

The repository has no `HEX_API_KEY` in its repository or shared Actions
secrets. Hex lists `pcharbon70` as the package owner. Publication needs a key
that can publish `term_ui`. Configure it in GitHub Actions secrets; do not
put its value in issues, logs, or chat.

## Release decision and publication

Prepare the complete record and obtain the separate release decision. Then
mark #67 ready and satisfy the review rules before it enters `develop`.

`AGENTS.md` requires: "Do not merge v2 work into `develop` until the project
makes a separate release decision." Both `develop` and `main` also require
one approving review. Their current six v1 status names must change to the
27 verified v2 names during that transition. Keep the review requirement.

Inspect the release workflow and its resolved implementation before use.
Run preparation in dry-run mode with an explicit `2.0.0` version and tests
enabled. Confirm the intended commits, version, changelog, and package files.
Keep publishing disabled until the reviewed `main` commit is ready.

The shared v5 workflow resolved to
`fa16d77ff51210b52c1c283e96875eb9d5ca668c` during the candidate check.
Inspect it again before publication. Its default preparation can commit,
tag, and push. Use only dry-run preparation until the release-branch changes
are concrete and reviewed. Tag and publish the exact approved `main` commit.
CI runs on `main` and `release/**` so the final commit can be checked too.

Run required checks on the final release commit. Confirm the package version
and contents, tag that exact commit, and publish it without skipping tests.
Do not rebuild or publish a different source commit under the same version.
Verify the public package and docs, then install the published version in a
clean consumer and check Jido Console again.

## Cleanup

After publication, align `develop` with the released code. Keep `maint/1.x`.
The dependency update configuration checks Mix and GitHub Actions separately
on `maint/1.x` and `develop`. It becomes active when it enters the default
branch through the reviewed v2 transition. Before that decision, manual v2
dependency fixes still target `next/v2`.
Retire `next/v2` only after all of its work is merged and no open PR needs it.
Delete merged work branches only after checking their commits and attachments.
Preserve the original PR #33 head, other unmerged work, and all published tags.
Archive finished managed worktrees only after their needed files are saved.
The cleanup plan and its execution table are in
`notes/planning/repository-cleanup-and-v2-release.md`.

The missing [GitHub 1.0.0 release record](https://github.com/agentjido/term_ui/releases/tag/v1.0.0)
is restored. All 171 files in the published Hex package match the existing
`v1.0.0` commit `560d99269a41e98d982a3776f341d37cd4bf87ed`. The public
archive SHA256 is `79f4bd86751ce142c3ce0af2a7323840c72923f864d7ac6270e12218fdf1a9f3`.
The tag stays unchanged. Later maintenance fixes are not in that package.
