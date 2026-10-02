#!/usr/bin/env bash
#
# Publishes one release fact to the platform repository.
# Step body for .github/actions/publish-release-event/action.yml.
#
# Required environment:
#   GH_TOKEN              Token that can create a repository dispatch.
#   PLATFORM_REPOSITORY   Consumer repository, org/repo.
#   EVENT_TYPE            repository_dispatch event type.
#   TAG_NAME              Bare semver tag.
#   PRERELEASE            "true" or "false"; must agree with TAG_NAME.
#
# Optional environment:
#   SOURCE_REPOSITORY  Empty uses GITHUB_REPOSITORY.
#   SOURCE_REF         Empty uses GITHUB_REF_NAME.
#
# Writes published=true to $GITHUB_OUTPUT after the dispatch is accepted.

set -euo pipefail

STABLE_PAT='^[0-9]+\.[0-9]+\.[0-9]+$'
PRE_PAT='^[0-9]+\.[0-9]+\.[0-9]+-(alpha|beta|rc)\.[1-9][0-9]*$'

if [[ -z "${GH_TOKEN:-}" ]]; then
  echo "::error::DISPATCH_TOKEN is required to publish ${EVENT_TYPE}."
  exit 1
fi
if [[ ! "$PLATFORM_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "::error::platform_repository must be org/repo, got '${PLATFORM_REPOSITORY}'."
  exit 1
fi

# The consumer rejects a v prefix and any tag that is not bare semver,
# so fail here where the message points at the caller.
if [[ ! "$TAG_NAME" =~ $STABLE_PAT && ! "$TAG_NAME" =~ $PRE_PAT ]]; then
  echo "::error::tag_name must be bare semver, for example 1.4.0 or 1.4.0-beta.1. Got '${TAG_NAME}'."
  exit 1
fi
if [[ "$TAG_NAME" == *-* ]]; then
  TAG_IS_PRERELEASE=true
else
  TAG_IS_PRERELEASE=false
fi
if [[ "$PRERELEASE" != "$TAG_IS_PRERELEASE" ]]; then
  echo "::error::prerelease '${PRERELEASE}' does not match tag '${TAG_NAME}'."
  exit 1
fi

REPOSITORY="${SOURCE_REPOSITORY:-$GITHUB_REPOSITORY}"
REF_NAME="${SOURCE_REF:-$GITHUB_REF_NAME}"

gh api --method POST \
  -H "Accept: application/vnd.github+json" \
  "/repos/${PLATFORM_REPOSITORY}/dispatches" \
  -f "event_type=${EVENT_TYPE}" \
  -f "client_payload[repository]=${REPOSITORY}" \
  -f "client_payload[tag_name]=${TAG_NAME}" \
  -f "client_payload[prerelease]=${PRERELEASE}" \
  -f "client_payload[ref]=${REF_NAME}"

echo "published=true" >> "$GITHUB_OUTPUT"
echo "::notice::Published ${EVENT_TYPE} for ${REPOSITORY}@${TAG_NAME} to ${PLATFORM_REPOSITORY}"
