# Maintainer documents

Use [guides](../guides/README.md) for current user instructions. Use this folder
for plans, design evidence, release checks, and build recipes. `docs` is the
canonical location for this material and replaces `notes`. It is excluded from
the Hex package. ExDoc writes generated output to `doc`, with no trailing `s`.

| Folder | Content |
| --- | --- |
| [plans](plans) | Dated work plans with scope, branch, checks, and completion conditions |
| [solutions](solutions/README.md) | Verified problems, their causes, fixes, and prevention checks |
| [releases](releases) | Evidence tied to a commit; a record does not publish a release |
| [recipes](recipes/linux-release/README.md) | Optional consumer build inputs |

For new plans, use `YYYY-MM-DD-NNN-type-topic-plan.md`. Include a short YAML
header with `title`, `type`, `date`, and `status`, then state the intended result,
scope, work order, checks, and open questions. This follows the Compound
Engineering document layout used in the Jido repositories. Record a tested
solution under `solutions`; link it from the plan rather than copy its evidence.

## Current work

- [Completed RC1 documentation and test work](plans/2026-09-30-001-refactor-rc1-documentation-plan.md)
- [Later quality and examples](plans/archive/2026-09-30-post-v2-quality-and-examples.md), retained
  as an earlier proposal; the RC1 plan controls the current work.
- [Completed repository cleanup](plans/archive/2026-09-30-repository-cleanup.md)

## Source transition evidence

- [RC1 readiness](releases/2026-09-30-2.0.0-rc.1-readiness.md)

- [V2 source transition](releases/2026-09-30-v2-source-transition.md)
- [Migration checks](releases/v2-migration-checks.md)
- [GitHub cleanup](releases/github-cleanup-2026-09-30.md)

These records describe the source transition before RC1. The current version
is `2.0.0-rc.1`; no final 2.0 release has been published by this work. Older
feature plans and research remain in Git history at
`1002f3fc85dc7ed103cf55de243877e4b19c3bac`. A local backup was saved before
folder changes. Keep backups outside the package.
