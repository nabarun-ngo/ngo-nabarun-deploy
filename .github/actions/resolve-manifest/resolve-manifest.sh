#!/usr/bin/env bash
#
# Loads one manifest and emits its fields as step outputs.
# Step body for .github/actions/resolve-manifest/action.yml.
#
# Required environment:
#   MANIFEST_NAME  Manifest filename without .json, under config/manifests/.
#   TARGET_ENV     Key inside the manifest's environments block.
#
# Reads config/manifests/ relative to the workspace, so the caller must have
# checked out this repository first. Writes the flat field set to $GITHUB_OUTPUT.

set -euo pipefail

MANIFEST_FILE="config/manifests/${MANIFEST_NAME}.json"

if [[ ! -f "$MANIFEST_FILE" ]]; then
  echo "::error::Manifest file not found: $MANIFEST_FILE"
  echo "::error::Available manifests:"
  ls config/manifests/ | sed 's/\.json//' | while read -r m; do echo "  - $m"; done
  exit 1
fi

MANIFEST=$(cat "$MANIFEST_FILE")

# Validate apiVersion
API_VERSION=$(echo "$MANIFEST" | jq -r '.apiVersion // empty')
if [[ "$API_VERSION" != "deploy.platform/v1" ]]; then
  echo "::error::Invalid apiVersion: '$API_VERSION'. Expected 'deploy.platform/v1'."
  exit 1
fi

# Validate target environment exists
ENV_BLOCK=$(echo "$MANIFEST" | jq -r --arg env "$TARGET_ENV" '.environments[$env] // empty')
if [[ -z "$ENV_BLOCK" ]]; then
  AVAILABLE=$(echo "$MANIFEST" | jq -r '.environments | keys | join(", ")')
  echo "::error::Environment '$TARGET_ENV' not found in manifest. Available: $AVAILABLE"
  exit 1
fi

# --- Extract flat outputs ---
APP_NAME=$(echo "$MANIFEST"    | jq -r '.metadata.name')
REPOSITORY=$(echo "$MANIFEST"  | jq -r '.source.repository')
BUILD_ROOT=$(echo "$MANIFEST"  | jq -r '.source.buildRoot // "."')
APP_ROOT=$(echo "$MANIFEST"    | jq -r '.source.appRoot // ""')
WS_PKG=$(echo "$MANIFEST"      | jq -r '.source.workspacePackages // ""')

NODE_VERSION=$(echo "$MANIFEST" | jq -r '.build.nodeVersion // "20"')
INSTALL_CMD=$(echo "$MANIFEST"  | jq -r '.build.install // "npm ci"')
BUILD_CMD=$(echo "$MANIFEST"    | jq -r '.build.command')
OUTPUT_PATH=$(echo "$MANIFEST"  | jq -r '.build.outputPath // "dist"')
BUNDLE_INC=$(echo "$MANIFEST"   | jq -r '.build.bundleIncludes // [] | join(",")')

PLATFORM=$(echo "$MANIFEST"     | jq -r '.deploy.platform')
CFG_TPL=$(echo "$MANIFEST"      | jq -r '.deploy.configTemplate // ""')
SVC_KEY=$(echo "$MANIFEST"      | jq -r '.deploy.serviceKey // ""')

# Resolve GAE service name via serviceKey indirection
TARGET_SERVICE=""
if [[ -n "$SVC_KEY" ]]; then
  TARGET_SERVICE=$(echo "$ENV_BLOCK" | jq -r --arg key "$SVC_KEY" '.[$key] // ""')
fi

SOURCE_REF=$(echo "$ENV_BLOCK"      | jq -r '.sourceRef')
DB_MIGRATE=$(echo "$MANIFEST"       | jq -r '.database.migrate // false')
DB_CMD=$(echo "$MANIFEST"           | jq -r '.database.command // ""')
HC_ENABLED=$(echo "$MANIFEST"       | jq -r '.healthCheck.enabled // false')
HC_PATH=$(echo "$MANIFEST"          | jq -r '.healthCheck.path // "/health"')
HC_URL=$(echo "$ENV_BLOCK"          | jq -r '.healthCheckUrl // ""')

SECRETS_PROVIDER=$(echo "$MANIFEST"  | jq -r '.deploy.secrets.provider // "none"')
DOPPLER_PROJECT=$(echo "$MANIFEST"   | jq -r '.deploy.secrets.project // ""')
DOPPLER_BUNDLE=$(echo "$MANIFEST"    | jq -r '.deploy.secrets.bundleCli // false')
DOPPLER_CONFIG=$(echo "$ENV_BLOCK"   | jq -r '.secrets.config // ""')

# Emit outputs
{
  echo "app_name=$APP_NAME"
  echo "repository=$REPOSITORY"
  echo "build_root=$BUILD_ROOT"
  echo "app_root=$APP_ROOT"
  echo "workspace_packages=$WS_PKG"
  echo "node_version=$NODE_VERSION"
  echo "install_command=$INSTALL_CMD"
  echo "build_command=$BUILD_CMD"
  echo "output_path=$OUTPUT_PATH"
  echo "bundle_includes=$BUNDLE_INC"
  echo "platform=$PLATFORM"
  echo "config_template=$CFG_TPL"
  echo "service_key=$SVC_KEY"
  echo "gae_service=$TARGET_SERVICE"
  echo "target_service=$TARGET_SERVICE"
  echo "source_ref=$SOURCE_REF"
  echo "db_migrate=$DB_MIGRATE"
  echo "db_command=$DB_CMD"
  echo "health_check_enabled=$HC_ENABLED"
  echo "health_check_path=$HC_PATH"
  echo "health_check_url=$HC_URL"
  echo "secrets_provider=$SECRETS_PROVIDER"
  echo "doppler_project=$DOPPLER_PROJECT"
  echo "doppler_bundle_cli=$DOPPLER_BUNDLE"
  echo "doppler_config=$DOPPLER_CONFIG"
  # Emit full manifest for audit (single-line JSON)
  printf "manifest_json=%s\n" "$(echo "$MANIFEST" | jq -c .)"
} >> "$GITHUB_OUTPUT"

echo "::notice::Manifest '$MANIFEST_NAME' resolved for environment '$TARGET_ENV' (platform: $PLATFORM)"
