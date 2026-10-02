#!/usr/bin/env bash
#
# Runs one Maven Cucumber shard, optionally under Doppler.
# Step body for .github/actions/run-cucumber-shard/action.yml.
#
# Required environment:
#   WORK_DIR, USE_DOPPLER, TEST_TAGS, SHARD_INDEX, TOTAL_SHARDS, TARGET_ENV
# Required when USE_DOPPLER is true:
#   DOPPLER_TOKEN, DOPPLER_PROJECT, DOPPLER_CONFIG

set -euo pipefail

if [[ -z "${WORK_DIR}" ]]; then
  echo "::error::working_directory is required."
  exit 1
fi
cd "$WORK_DIR" || exit 1

if [[ "$USE_DOPPLER" == "true" ]]; then
  doppler run \
    --project="$DOPPLER_PROJECT" \
    --config="$DOPPLER_CONFIG" \
    --token="$DOPPLER_TOKEN" \
    -- mvn test \
      -Dcucumber.filter.tags="$TEST_TAGS" \
      -DCONFIG_SOURCE=doppler \
      -DDOPPLER_PROJECT_NAME="$DOPPLER_PROJECT" \
      -DTARGET_ENV="$TARGET_ENV" \
      -DSHARD_INDEX="$SHARD_INDEX" \
      -DTOTAL_SHARDS="$TOTAL_SHARDS" \
      -Dallure.results.directory=allure-results \
      --batch-mode --no-transfer-progress
else
  mvn test \
    -Dcucumber.filter.tags="$TEST_TAGS" \
    -DTARGET_ENV="$TARGET_ENV" \
    -DSHARD_INDEX="$SHARD_INDEX" \
    -DTOTAL_SHARDS="$TOTAL_SHARDS" \
    -Dallure.results.directory=allure-results \
    --batch-mode --no-transfer-progress
fi
