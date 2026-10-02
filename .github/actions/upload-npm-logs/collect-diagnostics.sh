#!/usr/bin/env bash
#
# Collects npm debug logs and environment facts for upload.
# Step body for .github/actions/upload-npm-logs/action.yml.
#
# Runs without -e on purpose: diagnostics must survive a broken npm install.
# Does not print npm config, which can contain registry credentials.
# Writes everything under $RUNNER_TEMP/npm-debug.

set +e

ARTIFACT_DIR="${RUNNER_TEMP}/npm-debug"
NPM_CACHE="$(npm config get cache 2>/dev/null)"

mkdir -p "$ARTIFACT_DIR"

echo "=== npm diagnostics ==="

{
  echo "Runner OS: ${RUNNER_OS}"
  echo "Runner: ${RUNNER_NAME}"
  echo "Node: $(node --version 2>&1)"
  echo "npm: $(npm --version 2>&1)"
  echo "npm cache: ${NPM_CACHE}"
  echo "npm registry: $(npm config get registry 2>&1)"
  echo "Working directory: ${GITHUB_WORKSPACE}"
  echo "Repository: ${GITHUB_REPOSITORY}"
  echo "Run ID: ${GITHUB_RUN_ID}"
  echo "Run attempt: ${GITHUB_RUN_ATTEMPT}"
  echo ""
  echo "=== npm cache contents ==="
  ls -la "${NPM_CACHE}" 2>&1 || true
  echo ""
  echo "=== npm log directory ==="
  ls -la "${NPM_CACHE}/_logs" 2>&1 || true
  echo ""
  echo "=== npm log files ==="
  find "${NPM_CACHE}/_logs" \
    -maxdepth 1 \
    -type f \
    -print 2>&1 || true
} > "${ARTIFACT_DIR}/environment.txt"

# Copy all npm debug logs.
if [ -d "${NPM_CACHE}/_logs" ]; then
  cp -R "${NPM_CACHE}/_logs/." "${ARTIFACT_DIR}/" 2>/dev/null || true
fi

echo ""
echo "=== Files collected ==="
find "${ARTIFACT_DIR}" -type f -print
