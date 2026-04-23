#!/usr/bin/env bash
# Read the current dependency rev and upstream URL from lake-manifest.json.
# Emits:
#   previous_pin   — current rev, or empty
#   git_url        — upstream URL, or empty
#   resolved_from  — FROM_INPUT if set, else previous_pin (what `--from` will use)
#
# Required env:
#   DEP_NAME, FROM_INPUT, PROJECT_DIR

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

: "${DEP_NAME:?}"
: "${PROJECT_DIR:?}"
FROM_INPUT="${FROM_INPUT:-}"

MANIFEST="${PROJECT_DIR}/lake-manifest.json"
CURRENT_PIN=""
GIT_URL=""

if [ -f "$MANIFEST" ]; then
  CURRENT_PIN=$(jq -r --arg dep "$DEP_NAME" \
    '.packages[] | select(.name==$dep) | .rev // empty' \
    "$MANIFEST" | head -1)
  GIT_URL=$(jq -r --arg dep "$DEP_NAME" \
    '.packages[] | select(.name==$dep) | .url // empty' \
    "$MANIFEST" | head -1)
fi

RESOLVED_FROM="${FROM_INPUT:-$CURRENT_PIN}"

{
  echo "previous_pin=${CURRENT_PIN}"
  echo "git_url=${GIT_URL}"
  echo "resolved_from=${RESOLVED_FROM}"
} >> "$GITHUB_OUTPUT"
