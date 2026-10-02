#!/usr/bin/env bash
#
# Resolves trigger, manifest, environment, tag, and approval mode.
# Step body for .github/actions/resolve-workflow-context/action.yml.
#
# Required environment:
#   EVENT_NAME, INPUT_WORKFLOW_TYPE
# Optional environment:
#   INPUT_MANIFEST, INPUT_TARGET_ENV, INPUT_TAG,
#   DISPATCH_MANIFEST, DISPATCH_TAG, DISPATCH_ENV
#
# Writes trigger_type, manifest_name, target_environment, tag_name,
# approval_mode, and workflow_type to $GITHUB_OUTPUT.

set -euo pipefail

case "$EVENT_NAME" in
  schedule)
    TRIGGER_TYPE="schedule"
    APPROVAL_MODE="auto"
    ;;
  repository_dispatch)
    TRIGGER_TYPE="repository_dispatch"
    APPROVAL_MODE="manual"
    ;;
  *)
    TRIGGER_TYPE="workflow_dispatch"
    APPROVAL_MODE="manual"
    ;;
esac

MANIFEST_NAME="$INPUT_MANIFEST"
TARGET_ENV="$INPUT_TARGET_ENV"
TAG_NAME="$INPUT_TAG"
WORKFLOW_TYPE="$INPUT_WORKFLOW_TYPE"

if [[ "$TRIGGER_TYPE" == "repository_dispatch" ]]; then
  if [[ -n "$DISPATCH_MANIFEST" ]]; then
    MANIFEST_NAME="$DISPATCH_MANIFEST"
  fi
  if [[ -n "$DISPATCH_TAG" ]]; then
    TAG_NAME="$DISPATCH_TAG"
  fi
  if [[ -n "$DISPATCH_ENV" ]]; then
    TARGET_ENV="$DISPATCH_ENV"
  fi
fi

if [[ -z "$MANIFEST_NAME" && "$WORKFLOW_TYPE" == "deploy" ]]; then
  echo "::error::manifest_name is required for deploy workflows"
  exit 1
fi
if [[ -z "$TARGET_ENV" ]]; then
  TARGET_ENV="stage"
fi

{
  echo "trigger_type=$TRIGGER_TYPE"
  echo "manifest_name=$MANIFEST_NAME"
  echo "target_environment=$TARGET_ENV"
  echo "tag_name=$TAG_NAME"
  echo "approval_mode=$APPROVAL_MODE"
  echo "workflow_type=$WORKFLOW_TYPE"
} >> "$GITHUB_OUTPUT"

echo "::group::Resolved context"
echo "trigger_type=$TRIGGER_TYPE"
echo "manifest_name=$MANIFEST_NAME"
echo "target_environment=$TARGET_ENV"
echo "tag_name=$TAG_NAME"
echo "approval_mode=$APPROVAL_MODE"
echo "workflow_type=$WORKFLOW_TYPE"
echo "::endgroup::"
echo "::notice::Context resolved — trigger=$TRIGGER_TYPE, manifest=$MANIFEST_NAME, env=$TARGET_ENV, tag=$TAG_NAME"
