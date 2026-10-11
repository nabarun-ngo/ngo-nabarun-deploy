---
name: evaluate-deploy-project
description: Reviews changes to the deploy platform for workflow correctness, compatibility, operational safety, and deployment confidence. Use when evaluating deploy manifests, GitHub Actions workflows, schedules, environment routing, reusable actions, deployment scripts, or changes in the deploy project.
---

# Evaluate Deploy Project

Perform a read-only senior DevOps review unless the user explicitly requests fixes.

## Review scope

Review the complete deploy change set, including:

- `.github/workflows/`
- `.github/actions/`
- `config/manifests/`
- `config/schedules/`
- `config/platforms/`
- `schemas/`
- `scripts/`
- Relevant documentation and application-repository contracts

Determine the comparison base from Git. Review tracked, staged, and untracked files. Do not assume that only the currently open file changed.

## Evaluation workflow

1. Inspect repository status, diff statistics, changed paths, branch, and available comparison base.
2. Separate changes into:
   - Technical defects
   - Intentional behavior changes
   - External rollout prerequisites
   - Documentation-only changes
3. Trace each functional change end to end:
   - Trigger
   - Input or schedule resolution
   - Manifest parsing
   - GitHub Environment selection
   - Secret availability
   - Source-ref resolution
   - Build and artifact staging
   - Migration, deployment, health check, and promotion
4. Compare changed contracts with the frontend, backend, test, and toolkit repositories when applicable.
5. Run the strongest available local validation without installing unrequested dependencies or making network calls.
6. Report only evidence-backed findings. Do not classify an intentional behavior change as a defect unless its implementation is technically unsafe or inconsistent.

## Required checks

### GitHub Actions

- Trigger additions and removals, including dispatch payload compatibility
- Reusable workflow input, output, secret, and permission contracts
- Job dependency and output propagation
- Environment-secret timing and environment protection behavior
- Expression validity, matrix shape, concurrency, and conditional execution
- External repository checkout authentication and explicit checkout paths
- Action version pinning consistent with repository policy

### Manifests and schedules

- JSON syntax and schema compatibility
- Manifest names, source repositories, branches, build roots, app roots, and output paths
- Build commands against application `package.json` workspace names
- Schedule cron uniqueness and agreement with workflow cron declarations
- Scheduled target, tag, manifest, and GitHub Environment routing
- Manual and scheduled environment mappings

### Deployment behavior

- Firebase site and template selection
- PWA/service-worker cache behavior
- App Engine bundle contents and `.gcloudignore` effects
- Database migration ordering and required files
- Health checks before traffic promotion
- Doppler project/config/token alignment
- PAT requirements for private cross-repository checkouts

### Rollout safety

Treat these as prerequisites unless code proves they are defective:

- GitHub Environments exist with exact configured names
- Required reviewers and branch restrictions are configured
- Environment secrets are copied to newly introduced environments
- Doppler projects/configs and scoped tokens exist
- External callers are updated for intentionally removed triggers

Call out that GitHub may create a missing environment without its intended protection or secrets.

## Validation

Run applicable repository checks:

```bash
python3 scripts/test_workflow_guardrails.py
python3 .github/actions/release-model/test_release_model.py
python3 .github/actions/release-model/test_action.py
python3 .github/actions/release-model/test_staging.py
python3 scripts/validate-workflow-guardrails.py
scripts/validate-manifests.sh config/manifests/ schemas/manifest.v1.schema.json
check-jsonschema --schemafile schemas/schedules.v1.schema.json config/schedules/*.json
actionlint -color .github/workflows/*.yml
shellcheck --severity=warning scripts/*.sh .github/actions/**/*.sh
git diff --check
```

If a tool is unavailable, state that clearly. Do not present a syntax-only JSON check as full schema validation. Distinguish pre-existing or non-CI test failures from regressions caused by the reviewed diff.

## Finding standard

Every technical finding must include:

- Severity: Critical, High, Medium, or Low
- Affected file and lines
- Concrete failure scenario
- Existing functionality affected
- Recommended correction or verification

Do not report:

- Intended changes merely because they alter behavior
- Hypothetical failures without a plausible execution path
- Style preferences without operational impact
- Existing unrelated defects as regressions

## Confidence score

Provide two scores when external configuration cannot be inspected:

- **Implementation confidence**: likelihood that the code and workflow logic operate correctly
- **Rollout confidence**: likelihood that deployment succeeds with the current external environments, secrets, permissions, and provider configuration

Base confidence on validation coverage:

- 90–100%: full local checks and representative workflow/deployment evidence pass
- 75–89%: logic is consistent and core checks pass, but no real deployment was exercised
- 50–74%: important tools or external prerequisites remain unverified
- Below 50%: known blockers or failing core validation

Never use 100% without successful representative deployment evidence.

## Report format

Lead with one verdict:

- Approved
- Approved with prerequisites
- Changes requested

Then provide:

1. Technical findings, ordered by severity
2. Intentional behavior changes
3. External prerequisites
4. Validation performed and validation gaps
5. Implementation and rollout confidence scores

If there are no technical findings, say so directly. Do not invent a blocker to fill the report.
