# Platform setup

Reference for configuring this ops repository. For a step-by-step first-time setup, use the [deployment setup guide](deployment-setup-guide.html). Workflow-specific usage is in [../README.md](../README.md) and [workflows/](workflows/).

## GitHub Environments

Each tier (frontend, backend, tests) has its own environments. Every reusable workflow reads the same secret names, such as `DOPPLER_TOKEN`; the bound environment decides which value the job gets, and a job cannot see another tier's credentials.

No script hard-codes an environment name. Each name is declared once in config:

| Used by | Declared in |
|---------|-------------|
| Manual deploy | Manifest `environments.<target>.githubEnvironment` |
| Scheduled deploy | `config/schedules/deploys.json` → the entry's `githubEnvironment` |
| Manual test run | `config/schedules/tests.json` → `manualGithubEnvironments.<target>` |
| Scheduled test run | `config/schedules/tests.json` → the profile's `githubEnvironment` |
| GCP ops / cleanup | The `backend` manifest's `environments.<target>.githubEnvironment` |

### Naming GitHub Environments

Names follow `<tier>-<target>`, with `-scheduled` appended for the auto-approved copy a scheduled run uses:

| Part | Values | Meaning |
|------|--------|---------|
| `<tier>` | `fe`, `be`, `tests` | Whose secrets the environment holds: frontend (Firebase + frontend Doppler), backend (App Engine + backend Doppler), or the test suite |
| `<target>` | `stage`, `prod` | The logical environment, matching the manifest's `environments` keys |
| `-scheduled` | optional suffix | Same secrets as `<tier>-<target>`, but no reviewers, so a cron run is not blocked waiting for approval |

Examples: `fe-stage`, `be-prod`, `fe-prod-scheduled`. Scheduled tests use `tests-scheduled` without a target, because each cron profile picks its own target in `tests.json`.

Rules:

- Lowercase letters, digits and hyphens only (`^[a-z][a-z0-9-]*$`); the manifest and schedule schemas reject anything else.
- One environment per tier and target. Two apps in the same tier may share one only if they read the same secrets (both frontend apps share `fe-*` because they use one Doppler project).
- A `-scheduled` environment must hold copies of its manual counterpart's secrets and the same branch restriction; only the reviewer rule differs. Reserve it for apps listed in `config/schedules/deploys.json`.
- **Create the environment in GitHub before any config references it.** GitHub silently creates a referenced environment that does not exist, with no reviewers, no branch rule and no secrets. A misspelled name therefore does not stop the run at an approval step: the deploy starts unapproved and fails later on an empty secret. Nothing in CI catches the typo, so check new or renamed names in review against the table below and against **Settings → Environments**.

| Environment name | Required reviewers | Branch restriction | Used by |
|-----------------|-------------------|--------------------|---------|
| `fe-stage` | 1+ (`deployers`) | none | Manual frontend stage deploys |
| `fe-prod` | 1+ (`release-managers`) | `main` only | Manual frontend prod deploys |
| `fe-prod-scheduled` | 0 | `main` only | Biweekly public-site prod rebuild |
| `be-stage` | 1+ (`deployers`) | none | Manual backend stage deploys, GCP ops and cleanup on stage |
| `be-prod` | 1+ (`release-managers`) | `main` only | Manual backend prod deploys, GCP ops and cleanup on prod |
| `tests-stage` | 1+ (`deployers`) | none | Manual stage test runs |
| `tests-prod` | 1+ (`release-managers`) | `main` only | Manual prod test runs (one shard) |
| `tests-scheduled` | 0 | none | Cron test runs |

GitHub Environments do not share secrets. Copy the `fe-prod` secrets into `fe-prod-scheduled`, and update both when a production frontend credential is rotated.

## Environment secrets

| Secret | `fe-*` | `be-*` | `tests-*` | Value |
|--------|--------|--------|-----------|-------|
| `FB_PROJECT_ID` | yes | — | — | Firebase project ID |
| `FB_SA_KEY` | yes | — | — | Firebase deploy service-account JSON |
| `GCP_PROJECT_ID` | — | yes | — | App Engine project ID |
| `GCP_SA_KEY` | — | yes | — | App Engine deploy service-account JSON |
| `DOPPLER_TOKEN` | yes | yes | yes | Frontend: project `frontend`. Backend: project `backend-api`. Tests: `DOPPLER_PROJECT_TEST`. Config `stg` for stage, `prd` for prod and `fe-prod-scheduled`. |

## Repository secrets and variables

| Secret | Purpose |
|--------|---------|
| `PAT` | Token with read access to the test repo. Optional for deploys: they fall back to `GITHUB_TOKEN`, which reads public app repos; set `PAT` only if an app repo is private. Allure reports on this repo use `GITHUB_TOKEN`, not PAT. |

| Variable | Example | Purpose |
|----------|---------|---------|
| `TEST_REPOSITORY` | `YOUR_ORG/automation-tests` | Cucumber test repository |
| `DOPPLER_PROJECT_TEST` | `automation-tests` | Doppler project for tests |

Deploy Doppler projects are not variables; each manifest sets `deploy.secrets.project` (`backend-api`, `frontend`).

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
      "sourceRef": "develop",
      "githubEnvironment": "be-stage",
      "gaeService": "my-app-staging",
      "secrets": { "config": "stg" }
    },
    "prod": {
      "sourceRef": "main",
      "githubEnvironment": "be-prod",
      "gaeService": "my-app",
      "secrets": { "config": "prd" }
    }
  }
}
```

`githubEnvironment` is required in every environment block and must follow the [naming convention](#naming-github-environments). Manifests do not say when an app deploys; scheduled deploys are declared in `config/schedules/deploys.json` (see [Schedules](#schedules)).

Validate locally:

```bash
scripts/validate-manifests.sh config/manifests/ schemas/manifest.v1.schema.json
scripts/resolve-manifest.sh backend stage
check-jsonschema --schemafile schemas/schedules.v1.schema.json config/schedules/tests.json config/schedules/deploys.json
```

## Doppler

Optional per manifest (`deploy.secrets.provider: "doppler"`).

| Point | When | How |
|-------|------|-----|
| Build-time (frontend) | Firebase + Doppler | Both frontend manifests use Doppler project `frontend`. The build job reads `DOPPLER_TOKEN` from the bound `fe-*` environment and the CLI wraps `npm run build`. |
| Runtime (GAE) | `bundleCli: true` | Binary in artifact; `start.sh` uses `doppler run`. Deploy path, Cloud Build source, and failure points: [reusable-deploy-gae-node](workflows/reusable-deploy-gae-node.md). |
| Migration | `database.migrate: true` | `doppler run --` migrate command |
| Tests | `doppler_project` on the test workflow | Execute job reads environment `DOPPLER_TOKEN`; Maven `-DCONFIG_SOURCE=doppler`. Config names are `stg` / `prd`. |

Do not share a Doppler token across environments. Use a read-only service token per project and config: `frontend`/`stg` in `fe-stage`, `frontend`/`prd` in `fe-prod` and `fe-prod-scheduled`, `backend-api`/`stg` in `be-stage`, and so on.

## “Latest” tag resolution

When ops leave `tag_name` empty or `latest`, [resolve-git-ref](../.github/actions/resolve-git-ref/action.yml) picks the highest semver tag that is contained in the target branch (`v` prefix optional):

- `develop` → latest `X.Y.Z-(alpha|beta|rc).N` on that branch. If the branch has no prerelease tag, it falls back to the latest stable tag on that branch. The stage deployment environment uses this branch.
- `main` / prod → latest stable `X.Y.Z` on that branch.

Tags that exist only on another branch are ignored.

## Schedules

| Schedule | Cron | Workflow |
|----------|------|----------|
| Nightly smoke | `0 3 * * *` | [ops-run-tests](workflows/ops-run-tests.md) `@smoke` |
| Weekly regression | `0 2 * * 1` | [ops-run-tests](workflows/ops-run-tests.md) `@regression` |
| Biweekly public-site prod rebuild | `0 2 1,15 * *` | [ops-deploy-frontend](workflows/ops-deploy-frontend.md) |
| GCP cleanup | `0 17 * * 1,3,5` | [ops-gcp-cleanup](workflows/ops-gcp-cleanup.md) |

Backend deploys use [ops-deploy-backend](workflows/ops-deploy-backend.md), manual runs only. Frontend deploys use [ops-deploy-frontend](workflows/ops-deploy-frontend.md). Manual stage and prod deploys require a reviewer.

Scheduled deploys are declared in [config/schedules/deploys.json](../config/schedules/deploys.json), which uses the same schema as the test schedules. Each entry has a `cron`, a `deploy` block (`manifest`, `target`, optional `tag`, default `latest`) and the `githubEnvironment` the run binds to:

```json
{
  "id": "public-site-prod-rebuild",
  "cron": "0 2 1,15 * *",
  "deploy": { "manifest": "fe-public-site", "target": "prod" },
  "githubEnvironment": "fe-prod-scheduled"
}
```

On a cron trigger, `scripts/resolve-deploy-schedule.sh` finds the entry whose `cron` matches and deploys that manifest to that target. Only manifests listed here can deploy on a schedule. Today that is the public site, rebuilt in production through the auto-approved `fe-prod-scheduled` environment so build-time content stays fresh; nothing deploys to stage on a schedule.

Scheduled production deploys are otherwise not allowed. The public-site rebuild is the one documented exception in `.cursor/rules/deployment-safety.mdc`; adding another scheduled `prod` entry needs an explicit decision recorded there. Backend deploys stay manual-only because they run database migrations.

GitHub reads cron strings only from the workflow's `on.schedule`, so a cron lives in two places: the workflow and the entry. To add a scheduled deploy, add the entry and the same cron to the deploy workflow. `validate-workflow-guardrails.py` fails CI when a workflow cron matches no entry or more than one, or when an entry names a manifest or target that does not exist.

Cron test tags, SUT environment, shard count, and timeout come from [config/schedules/tests.json](../config/schedules/tests.json). The GitHub Environment for tests also comes from that file: a cron run uses its profile's `githubEnvironment` (`tests-scheduled`), and a manual run uses `manualGithubEnvironments.<target>` (`tests-stage`, or `tests-prod` with one shard). [resolve-deployment-environment](../.github/actions/resolve-deployment-environment/action.yml) receives the resolved name.

## Access control

Reusable workflows bind jobs with `use_gh_env` / `gh_env` (CI defaults `use_gh_env` to false; deploy and tests default to true). `resolve-deployment-environment` takes `github_environment` (from the manifest, or from `tests.json` for tests) and, for scheduled deploys, `schedule_github_environment` (from `deploys.json`), and outputs `gh_env`. It holds no environment names.

| Workflow | Trigger | Target | GitHub Environment | Approval |
|----------|---------|--------|-------------------|----------|
| Any deploy | `workflow_dispatch` | stage / prod | manifest `environments.<target>.githubEnvironment` (today `fe-*` or `be-*`) | Required |
| Scheduled deploy | `schedule` | the matching `deploys.json` entry's target | that entry's `githubEnvironment` (today `fe-public-site` → `fe-prod-scheduled`) | Auto |
| Cron with no `deploys.json` entry | `schedule` | — | rejected | — |
| GCP ops / cleanup | `workflow_dispatch` / `schedule` | stage / prod | `backend` manifest's `githubEnvironment` (`be-stage` / `be-prod`) | Per environment |
| Tests | `workflow_dispatch` | stage / prod | `tests.json` `manualGithubEnvironments.<target>` (`tests-stage` / `tests-prod`) | Required |
| Tests | `schedule` | per profile | profile `githubEnvironment` (`tests-scheduled`) | Auto |
