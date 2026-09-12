# Platform setup

One-time configuration for this ops repository. Workflow-specific usage is in [../README.md](../README.md) and [workflows/](workflows/).

## GitHub Environments

| Environment name | Required reviewers | Branch restriction | Notes |
|-----------------|-------------------|--------------------|-------|
| `stage` | 0 (optional — `deployers` team) | none | Manual/dispatch deploys and tests to stage |
| `prod` | 1+ (`release-managers`) | `main` only | Manual prod deploys and prod-targeted tests |
| `tests-scheduled` | 0 | none | Auto-approved cron test runs |
| `stage-scheduled` | 0 | none | Auto-approved bi-weekly public site deploy |

Duplicate the same secrets into `stage` and `stage-scheduled`, and into `prod` where needed. Scheduled jobs use `*-scheduled` environments so they do not share protection with manual deploys.

## Environment secrets

| Secret | `stage` | `prod` | `tests-scheduled` | `stage-scheduled` |
|--------|---------|--------|-------------------|-------------------|
| `GCP_PROJECT_ID` | yes | yes | — | yes |
| `GCP_SA_KEY` | yes | yes | — | yes |
| `FB_PROJECT_ID` | yes | yes | — | yes |
| `FB_SA_KEY` | yes | yes | — | yes |
| `DOPPLER_TOKEN` | yes | yes | yes | yes |

## Repository secrets and variables

| Secret | Purpose |
|--------|---------|
| `PAT` | Token with read access to app and test repos. Allure reports on this repo use `GITHUB_TOKEN`, not PAT. |

| Variable | Example | Purpose |
|----------|---------|---------|
| `TEST_REPOSITORY` | `YOUR_ORG/automation-tests` | Cucumber test repository |
| `DOPPLER_PROJECT_TEST` | `automation-tests` | Doppler project for tests |
| `DOPPLER_PROJECT_BACKEND` | `backend-api` | Doppler project for backend |

## GitHub Pages

1. **Settings → Pages**
2. Source: **Deploy from a branch**
3. Branch: `gh-pages`, folder: `/(root)`

Portal URL: `https://<org>.github.io/<repo>/` (published by [ops-publish-site](workflows/ops-publish-site.md)).

Allure HTML lives beside the portal on the same branch (`allure-report/<run_id>/`, plus `allure-report/last-run/` and a redirect at `allure-report/index.html`). The portal job uses `keep_files: true`. The portal publish job and the test report job share concurrency group `gh-pages` (`cancel-in-progress: false`) so they do not race. Reports are pushed with `GITHUB_TOKEN`, not `PAT`.

## Manifests

Files: `config/manifests/<name>.json`, schema `schemas/manifest.v1.schema.json`. There is no `layout` field. Behavior comes from `buildRoot` / `appRoot`:

| `buildRoot` | `appRoot` | Behavior |
|-------------|-----------|----------|
| `.` (default) | not set | Single-app: install and build at root |
| `.` | `apps/api` | Monorepo: install/build at root, stage from `apps/api` |
| `packages/server` | not set | Nested app directory |

```json
{
  "apiVersion": "deploy.platform/v1",
  "kind": "Application",
  "metadata": { "name": "my-app" },
  "source": {
    "repository": "YOUR_ORG/my-app",
    "buildRoot": ".",
    "appRoot": "apps/api"
  },
  "build": {
    "runtime": "node",
    "nodeVersion": "20",
    "command": "npm run build",
    "outputPath": "dist"
  },
  "deploy": {
    "platform": "gae",
    "configTemplate": "config/platforms/gae/app.yaml.tpl",
    "serviceKey": "gaeService",
    "secrets": {
      "provider": "doppler",
      "project": "my-app",
      "bundleCli": true
    }
  },
  "database": {
    "migrate": true,
    "command": "npx prisma migrate deploy"
  },
  "environments": {
    "stage": {
      "sourceRef": "stage",
      "gaeService": "my-app-staging",
      "secrets": { "config": "stg" }
    },
    "prod": {
      "sourceRef": "main",
      "gaeService": "my-app",
      "secrets": { "config": "prd" }
    }
  }
}
```

Validate locally:

```bash
scripts/validate-manifests.sh config/manifests/ schemas/manifest.v1.schema.json
scripts/resolve-manifest.sh backend stage
check-jsonschema --schemafile schemas/schedules.v1.schema.json config/schedules/tests.json
```

## Doppler

Optional per manifest (`deploy.secrets.provider: "doppler"`).

| Point | When | How |
|-------|------|-----|
| Build-time (frontend) | Firebase + Doppler | CLI wraps `npm run build` |
| Runtime (GAE) | `bundleCli: true` | Binary in artifact; `start.sh` uses `doppler run` |
| Migration | `database.migrate: true` | `doppler run --` migrate command |
| Tests | `doppler_project` on the test workflow | Execute job reads environment `DOPPLER_TOKEN`; Maven `-DCONFIG_SOURCE=doppler`. Config names are `stg` / `prd`. |

Do not share `DOPPLER_TOKEN` across environments.

## “Latest” tag resolution

When ops leave `tag_name` empty or `latest`, [resolve-git-ref](../.github/actions/resolve-git-ref/action.yml) picks the highest semver tag (`v` prefix optional):

- `stage` → latest `X.Y.Z-(alpha|beta|rc).N`
- `main` / prod → latest stable `X.Y.Z`

## Schedules

| Schedule | Cron | Workflow |
|----------|------|----------|
| Nightly smoke | `0 3 * * *` | [ops-run-tests](workflows/ops-run-tests.md) `@smoke` |
| Weekly regression | `0 2 * * 1` | [ops-run-tests](workflows/ops-run-tests.md) `@regression` |
| Bi-weekly public site | `0 2 1,15 * *` | [ops-deploy-frontend](workflows/ops-deploy-frontend.md) |
| GCP cleanup | `0 17 * * 1,3,5` | [ops-gcp-cleanup](workflows/ops-gcp-cleanup.md) |

Scheduled prod deploys are disabled. Production always requires a human.

Cron test tags, SUT environment, shard count, and timeout come from [config/schedules/tests.json](../config/schedules/tests.json). GitHub Environment routing for tests uses [resolve-deployment-environment](../.github/actions/resolve-deployment-environment/action.yml) (`workflow_type: tests`): cron → `tests-scheduled`, manual stage → `stage`, manual prod → `prod` (one shard).

## Access control

Reusable workflows bind jobs with `use_gh_env` / `gh_env` (CI defaults `use_gh_env` to false; deploy and tests default to true). `resolve-deployment-environment` outputs `gh_env`.

| Trigger | Target | GitHub Environment | Approval |
|---------|--------|-------------------|----------|
| `workflow_dispatch` | stage | `stage` | Optional |
| `workflow_dispatch` | prod | `prod` | Required |
| `repository_dispatch` | stage | `stage` | Optional |
| `schedule` | deploy | `stage-scheduled` | Auto |
| `schedule` | tests | `tests-scheduled` | Auto |
