#!/usr/bin/env bash
#
# Prints run context and appends a step summary.
# Step body for .github/actions/log-run-context/action.yml.
#
# Required environment:
#   LOG_TITLE    Heading used in the notice, group, and summary.
#   LOG_INPUTS   JSON object of workflow inputs.
#   LOG_VARIANT  "version" or "publish".
#
# Optional environment:
#   LOG_EXTRA
#   PUBLISH_VERSION, PUBLISH_BRANCH, STABLE_COMMAND, PRERELEASE_COMMAND,
#   NPM_TOKEN_PRESENT, JOB_STATUS  (publish summary)

set -euo pipefail

if [[ -z "${LOG_TITLE}" || -z "${LOG_VARIANT}" ]]; then
  echo "::error::title and variant are required."
  exit 1
fi

echo "::notice::${LOG_TITLE} — ${GITHUB_EVENT_NAME} ${GITHUB_REF} sha=${GITHUB_SHA:0:7} run=${GITHUB_RUN_ID}"
echo "::group::${LOG_TITLE} context"
echo "event=${GITHUB_EVENT_NAME}"
echo "ref=${GITHUB_REF}"
echo "sha=${GITHUB_SHA}"
echo "actor=${GITHUB_ACTOR}"
echo "run_id=${GITHUB_RUN_ID} attempt=${GITHUB_RUN_ATTEMPT}"
echo "job=${GITHUB_JOB}"
echo "workflow=${GITHUB_WORKFLOW}"
echo "repository=${GITHUB_REPOSITORY}"
echo "runner=${RUNNER_OS}/${RUNNER_ARCH}"
echo "run_url=${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
echo "--- inputs ---"
echo "${LOG_INPUTS}"
if [[ -n "${LOG_EXTRA:-}" ]]; then
  echo "--- extra ---"
  echo "${LOG_EXTRA}"
fi
echo "::endgroup::"

case "$LOG_VARIANT" in
  version)
    {
      echo "### ${LOG_TITLE}"
      echo ""
      echo "| Field | Value |"
      echo "|-------|-------|"
      echo "| Event | \`${GITHUB_EVENT_NAME}\` |"
      echo "| Ref | \`${GITHUB_REF}\` |"
      echo "| SHA | \`${GITHUB_SHA}\` |"
      echo "| Job | \`${GITHUB_JOB}\` |"
      echo "| Run | [${GITHUB_RUN_ID}](${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}) |"
      echo ""
      echo "<details><summary>inputs</summary>"
      echo ""
      echo '```json'
      echo "${LOG_INPUTS}"
      echo '```'
      echo "</details>"
    } >> "$GITHUB_STEP_SUMMARY"
    ;;
  publish)
    {
      echo "### ${LOG_TITLE}"
      echo ""
      echo "| Field | Value |"
      echo "|-------|-------|"
      echo "| Version | \`${PUBLISH_VERSION}\` |"
      echo "| Branch | \`${PUBLISH_BRANCH}\` |"
      echo "| stable command | \`${STABLE_COMMAND}\` |"
      echo "| prerelease command | \`${PRERELEASE_COMMAND}\` |"
      echo "| npm token present | \`${NPM_TOKEN_PRESENT}\` |"
      echo "| Job | ${JOB_STATUS} |"
    } >> "$GITHUB_STEP_SUMMARY"
    ;;
  *)
    echo "::error::variant must be version or publish."
    exit 1
    ;;
esac
