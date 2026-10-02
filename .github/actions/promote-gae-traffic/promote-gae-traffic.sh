#!/usr/bin/env bash
#
# Sends all service traffic to one App Engine version.
# Step body for .github/actions/promote-gae-traffic/action.yml.
#
# Required environment:
#   GCP_PROJECT_ID, VERSION_ID, GAE_SERVICE
#
# Writes deploy_url to $GITHUB_OUTPUT.

set -euo pipefail

gcloud app services set-traffic "$GAE_SERVICE" \
  --splits "$VERSION_ID=1" \
  --project="$GCP_PROJECT_ID" \
  --quiet

DEPLOY_URL="https://${GAE_SERVICE}-dot-${GCP_PROJECT_ID}.uc.r.appspot.com"
{
  echo "deploy_url=$DEPLOY_URL"
} >> "$GITHUB_OUTPUT"
echo "::notice::Traffic promoted to $VERSION_ID — $DEPLOY_URL"
