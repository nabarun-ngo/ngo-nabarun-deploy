#!/usr/bin/env bash
#
# Enters or exits Changesets prerelease mode for the current branch.
# Step body for .github/actions/configure-changesets-prerelease/action.yml.
#
# Required environment:
#   WORK_DIR, CURRENT_BRANCH, STABLE_BRANCH, PRERELEASE_BRANCH,
#   PRERELEASE_TAG, PENDING_COUNT
#
# Writes transition (enter, exit, or none) to $GITHUB_OUTPUT.

set -euo pipefail

if [[ -z "${WORK_DIR}" ]]; then
  echo "::error::working_directory is required."
  exit 1
fi
cd "$WORK_DIR" || exit 1

PRE_FILE=".changeset/pre.json"
TRANSITION="none"

if [[ "$CURRENT_BRANCH" == "$PRERELEASE_BRANCH" ]]; then
  if [[ -f "$PRE_FILE" ]]; then
    MODE=$(jq -r '.mode // empty' "$PRE_FILE")
    TAG=$(jq -r '.tag // empty' "$PRE_FILE")
    if [[ "$MODE" != "pre" || "$TAG" != "$PRERELEASE_TAG" ]]; then
      echo "::error::$PRE_FILE must use mode=pre and tag=$PRERELEASE_TAG on $PRERELEASE_BRANCH"
      exit 1
    fi
    echo "::notice::$PRERELEASE_BRANCH is already in $PRERELEASE_TAG prerelease mode"
  elif [[ "$PENDING_COUNT" -gt 0 ]]; then
    npx changeset pre enter "$PRERELEASE_TAG"
    TRANSITION="enter"
    echo "::notice::Entered $PRERELEASE_TAG prerelease mode on $PRERELEASE_BRANCH"
  else
    echo "::notice::No pending changesets; prerelease mode will begin with the next release change"
  fi
elif [[ "$CURRENT_BRANCH" == "$STABLE_BRANCH" && -f "$PRE_FILE" ]]; then
  MODE=$(jq -r '.mode // empty' "$PRE_FILE")
  if [[ "$MODE" == "pre" ]]; then
    npx changeset pre exit
    TRANSITION="exit"
    echo "::notice::Exiting prerelease mode on $STABLE_BRANCH"
  elif [[ "$MODE" == "exit" ]]; then
    TRANSITION="exit"
    echo "::notice::Prerelease exit is already pending on $STABLE_BRANCH"
  else
    echo "::error::Unsupported Changesets prerelease mode '$MODE' in $PRE_FILE"
    exit 1
  fi
fi

echo "transition=$TRANSITION" >> "$GITHUB_OUTPUT"
