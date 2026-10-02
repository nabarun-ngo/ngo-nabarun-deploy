#!/usr/bin/env bash
#
# Decides whether a Release-Created event is deployed.
# Step body for .github/actions/decide-release-deployment/action.yml.
#
# Required environment:
#   PAYLOAD_REPOSITORY  Application repository in owner/name form.
#   PAYLOAD_TAG         Bare semver tag (1.4.0 or 1.4.0-beta.1).
#   PAYLOAD_PRERELEASE  'true' or 'false'; must agree with PAYLOAD_TAG.
#   PAYLOAD_REF         Branch the release was created from (logged only).
#   MANIFESTS_DIR       Directory holding manifest JSON files.
#
# Writes action, manifest_name, tag_name, and reason to $GITHUB_OUTPUT.

set -euo pipefail

write_decision() {
  {
    echo "action=$1"
    echo "manifest_name=$2"
    echo "tag_name=$3"
    echo "reason=$4"
  } >> "$GITHUB_OUTPUT"
}

STABLE_PAT='^[0-9]+\.[0-9]+\.[0-9]+$'
PRE_PAT='^[0-9]+\.[0-9]+\.[0-9]+-(alpha|beta|rc)\.[1-9][0-9]*$'

if [[ -z "${PAYLOAD_REPOSITORY}" || -z "${PAYLOAD_TAG}" ]]; then
  echo "::error::Release-Created requires repository and tag_name."
  exit 1
fi
if [[ ! "${PAYLOAD_REPOSITORY}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "::error::repository must be owner/name."
  exit 1
fi
if [[ ! "$PAYLOAD_TAG" =~ $STABLE_PAT && ! "$PAYLOAD_TAG" =~ $PRE_PAT ]]; then
  echo "::error::tag_name must be bare semver, for example 1.4.0 or 1.4.0-beta.1."
  exit 1
fi

# Payload self-consistency is checked before any manifest is read: it describes
# the release itself, so it must fail the same way whatever the repository maps to.
PRERELEASE_FLAG=false
if [[ "${PAYLOAD_PRERELEASE}" == "true" ]]; then
  PRERELEASE_FLAG=true
fi
if [[ "$PAYLOAD_TAG" =~ $PRE_PAT ]]; then
  TAG_IS_PRERELEASE=true
else
  TAG_IS_PRERELEASE=false
fi
if [[ "$PRERELEASE_FLAG" != "$TAG_IS_PRERELEASE" ]]; then
  echo "::error::prerelease '${PAYLOAD_PRERELEASE}' does not match tag '${PAYLOAD_TAG}'."
  exit 1
fi

shopt -s nullglob
MANIFEST_FILES=("${MANIFESTS_DIR}"/*.json)
shopt -u nullglob
if [[ "${#MANIFEST_FILES[@]}" -eq 0 ]]; then
  echo "::error::No manifest files found in ${MANIFESTS_DIR}."
  exit 1
fi

mapfile -t MATCHES < <(jq -r --arg repo "$PAYLOAD_REPOSITORY" 'select(.source.repository == $repo) | input_filename' "${MANIFEST_FILES[@]}")
COUNT="${#MATCHES[@]}"

if [[ "$COUNT" -eq 0 ]]; then
  echo "::notice::No manifest matches ${PAYLOAD_REPOSITORY}. Release recorded and skipped."
  write_decision skip "" "$PAYLOAD_TAG" "unrecognized repository"
  exit 0
fi
# A repository may legitimately own several manifests (one frontend repo builds
# both frontend apps). The only automatic path is prerelease + App Engine, so
# ambiguity is only a failure when more than one App Engine manifest matches.
mapfile -t GAE_MATCHES < <(jq -r --arg repo "$PAYLOAD_REPOSITORY" 'select(.source.repository == $repo and .deploy.platform == "gae") | input_filename' "${MANIFEST_FILES[@]}")
GAE_COUNT="${#GAE_MATCHES[@]}"

if [[ "$GAE_COUNT" -gt 1 ]]; then
  echo "::error::Multiple App Engine manifests match ${PAYLOAD_REPOSITORY}; the stage deploy target is ambiguous."
  printf '  - %s\n' "${GAE_MATCHES[@]}"
  exit 1
fi

if [[ "$GAE_COUNT" -eq 1 ]]; then
  MANIFEST_FILE="${GAE_MATCHES[0]}"
elif [[ "$COUNT" -eq 1 ]]; then
  MANIFEST_FILE="${MATCHES[0]}"
else
  echo "::notice::${COUNT} manifests match ${PAYLOAD_REPOSITORY} and none deploy to App Engine. Release recorded and skipped."
  printf '  - %s\n' "${MATCHES[@]}"
  write_decision skip "" "$PAYLOAD_TAG" "no auto-deployed manifest for repository"
  exit 0
fi

MANIFEST_NAME="$(basename "$MANIFEST_FILE" .json)"
PLATFORM="$(jq -r '.deploy.platform' "$MANIFEST_FILE")"
echo "::notice::Matched ${PAYLOAD_REPOSITORY} to ${MANIFEST_NAME} (${PLATFORM}) ref=${PAYLOAD_REF}"

if [[ "$TAG_IS_PRERELEASE" != "true" ]]; then
  echo "::notice::Stable release ${PAYLOAD_TAG} is not deployed automatically."
  write_decision skip "$MANIFEST_NAME" "$PAYLOAD_TAG" "stable release stays manual"
  exit 0
fi
if [[ "$PLATFORM" != "gae" ]]; then
  echo "::notice::Manifest ${MANIFEST_NAME} uses ${PLATFORM}. Release recorded and skipped."
  write_decision skip "$MANIFEST_NAME" "$PAYLOAD_TAG" "platform is not auto-deployed"
  exit 0
fi

echo "::notice::Stage deploy selected for ${MANIFEST_NAME}@${PAYLOAD_TAG}"
write_decision deploy "$MANIFEST_NAME" "$PAYLOAD_TAG" "prerelease deploys to stage"
