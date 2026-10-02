#!/usr/bin/env bash
#
# Opens or updates the Version Packages pull request after a prerelease exit.
# Step body for .github/actions/open-version-packages-pr/action.yml.
#
# Required environment:
#   WORK_DIR, GH_TOKEN, GH_REPO, CURRENT_BRANCH, VERSION_COMMAND,
#   PR_TITLE, PR_COMMIT, PRERELEASE_TAG
#   GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME, GIT_COMMITTER_EMAIL
#
# Runs $RUNNER_TEMP/version-packages.sh, which reads VERSION_COMMAND and
# PRERELEASE_TAG itself.

set -euo pipefail

if [[ -z "$VERSION_COMMAND" ]]; then
  echo "::error::version_command is empty"
  exit 1
fi
if [[ -z "${WORK_DIR}" ]]; then
  echo "::error::working_directory is required."
  exit 1
fi
cd "$WORK_DIR" || exit 1

bash "$RUNNER_TEMP/version-packages.sh"
git add -A
if git diff --cached --quiet; then
  echo "::error::Prerelease transition did not change the tree, so no Version Packages pull request was opened."
  exit 1
fi

BRANCH="changeset-release/${CURRENT_BRANCH}"
git checkout -B "$BRANCH"
git commit -m "$PR_COMMIT"
if git ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
  git push --force-with-lease origin "HEAD:${BRANCH}"
else
  git push origin "HEAD:${BRANCH}"
fi

if gh pr view "$BRANCH" --repo "$GH_REPO" --json url --jq .url >/dev/null 2>&1; then
  echo "::notice::Updated Version Packages pull request for ${BRANCH}"
else
  gh pr create \
    --repo "$GH_REPO" \
    --base "$CURRENT_BRANCH" \
    --head "$BRANCH" \
    --title "$PR_TITLE" \
    --body "Changesets prerelease transition. Review the version and changelog updates, then merge."
  echo "::notice::Opened Version Packages pull request for ${BRANCH}"
fi
