# ops-deploy-frontend

Source: [`.github/workflows/ops-deploy-frontend.yml`](../../.github/workflows/ops-deploy-frontend.yml)

Deploy one frontend manifest to Firebase Hosting through [reusable-deploy-firebase-node](reusable-deploy-firebase-node.md).

Triggers:

- `workflow_dispatch`: operator chooses `fe-internal-app` or `fe-public-site`, the environment, and the tag.
- `0 2 1,15 * *`: automatic public-site rebuild in production using `latest` (newest stable tag on `main`). The site is a static export that fetches content at build time, so the rebuild picks up new content even when no new tag exists.

An application release does not start this workflow. Nothing deploys to stage on a schedule.

| Run | GitHub Environment | Approval |
|-----|-------------------|----------|
| Manual `stage` | `fe-stage` | Required |
| Manual `prod` | `fe-prod` | Required |
| Scheduled public-site prod | `fe-prod-scheduled` | Automatic |

Manual runs bind to the manifest's `environments.<target>.githubEnvironment`. A scheduled run deploys whatever [config/schedules/deploys.json](../../config/schedules/deploys.json) lists for its cron (today: `fe-public-site` to `prod` via `fe-prod-scheduled`); the `trigger` job resolves it with `scripts/resolve-deploy-schedule.sh`. A cron with no matching entry fails, so the internal portal cannot reach production without a reviewer unless someone adds it to that file.

Scheduled production entries may use `latest` or an explicit stable semver tag only; branches, commit SHAs, and prerelease tags are rejected.

`fe-stage` and `fe-prod` must have required reviewers in GitHub. `fe-prod-scheduled` has none, is restricted to `main`, and holds copies of the `fe-prod` secrets.

## How operators consume it

**Actions → Ops — Deploy Frontend (Firebase) → Run workflow**

- `manifest_name`: `fe-internal-app` or `fe-public-site`
- `target_environment`: `stage` or `prod`
- `tag_name`: empty or `latest` to auto-resolve (see [platform](../platform.md))
