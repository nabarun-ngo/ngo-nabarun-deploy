# reusable-run-tests-allure

Source: [`.github/workflows/reusable-run-tests-allure.yml`](../../.github/workflows/reusable-run-tests-allure.yml)

Checks out the automation repo, runs Cucumber (Maven) in a matrix, publishes an Allure report to `gh-pages` via [publish-allure](../../.github/actions/publish-allure/action.yml), then **fails** if discover/report failed, totals are zero, or any tests failed or broke.

Job order: **discover → execute (shards) → report → gate**.

Execute shards bind to a GitHub Environment when `use_gh_env` is true (default). Discover, report, and gate jobs do not. `DOPPLER_TOKEN` is read on the execute job from that environment (it is not a `workflow_call` secret). `PAT` is required for the test-repo checkout. The report job pushes with `GITHUB_TOKEN`.

The test repository must honor `-DSHARD_INDEX` / `-DTOTAL_SHARDS` if you want shards to split work. Feature files are counted only to size the matrix (`{"shard":[1,…,N]}` plus output `total_shards`). Empty `test_repository` fails discover (it must not fall back to this ops repo).

## Who calls it

[ops-run-tests](ops-run-tests.md) in this repository. The reusable uses `./.github/actions/publish-allure`, so it is not meant to be called from another repo.

## Inputs (summary)

`test_repository` (required, `org/repo`), `test_branch` (default `main`), `test_tags`, `target_environment`, `doppler_project`, `doppler_config` (`stg` / `prd`).

| Input | Default | Meaning |
|-------|---------|---------|
| `use_gh_env` | `true` | Bind execute jobs to a GitHub Environment |
| `gh_env` | empty | Environment name (required when `use_gh_env` is true) |

## Secrets

| Secret | Where | Purpose |
|--------|-------|---------|
| `PAT` | `workflow_call` | Checkout the test repository |
| `GITHUB_TOKEN` | automatic | Push Allure HTML to `gh-pages` |
| `DOPPLER_TOKEN` | GitHub Environment on execute | `doppler run` when `doppler_project` is set |

## Outputs

`report_url`, `total_tests`, `passed_tests`, `failed_tests`, `broken_tests`, `tests_passed` (`true` only if the gate succeeded).

## How operators consume it

Point `TEST_REPOSITORY` at the Cucumber repo and run **Ops — Run Tests**, or let the nightly/weekly schedules invoke [ops-run-tests](ops-run-tests.md).
