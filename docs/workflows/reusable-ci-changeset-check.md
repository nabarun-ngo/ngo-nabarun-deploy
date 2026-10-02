# reusable-ci-changeset-check

Source: [`.github/workflows/reusable-ci-changeset-check.yml`](../../.github/workflows/reusable-ci-changeset-check.yml)

PR gate for **Changesets** library repos. If files matching `packages_filter` changed, the PR must include a changeset vs the base branch (`npx changeset status --since=origin/<base>`).

Does not version or publish. Pair with [reusable-ci-publish](reusable-ci-publish.md).

A same-repository pull request from `changeset-release/<base>` is the generated Version Packages pull request. That pull request skips the requirement for another Changeset. Its title is still checked. Feature pull requests are checked regardless of who opens them.

**Commit title policy:** the pull request title must be a conventional commit (`fix:`, `feat:`, `feat!:`, `docs:`, `chore:`, or `ci:`) — that is a hard failure, since it is what the release/changelog actually uses and is editable in the GitHub UI without touching history. Individual commit messages pushed to the branch (`wip`, `address review comments`, ...) are reported as `::warning::` annotations, not failures — fixing those would require an amend/rebase and force-push, and they are discarded on merge, so they do not need to block the pull request. Only the title (and, when a changeset is required, its declared bump) determine the release version.

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
