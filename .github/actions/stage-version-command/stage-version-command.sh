#!/usr/bin/env bash
#
# Copies version-packages.sh to $RUNNER_TEMP so changesets/action can run it.
# Step body for .github/actions/stage-version-command/action.yml.

set -euo pipefail

cp "$GITHUB_ACTION_PATH/version-packages.sh" "$RUNNER_TEMP/version-packages.sh"
chmod +x "$RUNNER_TEMP/version-packages.sh"
