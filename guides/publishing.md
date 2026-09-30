# Publish TermUI

TermUI uses the shared Jido v5 publisher from
[`agentjido/github-actions`](https://github.com/agentjido/github-actions).
Publication is a manual maintainer action. Version changes go through a pull
request to `main`; the publisher uses an existing annotated release tag.
V1 publication uses the separate `maint/1.x` line.

## Local Hex login

From a terminal with the supported Elixir/OTP pair, run:

```sh
mix hex.user auth
mix hex.user whoami
```

Hex 2.5.1 uses browser device authorization. Follow the printed URL and code,
then return to the terminal. Confirm the correct account with `whoami`.
For this release, `mikehostetler` has full ownership of the public `term_ui`
package. Check current ownership with `mix hex.owner list term_ui`.

See the [Hex user task](https://hex.hexdocs.pm/Mix.Tasks.Hex.User.html).
Local login does not provide a credential to GitHub Actions.

## GitHub publishing key

The shared workflow needs an Actions secret named `HEX_API_KEY`. Use the same
organization secret as other Jido packages if its Hex account can publish
`term_ui`. An organization administrator must allow this repository to use
that secret. Otherwise, create a repository secret.

To create a separate key, sign in to the owning account and open the
[Hex keys page](https://hex.pm/dashboard/keys). Name the key
`term-ui-release`, choose an expiry, and select the package permission for
`term_ui`. This permits package and documentation publication for that package.
Hex shows the value once. Add it with the GitHub CLI's interactive prompt:

```sh
gh secret set HEX_API_KEY --repo agentjido/term_ui
```

Or use the repository's
[Actions secret settings](https://github.com/agentjido/term_ui/settings/secrets/actions).
Enter the value there rather than in source files or chat.

Check the available secret names without reading their values:

```sh
gh secret list --repo agentjido/term_ui
gh api repos/agentjido/term_ui/actions/organization-secrets --jq '.secrets[].name'
```

See [Hex publishing from CI](https://hex.pm/docs/publish#publishing-from-ci).
The GitHub organization name does not change this package into a private Hex
organization package. Publication remains in the public `hexpm` repository.

## Prepare the source and tag

Review the version in `mix.exs`, the changelog, package contents, and all required
CI results. Make version and changelog changes through a release pull request.
After that pull request merges, use its tested `main` source to create the
annotated tag. For example, when the reviewed version is `2.0.0`:

```sh
git fetch agentjido main --tags
git switch main
git merge --ff-only agentjido/main
git tag -a v2.0.0 -m "Release v2.0.0"
git push agentjido refs/tags/v2.0.0
```

Use a new tag for a new version. Tag push does not publish the package.
The manual publisher requires the tag to exist, to be annotated, to match the
package version, and to point to a commit reachable from `main`.

## Validate, then publish

The existing tag is required for both runs. First run full validation:

```sh
gh workflow run release.yml --repo agentjido/term_ui --ref main \
  -f tag_name=v2.0.0 -F dry_run=true
```

Read the run result and package output in Actions. This mode does not upload
to Hex or create a GitHub release. To also check the Hex publish command and
documentation package, run the Hex dry run:

```sh
gh workflow run release.yml --repo agentjido/term_ui --ref main \
  -f tag_name=v2.0.0 -F dry_run=false -F hex_dry_run=true
```

This runs `mix hex.publish --dry-run --yes` and does not upload or create a
GitHub release. When the results are accepted, start the publication run:

```sh
gh workflow run release.yml --repo agentjido/term_ui --ref main \
  -f tag_name=v2.0.0 -F dry_run=false -F hex_dry_run=false
```

The caller selects OTP 29 / Elixir 1.20. Its preflight runs source-NIF quality,
coverage, acceptance, strict docs, unused dependency checks, the dependency
audit, and a local package build. The shared workflow handles Hex upload and
GitHub release creation.

The checked publisher supports recovery for the same existing tag: it checks
the Hex and GitHub release state before writing. If a step fails after upload,
read the error and use the same publish operation. Do not create another tag
or prepare a new version just to retry that publication.

## Jido integration checklist

Checked against the [Jido integration guide](https://github.com/agentjido/github-actions/blob/main/INTEGRATION_GUIDE.md)
on 30 September 2026:

- [x] Three shared callers: CI, release, and review, pinned to the v5.2.6 commit.
- [x] CI has read permissions and receives no secrets. Review is advisory.
- [x] Strict quality checks and package checks pass. No retired workflow inputs remain.
- [x] `git_ops` has the repository URL and `v` tag prefix.
- [x] Local Hex publish dry run passes with a placeholder key.
- [x] Give Actions access to `HEX_API_KEY`.
- [ ] Run the remote release and Hex dry runs after a reviewed v2 tag exists.

TermUI uses its supported OTP 28/29 matrix. OTP 27 does not meet the raw
terminal contract; see [package quality](package-quality.md). Source and web
tests remain jobs in the CI caller. Version preparation uses a PR. The release
caller selects only the shared publish operation, with checked tag validation
enabled by `staged_prepare: true`. It does not use automated prepare staging.

## Setup record

On 30 September 2026, Hex listed `mikehostetler` as a full owner. The local CLI
confirmed that account and listed `term_ui` among its packages.

The repository now has an Actions secret named `HEX_API_KEY`. Its Hex key is
`term-ui-github-actions-2026-09-30`, owned by `mikehostetler`, with permission
`package:hexpm/term_ui`. It expires on 30 September 2027. A read-only Hex
account request verified the new key before the secret was stored in GitHub.
Rotate the key before expiry, then replace the same Actions secret.

No release tag was created and no package was published during this setup.
