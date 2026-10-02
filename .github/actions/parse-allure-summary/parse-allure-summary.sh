#!/usr/bin/env bash
#
# Reads Allure summary.json and writes the counts.
# Step body for .github/actions/parse-allure-summary/action.yml.
#
# Required environment:
#   TEST_TAGS, SUMMARY_JSON
# Optional environment:
#   REPORT_URL
#
# Writes total_tests, passed_tests, failed_tests, and broken_tests
# to $GITHUB_OUTPUT. A missing summary file records zeros.

set -euo pipefail

if [[ -f "$SUMMARY_JSON" ]]; then
  TOTAL=$(jq '.statistic.total // 0' "$SUMMARY_JSON")
  PASSED=$(jq '.statistic.passed // 0' "$SUMMARY_JSON")
  FAILED=$(jq '.statistic.failed // 0' "$SUMMARY_JSON")
  BROKEN=$(jq '.statistic.broken // 0' "$SUMMARY_JSON")
  SKIPPED=$(jq '.statistic.skipped // 0' "$SUMMARY_JSON")
else
  echo "::error::${SUMMARY_JSON} missing after generate"
  TOTAL=0
  PASSED=0
  FAILED=0
  BROKEN=0
  SKIPPED=0
fi

{
  echo "total_tests=$TOTAL"
  echo "passed_tests=$PASSED"
  echo "failed_tests=$FAILED"
  echo "broken_tests=$BROKEN"
} >> "$GITHUB_OUTPUT"

{
  echo "### Test Results — ${TEST_TAGS}"
  echo ""
  echo "| Status | Count |"
  echo "|--------|-------|"
  echo "| Total | $TOTAL |"
  echo "| Passed | $PASSED |"
  echo "| Failed | $FAILED |"
  echo "| Broken | $BROKEN |"
  echo "| Skipped | $SKIPPED |"
  echo ""
  echo "[View full Allure report](${REPORT_URL})"
} >> "$GITHUB_STEP_SUMMARY"
