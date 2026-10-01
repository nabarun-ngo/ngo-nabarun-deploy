#!/usr/bin/env bash
#
# Deletes untagged Artifact Registry images across every repository.
# Used by .github/workflows/ops-gcp-cleanup.yml.
#
# Required environment:
#   GCP_PROJECT_ID  Target project (environment secret).
#   DRY_RUN         "true" reports without deleting.
#
# Appends to cleanup-summary.md and writes ar_deleted to $GITHUB_OUTPUT.

set -euo pipefail

echo "" >> cleanup-summary.md
echo "## Artifact Registry Cleanup" >> cleanup-summary.md

# List all AR repositories in the project
REPOS=$(gcloud artifacts repositories list \
  --project="$GCP_PROJECT_ID" \
  --format='value(name)' 2>/dev/null || echo "")

if [[ -z "$REPOS" ]]; then
  echo "_No Artifact Registry repositories found._" >> cleanup-summary.md
  echo "ar_deleted=0" >> "$GITHUB_OUTPUT"
  exit 0
fi

AR_DELETED=0
while IFS= read -r REPO; do
  [[ -z "$REPO" ]] && continue
  REPO_PATH="${REPO##*/repositories/}"

  UNTAGGED=$(gcloud artifacts docker images list "$REPO" \
    --project="$GCP_PROJECT_ID" \
    --filter="tags=''" \
    --format='value(IMAGE)' 2>/dev/null || echo "")

  COUNT=$(echo "$UNTAGGED" | grep -c . || echo 0)
  echo "| $REPO_PATH | Untagged images: $COUNT |" >> cleanup-summary.md

  if [[ -n "$UNTAGGED" && "$DRY_RUN" == "false" ]]; then
    echo "$UNTAGGED" | while read -r img; do
      if [[ -n "$img" ]]; then
        gcloud artifacts docker images delete "$img" \
          --project="$GCP_PROJECT_ID" \
          --delete-tags \
          --quiet 2>/dev/null || true
      fi
    done
    AR_DELETED=$(( AR_DELETED + COUNT ))
  fi
done <<< "$REPOS"

echo "ar_deleted=$AR_DELETED" >> "$GITHUB_OUTPUT"
