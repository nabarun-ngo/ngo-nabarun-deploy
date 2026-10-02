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
cd "$WORK_DIR" || exit 1

# actions/upload-artifact / download-artifact do not preserve file modes,
# so make sure the bundled Doppler binary is executable.
if [[ -f bin/doppler && ! -x bin/doppler ]]; then
  echo "::warning::bin/doppler is not executable, fixing permissions"
  chmod +x bin/doppler
fi

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
