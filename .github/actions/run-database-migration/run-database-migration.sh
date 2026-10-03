#!/usr/bin/env bash
#
# Runs the database migration command inside the deploy bundle.
# Step body for .github/actions/run-database-migration/action.yml.
#
# Required environment:
#   WORK_DIR, DB_COMMAND
# Optional environment:
#   DOPPLER_TOKEN, DOPPLER_PROJECT, DOPPLER_CONFIG

set -euo pipefail

if [[ -z "${WORK_DIR:-}" ]]; then
  echo "::error::working_directory is required."
  exit 1
fi

if [[ -z "${DB_COMMAND:-}" ]]; then
  echo "::error::DB_COMMAND is required."
  exit 1
fi

echo "::notice::Changing to working directory: ${WORK_DIR}"
cd "$WORK_DIR" || {
  echo "::error::Unable to cd into working directory: ${WORK_DIR}"
  exit 1
}
echo "Current directory: $(pwd)"

# ---------------------------------------------------------------------------
# Install Node dependencies (only if the bundle contains a package.json)
# ---------------------------------------------------------------------------
if [[ -f package.json ]]; then
  echo "::notice::package.json found in $(pwd), installing npm dependencies"

  if ! command -v npm >/dev/null 2>&1; then
    echo "::error::package.json exists but npm is not installed or not on PATH."
    exit 1
  fi

  echo "Node version: $(node --version 2>/dev/null || echo 'not found')"
  echo "npm version:  $(npm --version)"

  install_start=$SECONDS
  echo "::group::npm install"
  if npm install --no-audit --no-fund --no-progress; then
    echo "::endgroup::"
    echo "::notice::npm install completed in $((SECONDS - install_start))s"
  else
    install_status=$?
    echo "::endgroup::"
    echo "::error::npm install failed with exit code ${install_status} after $((SECONDS - install_start))s"
    exit "$install_status"
  fi
else
  echo "::notice::No package.json found in $(pwd), skipping npm install"
fi

# ---------------------------------------------------------------------------
# Make sure the bundled Doppler binary is executable
# ---------------------------------------------------------------------------
# actions/upload-artifact / download-artifact do not preserve file modes,
# so make sure the bundled Doppler binary is executable.
if [[ -f bin/doppler && ! -x bin/doppler ]]; then
  echo "::warning::bin/doppler is not executable, fixing permissions"
  chmod +x bin/doppler
fi

# ---------------------------------------------------------------------------
# Run the migration
# ---------------------------------------------------------------------------
migration_start=$SECONDS

if [[ -x "bin/doppler" && -n "${DOPPLER_TOKEN:-}" ]]; then
  echo "::notice::Running migration via Doppler CLI (token present, binary present)"
  echo "::group::Migration command"
  echo "${DB_COMMAND}"
  echo "::endgroup::"
  # DOPPLER_TOKEN is read from the environment by the Doppler CLI, so it is
  # not passed via --token (avoids exposing it in the process list).
  ./bin/doppler run \
    --project="$DOPPLER_PROJECT" \
    --config="$DOPPLER_CONFIG" \
    -- bash -euo pipefail -c "$DB_COMMAND"
else
  if [[ -x bin/doppler ]]; then
    doppler_cli=yes
  else
    doppler_cli=no
  fi
  if [[ -n "${DOPPLER_TOKEN:-}" ]]; then
    token_set=yes
  else
    token_set=no
  fi
  echo "::notice::Running migration with ambient environment (doppler_cli=${doppler_cli} token_set=${token_set})"
  echo "::group::Migration command"
  echo "${DB_COMMAND}"
  echo "::endgroup::"
  bash -euo pipefail -c "$DB_COMMAND"
fi

echo "::notice::Migration completed successfully in $((SECONDS - migration_start))s"
