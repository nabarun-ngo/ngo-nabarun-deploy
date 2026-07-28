#!/usr/bin/env bash
# resolve-manifest.sh
# Usage: resolve-manifest.sh <manifest-name> <target-environment> [manifests-dir]
# Outputs flat key=value pairs for all manifest fields resolved for the given environment.
# Consumed by the resolve-manifest composite action.
# Requires: jq

set -euo pipefail

MANIFEST_NAME="${1:?manifest-name is required}"
TARGET_ENV="${2:?target-environment is required}"
MANIFESTS_DIR="${3:-config/manifests}"

MANIFEST_FILE="${MANIFESTS_DIR}/${MANIFEST_NAME}.json"

if [[ ! -f "$MANIFEST_FILE" ]]; then
  echo "ERROR: Manifest '$MANIFEST_NAME' not found at $MANIFEST_FILE" >&2
  echo "Available:" >&2
  ls "$MANIFESTS_DIR" | sed 's/\.json//' | while read m; do echo "  $m" >&2; done
  exit 1
fi

MANIFEST=$(cat "$MANIFEST_FILE")
ENV_BLOCK=$(echo "$MANIFEST" | jq -r --arg e "$TARGET_ENV" '.environments[$e] // empty')

if [[ -z "$ENV_BLOCK" ]]; then
  AVAIL=$(echo "$MANIFEST" | jq -r '.environments | keys | join(", ")')
  echo "ERROR: Environment '$TARGET_ENV' not found. Available: $AVAIL" >&2
  exit 1
fi

SERVICE_KEY=$(echo "$MANIFEST" | jq -r '.deploy.serviceKey // ""')
GAE_SERVICE=""
if [[ -n "$SERVICE_KEY" ]]; then
  GAE_SERVICE=$(echo "$ENV_BLOCK" | jq -r --arg k "$SERVICE_KEY" '.[$k] // ""')
fi

echo "app_name=$(echo "$MANIFEST" | jq -r '.metadata.name')"
echo "repository=$(echo "$MANIFEST" | jq -r '.source.repository')"
echo "build_root=$(echo "$MANIFEST" | jq -r '.source.buildRoot // "."')"
echo "app_root=$(echo "$MANIFEST" | jq -r '.source.appRoot // ""')"
echo "workspace_packages=$(echo "$MANIFEST" | jq -r '.source.workspacePackages // ""')"
echo "node_version=$(echo "$MANIFEST" | jq -r '.build.nodeVersion // "20"')"
echo "install_command=$(echo "$MANIFEST" | jq -r '.build.install // "npm ci"')"
echo "build_command=$(echo "$MANIFEST" | jq -r '.build.command')"
echo "output_path=$(echo "$MANIFEST" | jq -r '.build.outputPath // "dist"')"
echo "bundle_includes=$(echo "$MANIFEST" | jq -r '.build.bundleIncludes // [] | join(",")')"
echo "platform=$(echo "$MANIFEST" | jq -r '.deploy.platform')"
echo "config_template=$(echo "$MANIFEST" | jq -r '.deploy.configTemplate // ""')"
echo "service_key=$SERVICE_KEY"
echo "gae_service=$GAE_SERVICE"
echo "source_ref=$(echo "$ENV_BLOCK" | jq -r '.sourceRef')"
echo "db_migrate=$(echo "$MANIFEST" | jq -r '.database.migrate // false')"
echo "db_command=$(echo "$MANIFEST" | jq -r '.database.command // ""')"
echo "health_check_enabled=$(echo "$MANIFEST" | jq -r '.healthCheck.enabled // false')"
echo "health_check_path=$(echo "$MANIFEST" | jq -r '.healthCheck.path // "/health"')"
echo "health_check_url=$(echo "$ENV_BLOCK" | jq -r '.healthCheckUrl // ""')"
echo "secrets_provider=$(echo "$MANIFEST" | jq -r '.deploy.secrets.provider // "none"')"
echo "doppler_project=$(echo "$MANIFEST" | jq -r '.deploy.secrets.project // ""')"
echo "doppler_bundle_cli=$(echo "$MANIFEST" | jq -r '.deploy.secrets.bundleCli // false')"
echo "doppler_config=$(echo "$ENV_BLOCK" | jq -r '.secrets.config // ""')"
