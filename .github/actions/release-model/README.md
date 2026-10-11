# Release Model action

Single entry point for release validation, versioning, package publication, and
application tag creation.

The action is a bootstrap: it checks out `templates_repository` at the required
immutable `templates_ref` under `platform/`, then runs that checkout's release
implementation against the consumer workspace. This keeps the action reference
and the implementation source explicit.

## Invocation

Reference the action itself with an immutable commit SHA:

```yaml
- name: Validate release
  uses: YOUR_ORG/deploy-platform/.github/actions/release-model@ACTION_COMMIT_SHA
  with:
    templates_repository: YOUR_ORG/deploy-platform
    templates_ref: TEMPLATES_COMMIT_SHA
    templates_token: ${{ secrets.TEMPLATES_TOKEN }}
    operation: check-pr
    working_directory: .
    pr_title: ${{ github.event.pull_request.title }}
    base_ref: ${{ github.base_ref }}
    packages_changed: 'true'
```

`templates_ref` must be a full 40-character commit SHA. Branches and mutable
tags are rejected.

For operations that access GitHub or npm, pass tokens through the calling
step's environment:

```yaml
env:
  GH_TOKEN: ${{ secrets.GH_TOKEN }}
  NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
  NODE_AUTH_TOKEN: ${{ secrets.NPM_TOKEN }}
```

## Operations

- `plan`, `baseline`, `validate-pr`, `apply`
- `check-pr`
- `shift-prerelease`
- `skip-if-published`
- `verify-dist-tag`
- `assert-versions`
- `create-tag-release`
- `publish-packages`
- `open-version-pr`

Operation results are exposed as outputs:

- `plan`: `result_json`, `version`
- `baseline`: `baseline`
- `validate-pr` / `check-pr`: `valid`
- `shift-prerelease`: `changed_json`
- `skip-if-published`: `already_published`
- `create-tag-release`: `tag`, `created`, `prerelease`, `skipped`

`skip-if-published` treats both published and unpublished states as successful
action execution; callers branch on `already_published`. Validation operations
still fail the step when policy errors are present and also emit `valid=false`.

## Rollout

The action must exist in a committed remote revision before a reusable workflow
can reference its immutable SHA. Add the action first, then migrate callers in a
follow-up change. Legacy staging remains temporarily for that bootstrap phase.
The compatibility copies at `scripts/release_model.py` and
`.github/actions/create-tag-release/create-tag-release.py` must remain until
consumers pinned to older reusable-workflow revisions have migrated.
