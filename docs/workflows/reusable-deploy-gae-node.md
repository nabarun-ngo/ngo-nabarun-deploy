# reusable-deploy-gae-node

Source: [`.github/workflows/reusable-deploy-gae-node.yml`](../../.github/workflows/reusable-deploy-gae-node.yml)

Build, optional migrate, deploy a Node.js service to Google App Engine. Manifest fields are passed in as inputs (usually from [resolve-manifest](../../.github/actions/resolve-manifest/action.yml) after [reusable-setup-context](reusable-setup-context.md)).

Migrate and deploy jobs bind to a GitHub Environment when `use_gh_env` is true (default). The build job does not.

## Who calls it

[ops-deploy-backend](ops-deploy-backend.md) in this repo. Application repos do not call this directly.

## Inputs (environment)

| Input | Default | Meaning |
|-------|---------|---------|
| `use_gh_env` | `true` | Bind migrate/deploy to a GitHub Environment |
| `gh_env` | empty | Environment name (required when `use_gh_env` is true) |

Logical target (`stage` / `prod`) remains `target_environment`.

## How the client consumes it

Do not `uses:` this from an app repo. Operators run **Ops — Deploy Backend (GAE)** or send `repository_dispatch` type `Trigger-Deploy-Backend`. That caller resolves the manifest and invokes this reusable:

```yaml
jobs:
  deploy:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-deploy-gae-node.yml@main
    with:
      # ... manifest fields ...
      ref: ${{ needs.resolve_ref.outputs.ref }}
      use_gh_env: true
      gh_env: ${{ needs.resolve_env.outputs.gh_env }}
      target_environment: stage
```

For a new backend, add `config/manifests/<name>.json` with `"platform": "gae"` and extend the ops caller’s manifest `choice` list. See [platform setup](../platform.md).
