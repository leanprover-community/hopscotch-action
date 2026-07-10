#!/usr/bin/env bash
# Parse .lake/hopscotch/results.json (hopscotch's public, versioned output)
# into structured GitHub Actions outputs.
#
# Schema: docs/results.schema.json in the hopscotch repo. We accept
# schemaVersions 1–3 — every version whose field semantics this parser
# understands. The fields we read (status, items, firstFailingCommit,
# lastSuccessfulCommit, culpritLogPath, failureStage) are stable across
# all three; the autofix fields (proposedFixes / deprecatedImports /
# detectionNotes, added in v3) default to empty on older outputs. Any
# version outside that set aborts as a tool error so a breaking hopscotch
# change can't silently misreport results.
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
#   culprit_log_path — path to the culprit build log (empty unless stopped)
#   failure_stage    — failing step ("lake update|build|test|lint" / git check)
#   proposed_fix_count       — number of automated boundary repairs proposed
#   deprecated_import_count  — number of live-shim deprecation advisories
#   detection_note_count     — number of human-readable detection notes
#   proposed_fixes_md        — rendered markdown list of proposals (heredoc)
#   deprecated_imports_md    — rendered markdown list of advisories (heredoc)
#   detection_notes_md       — rendered markdown list of notes (heredoc)
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
case "$SCHEMA_VERSION" in
  1|2|3) ;;
  *)
    echo "outcome=tool-error" >> "$GITHUB_OUTPUT"
    die "Unsupported results.json schemaVersion: ${SCHEMA_VERSION} (this action understands 1–3). Bump hopscotch-action's parser."
    ;;
esac

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

TARGET_COMMIT=$(jq -r    '.items[-1] // ""'          "$RESULTS")
CULPRIT=$(jq -r          '.firstFailingCommit // ""' "$RESULTS")
LAST_GOOD=$(jq -r        '.lastSuccessfulCommit // ""' "$RESULTS")
CULPRIT_LOG_PATH=$(jq -r '.culpritLogPath // ""'     "$RESULTS")
FAILURE_STAGE=$(jq -r    '.failureStage // ""'       "$RESULTS")

# Automated-fix detection (schemaVersion 3+; absent fields default to empty).
PROPOSED_FIX_COUNT=$(jq -r      '(.proposedFixes // [])     | length' "$RESULTS")
DEPRECATED_IMPORT_COUNT=$(jq -r '(.deprecatedImports // []) | length' "$RESULTS")
DETECTION_NOTE_COUNT=$(jq -r    '(.detectionNotes // [])    | length' "$RESULTS")

# Render a ProposedFix array (.proposedFixes / .deprecatedImports) into a
# markdown bullet list, drawing solely from the tool's fields: a mapping
# (`old → new, new`), a removal (empty newModules), and a `[partial]` marker
# (with the tool's note) when the fix may be insufficient on its own. We do
# not characterize what kind of fix it is — that comes from the tool.
render_fixes() {
  jq -r --arg field "$1" '
    (.[$field] // [])[] |
    ( if (.newModules | length) == 0
      then "- remove `\(.oldModule)`"
      else "- `\(.oldModule)` → " + (.newModules | map("`" + . + "`") | join(", "))
      end )
    + ( if .partialFix
        then " _[partial" + (if (.note // "") != "" then ": " + .note else "" end) + "]_"
        else "" end )
  ' "$RESULTS"
}

PROPOSED_FIXES_MD=$(render_fixes proposedFixes)
DEPRECATED_IMPORTS_MD=$(render_fixes deprecatedImports)
DETECTION_NOTES_MD=$(jq -r '(.detectionNotes // [])[] | "- " + .' "$RESULTS")

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
  echo "culprit_log_path=$CULPRIT_LOG_PATH"
  echo "failure_stage=$FAILURE_STAGE"
  echo "proposed_fix_count=$PROPOSED_FIX_COUNT"
  echo "deprecated_import_count=$DEPRECATED_IMPORT_COUNT"
  echo "detection_note_count=$DETECTION_NOTE_COUNT"
  echo "proposed_fixes_md<<FIXES_EOF"
  printf '%s\n' "$PROPOSED_FIXES_MD"
  echo "FIXES_EOF"
  echo "deprecated_imports_md<<DEPRECATED_EOF"
  printf '%s\n' "$DEPRECATED_IMPORTS_MD"
  echo "DEPRECATED_EOF"
  echo "detection_notes_md<<NOTES_EOF"
  printf '%s\n' "$DETECTION_NOTES_MD"
  echo "NOTES_EOF"
  echo "summary_md<<SUMMARY_EOF"
  printf '%s\n' "$SUMMARY_MD"
  echo "SUMMARY_EOF"
} >> "$GITHUB_OUTPUT"
