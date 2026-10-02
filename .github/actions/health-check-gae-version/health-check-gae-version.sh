#!/usr/bin/env bash
#
# Polls a new App Engine version until it returns HTTP 200.
# Step body for .github/actions/health-check-gae-version/action.yml.
#
# Required environment:
#   GCP_PROJECT_ID, VERSION_ID, GAE_SERVICE, HC_TIMEOUT
# Optional environment:
#   HC_PATH, HC_URL_OVERRIDE
#
# A version URL that cannot be determined skips the check. The caller
# decides whether this step runs at all.

set -euo pipefail

HTTP_STATUS="000"

if [[ -n "${HC_URL_OVERRIDE}" ]]; then
  HC_URL="$HC_URL_OVERRIDE"
else
  VERSION_URL=$(gcloud app versions describe "$VERSION_ID" \
    --service="$GAE_SERVICE" \
    --project="$GCP_PROJECT_ID" \
    --format='value(versionUrl)' 2>/dev/null || true)

  if [[ -z "$VERSION_URL" ]]; then
    echo "::warning::Could not determine versioned URL; skipping health check."
    exit 0
  fi

  HC_URL="${VERSION_URL}${HC_PATH}"
fi

echo "::notice::Health checking: $HC_URL (timeout ${HC_TIMEOUT}s)"

ELAPSED=0
while (( ELAPSED < HC_TIMEOUT )); do
  HTTP_STATUS=$(curl -sf -o /dev/null -w '%{http_code}' "$HC_URL" 2>/dev/null || echo "000")
  if [[ "$HTTP_STATUS" == "200" ]]; then
    echo "::notice::Health check passed (HTTP $HTTP_STATUS)"
    exit 0
  fi
  echo "Waiting for $HC_URL (HTTP $HTTP_STATUS)..."
  sleep 10
  ELAPSED=$((ELAPSED + 10))
done

echo "::error::Health check timed out after ${HC_TIMEOUT}s. Last HTTP status: $HTTP_STATUS"
exit 1
