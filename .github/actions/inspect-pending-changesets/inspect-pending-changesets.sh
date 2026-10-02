#!/usr/bin/env bash
#
# Counts pending changeset files.
# Step body for .github/actions/inspect-pending-changesets/action.yml.
#
# Required environment:
#   WORK_DIR  Directory that contains .changeset, relative to the workspace.
#
# Writes count to $GITHUB_OUTPUT.

set -euo pipefail

CS_DIR="${WORK_DIR}/.changeset"
[[ "$WORK_DIR" == "." ]] && CS_DIR=".changeset"
if [[ ! -d "$CS_DIR" ]]; then
  echo "::error::Changesets directory not found: $CS_DIR"
  exit 1
fi

PENDING=0
while IFS= read -r -d '' file; do
  [[ "$(basename "$file")" == "README.md" ]] && continue
  PENDING=$((PENDING + 1))
done < <(find "$CS_DIR" -maxdepth 1 -type f -name '*.md' -print0)

echo "count=$PENDING" >> "$GITHUB_OUTPUT"
echo "::notice::Pending changesets before versioning: $PENDING"
