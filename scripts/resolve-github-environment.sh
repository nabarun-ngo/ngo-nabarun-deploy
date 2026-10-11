#!/usr/bin/env bash
#
# Prints the GitHub Environment a manifest declares for one logical environment.
# Used by ops workflows that have no manifest job of their own (GCP ops, cleanup).
#
# Usage: resolve-github-environment.sh <manifest-name> <target-environment> [manifests-dir]
# Prints environments[<target>].githubEnvironment. Requires jq.

set -euo pipefail

MANIFEST_NAME="${1:?manifest-name is required}"
TARGET_ENV="${2:?target-environment is required}"
MANIFESTS_DIR="${3:-config/manifests}"

MANIFEST_FILE="${MANIFESTS_DIR}/${MANIFEST_NAME}.json"

if [[ ! -f "$MANIFEST_FILE" ]]; then
  echo "::error::Manifest '$MANIFEST_NAME' not found at $MANIFEST_FILE" >&2
  exit 1
fi

GH_ENV=$(jq -r --arg e "$TARGET_ENV" '.environments[$e].githubEnvironment // empty' "$MANIFEST_FILE")

if [[ -z "$GH_ENV" ]]; then
  echo "::error::Manifest '$MANIFEST_NAME' has no environments.${TARGET_ENV}.githubEnvironment" >&2
  exit 1
fi

echo "$GH_ENV"
