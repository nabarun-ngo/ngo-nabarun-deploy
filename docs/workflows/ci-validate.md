# ci-validate

Source: [`.github/workflows/ci-validate.yml`](../../.github/workflows/ci-validate.yml)

CI **for this repository**. It runs:

- the workflow guardrail tests and checks (`scripts/test_workflow_guardrails.py`, the tests under `.github/actions/release-model/`, and `scripts/validate-workflow-guardrails.py`);
- manifest validation (`config/manifests/*.json` against `schemas/manifest.v1.schema.json`);
- schedule validation (every `config/schedules/*.json`, including `tests.json` and `deploys.json`, against `schemas/schedules.v1.schema.json`);
- actionlint on `.github/workflows/*.yml`;
- shellcheck on every `*.sh` under `scripts/` and `.github/actions/`.

The guardrails include the scheduled-deploy check: every cron in an `ops-deploy-*` workflow must match exactly one entry in `config/schedules/deploys.json`, and each entry must name an existing manifest and target. See [Pipeline guardrails](../../README.md#pipeline-guardrails) for the full list.

CI does not check GitHub Environment names against what exists in GitHub.

## Who calls it

GitHub Actions on pull_request / push to `main` when manifest, schedule, schema, script, workflow, or action paths change. Other repos do not call this.

## How to consume

No `uses:` from clients. Open a PR against this repo; the **Validate manifests** (and related) jobs must pass. To run the same checks locally:

```bash
python3 scripts/test_workflow_guardrails.py
python3 .github/actions/release-model/test_release_model.py
python3 .github/actions/release-model/test_action.py
python3 .github/actions/release-model/test_staging.py
python3 scripts/validate-workflow-guardrails.py
scripts/validate-manifests.sh config/manifests/ schemas/manifest.v1.schema.json
check-jsonschema --schemafile schemas/schedules.v1.schema.json config/schedules/*.json
```
