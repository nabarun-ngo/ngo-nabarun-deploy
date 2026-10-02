#!/usr/bin/env bash
#
# Appends DOPPLER_TOKEN under env_variables in app.yaml.
# Step body for .github/actions/inject-doppler-token/action.yml.
#
# Required environment:
#   WORK_DIR, DOPPLER_TOKEN
#
# The token is not printed. It exists only in the ephemeral deploy bundle.

set -euo pipefail

if [[ -z "${WORK_DIR}" ]]; then
  echo "::error::working_directory is required."
  exit 1
fi
cd "$WORK_DIR" || exit 1

cat >> app.yaml <<EOF
  DOPPLER_TOKEN: "$DOPPLER_TOKEN"
EOF
