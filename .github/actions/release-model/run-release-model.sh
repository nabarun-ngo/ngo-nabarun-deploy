#!/usr/bin/env bash
#
# Dispatches one release operation to the implementation checked out under
# platform/. The caller action validates and creates that checkout first.

set -euo pipefail

PLATFORM_DIR="$GITHUB_WORKSPACE/platform"
RELEASE_ACTION_DIR="$PLATFORM_DIR/.github/actions/release-model"
MODEL="$RELEASE_ACTION_DIR/release_model.py"
CREATE_TAG="$RELEASE_ACTION_DIR/create-tag-release.py"
PUBLISH_PACKAGES="$PLATFORM_DIR/.github/actions/publish-npm-packages/publish-npm-packages.sh"
STAGE_VERSION="$PLATFORM_DIR/.github/actions/stage-version-command/stage-version-command.sh"
OPEN_VERSION_PR="$PLATFORM_DIR/.github/actions/open-version-packages-pr/open-version-packages-pr.sh"

require_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    echo "::error::$name is required for operation '$OPERATION'."
    exit 1
  fi
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "::error::Required release-model file not found: $path"
    exit 1
  fi
}

write_output() {
  local name="$1"
  local value="$2"
  local delimiter="release_model_${name}_${RANDOM}_$$"
  {
    echo "${name}<<${delimiter}"
    printf '%s\n' "$value"
    echo "$delimiter"
  } >> "$GITHUB_OUTPUT"
}

require_file "$MODEL"
require_value "working_directory" "${WORK_DIR:-}"

if [[ ! -d "$WORK_DIR" ]]; then
  echo "::error::working_directory does not exist: $WORK_DIR"
  exit 1
fi

case "$OPERATION" in
  plan)
    require_value "payload" "${PAYLOAD:-}"
    RESULT=$(
      cd "$WORK_DIR"
      python3 "$MODEL" plan "$PAYLOAD"
    )
    printf '%s\n' "$RESULT"
    write_output "result_json" "$RESULT"
    VERSION=$(python3 -c 'import json, sys; print(json.load(sys.stdin).get("version", ""))' <<< "$RESULT")
    write_output "version" "$VERSION"
    ;;
  baseline)
    require_value "payload" "${PAYLOAD:-}"
    BASELINE=$(
      cd "$WORK_DIR"
      python3 "$MODEL" baseline "$PAYLOAD"
    )
    printf '%s\n' "$BASELINE"
    write_output "baseline" "$BASELINE"
    ;;
  validate-pr)
    require_value "payload" "${PAYLOAD:-}"
    if (
      cd "$WORK_DIR"
      python3 "$MODEL" validate-pr "$PAYLOAD"
    ); then
      write_output "valid" "true"
    else
      status=$?
      write_output "valid" "false"
      exit "$status"
    fi
    ;;
  apply)
    require_value "version" "${INPUT_VERSION:-}"
    require_value "version_file" "${VERSION_FILE:-}"
    require_value "changelog" "${CHANGELOG_FILE:-}"
    require_value "subjects_file" "${SUBJECTS_FILE:-}"
    (
      cd "$WORK_DIR"
      python3 "$MODEL" apply \
        --version "$INPUT_VERSION" \
        --version-file "$VERSION_FILE" \
        --changelog "$CHANGELOG_FILE" \
        --subjects-file "$SUBJECTS_FILE"
    )
    ;;
  check-pr)
    if (
      cd "$WORK_DIR"
      WORKING_DIRECTORY=. python3 "$MODEL" check-pr
    ); then
      write_output "valid" "true"
    else
      status=$?
      write_output "valid" "false"
      exit "$status"
    fi
    ;;
  shift-prerelease)
    require_value "tag" "${RELEASE_TAG:-${PRERELEASE_TAG:-}}"
    CHANGED_JSON=$(
      cd "$WORK_DIR"
      python3 "$MODEL" shift-prerelease \
        --root . \
        --tag "${RELEASE_TAG:-$PRERELEASE_TAG}"
    )
    printf '%s\n' "$CHANGED_JSON"
    write_output "changed_json" "$CHANGED_JSON"
    ;;
  skip-if-published)
    if (
      cd "$WORK_DIR"
      python3 "$MODEL" skip-if-published --root .
    ); then
      write_output "already_published" "true"
    else
      status=$?
      if [[ "$status" -ne 1 ]]; then
        exit "$status"
      fi
      write_output "already_published" "false"
    fi
    ;;
  verify-dist-tag)
    require_value "tag" "${RELEASE_TAG:-}"
    (
      cd "$WORK_DIR"
      python3 "$MODEL" verify-dist-tag --root . --tag "$RELEASE_TAG"
    )
    ;;
  assert-versions)
    require_value "tag" "${RELEASE_TAG:-}"
    ARGS=(assert-versions --root . --tag "$RELEASE_TAG")
    if [[ "$EXPECT_PRERELEASE" == "true" ]]; then
      ARGS+=(--prerelease)
    elif [[ "$EXPECT_PRERELEASE" != "false" ]]; then
      echo "::error::prerelease must be 'true' or 'false'."
      exit 1
    fi
    (
      cd "$WORK_DIR"
      python3 "$MODEL" "${ARGS[@]}"
    )
    ;;
  create-tag-release)
    require_file "$CREATE_TAG"
    (
      cd "$WORK_DIR"
      PYTHONPATH="$RELEASE_ACTION_DIR" python3 "$CREATE_TAG"
    )
    ;;
  publish-packages)
    require_file "$PUBLISH_PACKAGES"
    require_value "stable_command" "${STABLE_COMMAND:-}"
    require_value "prerelease_command" "${PRERELEASE_COMMAND:-}"
    RELEASE_MODEL_PATH="$MODEL" bash "$PUBLISH_PACKAGES"
    ;;
  open-version-pr)
    require_file "$STAGE_VERSION"
    require_file "$OPEN_VERSION_PR"
    require_value "version_command" "${VERSION_COMMAND:-}"
    require_value "pr_title" "${PR_TITLE:-}"
    require_value "pr_commit" "${PR_COMMIT:-}"
    RELEASE_MODEL_PATH="$MODEL" bash "$STAGE_VERSION"
    RELEASE_MODEL_PATH="$MODEL" bash "$OPEN_VERSION_PR"
    ;;
  *)
    echo "::error::Unsupported release-model operation: '$OPERATION'."
    exit 1
    ;;
esac
