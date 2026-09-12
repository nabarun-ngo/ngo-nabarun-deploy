# ops-deploy-frontend

Source: [`.github/workflows/ops-deploy-frontend.yml`](../../.github/workflows/ops-deploy-frontend.yml)

Thin caller for Firebase Hosting via [reusable-deploy-firebase-node](reusable-deploy-firebase-node.md).

Triggers: `workflow_dispatch`, schedule `0 2 1,15 * *` (public site to `stage-scheduled`), optional dispatch.

## How operators consume it

**Actions → Ops — Deploy Frontend (Firebase) → Run workflow**. Choose manifest, `stage`/`prod`, and tag (`latest` allowed).

Scheduled runs hard-route to the public-site manifest and stage. They do not deploy prod. They do not start [ops-run-tests](ops-run-tests.md); run tests from the Actions tab (or wait for the nightly/weekly crons).
