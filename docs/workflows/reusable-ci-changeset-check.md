# reusable-ci-changeset-check

Source: [`.github/workflows/reusable-ci-changeset-check.yml`](../../.github/workflows/reusable-ci-changeset-check.yml)

PR gate for **Changesets** library repos. If files matching `packages_filter` changed, the PR must include a changeset vs the base branch (`npx changeset status --since=origin/<base>`).

Does not version or publish. Pair with [reusable-ci-publish](reusable-ci-publish.md).

Skips PRs authored by `github-actions[bot]` so the Version Packages PR can merge.

## Who calls it

Package monorepos (`packages/**`) on `pull_request` to `main` and/or `stage`. Not used by this ops repo. App-only repos usually skip this unless they version with Changesets.

## Inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `node_version` | `22` | Node.js |
| `working_directory` | `.` | Lockfile and `.changeset` directory |
| `packages_filter` | `packages/**` | Path glob that requires a changeset |
| `install_command` | `npm ci` | Install before `changeset status` |
| `use_gh_env` | `false` | Bind the job to a GitHub Environment |
| `gh_env` | empty | Environment name (required when `use_gh_env` is true) |

## Secrets

None.

## How the client consumes it

`.github/workflows/changeset-check.yml` in the library repo. Replace `YOUR_ORG/deploy-platform` with this ops repo.

```yaml
name: Changeset Check

on:
  pull_request:
    branches: [main, stage]

concurrency:
  group: changeset-check-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  changeset-check:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-ci-changeset-check.yml@main
    with:
      node_version: '22'
      working_directory: '.'
      packages_filter: 'packages/**'
      # use_gh_env: true
      # gh_env: prod
```
