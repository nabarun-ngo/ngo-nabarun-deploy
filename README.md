# Deploy Platform

Manifest-driven CI/CD for Node.js apps on Google Cloud (App Engine and Firebase Hosting), plus Cucumber tests with Allure on GitHub Pages.

This repository is the **ops and reusable-engine** repo. Application and library repos call the reusable workflows below; operators run the ops workflows from the Actions tab.

Replace `YOUR_ORG/deploy-platform` in examples with this repository’s `owner/name`.

## Catalog

### Reusable workflows (called by other repos or by ops workflows)

| Workflow | Role | Doc |
|----------|------|-----|
| [`reusable-ci-pr-check.yml`](.github/workflows/reusable-ci-pr-check.yml) | PR install, lint, type-check, build, optional tests | [docs/workflows/reusable-ci-pr-check.md](docs/workflows/reusable-ci-pr-check.md) |
| [`reusable-ci-changeset-check.yml`](.github/workflows/reusable-ci-changeset-check.yml) | PR: require a Changeset when `packages/**` changes | [docs/workflows/reusable-ci-changeset-check.md](docs/workflows/reusable-ci-changeset-check.md) |
| [`reusable-ci-publish.yml`](.github/workflows/reusable-ci-publish.yml) | Changesets version, optional npm, optional git tags/Releases | [docs/workflows/reusable-ci-publish.md](docs/workflows/reusable-ci-publish.md) |
| [`reusable-setup-context.yml`](.github/workflows/reusable-setup-context.yml) | Normalize dispatch/schedule inputs for deploys | [docs/workflows/reusable-setup-context.md](docs/workflows/reusable-setup-context.md) |
| [`reusable-deploy-gae-node.yml`](.github/workflows/reusable-deploy-gae-node.yml) | Build, migrate, deploy Node.js to App Engine | [docs/workflows/reusable-deploy-gae-node.md](docs/workflows/reusable-deploy-gae-node.md) |
| [`reusable-deploy-firebase-node.yml`](.github/workflows/reusable-deploy-firebase-node.yml) | Build and deploy Node.js to Firebase Hosting | [docs/workflows/reusable-deploy-firebase-node.md](docs/workflows/reusable-deploy-firebase-node.md) |
| [`reusable-run-tests-allure.yml`](.github/workflows/reusable-run-tests-allure.yml) | Cucumber matrix + Allure on GitHub Pages | [docs/workflows/reusable-run-tests-allure.md](docs/workflows/reusable-run-tests-allure.md) |

### Workflows in this repository (not `workflow_call`)

| Workflow | Role | Doc |
|----------|------|-----|
| [`ci-validate.yml`](.github/workflows/ci-validate.yml) | Manifest, workflow, and shell lint on this repo | [docs/workflows/ci-validate.md](docs/workflows/ci-validate.md) |
| [`ops-deploy-backend.yml`](.github/workflows/ops-deploy-backend.yml) | Manual/dispatch deploy to App Engine | [docs/workflows/ops-deploy-backend.md](docs/workflows/ops-deploy-backend.md) |
| [`ops-deploy-frontend.yml`](.github/workflows/ops-deploy-frontend.yml) | Manual/schedule deploy to Firebase Hosting | [docs/workflows/ops-deploy-frontend.md](docs/workflows/ops-deploy-frontend.md) |
| [`ops-run-tests.yml`](.github/workflows/ops-run-tests.yml) | Manual/schedule tests | [docs/workflows/ops-run-tests.md](docs/workflows/ops-run-tests.md) |
| [`ops-publish-site.yml`](.github/workflows/ops-publish-site.yml) | Publish the docs portal to `gh-pages` | [docs/workflows/ops-publish-site.md](docs/workflows/ops-publish-site.md) |
| [`ops-gcp-ops.yml`](.github/workflows/ops-gcp-ops.yml) | Interactive GCP operations hub | [docs/workflows/ops-gcp-ops.md](docs/workflows/ops-gcp-ops.md) |
| [`ops-gcp-cleanup.yml`](.github/workflows/ops-gcp-cleanup.yml) | Scheduled GCP resource cleanup | [docs/workflows/ops-gcp-cleanup.md](docs/workflows/ops-gcp-cleanup.md) |

Client consumption examples live **in each workflow doc**, not in a separate `examples/` folder.

## Platform setup

Environments, secrets, manifests, Doppler, and schedules: [docs/platform.md](docs/platform.md).

Ops portal (GitHub Pages): [`docs/index.html`](docs/index.html).

## Debugging workflow runs

Every job starts with a **Log run context** step (or equivalent notices). Open that step for a collapsible `::group::` dump of event, ref, SHA, job name, and workflow inputs. Job summaries repeat the same facts plus outcome tables.

Secrets are never printed. Token presence is logged as `true`/`false` only (for example npm).

For runner-level debug (checkout internals, etc.), set Actions repository variable or secret `ACTIONS_STEP_DEBUG` to `true` on a single run via **Re-run jobs → Enable debug logging**.

## Composite actions

Building blocks used by the reusables (not called from app repos directly):

| Action | Purpose |
|--------|---------|
| [resolve-git-ref](.github/actions/resolve-git-ref/action.yml) | Resolve `latest` or an explicit tag (`v` prefix optional) |
| [resolve-manifest](.github/actions/resolve-manifest/action.yml) | Load a manifest for an environment |
| [resolve-deployment-environment](.github/actions/resolve-deployment-environment/action.yml) | Map trigger to GitHub Environment |
| [stage-node-artifact](.github/actions/stage-node-artifact/action.yml) | Stage the deploy bundle |
| [render-config](.github/actions/render-config/action.yml) | Render config templates |
| [publish-allure](.github/actions/publish-allure/action.yml) | Merge Allure shards, generate HTML, push `allure-report/` on `gh-pages` (`GITHUB_TOKEN`) |
