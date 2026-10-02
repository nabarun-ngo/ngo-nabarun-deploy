#!/bin/bash
#
# Applies Changesets versions, then moves an initial prerelease from .0 to .1.
# VERSION_COMMAND and PRERELEASE_TAG come from the step that runs this file.
# release_model.py must already be staged at $RUNNER_TEMP/release-model.

set -euo pipefail

bash -euo pipefail -c "$VERSION_COMMAND"
python3 "$RUNNER_TEMP/release-model/release_model.py" shift-prerelease --root . --tag "$PRERELEASE_TAG"
