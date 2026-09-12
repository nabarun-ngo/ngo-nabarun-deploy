# ops-run-tests

Source: [`.github/workflows/ops-run-tests.yml`](../../.github/workflows/ops-run-tests.yml)

Thin caller for [reusable-run-tests-allure](reusable-run-tests-allure.md).

Triggers: `workflow_dispatch` and nightly/weekly schedules (`0 3 * * *` smoke, `0 2 * * 1` regression). There is no `repository_dispatch` and no post-deploy hook from [ops-deploy-frontend](ops-deploy-frontend.md).

| Trigger | Target | GitHub Environment | Approval |
|---------|--------|-------------------|----------|
| Manual | stage | `stage` | Optional |
| Manual | prod | `prod` | Required (parallelism forced to 1) |
| Cron | `profile.environment` in `tests.json` (stage today) | `tests-scheduled` | Auto |

Cron profiles: [config/schedules/tests.json](../../config/schedules/tests.json). Doppler config names passed to Maven are `stg` (stage) and `prd` (prod).

The reusable **gate** job fails the workflow when discover/report failed, no tests were recorded, or any tests failed or broke. A green run means the suite passed, not only that a report was published.

## How operators consume it

**Actions → Ops — Run Tests**. Set Cucumber tags and `stage` or `prod`.

Set repository variable `TEST_REPOSITORY` to the automation repo (`org/repo`). Set `DOPPLER_PROJECT_TEST` to the Doppler project. `DOPPLER_TOKEN` is an **environment** secret on `stage`, `prod`, and `tests-scheduled` — the execute job reads it after binding `gh_env`. Do not rely on a repository-level token if environments must stay isolated.

`PAT` is used only to check out the test repository. Allure is pushed to `gh-pages` with `GITHUB_TOKEN`. Latest report: `https://<org>.github.io/<repo>/allure-report/` (redirects to `last-run`).
