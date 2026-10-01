#!/usr/bin/env bash
#
# Maps (trigger, target environment) to a GitHub Environment name.
# Step body for .github/actions/resolve-deployment-environment/action.yml.
#
# Required environment:
#   TRIGGER_TYPE   schedule | workflow_dispatch | repository_dispatch.
#   TARGET_ENV     stage | prod.
#   WORKFLOW_TYPE  deploy | tests.
#
# Writes gh_env, requires_approval, and approval_mode to $GITHUB_OUTPUT.

set -euo pipefail

GITHUB_ENV_NAME=""
REQUIRES_APPROVAL="false"
APPROVAL_MODE="manual"

if [[ "$TRIGGER_TYPE" == "schedule" ]]; then
  APPROVAL_MODE="auto"
  if [[ "$WORKFLOW_TYPE" == "tests" ]]; then
    GITHUB_ENV_NAME="tests-scheduled"
  else
    # Scheduled deploys only go to stage-scheduled (never prod)
    if [[ "$TARGET_ENV" == "prod" ]]; then
      echo "::error::Scheduled deploys to prod are disabled. Use a manual workflow_dispatch instead."
      exit 1
    fi
    GITHUB_ENV_NAME="stage-scheduled"
  fi
else
  APPROVAL_MODE="manual"
  case "$TARGET_ENV" in
    stage)
      GITHUB_ENV_NAME="stage"
      REQUIRES_APPROVAL="true"
      ;;
    prod)
      GITHUB_ENV_NAME="prod"
      REQUIRES_APPROVAL="true"
      ;;
    *)
      echo "::error::Unknown target_environment: '$TARGET_ENV'. Expected 'stage' or 'prod'."
      exit 1
      ;;
  esac
fi

echo "::notice::Resolved GitHub Environment: $GITHUB_ENV_NAME (approval_mode: $APPROVAL_MODE)"
echo "gh_env=$GITHUB_ENV_NAME"  >> "$GITHUB_OUTPUT"
echo "requires_approval=$REQUIRES_APPROVAL" >> "$GITHUB_OUTPUT"
echo "approval_mode=$APPROVAL_MODE"         >> "$GITHUB_OUTPUT"
