#!/usr/bin/env bash
#
# Resolves the test profile from a cron schedule or dispatch inputs.
# Step body for .github/workflows/ops-run-tests.yml.
#
# Required environment:
#   EVENT_NAME        schedule | workflow_dispatch.
#   CRON_SCHEDULE     Cron expression, matched against config/schedules/tests.json.
#   INPUT_TAGS / INPUT_ENV / INPUT_PARALLELISM   Dispatch inputs.
#
# Reads config/schedules/tests.json relative to the workspace. Writes the
# profile fields to $GITHUB_OUTPUT.

set -euo pipefail

TEST_TAGS="@smoke"
TARGET_ENV="stage"
PARALLELISM=3
TIMEOUT=60
REPORT_TITLE="Smoke Tests"

case "$EVENT_NAME" in
  schedule)
    if [[ "$CRON_SCHEDULE" == "0 3 * * *" ]]; then
      PROFILE=$(jq -c '.schedules[] | select(.id == "nightly-smoke")' config/schedules/tests.json)
      TEST_TAGS=$(echo "$PROFILE" | jq -r '.profile.tags')
      TARGET_ENV=$(echo "$PROFILE" | jq -r '.profile.environment')
      PARALLELISM=$(echo "$PROFILE" | jq -r '.profile.parallelism')
      TIMEOUT=$(echo "$PROFILE" | jq -r '.profile.timeoutMinutes')
      REPORT_TITLE="Nightly Smoke — $(date -u +%Y-%m-%d)"
    elif [[ "$CRON_SCHEDULE" == "0 2 * * 1" ]]; then
      PROFILE=$(jq -c '.schedules[] | select(.id == "weekly-regression")' config/schedules/tests.json)
      TEST_TAGS=$(echo "$PROFILE" | jq -r '.profile.tags')
      TARGET_ENV=$(echo "$PROFILE" | jq -r '.profile.environment')
      PARALLELISM=$(echo "$PROFILE" | jq -r '.profile.parallelism')
      TIMEOUT=$(echo "$PROFILE" | jq -r '.profile.timeoutMinutes')
      REPORT_TITLE="Weekly Regression — $(date -u +%Y-%m-%d)"
    fi
    ;;
  workflow_dispatch)
    TEST_TAGS="$INPUT_TAGS"
    TARGET_ENV="$INPUT_ENV"
    PARALLELISM="$INPUT_PARALLELISM"
    REPORT_TITLE="Manual — ${TEST_TAGS} (${TARGET_ENV})"
    ;;
  *)
    echo "::error::Unsupported event: $EVENT_NAME"
    exit 1
    ;;
esac

case "$TARGET_ENV" in
  stage) DOPPLER_CONFIG="stg" ;;
  prod) DOPPLER_CONFIG="prd" ;;
  *)
    echo "::error::Unknown target_environment: $TARGET_ENV"
    exit 1
    ;;
esac

{
  echo "test_tags=$TEST_TAGS"
  echo "target_environment=$TARGET_ENV"
  echo "parallelism=$PARALLELISM"
  echo "timeout_minutes=$TIMEOUT"
  echo "doppler_config=$DOPPLER_CONFIG"
  echo "report_title<<EOF"
  echo "$REPORT_TITLE"
  echo "EOF"
} >> "$GITHUB_OUTPUT"
