# ops-gcp-ops

Source: [`.github/workflows/ops-gcp-ops.yml`](../../.github/workflows/ops-gcp-ops.yml)

Interactive hub (`workflow_dispatch` only): download logs, restart GAE service, list versions, cleanup versions/GCS/Artifact Registry. Destructive ops require `confirm: yes`.

## How operators consume it

**Actions → Ops — GCP Operations Hub**. Pick `operation`, environment (`stage`/`prod`), and confirmation if required. Secrets come from the selected GitHub Environment. Not called from app repos.
