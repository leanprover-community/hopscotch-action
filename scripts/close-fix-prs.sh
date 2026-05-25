#!/usr/bin/env bash
# Close fix PRs that are no longer current. Runs only in
# `pin-to: first-bad` mode (gated externally by action.yml).
#
# Open fix PRs are identified by the static `hopscotch-action-fix` label
# applied in create-or-update-pr.sh.
#
# Two close paths:
#   recovery  — OUTCOME=passed: the regression cleared. Close every open
#               fix PR with a "resolved" comment.
#   stale     — OUTCOME=incompatible with a new CULPRIT: close PRs whose
#               head branch isn't the current FKB branch. The branch is
#               not deleted, so any maintainer WIP commits remain
#               reachable.
#
# When OUTCOME is neither `passed` nor `incompatible` (skipped, tool-error)
# the step is a no-op — we have no signal to act on.
#
# Required env:
#   GH_TOKEN, OUTCOME, CULPRIT, CURRENT_BRANCH, GIT_URL

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/github.sh
source "$(dirname "$0")/lib/github.sh"

OUTCOME="${OUTCOME:-}"
CULPRIT="${CULPRIT:-}"
CURRENT_BRANCH="${CURRENT_BRANCH:-}"
GIT_URL="${GIT_URL:-}"

FIX_LABEL="hopscotch-action-fix"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"

case "$OUTCOME" in
  passed|incompatible) ;;
  *)
    log "Outcome '$OUTCOME' is not actionable for fix-PR cleanup — skipping."
    exit 0
    ;;
esac

# Look up open PRs by the static label. Empty list means nothing to do.
OPEN_PRS=$(gh pr list \
  --label "$FIX_LABEL" \
  --state open \
  --json number,headRefName,url \
  2>/dev/null || echo '[]')

PR_COUNT=$(echo "$OPEN_PRS" | jq 'length')
if [ "$PR_COUNT" -eq 0 ]; then
  log "No open fix PRs with label '$FIX_LABEL' — nothing to close."
  exit 0
fi

while IFS= read -r pr; do
  PR_NUMBER=$(echo "$pr" | jq -r '.number')
  PR_URL=$(echo "$pr"    | jq -r '.url')
  HEAD_REF=$(echo "$pr"  | jq -r '.headRefName')

  if [ "$OUTCOME" = "passed" ]; then
    COMMENT=$(printf '✅ **Regression resolved.**\n\nThe downstream now builds against the upstream tip. Closing this fix PR.\n\n[View run](%s)' "$RUN_URL")
    gh pr comment "$PR_NUMBER" --body "$COMMENT"
    gh pr close "$PR_NUMBER"
    log "Closed fix PR #${PR_NUMBER} (recovery): $PR_URL"
    continue
  fi

  # OUTCOME=incompatible: close if the head branch isn't the current FKB
  # branch (stale).
  if [ -n "$CURRENT_BRANCH" ] && [ "$HEAD_REF" = "$CURRENT_BRANCH" ]; then
    log "Fix PR #${PR_NUMBER} on '$HEAD_REF' is current — keeping."
    continue
  fi

  FKB_REF=$(commit_link "$CULPRIT" "$GIT_URL")
  # shellcheck disable=SC2016
  # Backticks in the format string are markdown — the %s slots do the
  # actual variable expansion.
  COMMENT=$(printf 'The first-known-bad commit has advanced to %s; this PR'\''s lakefile is now outdated.\n\nA new fix PR will be opened on branch `%s`.\n\n_Closed automatically by [this workflow run](%s)._' \
    "$FKB_REF" "$CURRENT_BRANCH" "$RUN_URL")
  gh pr comment "$PR_NUMBER" --body "$COMMENT"
  gh pr close "$PR_NUMBER"
  log "Closed stale fix PR #${PR_NUMBER} (was on '$HEAD_REF'): $PR_URL"
done < <(echo "$OPEN_PRS" | jq -c '.[]')
