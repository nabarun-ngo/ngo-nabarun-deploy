#!/usr/bin/env bash
# validate-manifests.sh
# Usage: validate-manifests.sh <manifests-dir> <schema-file>
# Validates all *.json files in the manifests directory against the v1 schema.
# Requires: jq
# Optional: check-jsonschema (pip install check-jsonschema) — enables full JSON Schema Draft-07 validation.
# Exits non-zero if any manifest fails validation.

set -euo pipefail

MANIFESTS_DIR="${1:-config/manifests}"
SCHEMA_FILE="${2:-schemas/manifest.v1.schema.json}"

if ! command -v jq &>/dev/null; then
  echo "::error::jq is required but not installed."
  echo "  Install: sudo apt-get install -y jq (Linux) or brew install jq (macOS)"
  exit 1
fi

if [[ ! -d "$MANIFESTS_DIR" ]]; then
  echo "::error::Manifests directory not found: $MANIFESTS_DIR"
  exit 1
fi

if [[ ! -f "$SCHEMA_FILE" ]]; then
  echo "::error::Schema file not found: $SCHEMA_FILE"
  exit 1
fi

SCHEMA_VALIDATOR=""
if command -v check-jsonschema &>/dev/null; then
  SCHEMA_VALIDATOR="check-jsonschema"
  echo "::notice::check-jsonschema available — full JSON Schema Draft-07 validation enabled"
else
  echo "::warning::check-jsonschema not found — schema validation is jq-rules only. Install: pip install check-jsonschema"
fi

PASS=0
FAIL=0
ERRORS=()

echo "Validating manifests in $MANIFESTS_DIR against $SCHEMA_FILE..."
echo ""

for MANIFEST_FILE in "$MANIFESTS_DIR"/*.json; do
  [[ -f "$MANIFEST_FILE" ]] || continue

  MANIFEST_NAME=$(basename "$MANIFEST_FILE" .json)

  VALIDATION_ERRORS=()

  # 1. Valid JSON
  if ! jq empty "$MANIFEST_FILE" 2>/dev/null; then
    VALIDATION_ERRORS+=("Invalid JSON syntax")
    FAIL=$(( FAIL + 1 ))
    ERRORS+=("$MANIFEST_NAME: Invalid JSON")
    echo "❌ $MANIFEST_NAME"
    printf '   - %s\n' "${VALIDATION_ERRORS[@]}"
    continue
  fi

  # 1b. Full JSON Schema validation via check-jsonschema (when available)
  if [[ -n "$SCHEMA_VALIDATOR" ]]; then
    SCHEMA_OUTPUT=$(check-jsonschema --schemafile "$SCHEMA_FILE" "$MANIFEST_FILE" 2>&1)
    if [[ $? -ne 0 ]]; then
      SCHEMA_ERRORS=$(echo "$SCHEMA_OUTPUT" | grep -v '^ok' | head -10)
      VALIDATION_ERRORS+=("JSON Schema validation failed: $SCHEMA_ERRORS")
    fi
  fi

  # 2. apiVersion
  API_VERSION=$(jq -r '.apiVersion // empty' "$MANIFEST_FILE")
  if [[ "$API_VERSION" != "deploy.platform/v1" ]]; then
    VALIDATION_ERRORS+=("apiVersion must be 'deploy.platform/v1', got '$API_VERSION'")
  fi

  # 3. kind
  KIND=$(jq -r '.kind // empty' "$MANIFEST_FILE")
  if [[ "$KIND" != "Application" ]]; then
    VALIDATION_ERRORS+=("kind must be 'Application', got '$KIND'")
  fi

  # 4. metadata.name: required, lowercase alphanumeric + hyphen, 2-63 chars
  APP_NAME=$(jq -r '.metadata.name // empty' "$MANIFEST_FILE")
  if [[ -z "$APP_NAME" ]]; then
    VALIDATION_ERRORS+=("metadata.name is required")
  elif ! echo "$APP_NAME" | grep -qE '^[a-z][a-z0-9-]{1,62}$'; then
    VALIDATION_ERRORS+=("metadata.name '$APP_NAME' must match ^[a-z][a-z0-9-]{1,62}$")
  fi

  # 5. source.repository must match org/repo
  REPO=$(jq -r '.source.repository // empty' "$MANIFEST_FILE")
  if [[ -z "$REPO" ]]; then
    VALIDATION_ERRORS+=("source.repository is required")
  elif ! echo "$REPO" | grep -qE '^[^/]+/[^/]+$'; then
    VALIDATION_ERRORS+=("source.repository '$REPO' must be in org/repo format")
  fi

  # 6. build.command required
  BUILD_CMD=$(jq -r '.build.command // empty' "$MANIFEST_FILE")
  if [[ -z "$BUILD_CMD" ]]; then
    VALIDATION_ERRORS+=("build.command is required")
  fi

  # 7. build.runtime must be 'node' in v1
  RUNTIME=$(jq -r '.build.runtime // empty' "$MANIFEST_FILE")
  if [[ "$RUNTIME" != "node" ]]; then
    VALIDATION_ERRORS+=("build.runtime must be 'node' in v1, got '$RUNTIME'")
  fi

  # 8. deploy.platform must be gae|firebase
  PLATFORM=$(jq -r '.deploy.platform // empty' "$MANIFEST_FILE")
  if [[ "$PLATFORM" != "gae" && "$PLATFORM" != "firebase" ]]; then
    VALIDATION_ERRORS+=("deploy.platform must be 'gae' or 'firebase', got '$PLATFORM'")
  fi

  # 9. environments: at least one entry with sourceRef
  ENV_COUNT=$(jq '.environments | length' "$MANIFEST_FILE" 2>/dev/null || echo 0)
  if [[ "$ENV_COUNT" -lt 1 ]]; then
    VALIDATION_ERRORS+=("environments block must define at least one environment")
  else
    # Verify each environment has sourceRef
    jq -r '.environments | to_entries[] | select(.value.sourceRef == null or .value.sourceRef == "") | .key' \
      "$MANIFEST_FILE" | while read ENV_KEY; do
      echo "  Missing sourceRef in environments.$ENV_KEY"
    done | while read MSG; do
      VALIDATION_ERRORS+=("$MSG")
    done || true
  fi

  # 10. Doppler: if provider==doppler, project is required
  SECRETS_PROVIDER=$(jq -r '.deploy.secrets.provider // "none"' "$MANIFEST_FILE")
  if [[ "$SECRETS_PROVIDER" == "doppler" ]]; then
    DOPPLER_PROJECT=$(jq -r '.deploy.secrets.project // empty' "$MANIFEST_FILE")
    if [[ -z "$DOPPLER_PROJECT" ]]; then
      VALIDATION_ERRORS+=("deploy.secrets.project is required when provider is 'doppler'")
    fi
  fi

  # 11. DB migration: if migrate==true, command is required
  DB_MIGRATE=$(jq -r '.database.migrate // false' "$MANIFEST_FILE")
  if [[ "$DB_MIGRATE" == "true" ]]; then
    DB_CMD=$(jq -r '.database.command // empty' "$MANIFEST_FILE")
    if [[ -z "$DB_CMD" ]]; then
      VALIDATION_ERRORS+=("database.command is required when database.migrate is true")
    fi
  fi

  # ── Report result ──
  if [[ ${#VALIDATION_ERRORS[@]} -eq 0 ]]; then
    PASS=$(( PASS + 1 ))
    echo "✅ $MANIFEST_NAME ($APP_NAME | $PLATFORM | envs: $ENV_COUNT)"
  else
    FAIL=$(( FAIL + 1 ))
    echo "❌ $MANIFEST_NAME"
    printf '   - %s\n' "${VALIDATION_ERRORS[@]}"
    ERRORS+=("$MANIFEST_NAME")
  fi
done

echo ""
echo "────────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
echo "────────────────────────────────────────"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed manifests:"
  printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi

echo ""
echo "All manifests are valid."
exit 0
