# reusable-ci-pr-check

Source: [`.github/workflows/reusable-ci-pr-check.yml`](../../.github/workflows/reusable-ci-pr-check.yml)

Reusable **PR check** for application and library repos. Runs a semantic commit check, then install → type-check → lint → build → optional unit tests. The job name **Build check** is what branch protection should require.

Lint and type-check are skipped if the npm script is missing.

## Semantic commit messages

Only the pull request title must be a Conventional Commit. An invalid or empty title fails the job. Commit subjects on the branch (`wip`, `fix typo`, and similar) are `::warning::` annotations and do not fail the job. This check does not calculate the version. [reusable-ci-tag-release](reusable-ci-tag-release.md) does that after merge, from both the commit subjects and the pull request titles, and the higher bump wins.

| Subject | Version |
|---------|---------|
| `fix:` | patch |
| `feat:` | minor |
| `feat!:` or a body line `BREAKING CHANGE:` | major |
| `docs:`, `chore:`, `ci:` | no release |

A scope is optional (`feat(api): add filter`). Merge commits, `chore(release):`, `[skip ci]`, and `[skip actions]` are ignored. The check runs only when the caller event has a pull request base ref.

When the title fails, edit it in GitHub. That does not rewrite history. If the pull request is already merged, do not rewrite `main` or `develop`. Open a follow-up pull request with a valid title.

## Who calls it

App or package repos on `pull_request` to `main` and `develop`. This repo does not run it for itself.

## Inputs

| Input | Default | Meaning |
|-------|---------|---------|
| `node_version` | `20` | Node.js version |
| `build_root` | `.` | Working directory |
| `install_command` | `npm ci` | Install |
| `build_command` | `npm run build` | Build |
| `lint_command` | `npm run lint` | Lint (optional script) |
| `type_check_command` | `npm run type-check` | Type-check (optional script) |
| `enable_tests` | `false` | Run unit tests |
| `test_command` | `npm test` | Test command |
| `upload_coverage` | `false` | Upload coverage artifact |
| `coverage_path` | `coverage` | Coverage directory under `build_root` |
| `use_gh_env` | `false` | Bind the job to a GitHub Environment |
| `gh_env` | empty | Environment name (required when `use_gh_env` is true) |

## Secrets

None required.

## How the client consumes it

Put this in the **calling** repository as `.github/workflows/ci.yml`. Replace `YOUR_ORG/deploy-platform` with this ops repo.

```yaml
name: CI

on:
  pull_request:
    branches: [main, develop]
    types: [opened, synchronize, reopened]

jobs:
  check:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-ci-pr-check.yml@main
    with:
      node_version: '20'
      build_root: '.'
      install_command: 'npm ci'
      build_command: 'npm run build'
      lint_command: 'npm run lint'
      type_check_command: 'npm run type-check'
      enable_tests: true
      test_command: 'npm test -- --passWithNoTests'
      upload_coverage: false
      # use_gh_env: true
      # gh_env: prod
```

Require the **Build check** status on `main` and `develop` in branch protection.
