#!/usr/bin/env bash
#
# Maps a run to the GitHub Environment its jobs bind to.
# Step body for .github/actions/resolve-deployment-environment/action.yml.
#
# Holds no environment names. Callers pass names read from config: deploy
# manifests (config/manifests/) and schedules (config/schedules/).
#
# Required environment:
#   TRIGGER_TYPE   schedule | workflow_dispatch | repository_dispatch.
#   TARGET_ENV     stage | prod.
#   WORKFLOW_TYPE  deploy | tests.
#   INPUT_GH_ENV   Deploy: manifest environments[target].githubEnvironment (manual runs).
#                  Tests: the resolved test environment, manual or scheduled.
# Deploy environment:
#   MANIFEST_NAME     Manifest being deployed, for error messages.
#   SCHEDULE_GH_ENV   githubEnvironment of the matching config/schedules/deploys.json
#                     entry; required for scheduled deploys.
#
# Writes gh_env, requires_approval, and approval_mode to $GITHUB_OUTPUT.

set -euo pipefail

case "$TARGET_ENV" in
  stage|prod) ;;
  *)
    echo "::error::Unknown target_environment: '$TARGET_ENV'. Expected 'stage' or 'prod'."
    exit 1
    ;;
esac

GITHUB_ENV_NAME=""
REQUIRES_APPROVAL="true"
APPROVAL_MODE="manual"

if [[ "$TRIGGER_TYPE" == "schedule" ]]; then
  REQUIRES_APPROVAL="false"
  APPROVAL_MODE="auto"
fi

if [[ "$WORKFLOW_TYPE" == "tests" ]]; then
  if [[ -z "${INPUT_GH_ENV:-}" ]]; then
    echo "::error::No GitHub Environment was resolved for this test run (check config/schedules/tests.json)."
    exit 1
  fi
  GITHUB_ENV_NAME="$INPUT_GH_ENV"
elif [[ "$TRIGGER_TYPE" == "schedule" ]]; then
  if [[ -z "${SCHEDULE_GH_ENV:-}" ]]; then
    echo "::error::No config/schedules/deploys.json entry resolved for this scheduled deploy of '${MANIFEST_NAME:-}'."
    exit 1
  fi
  GITHUB_ENV_NAME="$SCHEDULE_GH_ENV"
else
  if [[ -z "${INPUT_GH_ENV:-}" ]]; then
    echo "::error::Manifest '${MANIFEST_NAME:-}' has no environments.${TARGET_ENV}.githubEnvironment."
    exit 1
  fi
  GITHUB_ENV_NAME="$INPUT_GH_ENV"
fi

echo "::notice::Resolved GitHub Environment: $GITHUB_ENV_NAME (approval_mode: $APPROVAL_MODE)"
echo "gh_env=$GITHUB_ENV_NAME"  >> "$GITHUB_OUTPUT"
echo "requires_approval=$REQUIRES_APPROVAL" >> "$GITHUB_OUTPUT"
echo "approval_mode=$APPROVAL_MODE"         >> "$GITHUB_OUTPUT"
