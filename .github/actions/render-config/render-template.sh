#!/usr/bin/env bash
#
# Renders a ${VARIABLE} template with envsubst.
# Step body for .github/actions/render-config/action.yml.
#
# Required environment:
#   TEMPLATE_PATH / OUTPUT_PATH  Source template and destination file.
#   EXTRA_VARS                   Newline-delimited VARIABLE=VALUE pairs.
#   STRICT                       "true" fails on leftover placeholders.
#
# Writes output_path to $GITHUB_OUTPUT.

set -euo pipefail

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "::error::Template file not found: $TEMPLATE_PATH"
  exit 1
fi

# Export any extra variables provided as input
if [[ -n "$EXTRA_VARS" ]]; then
  while IFS= read -r line; do
    # Skip empty lines and comments
    [[ -z "$line" || "$line" == \#* ]] && continue
    export "${line?}"
  done <<< "$EXTRA_VARS"
fi

# Create output directory if needed
OUTPUT_DIR=$(dirname "$OUTPUT_PATH")
mkdir -p "$OUTPUT_DIR"

# Run envsubst — substitutes only variables present in the environment
envsubst < "$TEMPLATE_PATH" > "$OUTPUT_PATH"

# Strict mode: detect any remaining ${...} placeholders
if [[ "$STRICT" == "true" ]]; then
  UNRESOLVED=$(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$OUTPUT_PATH" || true)
  if [[ -n "$UNRESOLVED" ]]; then
    echo "::error::Unresolved template variables in $OUTPUT_PATH:"
    echo "$UNRESOLVED" | sort -u | while read -r v; do echo "  $v"; done
    exit 1
  fi
fi

echo "output_path=$OUTPUT_PATH" >> "$GITHUB_OUTPUT"
echo "::notice::Template rendered: $TEMPLATE_PATH → $OUTPUT_PATH"
