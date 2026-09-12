# ci-validate

Source: [`.github/workflows/ci-validate.yml`](../../.github/workflows/ci-validate.yml)

CI **for this repository**. Validates manifests (`schemas/manifest.v1.schema.json`) and schedule files (`config/schedules/*.json` against `schemas/schedules.v1.schema.json`), lints workflow YAML (actionlint when available), and shellchecks `scripts/`.

## Who calls it

GitHub Actions on pull_request / push to `main` when manifest, schedule, schema, script, workflow, or action paths change. Other repos do not call this.

## How to consume

No `uses:` from clients. Open a PR against this repo; the **Validate manifests** (and related) jobs must pass.

```bash
scripts/validate-manifests.sh config/manifests/ schemas/manifest.v1.schema.json
check-jsonschema --schemafile schemas/schedules.v1.schema.json config/schedules/tests.json
```
