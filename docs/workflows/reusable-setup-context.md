# reusable-setup-context

Source: [`.github/workflows/reusable-setup-context.yml`](../../.github/workflows/reusable-setup-context.yml)

Normalizes `workflow_dispatch`, `repository_dispatch`, and `schedule` into a single context: manifest name, target environment, tag name.

## Who calls it

[ops-deploy-backend](ops-deploy-backend.md) and [ops-deploy-frontend](ops-deploy-frontend.md) in **this** repo. App repos do not call this.

## Inputs

`manifest_name`, `target_environment` (default `stage`), `tag_name` (default `latest`). Dispatch payloads override when present.

## How the client consumes it

From another workflow in this platform repo:

```yaml
jobs:
  context:
    uses: ./.github/workflows/reusable-setup-context.yml
    with:
      manifest_name: ${{ inputs.manifest_name }}
      target_environment: ${{ inputs.target_environment }}
      tag_name: ${{ inputs.tag_name }}
```

Use `needs.context.outputs.*` for the deploy reusable.
