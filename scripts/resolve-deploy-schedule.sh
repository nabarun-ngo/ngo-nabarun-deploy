#!/usr/bin/env bash
#
# Resolves what a deploy run releases: the matching config/schedules/deploys.json
# entry for a scheduled run, or the dispatch inputs for a manual run.
# Step body for the trigger job in ops-deploy-*.yml.
#
# Required environment:
#   EVENT_NAME      schedule | workflow_dispatch.
#   CRON_SCHEDULE   github.event.schedule, matched against each entry's cron.
#   INPUT_MANIFEST / INPUT_TARGET_ENV / INPUT_TAG   Dispatch inputs.
#
# Writes manifest_name, target_environment, tag_name and
# schedule_github_environment (scheduled runs only) to $GITHUB_OUTPUT.

set -euo pipefail

SCHEDULES_FILE="config/schedules/deploys.json"

MANIFEST_NAME="${INPUT_MANIFEST:-}"
TARGET_ENV="${INPUT_TARGET_ENV:-}"
TAG_NAME="${INPUT_TAG:-latest}"
SCHEDULE_GH_ENV=""

if [[ "$EVENT_NAME" == "schedule" ]]; then
  if [[ ! -f "$SCHEDULES_FILE" ]]; then
    echo "::error::$SCHEDULES_FILE not found; scheduled deploys are not configured."
    exit 1
  fi
  MATCHES=$(jq -c --arg cron "$CRON_SCHEDULE" \
    '[.schedules[] | select(.deploy != null and .cron == $cron)]' "$SCHEDULES_FILE")
  COUNT=$(echo "$MATCHES" | jq 'length')
  if [[ "$COUNT" -ne 1 ]]; then
    echo "::error::Expected exactly one deploy schedule in $SCHEDULES_FILE with cron '$CRON_SCHEDULE', found $COUNT."
    exit 1
  fi
  ENTRY=$(echo "$MATCHES" | jq -c '.[0]')
  MANIFEST_NAME=$(echo "$ENTRY"   | jq -r '.deploy.manifest')
  TARGET_ENV=$(echo "$ENTRY"      | jq -r '.deploy.target')
  TAG_NAME=$(echo "$ENTRY"        | jq -r '.deploy.tag // "latest"')
  SCHEDULE_GH_ENV=$(echo "$ENTRY" | jq -r '.githubEnvironment')
  if [[ "$TARGET_ENV" == "prod" && "$TAG_NAME" != "latest" &&
        ! "$TAG_NAME" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "::error::Scheduled production deploys require 'latest' or a stable semver tag; got '$TAG_NAME'."
    exit 1
  fi
  echo "::notice::Scheduled deploy '$(echo "$ENTRY" | jq -r '.id')' → $MANIFEST_NAME/$TARGET_ENV via $SCHEDULE_GH_ENV"
fi

{
  echo "manifest_name=$MANIFEST_NAME"
  echo "target_environment=$TARGET_ENV"
  echo "tag_name=${TAG_NAME:-latest}"
  echo "schedule_github_environment=$SCHEDULE_GH_ENV"
} >> "$GITHUB_OUTPUT"
