#!/bin/bash
#
# Applies Changesets versions, then moves an initial prerelease from .0 to .1.
# VERSION_COMMAND and PRERELEASE_TAG come from the step that runs this file.
# RELEASE_MODEL_PATH points to release_model.py. Legacy callers may still stage
# it at $RUNNER_TEMP/release-model until they migrate to the unified action.

set -euo pipefail

RELEASE_MODEL_PATH="${RELEASE_MODEL_PATH:-$RUNNER_TEMP/release-model/release_model.py}"
if [[ ! -f "$RELEASE_MODEL_PATH" ]]; then
  echo "::error::release_model.py not found at $RELEASE_MODEL_PATH"
  exit 1
fi

bash -euo pipefail -c "$VERSION_COMMAND"
python3 "$RELEASE_MODEL_PATH" shift-prerelease --root . --tag "$PRERELEASE_TAG"
