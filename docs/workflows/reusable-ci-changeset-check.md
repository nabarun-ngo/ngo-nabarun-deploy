# reusable-ci-changeset-check

Source: [`.github/workflows/reusable-ci-changeset-check.yml`](../../.github/workflows/reusable-ci-changeset-check.yml)

PR gate for **Changesets** library repos. If files matching `packages_filter` changed, the PR must include a changeset vs the base branch (`npx changeset status --since=origin/<base>`).

Does not version or publish. Pair with [reusable-ci-npm-publish](reusable-ci-npm-publish.md).

A same-repository pull request from `changeset-release/<base>` is the generated Version Packages pull request. That pull request skips the requirement for another Changeset. Its title is still checked. Feature pull requests are checked regardless of who opens them.

**Commit title policy:** the pull request title must be a Conventional Commit (`fix:`, `feat:`, `feat!:`, `docs:`, `chore:`, or `ci:`). An invalid title is a hard failure, and it can be edited in the GitHub UI. Commit subjects on the branch (`wip`, `address review comments`, ...) are `::warning::` annotations and do not fail the job. When a changeset is required, the expected bump is the highest of the title and the valid commit subjects. That bump must match the changeset. Invalid commit subjects add no bump. Library versions still come from Changesets, not from [reusable-ci-tag-release](reusable-ci-tag-release.md).

## Who calls it

Package monorepos (`packages/**`) on `pull_request` to `main` and/or `develop`. Not used by this ops repo. App-only repos usually skip this unless they version with Changesets. Application repositories call [reusable-ci-commit-check](reusable-ci-commit-check.md) instead.

## Inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `templates_repository` | — (**required**) | Repository holding `scripts/release_model.py`, as `owner/name`. A called workflow runs in the consumer repository, so the consumer passes this |
| `node_version` | `22` | Node.js |
| `working_directory` | `.` | Lockfile and `.changeset` directory |
| `packages_filter` | `packages/**` | Path glob that requires a changeset |
| `install_command` | `npm ci` | Install before `changeset status` |
| `use_gh_env` | `false` | Bind the job to a GitHub Environment |
| `gh_env` | empty | Environment name (required when `use_gh_env` is true) |
| `enable_validation` | `true` | Run the release-commit and Changeset bump validation step described above. Set to false only to onboard a repository that cannot satisfy it yet |

## Secrets

| Secret | Required | Meaning |
|--------|----------|---------|
| `TEMPLATES_TOKEN` | yes | Read access to `templates_repository`. `GITHUB_TOKEN` cannot read another repository |

## How the client consumes it

`.github/workflows/changeset-check.yml` in the library repo. Replace `YOUR_ORG/deploy-platform` with this ops repo.

```yaml
name: Changeset Check

on:
  pull_request:
    branches: [main, develop]

concurrency:
  group: changeset-check-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  changeset-check:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-ci-changeset-check.yml@main
    with:
      templates_repository: YOUR_ORG/deploy-platform
      node_version: '22'
      working_directory: '.'
      packages_filter: 'packages/**'
      # use_gh_env: true
      # gh_env: prod
    secrets:
      TEMPLATES_TOKEN: ${{ secrets.TEMPLATES_TOKEN }}
```

`templates_repository` is required. `TEMPLATES_TOKEN` needs read access to that repository. `GITHUB_TOKEN` cannot read another repository.
