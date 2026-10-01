# Deploy Platform

Manifest-driven CI/CD for Node.js apps on Google Cloud (App Engine and Firebase Hosting), plus Cucumber tests with Allure on GitHub Pages.

This repository is the **ops and reusable-engine** repo. Application and library repos call the reusable workflows below; operators run the ops workflows from the Actions tab.

Replace `YOUR_ORG/deploy-platform` in examples with this repository’s `owner/name`.

## Catalog

### Reusable workflows (called by other repos or by ops workflows)

| Workflow | Role | Doc |
|----------|------|-----|
| [`reusable-ci-pr-check.yml`](.github/workflows/reusable-ci-pr-check.yml) | PR install, lint, type-check, build, optional tests | [docs/workflows/reusable-ci-pr-check.md](docs/workflows/reusable-ci-pr-check.md) |
| [`reusable-ci-commit-check.yml`](.github/workflows/reusable-ci-commit-check.yml) | Reject pull requests whose titles are not conventional commits | [docs/workflows/reusable-ci-commit-check.md](docs/workflows/reusable-ci-commit-check.md) |
| [`reusable-ci-changeset-check.yml`](.github/workflows/reusable-ci-changeset-check.yml) | PR: require a Changeset when `packages/**` changes | [docs/workflows/reusable-ci-changeset-check.md](docs/workflows/reusable-ci-changeset-check.md) |
| [`reusable-ci-publish.yml`](.github/workflows/reusable-ci-publish.yml) | Changesets version and optional npm publish | [docs/workflows/reusable-ci-publish.md](docs/workflows/reusable-ci-publish.md) |
| [`reusable-ci-tag-release.yml`](.github/workflows/reusable-ci-tag-release.yml) | App repos: bare semver git tag and GitHub Release | [docs/workflows/reusable-ci-tag-release.md](docs/workflows/reusable-ci-tag-release.md) |
| [`reusable-ci-release-event.yml`](.github/workflows/reusable-ci-release-event.yml) | App repos: publish a release fact to this repo | [docs/workflows/reusable-ci-release-event.md](docs/workflows/reusable-ci-release-event.md) |
| [`reusable-setup-context.yml`](.github/workflows/reusable-setup-context.yml) | Normalize dispatch/schedule inputs for deploys | [docs/workflows/reusable-setup-context.md](docs/workflows/reusable-setup-context.md) |
| [`reusable-deploy-gae-node.yml`](.github/workflows/reusable-deploy-gae-node.yml) | Build, migrate, deploy Node.js to App Engine | [docs/workflows/reusable-deploy-gae-node.md](docs/workflows/reusable-deploy-gae-node.md) |
| [`reusable-deploy-firebase-node.yml`](.github/workflows/reusable-deploy-firebase-node.yml) | Build and deploy Node.js to Firebase Hosting | [docs/workflows/reusable-deploy-firebase-node.md](docs/workflows/reusable-deploy-firebase-node.md) |
| [`reusable-run-tests-allure.yml`](.github/workflows/reusable-run-tests-allure.yml) | Cucumber matrix + Allure on GitHub Pages | [docs/workflows/reusable-run-tests-allure.md](docs/workflows/reusable-run-tests-allure.md) |

### Workflows in this repository (not `workflow_call`)

| Workflow | Role | Doc |
|----------|------|-----|
| [`ci-validate.yml`](.github/workflows/ci-validate.yml) | Manifest, workflow, and shell lint on this repo | [docs/workflows/ci-validate.md](docs/workflows/ci-validate.md) |
| [`ops-deploy-backend.yml`](.github/workflows/ops-deploy-backend.yml) | App Engine deploy (`workflow_dispatch` or `Trigger-Deploy-Backend`) | [docs/workflows/ops-deploy-backend.md](docs/workflows/ops-deploy-backend.md) |
| [`ops-deploy-frontend.yml`](.github/workflows/ops-deploy-frontend.yml) | Manual Firebase deploy; scheduled public-site stage deploy | [docs/workflows/ops-deploy-frontend.md](docs/workflows/ops-deploy-frontend.md) |
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

## Pipeline guardrails

The validation workflow enforces repository-specific safety policies in addition
to schema, workflow, and shell linting:

```bash
python3 scripts/test_workflow_guardrails.py
python3 scripts/validate-workflow-guardrails.py
```

The checks reject mutable action branches, external checkouts without a separate
path, missing workflow permissions, unresolved scheduled manifests, unsafe
post-increment under `set -e`, caller-side environment credential mapping, and
destructive cleanup that does not default to dry-run.

## Firebase config templates

| Template | Use |
|----------|-----|
| [`firebase.json.tpl`](config/platforms/firebase/firebase.json.tpl) | Static site or SPA with no service worker |
| [`firebase.pwa.json.tpl`](config/platforms/firebase/firebase.pwa.json.tpl) | SPA that ships a service worker |

Pick the PWA template for any app built with Angular's `serviceWorker` option.
The plain template marks every `.js` immutable for a year, which would pin
`ngsw-worker.js` and the registered worker in browsers that already have them —
no later release would ever reach those users.

The PWA template therefore splits the immutable rule in two and excludes the
worker filenames from the `.js` half:

```text
**/*.@(css|woff2|png|jpg|svg|ico)
**/!(combined-sw|ngsw-worker|OneSignalSDKWorker|safety-worker|worker-basic.min).js
```

Excluding them is deliberate rather than relying on a later `Cache-Control`
entry to override an earlier one, because the two approaches fail in opposite
directions. If this glob is wrong it matches nothing and the bundles merely lose
their long cache — a performance cost. If an override were wrong, the service
worker would stay pinned for a year, which is unrecoverable for already-affected
browsers. The explicit `no-cache` entries that follow are belt-and-braces, so
the headers are correct whichever way Firebase resolves overlapping rules.

Add a filename here when an app starts shipping another unhashed worker script.

## Where step bodies live

Workflow steps longer than a few lines live in script files, not in `run:` blocks,
so they can be shellchecked and read on their own.

| Location | Used by | Notes |
|----------|---------|-------|
| [`scripts/`](scripts/) | `ci-validate.yml` and the `ops-*` workflows | Run as `bash scripts/<name>.sh`. The job must check this repository out first. |
| `.github/actions/<action>/*.sh` | That composite action only | Invoked as `bash "$GITHUB_ACTION_PATH/<name>.sh"`, so it resolves wherever the action is used. |

The release workflows (`reusable-ci-publish`, `reusable-ci-tag-release`,
`reusable-ci-changeset-check`, `reusable-ci-commit-check`) run in the consumer
repository, so they cannot see this repo on their own. Each takes a required
`templates_repository` input (`owner/name`). The job checks that repo out at
`ext_repo`, copies [`scripts/release_model.py`](scripts/release_model.py) to
`$RUNNER_TEMP/release-model/release_model.py`, then deletes the checkout so it
is not scanned with the consumer's packages. `TEMPLATES_TOKEN` must be able to
read `templates_repository`. `GITHUB_TOKEN` cannot.

Most `run:` steps in those workflows call `release_model.py` directly by path
(`python3 "$RUNNER_TEMP/release-model/release_model.py" <command> ...`) instead
of embedding Python in a heredoc, so the only script that ever needs writing or
reading as a file is the one already covered by
[`scripts/test_release_model.py`](scripts/test_release_model.py). See
`release_model.py`'s `build_parser()` for the full command list (`plan`,
`validate-pr`, `check-pr`, `shift-prerelease`, `skip-if-published`,
`verify-dist-tag`, `assert-versions`, ...). The one exception is
`create-tag-release` (a composite action), whose script is resolved via
`$GITHUB_ACTION_PATH` instead of `$RUNNER_TEMP`, so it imports `release_model`
as a module over `PYTHONPATH` rather than invoking it as a CLI.

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
