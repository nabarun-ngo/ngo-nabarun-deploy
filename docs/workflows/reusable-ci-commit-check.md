# reusable-ci-commit-check

Source: [`.github/workflows/reusable-ci-commit-check.yml`](../../.github/workflows/reusable-ci-commit-check.yml)

Pull request gate for Conventional Commit subjects. A title or commit uses one of:

- `fix:` patch
- `feat:` minor
- `feat!:` or `BREAKING CHANGE:` major
- `docs:`, `chore:`, or `ci:` no release

Library repositories also call [reusable-ci-changeset-check](reusable-ci-changeset-check.md), which checks that the declared Changeset bump matches the highest bump of the title and the valid commit subjects. Application repositories call this workflow, or the same title rule inside [reusable-ci-pr-check](reusable-ci-pr-check.md), and [reusable-ci-tag-release](reusable-ci-tag-release.md).

**Commit title policy:** only the pull request title is a hard failure. It is editable in the GitHub UI and does not require a history rewrite. Commit subjects on the branch (`wip`, `fix typo`, ...) are `::warning::` annotations and do not fail the job. After merge, [reusable-ci-tag-release](reusable-ci-tag-release.md) takes the highest bump among those commit subjects and the merged pull request titles. A `feat:` title can raise a release above `fix:` or non-conventional commits. A `docs:`, `chore:`, or `ci:` title cannot lower a higher commit bump.

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
    with:
      templates_repository: YOUR_ORG/deploy-platform
    secrets:
      TEMPLATES_TOKEN: ${{ secrets.TEMPLATES_TOKEN }}
```

`templates_repository` is required. A called workflow runs in the consumer repository, so it cannot find `scripts/release_model.py` unless the consumer names the templates repository. `TEMPLATES_TOKEN` needs read access to that repository. `GITHUB_TOKEN` cannot read another repository.
