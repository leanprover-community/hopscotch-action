#!/usr/bin/env bash
# Manage the per-dependency tracking issue across runs:
#   - incompatible: create or update
#   - passed:       close the existing issue (if any) with a recovery comment
#   - skipped/tool-error: no-op
#
# Emits outputs: issue_number, issue_url
#
# Required env:
#   GH_TOKEN, OUTCOME, DEP_NAME, CULPRIT, LAST_GOOD, GIT_URL,
#   ISSUE_LABELS

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/github.sh
source "$(dirname "$0")/lib/github.sh"

: "${DEP_NAME:?}"
OUTCOME="${OUTCOME:-}"
CULPRIT="${CULPRIT:-}"
LAST_GOOD="${LAST_GOOD:-}"
GIT_URL="${GIT_URL:-}"
ISSUE_LABELS="${ISSUE_LABELS:-}"

# Stable marker used to locate the tracking issue across runs.
MARKER="<!-- hopscotch-tracking:${DEP_NAME} -->"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"

# Static label applied to every tracking issue so lookups can filter
# server-side rather than scanning every issue in the repo.
HOPSCOTCH_LABEL="hopscotch-action"
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

# Returns: "<sha7> — <subject> (<date> (<author>))"
fetch_commit_info() {
  local sha="$1"
  local repo="$2"
  if [ -z "$sha" ] || [ -z "$repo" ]; then
    echo "${sha:0:7}"; return
  fi
  gh api "repos/${repo}/commits/${sha}" \
    --jq '"\(.sha[0:7]) — \(.commit.message | split("\n")[0]) (\(.commit.author.date[0:10]) (\(.commit.author.name)))"' \
    2>/dev/null || echo "${sha:0:7}"
}

if [ "$OUTCOME" = "incompatible" ]; then
  ISSUE_TITLE="Bumping ${DEP_NAME} to ${CULPRIT:0:7} would break the build"
  REPO=$(repo_from_git_url "$GIT_URL")
  DOWNSTREAM_REPO="${GITHUB_REPOSITORY:-}"
  DOWNSTREAM_SHA="${GITHUB_SHA:-}"

  CULPRIT_INFO=$(fetch_commit_info "$CULPRIT" "$REPO")
  LAST_GOOD_INFO=$(fetch_commit_info "$LAST_GOOD" "$REPO")
  DOWNSTREAM_INFO=$(fetch_commit_info "$DOWNSTREAM_SHA" "$DOWNSTREAM_REPO")

  INTRO="An incompatibility has been detected between this project and recent changes in \`${DEP_NAME}\`.
In other words, this project can't advance to the tip of \`${DEP_NAME}\` without breaking."

  CULPRIT_LINE=""
  [ -n "$CULPRIT" ] && CULPRIT_LINE="First incompatible \`${DEP_NAME}\` commit: \`${CULPRIT_INFO}\`."

  LAST_GOOD_LINE=""
  [ -n "$LAST_GOOD" ] && LAST_GOOD_LINE="Last-known-good \`${DEP_NAME}\` commit: \`${LAST_GOOD_INFO}\`."

  VERIFIED_BLOCK=""
  if [ -n "$DOWNSTREAM_SHA" ]; then
    VERIFIED_BLOCK="Verified when ${DOWNSTREAM_REPO} was at: \`${DOWNSTREAM_INFO}\`.
You can reproduce this break by:
- updating the \`${DEP_NAME}\` rev field in your lakefile to \`${CULPRIT}\`
- running \`lake update ${DEP_NAME}\`
- running \`lake build\`"
  fi

  FOOTER="_Managed by [hopscotch-action](https://github.com/leanprover-community/hopscotch-action). This issue is updated automatically on each run and closed when the regression is resolved._"

  ISSUE_BODY="${MARKER}

${INTRO}

${CULPRIT_LINE}

${LAST_GOOD_LINE}

${VERIFIED_BLOCK}

${FOOTER}"

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
