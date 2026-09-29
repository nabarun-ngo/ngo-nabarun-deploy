# reusable-ci-tag-release

Source: [`.github/workflows/reusable-ci-tag-release.yml`](../../.github/workflows/reusable-ci-tag-release.yml)

Reusable **git tag and GitHub Release** pipeline for app repos. It does not use Changesets and it does not publish to npm. Library repos keep using [reusable-ci-publish](reusable-ci-publish.md).

Tags are bare semver (`2.3.3`, `2.3.3-beta.1`) so [resolve-git-ref](../../.github/actions/resolve-git-ref/action.yml) can select them. Resolution only considers tags contained in the target branch. `stage` uses the latest `X.Y.Z-(alpha|beta|rc).N` tag on that branch, and falls back to the latest stable tag on that branch when no prerelease tag is there. `main` and prod use the latest stable `X.Y.Z` tag on that branch.

## Choosing the version

Pass `version` to tag exactly that value. A leading `v` is stripped, so `v2.5.0` tags `2.5.0`. The value must be `X.Y.Z` or `X.Y.Z-(alpha|beta|rc).N`. The ref must still be `main` or `stage`.

Leave `version` empty to compute it from `version_file`:

| Branch | `package.json` version | Tag |
|--------|------------------------|-----|
| `stage` | `2.3.2` | `2.3.3-beta.1`, then `2.3.3-beta.2` on the next push |
| `stage` | `2.3.3-beta.2` and that tag is free | `2.3.3-beta.2` |
| `main` | `2.3.3` | `2.3.3` |
| `main` | `2.3.3-beta.2` | Fails. Set a stable `X.Y.Z` first. |

The patch is applied before the prerelease counter. A stable `2.3.2` does not become `2.3.2-beta.1`.

A version containing `-` is a GitHub prerelease. Release notes are generated from commits since the previous tag. If this commit already has the tag, the job reuses it. If that tag already points at another commit, the job fails.

This workflow does not write the new version back to `package.json`. Before a stable release, set `package.json` to the stable version (`2.3.3`) and merge that to `main`.

## Inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `version` | empty | Explicit version to tag (`v` prefix optional). Empty computes from `version_file` |
| `version_file` | `package.json` | JSON file whose `version` is the release base when `version` is empty |
| `stable_branch` | `main` | Branch that tags `X.Y.Z` |
| `prerelease_branch` | `stage` | Branch that tags `X.Y.Z-<tag>.N` |
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
    branches: [main, stage]

concurrency:
  group: tag-release-${{ github.ref }}
  cancel-in-progress: false

permissions:
  contents: write

jobs:
  tag_release:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-ci-tag-release.yml@main
    with:
      version_file: package.json
      stable_branch: main
      prerelease_branch: stage
      prerelease_tag: beta
    secrets:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

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
