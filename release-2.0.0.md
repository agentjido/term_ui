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

Record the exact candidate SHA and archive SHA256 when these checks pass.
A source checkout is separate from an installed package check.

- [ ] All 27 required checks pass at the candidate SHA.
- [ ] `mix quality` and warning-strict `mix coveralls` pass.
- [ ] All declared toolchain pairs pass, with coverage at or above 90%.
- [ ] Raw, TTY, SSH, deterministic, browser, and optional Ghostty checks pass.
- [ ] Real macOS, Linux, and Windows input, resize, and cleanup checks pass.
- [ ] Physical Option+Delete and Windows frontend profiles are verified.
- [ ] The copied Oracle Linux 8.5 release works without host build tools.
- [ ] Counter, showcase, browser, and Ghostty examples pass their checks.
- [ ] The package contains the guides, browser assets, and required source.
- [ ] The package excludes test output, credentials, and native build output.
- [ ] A clean consumer installs and uses the built package.
- [ ] Jido Console passes its runtime, editor, stream, resize, and shutdown
      checks with that package and through a real PTY.
- [ ] Migration, parity, installation, source links, and package version agree.
- [ ] Original issues and PRs have evidence-based final results, apart from
      the current release review itself.
- [ ] PR #67 has the final scope, migration summary, and verification record.

The optional Ghostty 0.5 Linux ARM64 archive contains x86_64 binaries. Its
verified source build uses the SDK-pinned Ghostty commit, Zig 0.15.2, and the
native library search path set by `examples/ghostty/run_native.sh`.
Normal backends do not need Ghostty or Zigler.

## Release decision and publication

Prepare the complete record and obtain the separate release decision. Then
mark #67 ready and satisfy the review rules before it enters `develop`.

Inspect the release workflow and its resolved implementation before use.
Run preparation in dry-run mode with an explicit `2.0.0` version and tests
enabled. Confirm the intended commits, version, changelog, and package files.
Keep publishing disabled until the reviewed `main` commit is ready.

Run required checks on the final release commit. Confirm the package version
and contents, tag that exact commit, and publish it without skipping tests.
Do not rebuild or publish a different source commit under the same version.
Verify the public package and docs, then install the published version in a
clean consumer and check Jido Console again.

## Cleanup

After publication, align `develop` with the released code. Keep `maint/1.x`.
Retire `next/v2` only after all of its work is merged and no open PR needs it.
Delete merged work branches only after checking their commits and attachments.
Preserve the original PR #33 head, other unmerged work, and all published tags.
Archive finished managed worktrees only after their needed files are saved.
The cleanup plan and its execution table are in
`notes/planning/repository-cleanup-and-v2-release.md`.
