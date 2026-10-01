#!/usr/bin/env bash
#
# Applies environment-specific overrides to a resolved test profile.
# Step body for .github/workflows/ops-run-tests.yml.
#
# Required environment:
#   TEST_TAGS / TARGET_ENV / PARALLELISM / TIMEOUT / DOPPLER_CONFIG / REPORT_TITLE
#     Outputs of the resolve step.
#   GH_ENV  Resolved GitHub Environment; "prod" pins parallelism to 1.
#
# Re-emits the profile to $GITHUB_OUTPUT.

set -euo pipefail

if [[ "$GH_ENV" == "prod" ]]; then
  PARALLELISM=1
  echo "::notice::Pinning parallelism to 1 for prod (one approval per run)"
fi
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
echo "::group::Resolved test profile"
echo "test_tags=$TEST_TAGS"
echo "target_environment=$TARGET_ENV"
echo "parallelism=$PARALLELISM"
echo "timeout_minutes=$TIMEOUT"
echo "gh_env=$GH_ENV"
echo "doppler_config=$DOPPLER_CONFIG"
echo "report_title=$REPORT_TITLE"
echo "::endgroup::"
echo "::notice::Test profile — tags=$TEST_TAGS env=$TARGET_ENV gh_env=$GH_ENV shards=$PARALLELISM doppler=$DOPPLER_CONFIG"
