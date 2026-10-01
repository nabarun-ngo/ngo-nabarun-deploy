#!/usr/bin/env bash
#
# Resolves the effective git ref for a deployment.
# Step body for .github/actions/resolve-git-ref/action.yml.
#
# Required environment:
#   TAG_NAME        Explicit tag, or 'latest'/empty to auto-resolve.
#   TARGET_BRANCH   Branch that decides the tag stream.
#   REPOSITORY      Source repository in org/repo form.
#   GH_TOKEN        Token with read access to REPOSITORY.
#
# Writes ref, is_latest, and tag_stream to $GITHUB_OUTPUT.

set -euo pipefail

# Validate inputs
if [[ -z "$REPOSITORY" ]]; then
  echo "::error::repository input is required"
  exit 1
fi
if [[ -z "$TARGET_BRANCH" ]]; then
  echo "::error::target_branch input is required"
  exit 1
fi

# If an explicit non-latest tag is given, use it directly
if [[ -n "$TAG_NAME" && "$TAG_NAME" != "latest" ]]; then
  echo "::notice::Using explicit tag: $TAG_NAME"
  echo "ref=$TAG_NAME"      >> "$GITHUB_OUTPUT"
  echo "is_latest=false"   >> "$GITHUB_OUTPUT"
  # Determine stream from tag format
  if [[ "$TAG_NAME" =~ -beta\. || "$TAG_NAME" =~ -rc\. || "$TAG_NAME" =~ -alpha\. ]]; then
    echo "tag_stream=beta" >> "$GITHUB_OUTPUT"
  else
    echo "tag_stream=stable" >> "$GITHUB_OUTPUT"
  fi
  exit 0
fi

# Auto-resolve: only semver tags whose commit is contained in target_branch.
echo "::notice::Auto-resolving latest tag for branch '$TARGET_BRANCH' in $REPOSITORY"

if ! TAG_LINES=$(gh api --paginate "repos/${REPOSITORY}/tags" --jq '.[] | [.name, .commit.sha] | @tsv'); then
  echo "::error::Failed to list tags in $REPOSITORY"
  exit 1
fi
if [[ -z "$TAG_LINES" ]]; then
  echo "::error::No tags found in $REPOSITORY"
  exit 1
fi

if ! gh api "repos/${REPOSITORY}/commits/${TARGET_BRANCH}" --jq .sha >/dev/null; then
  echo "::error::Branch '$TARGET_BRANCH' was not found in $REPOSITORY"
  exit 1
fi

STABLE_PAT='^v?[0-9]+\.[0-9]+\.[0-9]+$'
PRE_PAT='^v?[0-9]+\.[0-9]+\.[0-9]+-(alpha|beta|rc)\.[0-9]+$'
REACHABLE=""
COMPARE_ERR=$(mktemp)

while IFS=$'\t' read -r name sha; do
  [[ -z "$name" || -z "$sha" ]] && continue
  if [[ ! "$name" =~ $STABLE_PAT && ! "$name" =~ $PRE_PAT ]]; then
    continue
  fi
  if ! STATUS=$(gh api "repos/${REPOSITORY}/compare/${sha}...${TARGET_BRANCH}" --jq '.status' 2>"$COMPARE_ERR"); then
    if grep -q '406' "$COMPARE_ERR"; then
      echo "::notice::Skipping tag $name; GitHub compare returned 406 (diff too large)."
      continue
    fi
    echo "::error::Failed to compare tag $name with $TARGET_BRANCH"
    cat "$COMPARE_ERR" >&2
    exit 1
  fi
  if [[ "$STATUS" == "ahead" || "$STATUS" == "identical" ]]; then
    REACHABLE+="${name}"$'\n'
  fi
done <<< "$TAG_LINES"
rm -f "$COMPARE_ERR"

if [[ -z "$REACHABLE" ]]; then
  echo "::error::No semver tags are reachable from '$TARGET_BRANCH' in $REPOSITORY"
  exit 1
fi

pick_latest() {
  local pattern="$1"
  printf '%s' "$REACHABLE" | grep -E "$pattern" | awk '{
    n = $0
    sub(/^v/, "", n)
    print n "\t" $0
  }' | sort -t $'\t' -k1,1V | tail -1 | cut -f2-
}

if [[ "$TARGET_BRANCH" == "main" || "$TARGET_BRANCH" == "production" || "$TARGET_BRANCH" == "prod" ]]; then
  RESOLVED=$(pick_latest "$STABLE_PAT" || true)
  STREAM="stable"
else
  RESOLVED=$(pick_latest "$PRE_PAT" || true)
  if [[ -z "$RESOLVED" ]]; then
    RESOLVED=$(pick_latest "$STABLE_PAT" || true)
    STREAM="stable"
    echo "::notice::No prerelease tag on '$TARGET_BRANCH'; falling back to the latest stable tag on that branch."
  else
    STREAM="beta"
  fi
fi

if [[ -z "$RESOLVED" ]]; then
  echo "::error::Could not resolve a tag for branch '$TARGET_BRANCH' in $REPOSITORY"
  exit 1
fi

echo "::notice::Resolved ref: $RESOLVED (stream: $STREAM)"
echo "ref=$RESOLVED"        >> "$GITHUB_OUTPUT"
echo "is_latest=true"       >> "$GITHUB_OUTPUT"
echo "tag_stream=$STREAM"   >> "$GITHUB_OUTPUT"
