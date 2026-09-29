# reusable-ci-publish

Source: [`.github/workflows/reusable-ci-publish.yml`](../../.github/workflows/reusable-ci-publish.yml)

Reusable **Changesets** pipeline for library repos. Two jobs:

1. **version** — open a Version Packages pull request, or mark the branch ready to publish once prerelease state matches that branch.
2. **npm** — only on `main` or `stage`, and only when versions are already in git. Runs `prerelease_publish_command` on `stage` and `publish_command` on `main`.

Publish readiness follows `.changeset/pre.json`, not the root `package.json` version. A private workspace root with no `version` field can still publish its packages. On `stage`, prerelease mode must be active. On `main`, `pre.json` must be gone, and every public package version must be a stable `X.Y.Z`.

The workflow enters Changesets prerelease mode when the first release changeset reaches `stage`. When that line reaches `main` with no changeset files left, it runs `changeset pre exit`, applies the stable versions, and opens the Version Packages pull request itself. `changesets/action` only runs the version command when changeset files are present, so the exit step cannot rely on it.

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
| `prerelease_branch` | `stage` | Prerelease branch |
| `prerelease_tag` | `beta` | Changesets prerelease identifier |
| `version_file` | `package.json` | Path relative to `working_directory`. Recorded when it has a version; not used to decide publish. |
| `changeset_title` / `changeset_commit` | `chore: version packages` | Version PR |
| `use_gh_env` | `false` | Bind jobs to a GitHub Environment |
| `gh_env` | empty | Environment name (required when `use_gh_env` is true) |

## Secrets

| Secret | Required |
|--------|----------|
| `GH_TOKEN` | Always. `secrets.GITHUB_TOKEN` does not start workflows on the Version Packages pull request it opens. Pass a GitHub App token or PAT with `contents: write` and `pull-requests: write` when that pull request must run checks. |
| `NPM_TOKEN` | When `publish_to_npm` is true |

## How the client consumes it

`.github/workflows/release.yml` in the package repo:

```yaml
name: Release

on:
  push:
    branches: [main, stage]

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
      node_version: '22'
      working_directory: '.'
      npm_scope: '@web-toolkit'
      version_command: 'npm run version-packages'
      publish_to_npm: true
      publish_command: 'npm run release'
      prerelease_publish_command: 'npm run release:beta'
      stable_branch: main
      prerelease_branch: stage
      prerelease_tag: beta
      # use_gh_env: true
      # gh_env: prod
    secrets:
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
      GH_TOKEN: ${{ secrets.RELEASE_TOKEN }}
```

`RELEASE_TOKEN` is a GitHub App token or a fine-grained PAT with `contents: write` and `pull-requests: write`. Do not pass `secrets.GITHUB_TOKEN`. A pull request opened with that token does not start the repository's pull request checks.

## Release flow

1. A feature pull request includes a normal Changesets markdown file and merges into `stage`.
2. The workflow sees the pending changeset, runs `changeset pre enter beta`, and opens a Version Packages pull request containing `.changeset/pre.json` and a version such as `2.3.3-beta.0`.
3. Merging that Version Packages pull request publishes the committed version with the npm `beta` dist-tag.
4. Later feature changes repeat the Version Packages flow and increment the prerelease number.
5. When `stage` reaches `main`, the workflow runs `changeset pre exit` and opens a stable Version Packages pull request, such as `2.3.3`.
6. Merging the stable Version Packages pull request publishes with npm’s default `latest` dist-tag.
