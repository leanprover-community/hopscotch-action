#!/usr/bin/env bash
# Open (or update) the PR. Emits outputs: pr_number, pr_url, pr_action.
#
# In `pin-to: first-bad` mode the static `hopscotch-action-fix` label is
# applied so close-fix-prs.sh can find these PRs across runs (mirrors how
# manage-issue.sh tags tracking issues with `hopscotch-action`).
#
# Required env:
#   GH_TOKEN, BRANCH, BASE, TITLE, BODY, LABELS, REVIEWERS
# Optional env:
#   PIN_TO (defaults to last-good)

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/github.sh
source "$(dirname "$0")/lib/github.sh"

: "${BRANCH:?}"
TITLE="${TITLE:-chore: dependency update}"
BODY="${BODY:-}"
BASE="${BASE:-}"
LABELS="${LABELS:-}"
REVIEWERS="${REVIEWERS:-}"
PIN_TO="${PIN_TO:-last-good}"

BASE_ARGS=()
[ -n "$BASE" ] && BASE_ARGS=(--base "$BASE")

# parse_labels_csv emits `--label` / `<name>` on alternating lines; mapfile
# collects them into a flat array suitable for `gh pr create`.
mapfile -t LABEL_ARGS < <(parse_labels_csv "$LABELS")

# In fix-PR mode, tag with the static label so close-fix-prs.sh can find
# these PRs across runs.
if [ "$PIN_TO" = "first-bad" ]; then
  FIX_LABEL="hopscotch-action-fix"
  ensure_label "$FIX_LABEL" "0075CA" "Fix PR opened by hopscotch-action"
  LABEL_ARGS+=(--label "$FIX_LABEL")
fi

REVIEWER_ARGS=()
if [ -n "$REVIEWERS" ]; then
  REVIEWER_ARGS=(--reviewer "$REVIEWERS")
fi

EXISTING=$(gh pr list \
  --head "$BRANCH" \
  --state open \
  --json number,url \
  --jq '.[0] // empty')

if [ -n "$EXISTING" ]; then
  PR_NUMBER=$(echo "$EXISTING" | jq -r '.number')
  PR_URL=$(echo "$EXISTING"    | jq -r '.url')
  gh pr edit "$PR_NUMBER" --title "$TITLE" --body "$BODY"
  if [ "$PIN_TO" = "first-bad" ]; then
    # --add-label is idempotent and backfills the static label on pre-existing PRs.
    gh pr edit "$PR_NUMBER" --add-label "hopscotch-action-fix"
  fi
  log "PR #${PR_NUMBER} updated: $PR_URL"
  PR_ACTION="updated"
else
  PR_URL=$(gh pr create \
    --head "$BRANCH" \
    "${BASE_ARGS[@]}" \
    --title "$TITLE" \
    --body "$BODY" \
    "${LABEL_ARGS[@]}" \
    "${REVIEWER_ARGS[@]}")
  PR_NUMBER="${PR_URL##*/}"
  log "PR #${PR_NUMBER} created: $PR_URL"
  PR_ACTION="created"
fi

{
  echo "pr_number=$PR_NUMBER"
  echo "pr_url=$PR_URL"
  echo "pr_action=$PR_ACTION"
} >> "$GITHUB_OUTPUT"
