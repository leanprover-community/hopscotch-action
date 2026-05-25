#!/usr/bin/env bash
# Build the PR's title, commit message, and body from dep metadata.
#
# Two PR shapes, selected by PIN_TO:
#   last-good (bump PR)  — title "chore: bump <dep> to <short>"; body lists
#                          the new pin, previous pin, commit count, and a
#                          breaking-commit note if applicable.
#   first-bad (fix PR)   — title "fix: bump <dep> to <fkb-short>, fix
#                          breaking changes"; body explains the PR pins to
#                          the FKB so the maintainer can check out the
#                          branch and reproduce the break. Includes a
#                          collapsible build-failure log when available.
#
# Emits outputs: pr_title, commit_message, pr_body (heredoc)
#
# Required env:
#   GH_TOKEN, NEW_PIN, PREVIOUS_PIN, DEP_NAME, GIT_URL, OUTCOME, CULPRIT
# Optional env:
#   PIN_TO (defaults to last-good), LAST_GOOD, CULPRIT_LOG_PATH

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=lib/github.sh
source "$(dirname "$0")/lib/github.sh"

: "${DEP_NAME:?}"
: "${NEW_PIN:?}"
PIN_TO="${PIN_TO:-last-good}"
PREVIOUS_PIN="${PREVIOUS_PIN:-}"
GIT_URL="${GIT_URL:-}"
OUTCOME="${OUTCOME:-}"
CULPRIT="${CULPRIT:-}"
LAST_GOOD="${LAST_GOOD:-}"
CULPRIT_LOG_PATH="${CULPRIT_LOG_PATH:-}"

REPO=$(repo_from_git_url "$GIT_URL")

fetch_subject() {
  local sha="$1"
  if [ -z "$sha" ] || [ -z "$REPO" ]; then
    echo ""; return
  fi
  gh api "repos/${REPO}/commits/${sha}" \
    --jq '.commit.message | split("\n")[0]' 2>/dev/null || true
}

fetch_commit_count() {
  local base="$1" head="$2"
  if [ -z "$base" ] || [ -z "$head" ] || [ -z "$REPO" ]; then
    echo ""; return
  fi
  gh api "repos/${REPO}/compare/${base}...${head}" \
    --jq '.ahead_by' 2>/dev/null || true
}

# Filter and wrap a culprit log file into a collapsible <details> block, or
# return empty when no log is available. Mirrors manage-issue.sh.
build_log_block() {
  local log_path="$1"
  if [ -z "$log_path" ] || [ ! -f "$log_path" ]; then
    return 0
  fi
  local filtered line trimmed
  filtered=$(
    while IFS= read -r line; do
      trimmed="${line#"${line%%[![:space:]]*}"}"
      trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
      case "$trimmed" in
        "✔"*|"trace: .>"*) ;;
        *) printf '%s\n' "$line" ;;
      esac
    done < "$log_path"
  )
  [ -z "$filtered" ] && return 0
  printf $'<details>\n<summary>Build failure log</summary>\n\n```\n%s\n```\n\n</details>' "$filtered"
}

NEW_SHORT="${NEW_PIN:0:7}"
NEW_SUBJECT=$(fetch_subject "$NEW_PIN")

RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"

if [ "$PIN_TO" = "first-bad" ]; then
  PR_TITLE="fix: bump ${DEP_NAME} to ${NEW_SHORT}, fix breaking changes"
  COMMIT_MSG="$PR_TITLE"

  TARGET_REF=$(commit_link "$NEW_PIN" "$GIT_URL")
  TARGET_LINE="Pin \`${DEP_NAME}\` to ${TARGET_REF}"
  [ -n "$NEW_SUBJECT" ] && TARGET_LINE="${TARGET_LINE}: ${NEW_SUBJECT}"

  LAST_GOOD_LINE=""
  if [ -n "$LAST_GOOD" ]; then
    LAST_GOOD_REF=$(commit_link "$LAST_GOOD" "$GIT_URL")
    LAST_GOOD_LINE=$'\n'"Last-known-good \`${DEP_NAME}\` commit: ${LAST_GOOD_REF}"
  fi

  LOG_BLOCK=$(build_log_block "$CULPRIT_LOG_PATH")
  LOG_SECTION=""
  [ -n "$LOG_BLOCK" ] && LOG_SECTION=$'\n\n'"$LOG_BLOCK"

  # shellcheck disable=SC2016
  # Backticks are markdown literals — %s does the actual expansion.
  EXPLAINER=$(printf 'This PR bumps `%s` to the first-known-bad commit so you can check out the branch and reproduce the break locally.' "$DEP_NAME")

  FOOTER="_Opened by [hopscotch-action](https://github.com/leanprover-community/hopscotch-action) · [run](${RUN_URL})_"

  PR_BODY=$(printf '%s%s%s\n\n%s\n\n%s' \
    "$TARGET_LINE" \
    "$LAST_GOOD_LINE" \
    "$LOG_SECTION" \
    "$EXPLAINER" \
    "$FOOTER")
else
  PREV_SUBJECT=$(fetch_subject "$PREVIOUS_PIN")
  COMMIT_COUNT=$(fetch_commit_count "$PREVIOUS_PIN" "$NEW_PIN")

  PR_TITLE="chore: bump ${DEP_NAME} to ${NEW_SHORT}"
  COMMIT_MSG="$PR_TITLE"

  TARGET_REF=$(commit_link "$NEW_PIN" "$GIT_URL")
  PREV_REF=$(commit_link "$PREVIOUS_PIN" "$GIT_URL")

  TARGET_LINE="Bump \`${DEP_NAME}\` to ${TARGET_REF}"
  [ -n "$NEW_SUBJECT" ] && TARGET_LINE="${TARGET_LINE}: ${NEW_SUBJECT}"

  PREV_LINE="Previously at: ${PREV_REF}"
  [ -n "$PREV_SUBJECT" ] && PREV_LINE="${PREV_LINE}: ${PREV_SUBJECT}"

  COMMIT_COUNT_LINE=""
  [ -n "$COMMIT_COUNT" ] && COMMIT_COUNT_LINE=$'\n'"This bump advances the dependency by ${COMMIT_COUNT} commits."

  CULPRIT_NOTE=""
  if [ "$OUTCOME" = "incompatible" ] && [ -n "$CULPRIT" ]; then
    CULPRIT_REF=$(commit_link "$CULPRIT" "$GIT_URL")
    CULPRIT_NOTE=$(printf '\n\n> **Note:** Upstream commit %s is the first known breaking commit. This PR bumps to the last passing revision before it.' "$CULPRIT_REF")
  fi

  FOOTER="_Updated by [hopscotch-action](https://github.com/leanprover-community/hopscotch-action) · [run](${RUN_URL})_"

  PR_BODY=$(printf '%s\n%s%s%s\n\n%s' \
    "$TARGET_LINE" \
    "$PREV_LINE" \
    "$COMMIT_COUNT_LINE" \
    "$CULPRIT_NOTE" \
    "$FOOTER")
fi

{
  echo "pr_title=${PR_TITLE}"
  echo "commit_message=${COMMIT_MSG}"
  echo "pr_body<<PR_BODY_EOF"
  printf '%s\n' "$PR_BODY"
  echo "PR_BODY_EOF"
} >> "$GITHUB_OUTPUT"
