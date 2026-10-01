# reusable-ci-publish

Source: [`.github/workflows/reusable-ci-publish.yml`](../../.github/workflows/reusable-ci-publish.yml)

Reusable **Changesets** pipeline for library repos. Two jobs:

1. **version** — open a Version Packages pull request, or mark the branch ready to publish once prerelease state matches that branch.
2. **npm** — only on `main` or `develop`, and only when versions are already in git. Runs `prerelease_publish_command` on `develop` and `publish_command` on `main`. The npm dist-tag is `beta` on `develop` and `latest` on `main`.

Publish readiness follows `.changeset/pre.json`, not the root `package.json` version. A private workspace root with no `version` field can still publish its packages. On `develop`, prerelease mode must be active and public versions must look like `2.3.3-beta.1`. Changesets starts the first prerelease at `.0`; this workflow moves that initial version to `.1` in package metadata, changelogs, and lockfiles before opening the review pull request. On `main`, `pre.json` must be gone, and every public package version must be a stable `X.Y.Z`.

The workflow enters Changesets prerelease mode when the first release changeset reaches `develop`. When that line reaches `main` with no changeset files left, it runs `changeset pre exit`, applies the stable versions, and opens the Version Packages pull request itself. `changesets/action` only runs the version command when changeset files are present, so the exit step cannot rely on it.

Runs on one release at a time per branch. Does not create git tags or GitHub Releases. Does not auto-deploy. Does not invent versions from conventional commits. The calling repo must already use Changesets (`.changeset` and `version_command`).

## Who calls it

Library repos (for example web-toolkit): npm on. App repos that only need a git tag and GitHub Release call [reusable-ci-tag-release](reusable-ci-tag-release.md).

## Inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `node_version` | `22` | Node.js |
| `working_directory` | `.` | Install / Changesets cwd |
| `npm_scope` | empty | `setup-node` scope |
| `version_command` | `npm run version-packages` | Changesets version |
| `publish_to_npm` | `true` | Run the npm job |
| `publish_command` | `npm run release` | Stable publish command |
| `prerelease_publish_command` | `npm run release:beta` | Prerelease publish command |
| `manage_prerelease_mode` | `true` | Automatically enter/exit Changesets prerelease mode |
| `stable_branch` | `main` | Stable release branch |
| `prerelease_branch` | `develop` | Prerelease branch |
| `prerelease_tag` | `beta` | Changesets prerelease identifier |
| `version_file` | `package.json` | Path relative to `working_directory`. Recorded when it has a version; not used to decide publish. |
| `changeset_title` / `changeset_commit` | `chore: version packages` | Version PR |
| `use_gh_env` | `false` | Bind jobs to a GitHub Environment |
| `gh_env` | empty | Environment name (required when `use_gh_env` is true) |

## Secrets

| Secret | Required |
|--------|----------|
| `GH_TOKEN` | Always. It creates and updates `changeset-release/develop` or `changeset-release/main` and opens the Version Packages pull request. `secrets.GITHUB_TOKEN` does not start workflows on a pull request it creates, so pass a GitHub App token or PAT with `contents: write` and `pull-requests: write` when required checks must run. |
| `NPM_TOKEN` | When `publish_to_npm` is true |

## How the client consumes it

`.github/workflows/release.yml` in the package repo:

```yaml
name: Release

on:
  push:
    branches: [main, develop]

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false

permissions:
  contents: write
  pull-requests: write

jobs:
  publish:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-ci-publish.yml@main
    with:
      templates_repository: YOUR_ORG/deploy-platform
      node_version: '22'
      working_directory: '.'
      npm_scope: '@web-toolkit'
      version_command: 'npm run version-packages'
      publish_to_npm: true
      publish_command: 'npm run release'
      prerelease_publish_command: 'npm run release:beta'
      stable_branch: main
      prerelease_branch: develop
      prerelease_tag: beta
      # use_gh_env: true
      # gh_env: prod
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
      GH_TOKEN: ${{ secrets.RELEASE_TOKEN }}
      TEMPLATES_TOKEN: ${{ secrets.TEMPLATES_TOKEN }}
```

`templates_repository` is required. `TEMPLATES_TOKEN` needs read access to that repository. `GH_TOKEN` stays the token that pushes to the consumer repository.

`RELEASE_TOKEN` is a GitHub App token or a fine-grained PAT with `contents: write` and `pull-requests: write`. Do not pass `secrets.GITHUB_TOKEN`. A pull request opened with that token does not start the repository's pull request checks.

## Release flow

1. A feature pull request includes a conventional commit title and a Changeset, then merges into `develop`.
2. The workflow sees the pending changeset, runs `changeset pre enter beta`, and opens one rolling Version Packages pull request. The first beta in a line is `2.3.3-beta.1`, not `beta.0`.
3. Merging that Version Packages pull request publishes the committed version with the npm `beta` dist-tag.
4. Later feature changes update the same Version Packages pull request until it is merged.
5. When `develop` reaches `main`, the workflow runs `changeset pre exit` and opens a stable Version Packages pull request, such as `2.3.3`.
6. Merging the stable Version Packages pull request publishes with the npm `latest` dist-tag.

The version commit does not contain `[skip ci]`. Merging it is the publication trigger, and the publish job does not push another commit. A commit whose versions are already on npm is not published again.
