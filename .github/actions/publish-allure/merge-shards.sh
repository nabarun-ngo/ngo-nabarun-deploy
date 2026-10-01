#!/usr/bin/env bash
#
# Merges downloaded Allure result shards into a single results directory.
# Step body for .github/actions/publish-allure/action.yml.
#
# Required environment:
#   SERVER_URL / REPO / RUN_ID  Used to write executor.json for the report.
#
# Reads allure-results-raw/ and writes allure-results/.

set -euo pipefail
mkdir -p allure-results

count=0
while IFS= read -r -d '' f; do
  cp "$f" allure-results/
  count=$((count + 1))
done < <(find allure-results-raw/ \( \
  -name '*.json' -o -name '*.xml' -o -name '*.txt' -o -name '*.png' \
  -o -name '*.html' -o -name '*.jpeg' -o -name '*.jpg' -o -name '*.webm' \
  -o -name '*.log' -o -name '*.attach' -o -name 'environment.properties' \
\) -print0 2>/dev/null || true)

if (( count < 1 )); then
  echo "::error::No Allure result files merged from shard artifacts"
  exit 1
fi
echo "::notice::Merged ${count} result files"

cat > allure-results/executor.json <<EOF
{
  "name": "GitHub Actions",
  "type": "github",
  "buildName": "${RUN_ID}",
  "buildUrl": "${SERVER_URL}/${REPO}/actions/runs/${RUN_ID}"
}
EOF
