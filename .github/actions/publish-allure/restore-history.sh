#!/usr/bin/env bash
#
# Clones the Pages branch and restores prior Allure history for trend lines.
# Step body for .github/actions/publish-allure/action.yml.
#
# Required environment:
#   GH_PAGES_BRANCH / REPORT_BASE_PATH  Publish target.
#   GH_TOKEN                            Token with write access to the branch.
#   REPO                                owner/name of this repository.
#
# Leaves the clone in gh-pages-work/ and history in allure-results/history/.

set -euo pipefail

mkdir -p allure-results/history

if git clone --depth=1 --branch "$GH_PAGES_BRANCH" \
      "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git" \
      gh-pages-work; then
  echo "::notice::Cloned existing ${GH_PAGES_BRANCH} branch"
else
  echo "::notice::${GH_PAGES_BRANCH} missing — creating orphan branch"
  git clone --depth=1 \
    "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git" \
    gh-pages-work
  git -C gh-pages-work checkout --orphan "$GH_PAGES_BRANCH"
  git -C gh-pages-work rm -rf . || true
fi

HISTORY_SRC="gh-pages-work/${REPORT_BASE_PATH}/last-run/history"
if [[ -d "$HISTORY_SRC" ]]; then
  cp -r "${HISTORY_SRC}/." allure-results/history/ || true
  echo "::notice::Restored Allure history from gh-pages last-run"
else
  echo "::notice::No prior Allure history found — first run or history not yet published."
fi
