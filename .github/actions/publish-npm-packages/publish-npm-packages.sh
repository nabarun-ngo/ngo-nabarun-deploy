#!/usr/bin/env bash
#
# Publishes package versions that are not already on npm.
# Step body for .github/actions/publish-npm-packages/action.yml.
#
# Required environment:
#   WORK_DIR, NODE_AUTH_TOKEN, NPM_TOKEN, CURRENT_BRANCH, STABLE_BRANCH,
#   PRERELEASE_BRANCH, STABLE_COMMAND, PRERELEASE_COMMAND, PRERELEASE_TAG
#
# release_model.py must already be staged at $RUNNER_TEMP/release-model.

set -euo pipefail

if [[ -z "${WORK_DIR}" ]]; then
  echo "::error::working_directory is required."
  exit 1
fi
cd "$WORK_DIR" || exit 1

run_publish() {
  local publish_command="$1"
  if [[ -z "$publish_command" ]]; then
    echo "::error::Publish command is empty"
    exit 1
  fi
  bash -euo pipefail -c "$publish_command"
}

skip_if_published() {
  python3 "$RUNNER_TEMP/release-model/release_model.py" skip-if-published --root .
}

verify_dist_tag() {
  local tag="$PRERELEASE_TAG"
  [[ "$CURRENT_BRANCH" == "$PRERELEASE_BRANCH" ]] || tag="latest"
  python3 "$RUNNER_TEMP/release-model/release_model.py" verify-dist-tag --root . --tag "$tag"
}

if skip_if_published; then
  echo "::notice::All package versions are already on npm. This commit will not publish again."
  exit 0
fi

if [[ "$CURRENT_BRANCH" == "$PRERELEASE_BRANCH" ]]; then
  npm config set tag "$PRERELEASE_TAG"
  echo "::notice::Running prerelease publish command: $PRERELEASE_COMMAND"
  python3 "$RUNNER_TEMP/release-model/release_model.py" assert-versions --root . --tag "$PRERELEASE_TAG" --prerelease
  run_publish "$PRERELEASE_COMMAND"
  verify_dist_tag
elif [[ "$CURRENT_BRANCH" == "$STABLE_BRANCH" ]]; then
  npm config set tag latest
  if [[ -f .changeset/pre.json ]]; then
    echo "::error::Refusing to publish on $STABLE_BRANCH while .changeset/pre.json exists"
    exit 1
  fi
  python3 "$RUNNER_TEMP/release-model/release_model.py" assert-versions --root . --tag beta
  while IFS= read -r -d '' pkg; do
    private=$(jq -r '.private // false' "$pkg")
    ver=$(jq -r '.version // empty' "$pkg")
    [[ "$private" == "true" || -z "$ver" || "$ver" == "null" ]] && continue
    if [[ "$ver" == *-* ]]; then
      echo "::error::$pkg is $ver. Refusing to publish a prerelease as latest."
      exit 1
    fi
  done < <(find . -name node_modules -prune -o -name package.json -print0)
  echo "::notice::Running stable publish command: $STABLE_COMMAND"
  run_publish "$STABLE_COMMAND"
  verify_dist_tag
else
  echo "::error::Refusing to publish from branch '$CURRENT_BRANCH'"
  exit 1
fi
