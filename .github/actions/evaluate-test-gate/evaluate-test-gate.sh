#!/usr/bin/env bash
#
# Fails the step unless the test jobs and Allure counts are clean.
# Step body for .github/actions/evaluate-test-gate/action.yml.
#
# Required environment:
#   DISCOVER_RESULT, EXECUTE_RESULT, REPORT_RESULT
# Optional environment:
#   TOTAL, FAILED, BROKEN
#
# Writes tests_passed to $GITHUB_OUTPUT.

set -euo pipefail

ok=true
TOTAL=${TOTAL:-0}
FAILED=${FAILED:-0}
BROKEN=${BROKEN:-0}

if [[ "$DISCOVER_RESULT" != "success" ]]; then
  echo "::error::Discover job did not succeed (${DISCOVER_RESULT})"
  ok=false
fi
if [[ "$EXECUTE_RESULT" == "failure" || "$EXECUTE_RESULT" == "cancelled" ]]; then
  echo "::error::Execute job result is ${EXECUTE_RESULT}"
  ok=false
fi
if [[ "$REPORT_RESULT" != "success" ]]; then
  echo "::error::Report job did not succeed (${REPORT_RESULT})"
  ok=false
fi
if [[ "$TOTAL" == "0" || -z "$TOTAL" ]]; then
  echo "::error::No tests recorded (total=${TOTAL})"
  ok=false
fi
if [[ "$FAILED" != "0" ]]; then
  echo "::error::Failed tests: ${FAILED}"
  ok=false
fi
if [[ "$BROKEN" != "0" ]]; then
  echo "::error::Broken tests: ${BROKEN}"
  ok=false
fi

if [[ "$ok" == "true" ]]; then
  echo "tests_passed=true" >> "$GITHUB_OUTPUT"
  echo "::notice::Test gate passed (total=${TOTAL})"
else
  echo "tests_passed=false" >> "$GITHUB_OUTPUT"
  exit 1
fi
