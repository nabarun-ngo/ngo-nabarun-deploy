# ops-deploy-backend

Source: [`.github/workflows/ops-deploy-backend.yml`](../../.github/workflows/ops-deploy-backend.yml)

Deploy the backend manifest to App Engine through [reusable-deploy-gae-node](reusable-deploy-gae-node.md). That page describes the bundle, what Cloud Build receives, and where a failed run stops.

Trigger: `workflow_dispatch` only. Backend deploys are manual; there is no schedule or `repository_dispatch` hook, and an application release does not start this workflow.

| Target | GitHub Environment | Approval |
|--------|-------------------|----------|
| `stage` | `be-stage` | Required |
| `prod` | `be-prod` | Required |

The names come from `environments.<target>.githubEnvironment` in `config/manifests/backend.json`. `be-stage` must have at least one required reviewer in GitHub. The workflow binds the job to that environment; it cannot create the reviewer rule.

## How operators consume it

**Actions → Ops — Deploy Backend (GAE) → Run workflow**

- `manifest_name`: `backend`
- `target_environment`: `stage` or `prod`
- `tag_name`: empty or `latest` to auto-resolve (see [platform](../platform.md))
