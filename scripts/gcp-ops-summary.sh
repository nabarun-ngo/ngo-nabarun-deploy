#!/usr/bin/env bash
#
# Writes the job summary for .github/workflows/ops-gcp-ops.yml.
#
# Required environment:
#   OPERATION / TARGET_ENV / SERVICE_NAME / DRY_RUN   Dispatch inputs.
#   RESULT_SUMMARY / ARTIFACT_NAME / EXECUTE_RESULT   Outputs of the execute job.

set -euo pipefail

GCP_CONSOLE_BASE="https://console.cloud.google.com"
{
  echo "## GCP Operations Hub"
  echo ""
  echo "| Field | Value |"
  echo "|-------|-------|"
  echo "| Operation | \`${OPERATION}\` |"
  echo "| Environment | \`${TARGET_ENV}\` |"
  echo "| Service | \`${SERVICE_NAME}\` |"
  echo "| Dry run | ${DRY_RUN} |"
  echo "| Result | ${RESULT_SUMMARY} |"
  echo "| Status | ${EXECUTE_RESULT} |"
  echo ""
  echo "### GCP Console Links"
  echo ""
  echo "- [App Engine Versions](${GCP_CONSOLE_BASE}/appengine/versions)"
  echo "- [Cloud Logging](${GCP_CONSOLE_BASE}/logs/query)"
  echo "- [Artifact Registry](${GCP_CONSOLE_BASE}/artifacts)"
  echo "- [GCS Browser](${GCP_CONSOLE_BASE}/storage/browser)"
  echo ""
  if [[ -n "$ARTIFACT_NAME" ]]; then
    echo "> Detailed report available as a workflow artifact: \`${ARTIFACT_NAME}\`"
  fi
} >> "$GITHUB_STEP_SUMMARY"
