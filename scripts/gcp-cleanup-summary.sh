#!/usr/bin/env bash
#
# Writes the per-environment job summary for .github/workflows/ops-gcp-cleanup.yml.
#
# Required environment:
#   TARGET_ENV   Environment name.
#   DRY_RUN      "true" adds the dry-run notice.
#   GAE_DELETED / GCS_DELETED / AR_DELETED   Step counts; blank counts as 0.

set -euo pipefail

{
  echo "## GCP Cleanup — \`${TARGET_ENV}\`"
  echo ""
  echo "| Resource | Deleted |"
  echo "|----------|---------|"
  echo "| GAE versions | ${GAE_DELETED:-0} |"
  echo "| GCS files | ${GCS_DELETED:-0} |"
  echo "| AR images | ${AR_DELETED:-0} |"
  echo ""
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "> ⚠️ **DRY RUN** — no resources were actually deleted."
  fi
} >> "$GITHUB_STEP_SUMMARY"
