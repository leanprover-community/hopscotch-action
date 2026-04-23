#!/usr/bin/env bash
# Parse .lake/hopscotch/state.json (and summary.md) into structured outputs.
#
# Emits outputs:
#   outcome          — "passed" | "incompatible" | "skipped" | "tool-error"
#   culprit_commit   — SHA of first failing commit (incompatible only)
#   last_good_commit — SHA of last passing commit
#   target_commit    — SHA the --to ref resolved to
#   new_pin          — dep rev in lake-manifest.json after the run
#   items_count      — number of commits in the bisect range
#   summary_md       — contents of hopscotch's summary.md (heredoc)
#
# Required env:
#   DEP_NAME, PROJECT_DIR, PREVIOUS_PIN, EXIT_CODE, MAX_WINDOW

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

: "${DEP_NAME:?}"
: "${PROJECT_DIR:?}"
: "${MAX_WINDOW:?}"
PREVIOUS_PIN="${PREVIOUS_PIN:-}"
EXIT_CODE="${EXIT_CODE:-0}"

STATE="${PROJECT_DIR}/.lake/hopscotch/state.json"
SUMMARY="${PROJECT_DIR}/.lake/hopscotch/summary.md"
MANIFEST="${PROJECT_DIR}/lake-manifest.json"

if [ ! -f "$STATE" ]; then
  echo "outcome=tool-error" >> "$GITHUB_OUTPUT"
  die "state.json not found — hopscotch did not write state."
fi

STATUS=$(jq -r '.status' "$STATE")
RUN_MODE=$(jq -r '.runMode' "$STATE")
ITEMS_COUNT=$(jq -r '.items | length' "$STATE")

if [ "$ITEMS_COUNT" -gt "$MAX_WINDOW" ]; then
  echo "outcome=tool-error" >> "$GITHUB_OUTPUT"
  die "Commit range (${ITEMS_COUNT} commits) exceeds max-window-size (${MAX_WINDOW}). Increase max-window-size or bump the pin manually."
fi

CULPRIT=""
LAST_GOOD=""
TARGET_COMMIT=$(jq -r '.items[-1] // ""' "$STATE")

case "$STATUS" in
  completed)
    OUTCOME="passed"
    LAST_GOOD="$TARGET_COMMIT"
    ;;
  failed)
    OUTCOME="incompatible"
    if [ "$RUN_MODE" = "bisect" ]; then
      BAD_IDX=$(jq -r '.bisect.knownBadIndex'   "$STATE")
      GOOD_IDX=$(jq -r '.bisect.knownGoodIndex' "$STATE")
      CULPRIT=$(jq -r --argjson i "$BAD_IDX"    '.items[$i]' "$STATE")
      LAST_GOOD=$(jq -r --argjson i "$GOOD_IDX" '.items[$i]' "$STATE")
    else
      CULPRIT=$(jq -r '.currentCommit // ""'          "$STATE")
      LAST_GOOD=$(jq -r '.lastSuccessfulCommit // ""' "$STATE")
    fi
    ;;
  *)
    OUTCOME="tool-error"
    ;;
esac

# Read the pin hopscotch left in lake-manifest.json.
NEW_PIN="$PREVIOUS_PIN"
if [ -f "$MANIFEST" ]; then
  NEW_PIN=$(jq -r --arg dep "$DEP_NAME" \
    '.packages[] | select(.name==$dep) | .rev // empty' \
    "$MANIFEST" | head -1)
fi

# No-op detection: whole range passed and pin is unchanged.
if [ "$OUTCOME" = "passed" ] && [ "$NEW_PIN" = "$PREVIOUS_PIN" ] && [ -n "$PREVIOUS_PIN" ]; then
  OUTCOME="skipped"
fi

SUMMARY_MD=""
[ -f "$SUMMARY" ] && SUMMARY_MD=$(cat "$SUMMARY")

{
  echo "outcome=$OUTCOME"
  echo "culprit_commit=$CULPRIT"
  echo "last_good_commit=$LAST_GOOD"
  echo "target_commit=$TARGET_COMMIT"
  echo "new_pin=$NEW_PIN"
  echo "items_count=$ITEMS_COUNT"
  echo "summary_md<<SUMMARY_EOF"
  printf '%s\n' "$SUMMARY_MD"
  echo "SUMMARY_EOF"
} >> "$GITHUB_OUTPUT"
