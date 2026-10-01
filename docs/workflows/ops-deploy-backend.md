# ops-deploy-backend

Source: [`.github/workflows/ops-deploy-backend.yml`](../../.github/workflows/ops-deploy-backend.yml)

Deploy the backend manifest to App Engine through [reusable-deploy-gae-node](reusable-deploy-gae-node.md).

Triggers: `workflow_dispatch`, and `repository_dispatch` type `Trigger-Deploy-Backend`. An application release does not start this workflow.

| Target | GitHub Environment | Approval |
|--------|-------------------|----------|
| `stage` | `stage` | Required |
| `prod` | `prod` | Required |

`stage` must have at least one required reviewer in GitHub. The workflow binds the job to that environment; it cannot create the reviewer rule. `Trigger-Deploy-Backend` uses the same environments, so a dispatched stage or prod run also waits.

`Trigger-Deploy-Backend` is an explicit deploy request. The payload names the manifest, environment, and tag.

## How operators consume it

**Actions → Ops — Deploy Backend (GAE) → Run workflow**

- `manifest_name`: `backend`
- `target_environment`: `stage` or `prod`
- `tag_name`: empty or `latest` to auto-resolve (see [platform](../platform.md))

An operator, or another workflow, may request the same deploy:

```bash
gh api --method POST -H "Accept: application/vnd.github+json" \
  /repos/YOUR_ORG/deploy-platform/dispatches \
  -f event_type=Trigger-Deploy-Backend \
  -f 'client_payload[tag_name]=1.4.0-beta.1' \
  -f 'client_payload[manifest_name]=backend' \
  -f 'client_payload[target_environment]=stage'
```
