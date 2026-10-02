#!/usr/bin/env bash
#
# Stages the production deploy bundle from a built Node.js app.
# Step body for .github/actions/stage-node-artifact/action.yml.
#
# Required environment:
#   BUILD_ROOT / APP_ROOT  Source layout; APP_ROOT wins when set.
#   OUTPUT_PATH            Build output directory under the source base.
#   BUNDLE_INCLUDES        Comma-separated extra paths to copy in.
#   ARTIFACT_NAME          Artifact name, logged for traceability.
#
# Writes bundle_dir to $GITHUB_OUTPUT.

set -euo pipefail

BUNDLE_DIR="deploy-bundle"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"

# If app_root is set, stage from there; otherwise use build_root.
# This covers both single-app repos and monorepo workspaces without
# needing an explicit layout flag.
if [[ -n "$APP_ROOT" ]]; then
  SRC_BASE="$APP_ROOT"
else
  SRC_BASE="$BUILD_ROOT"
fi

echo "::group::Stage bundle"
echo "Staging output from: $SRC_BASE/$OUTPUT_PATH"
echo "build_root=$BUILD_ROOT app_root=$APP_ROOT output_path=$OUTPUT_PATH"
echo "bundle_includes=$BUNDLE_INCLUDES artifact=$ARTIFACT_NAME"
echo "::endgroup::"
cp -r "$SRC_BASE/$OUTPUT_PATH" "$BUNDLE_DIR/dist"

# Copy package.json and production lock file
if [[ -f "$SRC_BASE/package.json" ]]; then
  cp "$SRC_BASE/package.json" "$BUNDLE_DIR/"
fi
if [[ -f "$SRC_BASE/package-lock.json" ]]; then
  cp "$SRC_BASE/package-lock.json" "$BUNDLE_DIR/"
fi

# Install production node_modules into the bundle
cd "$BUNDLE_DIR" || exit 1
npm ci --omit=dev --ignore-scripts 2>&1 | tail -5
cd - || exit 1

# Stage extra includes (e.g. prisma schema, migrations)
if [[ -n "$BUNDLE_INCLUDES" ]]; then
  IFS=',' read -ra EXTRAS <<< "$BUNDLE_INCLUDES"
  for EXTRA in "${EXTRAS[@]}"; do
    EXTRA=$(echo "$EXTRA" | xargs)
    EXTRA_SRC="$SRC_BASE/$EXTRA"
    if [[ -e "$EXTRA_SRC" ]]; then
      echo "Including extra: $EXTRA"
      cp -r "$EXTRA_SRC" "$BUNDLE_DIR/$EXTRA"
    else
      echo "::warning::bundle_includes entry '$EXTRA' not found at '$EXTRA_SRC', skipping."
    fi
  done
fi

# Copy start.sh from the platform checkout. Prefer platform/ so a called
# workflow uses the ref it was invoked at, then the workspace root for a
# job that already checked this repository out there.
START_SH="platform/config/platforms/gae/start.sh"
if [[ ! -f "$START_SH" ]]; then
  START_SH="config/platforms/gae/start.sh"
fi
if [[ -f "$START_SH" ]]; then
  cp "$START_SH" "$BUNDLE_DIR/start.sh"
  chmod +x "$BUNDLE_DIR/start.sh"
fi

echo "bundle_dir=$BUNDLE_DIR" >> "$GITHUB_OUTPUT"
echo "::notice::Bundle staged at $BUNDLE_DIR"
du -sh "$BUNDLE_DIR"
