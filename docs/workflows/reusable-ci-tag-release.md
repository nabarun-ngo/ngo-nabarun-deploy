# reusable-ci-tag-release

Source: [`.github/workflows/reusable-ci-tag-release.yml`](../../.github/workflows/reusable-ci-tag-release.yml)

Reusable **git tag and GitHub Release** pipeline for app repos. It does not use Changesets and it does not publish to npm. Library repos keep using [reusable-ci-npm-publish](reusable-ci-npm-publish.md).

Tags are bare semver (`2.3.3`, `2.3.3-beta.1`) so [resolve-git-ref](../../.github/actions/resolve-git-ref/action.yml) can select them. Resolution only considers tags contained in the target branch. `develop` uses the latest `X.Y.Z-(alpha|beta|rc).N` tag on that branch, and falls back to the latest stable tag on that branch when no prerelease tag is there. `main` and prod use the latest stable `X.Y.Z` tag on that branch.

## Choosing the version

Leave `version` empty to calculate it from conventional commit subjects since the latest tag and the titles of the pull requests that introduced those commits. The tag job asks GitHub which pull request each commit belongs to, for the 100 newest commits in that range. The highest bump wins, so a pull request title can raise the version and cannot lower it:

| Change on `develop`, current stable `2.3.2` | Tag |
|---------------------------------------------|-----|
| `fix:` | `2.3.3-beta.1`, then `2.3.3-beta.2` |
| `feat:` | `2.4.0-beta.1` |
| `feat!:` or `BREAKING CHANGE:` | `3.0.0-beta.1` |
| `docs:`, `chore:`, or `ci:` only | No release |

A `feat:` title therefore releases a minor even when the commits on the branch are only `fix:` or are not conventional. A `docs:`, `chore:`, or `ci:` title leaves a `fix:` release as a patch.

Merging `develop` into `main` promotes the beta line when those commits and that pull request title have no release bump: `2.3.3-beta.N` becomes `2.3.3`. Title that promotion `chore:`, `docs:`, or `ci:`. A `Merge pull request` title is ignored and also promotes. A `fix:` or `feat:` title on `main` is a hotfix bump instead. A hotfix merged to `main` bumps the stable version, then the workflow opens a pull request back into `develop`.

The job tags the current commit and opens a GitHub Release. It does not commit `package.json` or `CHANGELOG.md`. The tag has no `v` prefix. If that tag already points at another commit, the job fails instead of moving it. `docs:`, `chore:`, and `ci:` subjects do not create a release on their own. A commit subject that starts with `Merge `, or that contains `chore(release):`, `[skip ci]`, or `[skip actions]`, is ignored.

Pass `version` only for an explicit override. `develop` still accepts only a beta tag, and `main` still accepts only a stable tag.

## Inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `version` | empty | Explicit version to tag (`v` prefix optional). Empty computes from `version_file` |
| `version_file` | `package.json` | Stable `X.Y.Z` used only when the branch has no stable tag yet |
| `stable_branch` | `main` | Branch that tags `X.Y.Z` |
| `prerelease_branch` | `develop` | Branch that tags `X.Y.Z-<tag>.N` |
| `prerelease_tag` | `beta` | `alpha`, `beta`, or `rc` |
| `use_gh_env` | `false` | Bind the job to a GitHub Environment |
| `gh_env` | empty | Environment name when `use_gh_env` is true |

## Secrets

| Secret | Required |
|--------|----------|
| `GH_TOKEN` | Always (pass `secrets.GITHUB_TOKEN`). Also used to read pull request titles |
| `TEMPLATES_TOKEN` | Always. Read access to `templates_repository` |

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
      templates_repository: YOUR_ORG/deploy-platform
      version_file: package.json
      stable_branch: main
      prerelease_branch: develop
      prerelease_tag: beta
    secrets:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      TEMPLATES_TOKEN: ${{ secrets.TEMPLATES_TOKEN }}
```

`templates_repository` is required. `TEMPLATES_TOKEN` needs read access to that repository. `GITHUB_TOKEN` can still push the tag to the consumer repository, and it cannot read the templates repository.

A created tag does not deploy. Operators run [ops-deploy-backend](ops-deploy-backend.md) or [ops-deploy-frontend](ops-deploy-frontend.md).

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
      templates_repository: YOUR_ORG/deploy-platform
      version: ${{ inputs.version }}
    secrets:
      GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      TEMPLATES_TOKEN: ${{ secrets.TEMPLATES_TOKEN }}
```
