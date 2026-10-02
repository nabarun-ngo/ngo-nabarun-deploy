#!/usr/bin/env bash
#
# Decides whether versions are already in git and safe to publish.
# Step body for .github/actions/decide-publish-ready/action.yml.
#
# Required environment:
#   WORK_DIR, VERSION_FILE, CURRENT_BRANCH, REF_TYPE, STABLE_BRANCH,
#   PRERELEASE_BRANCH, PRERELEASE_TAG, MANAGE_PRERELEASE, PENDING,
#   PRE_TRANSITION
#
# Writes version_ready and version to $GITHUB_OUTPUT.
# Paths are relative to the workspace root. Do not cd.

set -euo pipefail

write_output() {
  local ready="$1"
  local version="$2"
  {
    echo "version_ready=${ready}"
    echo "version=${version}"
  } >> "$GITHUB_OUTPUT"
}

CS_DIR=".changeset"
if [[ "$WORK_DIR" != "." ]]; then
  CS_DIR="${WORK_DIR}/.changeset"
fi

PENDING_LIST=""
if [[ -d "$CS_DIR" ]]; then
  echo "::group::Changeset directory ${CS_DIR}"
  ls -la "$CS_DIR" || true
  echo "::endgroup::"
  while IFS= read -r -d '' file; do
    base=$(basename "$file")
    if [[ "$base" == "README.md" ]]; then
      continue
    fi
    PENDING_LIST="${PENDING_LIST}${base}"$'\n'
  done < <(find "$CS_DIR" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null || true)
fi

if [[ "$REF_TYPE" != "branch" || ( "$CURRENT_BRANCH" != "$STABLE_BRANCH" && "$CURRENT_BRANCH" != "$PRERELEASE_BRANCH" ) ]]; then
  echo "::error::Ref '$CURRENT_BRANCH' ($REF_TYPE) is neither $STABLE_BRANCH nor $PRERELEASE_BRANCH."
  exit 1
fi

if [[ "$PENDING" -gt 0 || "$PRE_TRANSITION" != "none" ]]; then
  write_output false ""
  echo "::notice::Release changes detected (changesets=$PENDING prerelease_transition=$PRE_TRANSITION); Version Packages PR only."
  echo "::group::Pending changeset files"
  printf '%s' "$PENDING_LIST"
  echo "::endgroup::"
  {
    echo "### Version gate"
    echo ""
    echo "version_ready: \`false\` — $PENDING pending changeset(s), prerelease transition \`$PRE_TRANSITION\`."
    echo ""
    echo '```'
    printf '%s' "$PENDING_LIST"
    echo '```'
  } >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi

PRE_FILE="${CS_DIR}/pre.json"
PRE_MODE=""
PRE_TAG=""
if [[ -f "$PRE_FILE" ]]; then
  PRE_MODE=$(jq -r '.mode // empty' "$PRE_FILE")
  PRE_TAG=$(jq -r '.tag // empty' "$PRE_FILE")
fi

if [[ "$CURRENT_BRANCH" == "$PRERELEASE_BRANCH" ]]; then
  if [[ "$MANAGE_PRERELEASE" == "true" && ( "$PRE_MODE" != "pre" || "$PRE_TAG" != "$PRERELEASE_TAG" ) ]]; then
    write_output false ""
    echo "::notice::$PRERELEASE_BRANCH is not in $PRERELEASE_TAG prerelease mode yet."
    exit 0
  fi
elif [[ -f "$PRE_FILE" ]]; then
  echo "::error::$STABLE_BRANCH still has $PRE_FILE (mode=$PRE_MODE). Refusing to publish a prerelease as latest."
  exit 1
fi

VERSION=""
VERSION_PATH="$VERSION_FILE"
if [[ "$WORK_DIR" != "." && "$VERSION_FILE" != /* ]]; then
  VERSION_PATH="${WORK_DIR}/${VERSION_FILE}"
fi
if [[ -f "$VERSION_PATH" ]]; then
  VERSION=$(jq -r '.version // empty' "$VERSION_PATH")
  if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]]; then
    VERSION=""
  fi
fi

write_output true "$VERSION"
echo "::notice::Version ready for publish on $CURRENT_BRANCH"
{
  echo "### Version gate"
  echo ""
  echo "version_ready: \`true\`"
  echo "prerelease mode: \`${PRE_MODE:-none}\`"
  if [[ -n "$VERSION" ]]; then
    echo "version file: \`$VERSION\` from \`$VERSION_PATH\`"
  fi
} >> "$GITHUB_STEP_SUMMARY"
