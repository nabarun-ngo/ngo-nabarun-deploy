#!/usr/bin/env bash
#
# Deploys app.yaml without promoting traffic.
# Step body for .github/actions/deploy-gae-version/action.yml.
#
# Required environment:
#   WORK_DIR, GCP_PROJECT_ID, GAE_SERVICE
#
# Writes version_id to $GITHUB_OUTPUT.

set -euo pipefail

if [[ -z "${WORK_DIR}" ]]; then
  echo "::error::working_directory is required."
  exit 1
fi
cd "$WORK_DIR" || exit 1

VERSION_ID="run-${GITHUB_RUN_ID}"
echo "::notice::Deploying version $VERSION_ID to service ${GAE_SERVICE}"

gcloud app deploy app.yaml \
  --project="$GCP_PROJECT_ID" \
  --version="$VERSION_ID" \
  --no-promote \
  --quiet

echo "version_id=$VERSION_ID" >> "$GITHUB_OUTPUT"
