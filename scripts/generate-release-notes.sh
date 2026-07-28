#!/usr/bin/env bash
# generate-release-notes.sh
# Usage: generate-release-notes.sh <tag_name> <git_log_range>
# Outputs: Markdown-formatted release notes to stdout.
#
# Groups commits by conventional commit type.
# Works with merge commits whose subjects follow the pattern:
#   feat(scope): description
#   fix: description
#   chore: description
#   BREAKING CHANGE: description

set -euo pipefail

TAG_NAME="${1:-HEAD}"
LOG_RANGE="${2:-HEAD}"

echo "## Release — ${TAG_NAME}"
echo ""
echo "> $(date -u '+%Y-%m-%d')"
echo ""

# Collect commits in range
COMMITS=$(git log "$LOG_RANGE" \
  --pretty=format:"%H|%s|%an" \
  --no-merges \
  2>/dev/null || git log --pretty=format:"%H|%s|%an" --no-merges)

if [[ -z "$COMMITS" ]]; then
  echo "_No conventional commits found in this range._"
  exit 0
fi

declare -A SECTIONS
SECTIONS[breaking]="### 💥 Breaking Changes"
SECTIONS[feat]="### ✨ Features"
SECTIONS[fix]="### 🐛 Bug Fixes"
SECTIONS[perf]="### ⚡ Performance"
SECTIONS[refactor]="### ♻️  Refactors"
SECTIONS[chore]="### 🔧 Chores"
SECTIONS[docs]="### 📝 Documentation"
SECTIONS[other]="### 🔀 Other"

declare -A LINES

while IFS='|' read -r HASH SUBJECT AUTHOR; do
  [[ -z "$HASH" ]] && continue

  SHORT_HASH="${HASH:0:7}"

  if echo "$SUBJECT" | grep -qiE 'BREAKING CHANGE|^[a-z]+(\([^)]+\))?!:'; then
    LINES[breaking]+="- ${SUBJECT} (\`${SHORT_HASH}\`) — ${AUTHOR}\n"
  elif echo "$SUBJECT" | grep -qiE '^feat(\([^)]+\))?:'; then
    SCOPE=$(echo "$SUBJECT" | sed -n 's/^feat(\([^)]*\)):.*/\1/p')
    DESC=$(echo "$SUBJECT" | sed 's/^feat([^)]*): //' | sed 's/^feat: //')
    [[ -n "$SCOPE" ]] && DESC="**${SCOPE}**: ${DESC}"
    LINES[feat]+="- ${DESC} (\`${SHORT_HASH}\`)\n"
  elif echo "$SUBJECT" | grep -qiE '^fix(\([^)]+\))?:'; then
    DESC=$(echo "$SUBJECT" | sed 's/^fix([^)]*): //' | sed 's/^fix: //')
    LINES[fix]+="- ${DESC} (\`${SHORT_HASH}\`)\n"
  elif echo "$SUBJECT" | grep -qiE '^perf(\([^)]+\))?:'; then
    DESC=$(echo "$SUBJECT" | sed 's/^perf([^)]*): //' | sed 's/^perf: //')
    LINES[perf]+="- ${DESC} (\`${SHORT_HASH}\`)\n"
  elif echo "$SUBJECT" | grep -qiE '^refactor(\([^)]+\))?:'; then
    DESC=$(echo "$SUBJECT" | sed 's/^refactor([^)]*): //' | sed 's/^refactor: //')
    LINES[refactor]+="- ${DESC} (\`${SHORT_HASH}\`)\n"
  elif echo "$SUBJECT" | grep -qiE '^(chore|build|ci|style|test)(\([^)]+\))?:'; then
    DESC=$(echo "$SUBJECT" | sed 's/^[a-z]*([^)]*): //' | sed 's/^[a-z]*: //')
    LINES[chore]+="- ${DESC} (\`${SHORT_HASH}\`)\n"
  elif echo "$SUBJECT" | grep -qiE '^docs(\([^)]+\))?:'; then
    DESC=$(echo "$SUBJECT" | sed 's/^docs([^)]*): //' | sed 's/^docs: //')
    LINES[docs]+="- ${DESC} (\`${SHORT_HASH}\`)\n"
  else
    LINES[other]+="- ${SUBJECT} (\`${SHORT_HASH}\`)\n"
  fi
done <<< "$COMMITS"

# Output sections in priority order
for KEY in breaking feat fix perf refactor chore docs other; do
  if [[ -n "${LINES[$KEY]:-}" ]]; then
    echo "${SECTIONS[$KEY]}"
    echo ""
    printf "%b" "${LINES[$KEY]}"
    echo ""
  fi
done
