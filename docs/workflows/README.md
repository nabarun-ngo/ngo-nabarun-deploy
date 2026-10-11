# Workflow docs

Each GitHub Actions workflow in this repository has a page here. The root [README](../../README.md) is the catalog; [platform setup](../platform.md) covers environments, secrets, manifests and schedules; the [deployment setup guide](../deployment-setup-guide.html) walks through first-time setup.

Client `uses:` samples are on the reusable-workflow pages. Operators’ run instructions are on the ops pages.

Deploys: [ops-deploy-backend](ops-deploy-backend.md) (manual only) and [ops-deploy-frontend](ops-deploy-frontend.md) (manual, plus scheduled deploys from `config/schedules/deploys.json`) call [reusable-deploy-gae-node](reusable-deploy-gae-node.md) and [reusable-deploy-firebase-node](reusable-deploy-firebase-node.md).

Tests: [ops-run-tests](ops-run-tests.md) (manual and cron) calls [reusable-run-tests-allure](reusable-run-tests-allure.md). Reports share `gh-pages` with [ops-publish-site](ops-publish-site.md).
