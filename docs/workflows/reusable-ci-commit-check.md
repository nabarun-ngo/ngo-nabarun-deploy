# reusable-ci-commit-check

Source: [`.github/workflows/reusable-ci-commit-check.yml`](../../.github/workflows/reusable-ci-commit-check.yml)

Pull request gate for conventional commit titles. A title or commit must use one of:

- `fix:` patch
- `feat:` minor
- `feat!:` or `BREAKING CHANGE:` major
- `docs:`, `chore:`, or `ci:` no release

Library repositories also call [reusable-ci-changeset-check](reusable-ci-changeset-check.md), which checks that the declared Changeset bump matches the commit. Application repositories call this workflow and [reusable-ci-tag-release](reusable-ci-tag-release.md).

## How the client consumes it

```yaml
name: Commit check

on:
  pull_request:
    branches: [main, develop]

permissions:
  contents: read
  pull-requests: read

jobs:
  commits:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-ci-commit-check.yml@main
```
