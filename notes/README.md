# Maintenance records

Current public guidance is in [guides](../guides). This folder holds active
plans and completed release evidence. It is excluded from the Hex package.

## Current plans

- [Repository cleanup](planning/repository-cleanup.md): folder and package
  cleanup before new test suites or examples.
- [Later quality and examples](planning/post-v2-quality-and-examples.md): the
  proposed next cycle, deferred until repository cleanup is complete.

## Completed source release

- [2.0.0 source release](releases/2.0.0.md)
- [V2 migration checks](releases/v2-migration-checks.md)
- [GitHub branch cleanup](releases/github-cleanup-2026-09-30.md)

These records describe results at the recorded commits. They are not
instructions to publish the current tree.

Old v1 feature plans, research, reviews, and summaries remain in Git history
at `1002f3fc85dc7ed103cf55de243877e4b19c3bac`. Use `git show <commit>:<path>`
to read one. A local copy was also saved before cleanup. Keep that archive
outside the package.
