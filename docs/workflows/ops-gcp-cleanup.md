# ops-gcp-cleanup

Source: [`.github/workflows/ops-gcp-cleanup.yml`](../../.github/workflows/ops-gcp-cleanup.yml)

Scheduled cleanup (Mon/Wed/Fri 17:00 UTC) and manual run. Matrix over `stage` and `prod`: old GAE versions, stale GCS staging objects, untagged Artifact Registry images.

## How operators consume it

Leave the schedule enabled, or **Actions → Ops — GCP Scheduled Cleanup → Run workflow**. Not called from app repos.
