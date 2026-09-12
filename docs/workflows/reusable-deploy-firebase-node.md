# reusable-deploy-firebase-node

Source: [`.github/workflows/reusable-deploy-firebase-node.yml`](../../.github/workflows/reusable-deploy-firebase-node.yml)

Build (optional Doppler) and deploy a Node.js frontend to Firebase Hosting.

Build and deploy jobs bind to a GitHub Environment when `use_gh_env` is true (default). Same flags as the CI reusables (`use_gh_env`, `gh_env`).

## Who calls it

[ops-deploy-frontend](ops-deploy-frontend.md) in this repo. Application repos do not call this directly.

## Inputs (environment)

| Input | Default | Meaning |
|-------|---------|---------|
| `use_gh_env` | `true` | Bind jobs to a GitHub Environment |
| `gh_env` | empty | Environment name (required when `use_gh_env` is true) |

## How the client consumes it

Operators run **Ops — Deploy Frontend (Firebase)** or rely on the bi-weekly schedule. Add a Firebase manifest and wire it in the ops caller. See [platform setup](../platform.md).

```yaml
jobs:
  deploy:
    uses: YOUR_ORG/deploy-platform/.github/workflows/reusable-deploy-firebase-node.yml@main
    with:
      # ... manifest fields ...
      use_gh_env: true
      gh_env: ${{ needs.resolve_env.outputs.gh_env }}
      target_environment: stage
```
