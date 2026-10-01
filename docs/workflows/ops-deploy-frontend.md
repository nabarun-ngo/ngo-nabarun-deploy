# ops-deploy-frontend

Source: [`.github/workflows/ops-deploy-frontend.yml`](../../.github/workflows/ops-deploy-frontend.yml)

Deploy one frontend manifest to Firebase Hosting through [reusable-deploy-firebase-node](reusable-deploy-firebase-node.md).

Triggers:

- `workflow_dispatch`: operator chooses `fe-internal-app` or `fe-public-site`, the environment, and the tag.
- `0 2 1,15 * *`: automatic public-site deployment to `stage-scheduled` using `latest`.

An application release does not start this workflow.

| Target | GitHub Environment | Approval |
|--------|-------------------|----------|
| Manual `stage` | `stage` | Required |
| `prod` | `prod` | Required |
| Scheduled public-site stage | `stage-scheduled` | Automatic |

`stage` must have at least one required reviewer in GitHub. The scheduled run uses `stage-scheduled`, which stays auto-approved.

## How operators consume it

**Actions → Ops — Deploy Frontend (Firebase) → Run workflow**

- `manifest_name`: `fe-internal-app` or `fe-public-site`
- `target_environment`: `stage` or `prod`
- `tag_name`: empty or `latest` to auto-resolve (see [platform](../platform.md))
