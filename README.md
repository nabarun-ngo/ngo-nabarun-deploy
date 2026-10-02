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
| `.github/actions/<action>/*.sh` | Composite actions and reusable workflows | `ops-*` workflows call the action with `uses: ./.github/actions/<action>`. A reusable workflow checks this repository out at `platform/` and runs `bash platform/.github/actions/<action>/<action>.sh`. |

Reusable workflows run in the caller repository. `uses: ./.github/actions/...`
is resolved before any step, so it does not see a `platform/` checkout.
`uses: ./platform/.github/actions/...` is not a valid substitute. The job
parses `GITHUB_WORKFLOW_REF` for the repository and ref, checks that
repository out at `platform/` (after any caller checkout at the workspace
root), and excludes `platform/` from the caller git tree. `TEMPLATES_TOKEN`
or another declared secret must be able to read that repository when the
caller is a different repo. `github.token` is enough when the caller is this
repository.

`reusable-ci-publish` and `reusable-ci-tag-release` copy
[`scripts/release_model.py`](scripts/release_model.py) from `platform/scripts/`
to `$RUNNER_TEMP/release-model/release_model.py` and leave the checkout in
place. `reusable-ci-changeset-check` and `reusable-ci-commit-check` still
check the templates repository out at `ext_repo`, copy the same file, and
remove that checkout because later steps only read `$RUNNER_TEMP`.

Most of those steps call `release_model.py` as a command
(`python3 "$RUNNER_TEMP/release-model/release_model.py" <command> ...`).
`create-tag-release.py` imports `release_model` as a module from `PYTHONPATH`
and is run as
`python3 platform/.github/actions/create-tag-release/create-tag-release.py`.
See `release_model.py`'s `build_parser()` for the command list (`plan`,
`validate-pr`, `check-pr`, `shift-prerelease`, `skip-if-published`,
`verify-dist-tag`, `assert-versions`, ...).

## Composite actions

Building blocks used by the reusables (not called from app repos directly):

| Action | Purpose |
|--------|---------|
| [decide-release-deployment](.github/actions/decide-release-deployment/action.yml) | Match a `Release-Created` event to a manifest and decide deploy or skip |
| [log-run-context](.github/actions/log-run-context/action.yml) | Print run context and a step summary |
| [stage-version-command](.github/actions/stage-version-command/action.yml) | Stage the Changesets version script |
| [inspect-pending-changesets](.github/actions/inspect-pending-changesets/action.yml) | Count pending changeset files |
| [configure-changesets-prerelease](.github/actions/configure-changesets-prerelease/action.yml) | Enter or exit Changesets prerelease mode |
| [open-version-packages-pr](.github/actions/open-version-packages-pr/action.yml) | Open the Version Packages pull request after a prerelease exit |
| [decide-publish-ready](.github/actions/decide-publish-ready/action.yml) | Decide whether versions are already in git and safe to publish |
| [publish-npm-packages](.github/actions/publish-npm-packages/action.yml) | Publish with the stable or prerelease command |
| [publish-release-event](.github/actions/publish-release-event/action.yml) | Validate a bare semver tag and publish the release fact |
| [run-database-migration](.github/actions/run-database-migration/action.yml) | Run the migration command, through Doppler when the bundle has it |
| [inject-doppler-token](.github/actions/inject-doppler-token/action.yml) | Write the Doppler token into the ephemeral app.yaml |
| [deploy-gae-version](.github/actions/deploy-gae-version/action.yml) | Deploy App Engine with `--no-promote` |
| [health-check-gae-version](.github/actions/health-check-gae-version/action.yml) | Poll the new version until it returns HTTP 200 |
| [promote-gae-traffic](.github/actions/promote-gae-traffic/action.yml) | Send all service traffic to the new version |
| [resolve-workflow-context](.github/actions/resolve-workflow-context/action.yml) | Resolve trigger, manifest, environment, and tag |
| [discover-test-features](.github/actions/discover-test-features/action.yml) | Count feature files and build the shard matrix |
| [run-cucumber-shard](.github/actions/run-cucumber-shard/action.yml) | Run one Cucumber shard, with Doppler when configured |
| [parse-allure-summary](.github/actions/parse-allure-summary/action.yml) | Read Allure summary counts |
| [evaluate-test-gate](.github/actions/evaluate-test-gate/action.yml) | Fail the run unless the test counts are clean |
| [upload-npm-logs](.github/actions/upload-npm-logs/action.yml) | Collect npm debug logs on failure and upload them |
| [resolve-git-ref](.github/actions/resolve-git-ref/action.yml) | Resolve `latest` or an explicit tag (`v` prefix optional) |
| [resolve-manifest](.github/actions/resolve-manifest/action.yml) | Load a manifest for an environment |
| [resolve-deployment-environment](.github/actions/resolve-deployment-environment/action.yml) | Map trigger to GitHub Environment |
| [stage-node-artifact](.github/actions/stage-node-artifact/action.yml) | Stage the deploy bundle |
| [render-config](.github/actions/render-config/action.yml) | Render config templates |
| [publish-allure](.github/actions/publish-allure/action.yml) | Merge Allure shards, generate HTML, push `allure-report/` on `gh-pages` (`GITHUB_TOKEN`) |
