#!/usr/bin/env bash
#
# Prunes old non-serving App Engine versions for one environment.
# Used by .github/workflows/ops-gcp-cleanup.yml.
#
# Required environment:
#   GCP_PROJECT_ID  Target project (environment secret).
#   KEEP_VERSIONS   Versions retained per service.
#   DRY_RUN         "true" reports without deleting.
#   TARGET_ENV      Environment name, used in the report heading.
#
# Appends to cleanup-summary.md and writes gae_deleted to $GITHUB_OUTPUT.

set -euo pipefail

echo "## GAE Version Cleanup ($TARGET_ENV)" >> cleanup-summary.md

# List all services
SERVICES=$(gcloud app services list \
  --project="$GCP_PROJECT_ID" \
  --format='value(id)' 2>/dev/null || echo "")

if [[ -z "$SERVICES" ]]; then
  echo "_No App Engine services found._" >> cleanup-summary.md
  exit 0
fi

TOTAL_DELETED=0

while IFS= read -r SERVICE; do
  [[ -z "$SERVICE" ]] && continue

  # Get versions sorted by creation time (newest first)
  VERSIONS=$(gcloud app versions list \
    --service="$SERVICE" \
    --project="$GCP_PROJECT_ID" \
    --format='value(id,TRAFFIC_SPLIT,SERVING_STATUS)' \
    --sort-by='~creationTime' 2>/dev/null || echo "")

  # Keep first N serving versions, collect rest for deletion
  SERVING_COUNT=0
  TO_DELETE=()

  while IFS=$'\t' read -r VID _ STATUS; do
    [[ -z "$VID" ]] && continue
    if [[ "$STATUS" == "SERVING" || ( "$SERVING_COUNT" -lt "$KEEP_VERSIONS" ) ]]; then
      (( ++SERVING_COUNT ))
    else
      TO_DELETE+=("$VID")
    fi
  done <<< "$VERSIONS"

  if [[ ${#TO_DELETE[@]} -eq 0 ]]; then
    echo "| $SERVICE | No versions to prune (${SERVING_COUNT} active) |" >> cleanup-summary.md
    continue
  fi

  DELETE_LIST=$(printf '%s\n' "${TO_DELETE[@]}" | tr '\n' ' ')
  echo "| $SERVICE | Pruning ${#TO_DELETE[@]} version(s): $DELETE_LIST |" >> cleanup-summary.md

  if [[ "$DRY_RUN" == "false" ]]; then
    gcloud app versions delete "${TO_DELETE[@]}" \
      --service="$SERVICE" \
      --project="$GCP_PROJECT_ID" \
      --quiet || echo "::warning::Some versions could not be deleted in $SERVICE"
    TOTAL_DELETED=$(( TOTAL_DELETED + ${#TO_DELETE[@]} ))
  fi
done <<< "$SERVICES"

echo "gae_deleted=$TOTAL_DELETED" >> "$GITHUB_OUTPUT"
