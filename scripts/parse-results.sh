#!/usr/bin/env bash
# Parse .lake/hopscotch/results.json (hopscotch's public, versioned output)
# into structured GitHub Actions outputs.
#
# Schema: docs/results.schema.json in the hopscotch repo. We pin to
# schemaVersion = 1; any other value aborts as a tool error so a breaking
# hopscotch change can't silently misreport results.
#
# Outcome is determined directly by `firstFailingCommit`:
#   * null → no failing commit → "passed"
#   * set  → a culprit was identified → "incompatible"
#
# Emits outputs:
#   outcome          — "passed" | "incompatible" | "skipped" | "tool-error"
#   culprit_commit   — firstFailingCommit (empty on passed)
#   last_good_commit — lastSuccessfulCommit (falls back to items[-1] if null)
#   target_commit    — items[-1]
#   new_pin          — dep rev in lake-manifest.json after the run
#   items_count      — items.length
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

RESULTS="${PROJECT_DIR}/.lake/hopscotch/results.json"
SUMMARY="${PROJECT_DIR}/.lake/hopscotch/summary.md"
MANIFEST="${PROJECT_DIR}/lake-manifest.json"

if [ ! -f "$RESULTS" ]; then
  echo "outcome=tool-error" >> "$GITHUB_OUTPUT"
  die "results.json not found — hopscotch did not write structured results."
fi

SCHEMA_VERSION=$(jq -r '.schemaVersion' "$RESULTS")
if [ "$SCHEMA_VERSION" != "1" ]; then
  echo "outcome=tool-error" >> "$GITHUB_OUTPUT"
  die "Unexpected results.json schemaVersion: ${SCHEMA_VERSION} (expected 1). Bump hopscotch-action's parser."
fi

STATUS=$(jq -r '.status' "$RESULTS")
case "$STATUS" in
  stopped|fullySuccessful) ;;
  *)
    echo "outcome=tool-error" >> "$GITHUB_OUTPUT"
    die "Unexpected terminal status '${STATUS}' in results.json — hopscotch did not reach a terminal state."
    ;;
esac

ITEMS_COUNT=$(jq -r '.items | length' "$RESULTS")
if [ "$ITEMS_COUNT" -gt "$MAX_WINDOW" ]; then
  echo "outcome=tool-error" >> "$GITHUB_OUTPUT"
  die "Commit range (${ITEMS_COUNT} commits) exceeds max-window-size (${MAX_WINDOW}). Increase max-window-size or bump the pin manually."
fi

TARGET_COMMIT=$(jq -r '.items[-1] // ""'           "$RESULTS")
CULPRIT=$(jq -r       '.firstFailingCommit // ""'  "$RESULTS")
LAST_GOOD=$(jq -r     '.lastSuccessfulCommit // ""' "$RESULTS")

if [ -z "$CULPRIT" ]; then
  OUTCOME="passed"
  [ -z "$LAST_GOOD" ] && LAST_GOOD="$TARGET_COMMIT"
else
  OUTCOME="incompatible"
fi

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
