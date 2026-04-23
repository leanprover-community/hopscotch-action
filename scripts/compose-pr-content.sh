#!/usr/bin/env bash
# Build the bump PR's title, commit message, and body from dep metadata.
#
# Emits outputs: pr_title, commit_message, pr_body (heredoc)
#
# Required env:
#   GH_TOKEN, NEW_PIN, PREVIOUS_PIN, DEP_NAME, GIT_URL, OUTCOME, CULPRIT

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/github.sh
source "$(dirname "$0")/lib/github.sh"

: "${DEP_NAME:?}"
: "${NEW_PIN:?}"
PREVIOUS_PIN="${PREVIOUS_PIN:-}"
GIT_URL="${GIT_URL:-}"
OUTCOME="${OUTCOME:-}"
CULPRIT="${CULPRIT:-}"

REPO=$(repo_from_git_url "$GIT_URL")

fetch_subject() {
  local sha="$1"
  if [ -z "$sha" ] || [ -z "$REPO" ]; then
    echo ""; return
  fi
  gh api "repos/${REPO}/commits/${sha}" \
    --jq '.commit.message | split("\n")[0]' 2>/dev/null || true
}

NEW_SUBJECT=$(fetch_subject "$NEW_PIN")
PREV_SUBJECT=$(fetch_subject "$PREVIOUS_PIN")

NEW_SHORT="${NEW_PIN:0:7}"

PR_TITLE="chore: bump ${DEP_NAME} to ${NEW_SHORT}"
[ -n "$NEW_SUBJECT" ] && PR_TITLE="${PR_TITLE}: ${NEW_SUBJECT}"

COMMIT_MSG="$PR_TITLE"

TARGET_REF=$(commit_link "$NEW_PIN" "$GIT_URL")
PREV_REF=$(commit_link "$PREVIOUS_PIN" "$GIT_URL")

TARGET_LINE="Bump \`${DEP_NAME}\` to ${TARGET_REF}"
[ -n "$NEW_SUBJECT" ] && TARGET_LINE="${TARGET_LINE}: ${NEW_SUBJECT}"

PREV_LINE="Previously at: ${PREV_REF}"
[ -n "$PREV_SUBJECT" ] && PREV_LINE="${PREV_LINE}: ${PREV_SUBJECT}"

CULPRIT_NOTE=""
if [ "$OUTCOME" = "incompatible" ] && [ -n "$CULPRIT" ]; then
  CULPRIT_REF=$(commit_link "$CULPRIT" "$GIT_URL")
  CULPRIT_NOTE=$(printf '\n\n> **Note:** Upstream commit %s is the first known breaking commit. This PR bumps to the last passing revision before it.' "$CULPRIT_REF")
fi

RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
FOOTER="_Updated by [hopscotch-action](https://github.com/leanprover-community/hopscotch-action) · [run](${RUN_URL})_"

PR_BODY=$(printf '%s\n%s%s\n\n%s' \
  "$TARGET_LINE" \
  "$PREV_LINE" \
  "$CULPRIT_NOTE" \
  "$FOOTER")

{
  echo "pr_title=${PR_TITLE}"
  echo "commit_message=${COMMIT_MSG}"
  echo "pr_body<<PR_BODY_EOF"
  printf '%s\n' "$PR_BODY"
  echo "PR_BODY_EOF"
} >> "$GITHUB_OUTPUT"
