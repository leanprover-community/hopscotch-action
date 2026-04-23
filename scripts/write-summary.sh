#!/usr/bin/env bash
# Render the GitHub Actions job summary for this run.
#
# Required env:
#   OUTCOME, DEP_NAME, CULPRIT, LAST_GOOD, TARGET, PREV_PIN, NEW_PIN, PR_URL,
#   GIT_URL, SUMMARY_MD

source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/github.sh"

OUTCOME="${OUTCOME:-}"
DEP_NAME="${DEP_NAME:-}"
CULPRIT="${CULPRIT:-}"
LAST_GOOD="${LAST_GOOD:-}"
TARGET="${TARGET:-}"
PREV_PIN="${PREV_PIN:-}"
NEW_PIN="${NEW_PIN:-}"
PR_URL="${PR_URL:-}"
GIT_URL="${GIT_URL:-}"
SUMMARY_MD="${SUMMARY_MD:-}"

{
  echo "## Hopscotch: \`${DEP_NAME}\`"
  echo ""
  case "$OUTCOME" in
    passed)
      echo "**Outcome:** ✅ All commits passed."
      [ -n "$NEW_PIN" ] && [ "$NEW_PIN" != "$PREV_PIN" ] \
        && echo "**Bumped to:** $(commit_link "$NEW_PIN" "$GIT_URL")"
      ;;
    incompatible)
      echo "**Outcome:** ❌ Culprit found."
      echo ""
      [ -n "$CULPRIT" ]   && echo "**First failing commit:** $(commit_link "$CULPRIT" "$GIT_URL")"
      [ -n "$LAST_GOOD" ] && echo "**Last good commit:** $(commit_link "$LAST_GOOD" "$GIT_URL")"
      [ -n "$NEW_PIN" ] && [ "$NEW_PIN" != "$PREV_PIN" ] \
        && echo "**Bumped pin to:** $(commit_link "$NEW_PIN" "$GIT_URL")"
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
  [ -n "$PR_URL" ]   && echo "**Bump PR:** $PR_URL"
  if [ -n "$SUMMARY_MD" ]; then
    echo ""
    echo "### hopscotch summary"
    echo ""
    echo "$SUMMARY_MD"
  fi
} >> "$GITHUB_STEP_SUMMARY"
