# reusable-ci-pr-check

Source: [`.github/workflows/reusable-ci-pr-check.yml`](../../.github/workflows/reusable-ci-pr-check.yml)

Reusable **PR check** for application and library repos. Runs install → type-check → lint → build → optional unit tests. The job name **Build check** is what branch protection should require.

Lint and type-check are skipped if the npm script is missing.

## Who calls it

App or package repos on `pull_request` to `main` and `stage`. This repo does not run it for itself.

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
    branches: [main, stage]
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

Require the **Build check** status on `main` and `stage` in branch protection.
