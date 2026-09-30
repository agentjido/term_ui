# Contributing to TermUI

See [Community and examples](guides/community.md) for discussion, issue
reports, example contributions, and optional prompt examples.

Use `main` as the pull request target for v2 work. Use `maint/1.x` for v1
fixes. Base each change on its target branch. Keep changes focused and include
tests for behavior changes. Keep the two version lines separate. `develop`
is a historical v1 integration branch; new work uses the supported targets.

Before you submit a pull request, run:

```bash
mix deps.get
mix quality
mix coveralls
mix deps.unlock --check-unused
mix hex.audit
mix docs --warnings-as-errors -f html
HEX_API_KEY=dry-run mix hex.publish --dry-run --yes
```

TermUI uses the shared v5 Jido CI, review, and release workflows. Dependabot
checks Mix and GitHub Actions dependencies each week for both supported lines:
`maint/1.x` and `main`. Use Conventional Commits. Do not edit `CHANGELOG.md`
in a normal pull request. Release preparation can add reviewed version entries.
Use a `release/` source branch or a `chore(release):` PR title for that work.
The release changelog check still rejects a new Unreleased section.

Terminal lifecycle changes also need a manual check in a real terminal. Verify
normal exit, application failure, backend failure, and forced process exit.
After each case, confirm that cooked input, the cursor, style, paste mode,
focus events, mouse tracking, and the active screen are restored.

The supported runtime matrix is Elixir 1.18.4 or later on OTP 28 or later. CI
tests Elixir 1.18.4, 1.19, and 1.20 on OTP 28, and Elixir 1.20 on OTP 29.

See [Package quality](guides/package-quality.md) for the Jido standard and the
documented compatibility exceptions.

The current release checks and branch transition are in
[the 2.0 release record](https://github.com/agentjido/term_ui/blob/main/release-2.0.0.md).
Hex publication is managed separately by the maintainer. Use the exact
reviewed `main` commit for publication. Repository cleanup does not push a
release tag or run the publication workflow. The preparation workflow can
write commits and tags when its dry-run option is false.
