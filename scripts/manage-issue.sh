#!/usr/bin/env bash
# Manage the per-dependency tracking issue across runs:
#   - incompatible: create or update
#   - passed:       close the existing issue (if any) with a recovery comment
#   - skipped/tool-error: no-op
#
# When hopscotch proposes an automated fix for the boundary, the issue says
# so and points at `hopscotch fix apply` / the action's fix-PR mode; when it
# can't (a genuine removal), the recorded detection notes explain why.
#
# Emits outputs: issue_number, issue_url
#
# Required env:
#   GH_TOKEN, OUTCOME, DEP_NAME, CULPRIT, LAST_GOOD, GIT_URL,
#   ISSUE_LABELS, CULPRIT_LOG_PATH
# Optional env:
#   FAILURE_STAGE, PROPOSED_FIX_COUNT, PROPOSED_FIXES_MD, DETECTION_NOTES_MD

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
CULPRIT_LOG_PATH="${CULPRIT_LOG_PATH:-}"
FAILURE_STAGE="${FAILURE_STAGE:-}"
PROPOSED_FIX_COUNT="${PROPOSED_FIX_COUNT:-0}"
PROPOSED_FIXES_MD="${PROPOSED_FIXES_MD:-}"
DETECTION_NOTES_MD="${DETECTION_NOTES_MD:-}"

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

# Filter a culprit log file: drop successful-target lines (✔ …) and trace
# lines (trace: .> …), which are noise. Reads from the file path in $1.
filter_culprit_log() {
  local line trimmed
  while IFS= read -r line; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    case "$trimmed" in
      "✔"*|"trace: .>"*) ;;
      *) printf '%s\n' "$line" ;;
    esac
  done < "$1"
}

# Build a collapsible <details> block for the culprit log, or return empty.
build_log_block() {
  local log_path="$1"
  [ -z "$log_path" ] || [ ! -f "$log_path" ] && return 0
  local filtered
  filtered=$(filter_culprit_log "$log_path")
  [ -z "$filtered" ] && return 0
  printf $'<details>\n<summary>Build failure log</summary>\n\n```\n%s\n```\n\n</details>' "$filtered"
}

# Returns: "[`sha7`](https://github.com/repo/commit/sha) — <subject> (<date> (<author>))"
fetch_commit_info() {
  local sha="$1"
  local repo="$2"
  if [ -z "$sha" ]; then
    echo "—"; return
  fi
  local short="${sha:0:7}"
  if [ -z "$repo" ]; then
    echo "\`${short}\`"; return
  fi
  local link="[\`${short}\`](https://github.com/${repo}/commit/${sha})"
  local desc
  desc=$(gh api "repos/${repo}/commits/${sha}" \
    --jq '"\(.commit.message | split("\n")[0]) (\(.commit.author.date[0:10]) (\(.commit.author.name)))"' \
    2>/dev/null) || true
  if [ -n "$desc" ]; then
    echo "${link} — ${desc}"
  else
    echo "$link"
  fi
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

  # Note a non-build failure stage (lake test / lint / git check) so the
  # break isn't mistaken for a plain compile error.
  STAGE_NOTE=""
  [ -n "$FAILURE_STAGE" ] && [ "$FAILURE_STAGE" != "lake build" ] \
    && STAGE_NOTE=" (failed at \`${FAILURE_STAGE}\`)"

  CULPRIT_LINE=""
  [ -n "$CULPRIT" ] && CULPRIT_LINE="First incompatible \`${DEP_NAME}\` commit: ${CULPRIT_INFO}${STAGE_NOTE}."

  LAST_GOOD_LINE=""
  [ -n "$LAST_GOOD" ] && LAST_GOOD_LINE="Last-known-good \`${DEP_NAME}\` commit: ${LAST_GOOD_INFO}."

  # Automated-fix detection: surface a repairable boundary, or explain why
  # the break could not be auto-repaired (a genuine removal).
  FIX_BLOCK=""
  if [ "$PROPOSED_FIX_COUNT" -gt 0 ] && [ -n "$PROPOSED_FIXES_MD" ]; then
    FIX_BLOCK="**An automated fix is available.** hopscotch can repair the broken import(s):

${PROPOSED_FIXES_MD}

Apply locally with \`hopscotch fix apply\`, or run this action in \`pin-to: first-bad\` mode with \`apply-fixes\` to open a ready-to-merge fix PR."
  elif [ -n "$DETECTION_NOTES_MD" ]; then
    FIX_BLOCK="**No automated fix found** — this looks like a genuine breaking change that needs manual work:

${DETECTION_NOTES_MD}"
  fi

  VERIFIED_BLOCK=""
  if [ -n "$DOWNSTREAM_SHA" ]; then
    VERIFIED_BLOCK="Verified when ${DOWNSTREAM_REPO} was at: ${DOWNSTREAM_INFO}.
You can reproduce this break by:
- updating the \`${DEP_NAME}\` rev field in your lakefile to \`${CULPRIT}\`
- running \`lake update ${DEP_NAME}\`
- running \`lake build\`"
  fi

  LOG_BLOCK=$(build_log_block "$CULPRIT_LOG_PATH")

  FOOTER="_Managed by [hopscotch-action](https://github.com/leanprover-community/hopscotch-action). This issue is updated automatically on each run and closed when the regression is resolved._"

  ISSUE_BODY="${MARKER}

${INTRO}

${CULPRIT_LINE}

${LAST_GOOD_LINE}

${VERIFIED_BLOCK}

${FIX_BLOCK}

${LOG_BLOCK}

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
