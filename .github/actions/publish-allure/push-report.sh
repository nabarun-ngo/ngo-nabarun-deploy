#!/usr/bin/env bash
#
# Publishes the generated Allure HTML to the Pages branch and prunes old runs.
# Step body for .github/actions/publish-allure/action.yml.
#
# Required environment:
#   GH_TOKEN                            Token with write access to the branch.
#   GH_PAGES_BRANCH / REPORT_BASE_PATH  Publish target.
#   MAX_HISTORY                         Reports to keep; oldest pruned first.
#   RUN_ID / REPO                       Identify this run.
#
# Expects gh-pages-work/ and allure-html/ to exist. Writes report_url to
# $GITHUB_OUTPUT.

set -euo pipefail

if ! [[ "$MAX_HISTORY" =~ ^[0-9]+$ ]] || (( MAX_HISTORY < 1 )); then
  echo "::error::max_history must be a positive integer"
  exit 1
fi

RUN_REPORT_PATH="gh-pages-work/${REPORT_BASE_PATH}/${RUN_ID}"
LAST_RUN_PATH="gh-pages-work/${REPORT_BASE_PATH}/last-run"
RUNS_DIR="gh-pages-work/${REPORT_BASE_PATH}"

mkdir -p "$RUN_REPORT_PATH"
cp -r allure-html/. "$RUN_REPORT_PATH/"

EXISTING_RUNS=$(find "$RUNS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
  | grep -E '^[0-9]+$' | sort -n || true)
TOTAL=$(printf '%s\n' "$EXISTING_RUNS" | grep -c '[^[:space:]]' || true)
TOTAL=${TOTAL:-0}
if (( TOTAL > MAX_HISTORY )); then
  TO_DELETE=$(( TOTAL - MAX_HISTORY ))
  printf '%s\n' "$EXISTING_RUNS" | head -n "$TO_DELETE" | while read -r dir; do
    echo "Pruning old report: ${RUNS_DIR}/${dir}"
    rm -rf "${RUNS_DIR}/${dir}"
  done
fi

rm -rf "$LAST_RUN_PATH"
cp -r "$RUN_REPORT_PATH" "$LAST_RUN_PATH"

cat > "${RUNS_DIR}/index.html" <<EOF
<!DOCTYPE html>
<html>
  <head>
    <meta http-equiv="refresh" content="0; url=last-run/index.html" />
    <title>Allure Report</title>
  </head>
  <body><p>Redirecting to <a href="last-run/index.html">latest report</a>…</p></body>
</html>
EOF

cd gh-pages-work || exit 1
git config user.name  "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add "${REPORT_BASE_PATH}/"
git commit -m "report: allure run ${RUN_ID} [skip ci]" \
  || echo "Nothing to commit"

pushed=0
for attempt in 1 2 3; do
  if git push origin "$GH_PAGES_BRANCH"; then
    pushed=1
    break
  fi
  echo "::warning::gh-pages push attempt ${attempt} rejected — rebase and retry"
  git pull --rebase origin "$GH_PAGES_BRANCH"
done
if (( pushed != 1 )); then
  echo "::error::Failed to push Allure report to ${GH_PAGES_BRANCH}"
  exit 1
fi

PAGES_OWNER=$(echo "$REPO" | cut -d/ -f1)
PAGES_REPONAME=$(echo "$REPO" | cut -d/ -f2)
REPORT_URL="https://${PAGES_OWNER}.github.io/${PAGES_REPONAME}/${REPORT_BASE_PATH}/${RUN_ID}/index.html"

echo "report_url=$REPORT_URL" >> "$GITHUB_OUTPUT"
echo "::notice::Allure report published: $REPORT_URL"
