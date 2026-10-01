# reusable-ci-tag-release

Source: [`.github/workflows/reusable-ci-tag-release.yml`](../../.github/workflows/reusable-ci-tag-release.yml)

Reusable **git tag and GitHub Release** pipeline for app repos. It does not use Changesets and it does not publish to npm. Library repos keep using [reusable-ci-publish](reusable-ci-publish.md).

Tags are bare semver (`2.3.3`, `2.3.3-beta.1`) so [resolve-git-ref](../../.github/actions/resolve-git-ref/action.yml) can select them. Resolution only considers tags contained in the target branch. `develop` uses the latest `X.Y.Z-(alpha|beta|rc).N` tag on that branch, and falls back to the latest stable tag on that branch when no prerelease tag is there. `main` and prod use the latest stable `X.Y.Z` tag on that branch.

## Choosing the version

Leave `version` empty to calculate it from merged conventional commits:

| Change on `develop`, current stable `2.3.2` | Tag |
|---------------------------------------------|-----|
| `fix:` | `2.3.3-beta.1`, then `2.3.3-beta.2` |
| `feat:` | `2.4.0-beta.1` |
| `feat!:` or `BREAKING CHANGE:` | `3.0.0-beta.1` |
| `docs:`, `chore:`, or `ci:` only | No release |

Merging `develop` into `main` promotes the beta line: `2.3.3-beta.N` becomes `2.3.3`. A hotfix merged to `main` bumps the stable version, then the workflow opens a pull request back into `develop`.

The release commit updates `package.json` and `CHANGELOG.md`, is tagged once, and includes `[skip ci]`. The tag has no `v` prefix. If that tag already points at another commit, the job fails instead of moving it. `docs:`, `chore:`, and `ci:` commits do not create a release.

Pass `version` only for an explicit override. `develop` still accepts only a beta tag, and `main` still accepts only a stable tag.

## Inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `version` | empty | Explicit version to tag (`v` prefix optional). Empty computes from `version_file` |
| `version_file` | `package.json` | JSON file whose `version` is the release base when `version` is empty |
| `stable_branch` | `main` | Branch that tags `X.Y.Z` |
| `prerelease_branch` | `develop` | Branch that tags `X.Y.Z-<tag>.N` |
| `prerelease_tag` | `beta` | `alpha`, `beta`, or `rc` |
| `use_gh_env` | `false` | Bind the job to a GitHub Environment |
| `gh_env` | empty | Environment name when `use_gh_env` is true |

## Secrets

| Secret | Required |
|--------|----------|
| `GH_TOKEN` | Always (pass `secrets.GITHUB_TOKEN`) |

## How the client consumes it

`.github/workflows/release.yml` in the app repo:

```yaml
name: Release

on:
  push:
    branches: [main, develop]

concurrency:
  group: tag-release-${{ github.ref }}
  cancel-in-progress: false

permissions:
  contents: write
  pull-requests: write

jobs:
  tag_release:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-ci-tag-release.yml@main
    with:
      version_file: package.json
      stable_branch: main
      prerelease_branch: develop
      prerelease_tag: beta
    secrets:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

When `created` is `true`, chain [reusable-ci-release-event](reusable-ci-release-event.md) to publish a `Release-Created` fact to this repository. That fact does not name a manifest or an environment; [ops-on-release](ops-on-release.md) decides whether it becomes a deployment.

To let an operator tag an exact version by hand, add a dispatch input and forward it. An empty box keeps the computed behavior:

```yaml
on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Version to tag (blank = compute)'
        required: false
        default: ''

jobs:
  tag_release:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-ci-tag-release.yml@main
    with:
      version: ${{ inputs.version }}
    secrets:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```
