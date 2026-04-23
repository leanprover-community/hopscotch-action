#!/usr/bin/env bash
# Manage the per-dependency tracking issue across runs:
#   - incompatible: create or update
#   - passed:       close the existing issue (if any) with a recovery comment
#   - skipped/tool-error: no-op
#
# Emits outputs: issue_number, issue_url
#
# Required env:
#   GH_TOKEN, OUTCOME, DEP_NAME, CULPRIT, LAST_GOOD, TARGET, GIT_URL,
#   ISSUE_LABELS

source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/github.sh"

: "${DEP_NAME:?}"
OUTCOME="${OUTCOME:-}"
CULPRIT="${CULPRIT:-}"
LAST_GOOD="${LAST_GOOD:-}"
TARGET="${TARGET:-}"
GIT_URL="${GIT_URL:-}"
ISSUE_LABELS="${ISSUE_LABELS:-}"

# Stable marker used to locate the tracking issue across runs.
MARKER="<!-- hopscotch-tracking:${DEP_NAME} -->"
ISSUE_TITLE="Hopscotch: ${DEP_NAME} regression detected"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"

# Static label applied to every tracking issue so lookups can filter
# server-side rather than scanning every issue in the repo.
HOPSCOTCH_LABEL="hopscotch"
ensure_label "$HOPSCOTCH_LABEL" "eec9fd" "Managed by hopscotch-action"

# Find an existing open tracking issue. Label pre-filters; jq matches the
# per-dependency marker in the body.
ISSUE_LINE=$(gh issue list \
  --label "$HOPSCOTCH_LABEL" \
  --state open \
  --json number,url,body \
  2>/dev/null \
  | jq -r --arg m "hopscotch-tracking:${DEP_NAME}" \
      '.[] | select(.body | contains($m)) | "\(.number) \(.url)"' \
  | head -1 || true)

ISSUE_NUMBER=$(echo "$ISSUE_LINE" | awk 'NF{print $1}')
ISSUE_URL=$(echo "$ISSUE_LINE"    | awk 'NF{print $2}')

if [ "$OUTCOME" = "incompatible" ]; then
  CULPRIT_LINE=""
  [ -n "$CULPRIT" ]   && CULPRIT_LINE="**First failing commit:** $(commit_link "$CULPRIT" "$GIT_URL")"
  LAST_GOOD_LINE=""
  [ -n "$LAST_GOOD" ] && LAST_GOOD_LINE="**Last known-good commit:** $(commit_link "$LAST_GOOD" "$GIT_URL")"
  TARGET_LINE=""
  [ -n "$TARGET" ]    && TARGET_LINE="**Target ref tested:** \`${TARGET:0:7}\`"

  ISSUE_BODY=$(printf '%s\n\nThe \`%s\` dependency has a breaking upstream commit.\n\n%s\n%s\n%s\n\n[View run](%s)\n\n%s' \
    "$MARKER" \
    "$DEP_NAME" \
    "$CULPRIT_LINE" \
    "$LAST_GOOD_LINE" \
    "$TARGET_LINE" \
    "$RUN_URL" \
    "_Managed by [hopscotch-action](https://github.com/leanprover-community/hopscotch-action). This issue is updated automatically on each run and closed when the regression is resolved._")

  mapfile -t LABEL_ARGS < <(parse_labels_csv "$ISSUE_LABELS")

  if [ -n "$ISSUE_NUMBER" ]; then
    # --add-label is idempotent and backfills the static label on pre-existing issues.
    gh issue edit "$ISSUE_NUMBER" \
      --title "$ISSUE_TITLE" \
      --body "$ISSUE_BODY" \
      --add-label "$HOPSCOTCH_LABEL"
    log "Tracking issue #${ISSUE_NUMBER} updated."
  else
    ISSUE_URL=$(gh issue create \
      --title "$ISSUE_TITLE" \
      --body "$ISSUE_BODY" \
      --label "$HOPSCOTCH_LABEL" \
      "${LABEL_ARGS[@]}")
    ISSUE_NUMBER="${ISSUE_URL##*/}"
    log "Tracking issue #${ISSUE_NUMBER} created: $ISSUE_URL"
  fi

elif [ "$OUTCOME" = "passed" ]; then
  if [ -n "$ISSUE_NUMBER" ]; then
    RECOVERY_MSG=$(printf '✅ **Regression resolved.**\n\nThe downstream built successfully against the upstream. Closing this issue.\n\n[View run](%s)' "$RUN_URL")
    gh issue comment "$ISSUE_NUMBER" --body "$RECOVERY_MSG"
    gh issue close "$ISSUE_NUMBER"
    log "Tracking issue #${ISSUE_NUMBER} closed (regression resolved)."
  fi
  ISSUE_NUMBER=""
  ISSUE_URL=""
fi

{
  echo "issue_number=${ISSUE_NUMBER}"
  echo "issue_url=${ISSUE_URL}"
} >> "$GITHUB_OUTPUT"
