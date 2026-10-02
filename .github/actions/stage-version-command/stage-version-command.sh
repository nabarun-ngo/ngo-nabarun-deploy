#!/usr/bin/env bash
#
# Copies version-packages.sh to $RUNNER_TEMP so changesets/action can run it.
# Step body for .github/actions/stage-version-command/action.yml.

set -euo pipefail

# $0 is the script path both when action.yml sets GITHUB_ACTION_PATH and when
# a reusable workflow runs this file from the platform/ checkout.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cp "$SCRIPT_DIR/version-packages.sh" "$RUNNER_TEMP/version-packages.sh"
chmod +x "$RUNNER_TEMP/version-packages.sh"
