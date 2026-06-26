#!/usr/bin/env bash
# Render the GitHub Actions job summary for this run.
#
# Wording branches on PIN_TO so a fix-PR run reads as such (pinning to the
# FKB) rather than as a bump (advancing past the LKG).
#
# Required env:
#   OUTCOME, DEP_NAME, CULPRIT, LAST_GOOD, TARGET, PREV_PIN, NEW_PIN, PR_URL,
#   GIT_URL, SUMMARY_MD
# Optional env:
#   PIN_TO (defaults to last-good), FAILURE_STAGE, FIXES_APPLIED,
#   PROPOSED_FIX_COUNT, DEPRECATED_IMPORT_COUNT

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/github.sh
source "$(dirname "$0")/lib/github.sh"

OUTCOME="${OUTCOME:-}"
PIN_TO="${PIN_TO:-last-good}"
DEP_NAME="${DEP_NAME:-}"
CULPRIT="${CULPRIT:-}"
LAST_GOOD="${LAST_GOOD:-}"
TARGET="${TARGET:-}"
PREV_PIN="${PREV_PIN:-}"
NEW_PIN="${NEW_PIN:-}"
PR_URL="${PR_URL:-}"
GIT_URL="${GIT_URL:-}"
SUMMARY_MD="${SUMMARY_MD:-}"
FAILURE_STAGE="${FAILURE_STAGE:-}"
FIXES_APPLIED="${FIXES_APPLIED:-false}"
PROPOSED_FIX_COUNT="${PROPOSED_FIX_COUNT:-0}"
DEPRECATED_IMPORT_COUNT="${DEPRECATED_IMPORT_COUNT:-0}"

if [ "$PIN_TO" = "first-bad" ]; then
  HEADING="Hopscotch (fix mode): \`${DEP_NAME}\`"
  PR_LABEL="Fix PR"
else
  HEADING="Hopscotch: \`${DEP_NAME}\`"
  PR_LABEL="Bump PR"
fi

{
  echo "## ${HEADING}"
  echo ""
  case "$OUTCOME" in
    passed)
      if [ "$PIN_TO" = "first-bad" ]; then
        echo "**Outcome:** ✅ No incompatibility — nothing to fix."
      else
        echo "**Outcome:** ✅ All commits passed."
        [ -n "$NEW_PIN" ] && [ "$NEW_PIN" != "$PREV_PIN" ] \
          && echo "**Bumped to:** $(commit_link "$NEW_PIN" "$GIT_URL")"
      fi
      ;;
    incompatible)
      echo "**Outcome:** ❌ Culprit found."
      echo ""
      [ -n "$CULPRIT" ]   && echo "**First failing commit:** $(commit_link "$CULPRIT" "$GIT_URL")"
      [ -n "$LAST_GOOD" ] && echo "**Last good commit:** $(commit_link "$LAST_GOOD" "$GIT_URL")"
      [ -n "$FAILURE_STAGE" ] && [ "$FAILURE_STAGE" != "lake build" ] \
        && echo "**Failed at:** \`${FAILURE_STAGE}\`"
      if [ -n "$NEW_PIN" ] && [ "$NEW_PIN" != "$PREV_PIN" ]; then
        if [ "$PIN_TO" = "first-bad" ]; then
          echo "**Pinned to (FKB):** $(commit_link "$NEW_PIN" "$GIT_URL")"
        else
          echo "**Bumped pin to:** $(commit_link "$NEW_PIN" "$GIT_URL")"
        fi
      fi
      ;;
    skipped)
      echo "**Outcome:** ⏭ Already at target — nothing to do."
      ;;
    tool-error)
      echo "**Outcome:** ⚠️ Tool error — see logs above."
      ;;
  esac
  echo ""
  [ -n "$PREV_PIN" ] && echo "**Previous pin:** \`${PREV_PIN:0:7}\`"
  [ -n "$TARGET" ]   && echo "**Target commit:** \`${TARGET:0:7}\`"
  [ -n "$PR_URL" ]   && echo "**${PR_LABEL}:** $PR_URL"
  if [ "$FIXES_APPLIED" = "true" ]; then
    echo "**Automated fixes:** ✅ applied"
  elif [ "$PROPOSED_FIX_COUNT" -gt 0 ]; then
    echo "**Automated fixes:** ${PROPOSED_FIX_COUNT} proposed (not applied — run \`hopscotch fix apply\`)"
  fi
  [ "$DEPRECATED_IMPORT_COUNT" -gt 0 ] && echo "**Deprecation advisories:** ${DEPRECATED_IMPORT_COUNT}"
  if [ -n "$SUMMARY_MD" ]; then
    echo ""
    echo "### hopscotch summary"
    echo ""
    echo "$SUMMARY_MD"
  fi
} >> "$GITHUB_STEP_SUMMARY"
