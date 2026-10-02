#!/usr/bin/env bash
#
# Counts feature files and builds a shard matrix.
# Step body for .github/actions/discover-test-features/action.yml.
#
# Required environment:
#   WORK_DIR, PARALLELISM
#
# Writes feature_count, matrix, and total_shards to $GITHUB_OUTPUT.

set -euo pipefail

if [[ -z "${WORK_DIR}" ]]; then
  echo "::error::working_directory is required."
  exit 1
fi
cd "$WORK_DIR" || exit 1

FEATURE_FILES=$(find . -name '*.feature' -not -path '*/node_modules/*' | sort || true)
FEATURE_COUNT=$(printf '%s\n' "$FEATURE_FILES" | grep -c '[^[:space:]]' || true)
FEATURE_COUNT=${FEATURE_COUNT:-0}
echo "feature_count=$FEATURE_COUNT" >> "$GITHUB_OUTPUT"
echo "::notice::Found $FEATURE_COUNT feature files"

SHARDS=$PARALLELISM
if (( FEATURE_COUNT < SHARDS )); then
  SHARDS=$FEATURE_COUNT
fi
if (( SHARDS < 1 )); then
  SHARDS=1
fi

MATRIX_JSON=$(jq -nc --argjson n "$SHARDS" '{shard:[range(1;$n+1)]}')
{
  echo "matrix=$MATRIX_JSON"
  echo "total_shards=$SHARDS"
} >> "$GITHUB_OUTPUT"
echo "::notice::Matrix: $MATRIX_JSON total_shards=$SHARDS"
