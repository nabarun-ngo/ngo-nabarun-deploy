# ops-gcp-cleanup

Source: [`.github/workflows/ops-gcp-cleanup.yml`](../../.github/workflows/ops-gcp-cleanup.yml)

Scheduled cleanup (Mon/Wed/Fri 17:00 UTC) and manual run. Matrix over `stage` and `prod`. Each entry binds to the GitHub Environment that `config/manifests/backend.json` declares for that target (`be-stage` / `be-prod`) for `GCP_SA_KEY` and `GCP_PROJECT_ID`. Cleans: old GAE versions, stale GCS staging objects, untagged Artifact Registry images.

Scheduled runs are always a dry run: they report what would be deleted and delete nothing. Only a manual run with `dry_run` unticked deletes. Because `be-stage` and `be-prod` have required reviewers, every run (scheduled or manual) waits for approval on each matrix entry before it can read the GCP credentials.

## How operators consume it

Leave the schedule enabled, or **Actions → Ops — GCP Scheduled Cleanup → Run workflow**. Not called from app repos.
