# Deploy Platform v1

Production-grade, manifest-driven CI/CD platform for Node.js applications on Google Cloud (App Engine + Firebase Hosting), with parallel Cucumber test execution and Allure reporting on GitHub Pages.

## What's in this repo

| Layer | Files | Purpose |
|-------|-------|---------|
| **Schema** | `schemas/manifest.v1.schema.json` | Kubernetes-style manifest contract (no layout enum — generic) |
| **Manifests** | `config/manifests/*.json` | Per-application deploy config (`backend.json`, `frontend.json`) |
| **Platform templates** | `config/platforms/gae/`, `config/platforms/firebase/` | `app.yaml.tpl`, Firebase hosting JSON |
| **Composite actions** | `.github/actions/*/action.yml` | Small, purpose-built building blocks |
| **Reusable workflows** | `.github/workflows/reusable-*.yml` | Deploy + test engine |
| **Ops workflows** | `.github/workflows/ops-*.yml` | Manual trigger + scheduled operations |
| **CI** | `.github/workflows/ci-validate.yml` | Manifest + YAML + shell lint on PR |
| **App CI/CD stubs** | `examples/` | Drop-in files for application repos |
| **Scripts** | `scripts/` | Offline validation, release notes, manifest resolver |
| **Portal** | `docs/index.html` | GitHub Pages ops portal |

---

## Architecture

```
Ops Workflows (thin callers)
  ops-deploy-backend.yml   → reusable-deploy-gae-node.yml
  ops-deploy-frontend.yml  → reusable-deploy-firebase-node.yml
  ops-run-tests.yml        → reusable-run-tests-allure.yml
  ops-publish-site.yml     → gh-pages (portal)
  ops-gcp-cleanup.yml      → gcloud (scheduled resource cleanup)
  ops-gcp-ops.yml          → gcloud (interactive operations hub)

Reusable Engine
  reusable-setup-context.yml       — normalize dispatch/schedule inputs
  reusable-deploy-gae-node.yml     — build → migrate → deploy → promote
  reusable-deploy-firebase-node.yml — build (Doppler) → Firebase deploy
  reusable-run-tests-allure.yml    — discover → matrix execute → publish report

Composite Actions
  resolve-git-ref               — tag / "latest" resolution
  resolve-manifest              — load manifest + env → flat outputs
  resolve-deployment-environment — trigger → GitHub Environment name
  stage-node-artifact           — bundle + optional Doppler CLI embed
  render-config                 — envsubst template renderer
  publish-allure                — merge shards, history, push gh-pages
```

---

## One-time repo setup

### 1. Create GitHub Environments

Go to **Settings → Environments** and create these four environments:

| Environment name | Required reviewers | Branch restriction | Notes |
|-----------------|-------------------|--------------------|-------|
| `stage` | 0 (optional — add your `deployers` team if desired) | none | Manual/dispatch deploys and tests to stage |
| `prod` | **1+** (add `release-managers` team) | `main` only | Manual prod deploys — always requires human approval |
| `tests-scheduled` | **0** — must be zero | none | Auto-approved cron test runs |
| `stage-scheduled` | **0** — must be zero | none | Auto-approved bi-weekly public site deploy |

> **Tip:** Duplicate the same secrets into both `stage` and `stage-scheduled`, and into both `prod` and `stage` (where needed). Scheduled jobs use `-scheduled` variants so they never touch the same environment as a protected manual deploy.

### 2. Add secrets to each environment

| Secret | `stage` | `prod` | `tests-scheduled` | `stage-scheduled` |
|--------|---------|--------|-------------------|-------------------|
| `GCP_PROJECT_ID` | ✅ | ✅ | — | ✅ |
| `GCP_SA_KEY` | ✅ | ✅ | — | ✅ |
| `FB_PROJECT_ID` | ✅ | ✅ | — | ✅ |
| `FB_SA_KEY` | ✅ | ✅ | — | ✅ |
| `DOPPLER_TOKEN` | ✅ | ✅ | ✅ | ✅ |

### 3. Add repository secrets

| Secret | Purpose |
|--------|---------|
| `PAT` | GitHub Personal Access Token (read access to app + test repos, write for tagging/releases) |

### 4. Add repository variables

| Variable | Example | Purpose |
|----------|---------|---------|
| `TEST_REPOSITORY` | `YOUR_ORG/automation-tests` | Cucumber test repository |
| `DOPPLER_PROJECT_TEST` | `automation-tests` | Doppler project for test credentials |
| `DOPPLER_PROJECT_BACKEND` | `backend-api` | Doppler project for backend (used in ops) |

### 5. Enable GitHub Pages

1. Go to **Settings → Pages**
2. Set source: **Deploy from a branch**
3. Branch: `gh-pages`, folder: `/(root)`
4. Save — your portal will be at `https://<org>.github.io/<repo>/`

---

## Deploying an application

### Manual deploy (recommended first run)

1. Go to **Actions → Ops — Deploy Backend (GAE)**
2. Click **Run workflow**
3. Fill in:
   - `manifest_name`: e.g. `backend`
   - `target_environment`: `stage` or `prod`
   - `tag_name`: leave blank for latest auto-resolved tag
4. For `prod`: a **review card** appears — only `release-managers` can approve

### Automated deploy (after PR merge)

Application repos call `reusable-ci-tag-publish.yml` via `examples/app-cd.yml`. When a PR merges to `stage`:
1. A `v1.x.x-beta.N` tag is created automatically
2. A `repository_dispatch` fires to this repo with `event_type: Trigger-Deploy-Backend`
3. `ops-deploy-backend.yml` picks it up and deploys to `stage` with no approval gate

### "Latest" tag resolution

When `tag_name` is omitted or set to `latest`, `resolve-git-ref` queries the source repository:
- `stage` branch → latest `v*-beta.*` tag
- `main` branch → latest stable `v*.*.*` tag (no pre-release suffix)

---

## Application repo CI/CD integration

Copy two files from `examples/` into your app repo:

```yaml
# .github/workflows/ci.yml  (from examples/app-ci.yml)
# .github/workflows/cd.yml  (from examples/app-cd.yml)
```

Update `YOUR_ORG/deploy-platform` to your actual platform repo name. Then configure branch protection on both `main` and `stage` branches:

| Rule | `stage` | `main` |
|------|---------|--------|
| Require status checks | `Build check` | `Build check` |
| Required reviewers | 0 | 1 |
| Dismiss stale reviews | — | ✅ |
| Restrict push | — | deployers team only |

---

## Manifest reference

Manifests live in `config/manifests/<name>.json`. Validated against `schemas/manifest.v1.schema.json` on every PR via `ci-validate.yml`.

There is **no `layout` field**. The platform infers behavior from two optional source fields:

| `buildRoot` | `appRoot` | Behavior |
|-------------|-----------|----------|
| `.` (default) | not set | Single-app repo: install + build at root, stage from `outputPath` |
| `.` | `apps/api` | Workspace monorepo: install + build at root, stage from `apps/api/outputPath` |
| `packages/server` | not set | Nested single-app: install + build in subdirectory |

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
chmod +x scripts/validate-manifests.sh
scripts/validate-manifests.sh config/manifests/ schemas/manifest.v1.schema.json
```

---

## Doppler integration

Doppler is optional per manifest (`deploy.secrets.provider: "doppler"` enables it).

| Integration point | When | How |
|------------------|------|-----|
| **Build-time** (frontend) | Firebase deploy with `provider: doppler` | Doppler CLI wraps `npm run build`; env vars injected as `process.env` |
| **Runtime** (GAE backend) | `bundleCli: true` | Doppler binary embedded in artifact; `start.sh` calls `doppler run -- node dist/main.js` |
| **Migration** | `database.migrate: true` + Doppler | `doppler run -- npx prisma migrate deploy` |
| **Tests** | `doppler_project` input on test workflow | Maven receives `-DCONFIG_SOURCE=doppler` and service token |

Each GitHub Environment needs its own `DOPPLER_TOKEN` scoped to the project + config for that environment. Never share tokens across environments.

---

## Scheduled operations

| Schedule | Cron | What runs |
|----------|------|-----------|
| Nightly smoke tests | `0 3 * * *` | `ops-run-tests.yml` → `@smoke` tag on `tests-scheduled` env |
| Weekly regression | `0 2 * * 1` | `ops-run-tests.yml` → `@regression` tag on `tests-scheduled` env |
| Bi-weekly public site | `0 2 1,15 * *` | `ops-deploy-frontend.yml` → `frontend` to `stage-scheduled` env, then dispatches `@publicsmoke` tests |
| GCP resource cleanup | `0 17 * * 1,3,5` | `ops-gcp-cleanup.yml` → prune old GAE versions, GCS files, AR images |

All scheduled workflows bind to `*-scheduled` environments (no required reviewers — auto-approved).

---

## Access control summary

| Trigger | Target | GitHub Environment | Approval |
|---------|--------|-------------------|----------|
| `workflow_dispatch` | stage | `stage` | Optional |
| `workflow_dispatch` | prod | `prod` | **Required** |
| `repository_dispatch` | stage | `stage` | Optional |
| `schedule` | deploy | `stage-scheduled` | **Auto** |
| `schedule` | tests | `tests-scheduled` | **Auto** |
| `schedule` | prod deploy | ❌ **Blocked** | N/A |

Scheduled prod deploys are disabled in v1 — production always requires a human.

---

## Local development

```bash
# Validate all manifests
chmod +x scripts/validate-manifests.sh
scripts/validate-manifests.sh config/manifests/ schemas/manifest.v1.schema.json

# Resolve a manifest for a specific environment (outputs key=value)
chmod +x scripts/resolve-manifest.sh
scripts/resolve-manifest.sh backend stage

# Generate release notes for a tag range
chmod +x scripts/generate-release-notes.sh
scripts/generate-release-notes.sh v1.2.3 v1.2.2..v1.2.3
```

---

## What was intentionally removed

| Removed | Reason |
|---------|--------|
| `ops-main/` + `templates-main/` two-repo split | Replaced by this monorepo |
| `YOUR_ORG` sed script | No org-specific placeholders in v1 |
| QMetry integration | Out of scope for v1 |
| Redis ops | Out of scope |
| Mobile deploy | Out of scope |
| DAST / load tests | Out of scope |
| Auth0 sync, MongoDB ops | Out of scope |
| Ad-hoc data migrations (`migrate.yml`) | Deliberately excluded — too risky to automate |
| Legacy `_stage`/`_prod` manifest suffix pattern | Replaced by `environments` block in manifest |
