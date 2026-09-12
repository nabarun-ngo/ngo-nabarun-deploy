# ops-deploy-backend

Source: [`.github/workflows/ops-deploy-backend.yml`](../../.github/workflows/ops-deploy-backend.yml)

Thin caller: setup context → resolve manifest → [reusable-deploy-gae-node](reusable-deploy-gae-node.md).

Triggers: `workflow_dispatch`, `repository_dispatch` type `Trigger-Deploy-Backend`.

- `stage` → GitHub Environment `stage`
- `prod` → `prod` (reviewers, `main` only)

## How operators consume it

**Actions → Ops — Deploy Backend (GAE) → Run workflow**

- `manifest_name`: e.g. `backend`
- `target_environment`: `stage` or `prod`
- `tag_name`: empty or `latest` to auto-resolve (see [platform](../platform.md))

App CD may dispatch:

```bash
gh api --method POST -H "Accept: application/vnd.github+json" \
  /repos/YOUR_ORG/deploy-platform/dispatches \
  -f event_type=Trigger-Deploy-Backend \
  -f 'client_payload[tag_name]=1.4.0-beta.1' \
  -f 'client_payload[manifest_name]=backend' \
  -f 'client_payload[target_environment]=stage'
```

Do not auto-dispatch prod.
