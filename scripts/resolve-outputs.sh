#!/usr/bin/env bash
# Consolidate the final PR output triple (action, number, url) depending on
# whether a PR was attempted, whether there were changes to push, and
# whether the remote branch already had the same tree (with an open PR
# pointing at it).
#
# action takes one of:
#   "created"     — opened a fresh PR
#   "updated"     — edited an existing PR's title/body after a force-push
#   "up-to-date"  — remote branch already had identical tree at HEAD with
#                   an open PR; no push, no edit
#   "none"        — no PR work happened (mode said no, or no changes)
#
# Required env:
#   SHOULD_OPEN_PR, NO_CHANGES, TREE_UNCHANGED, PR_NUMBER, PR_URL, PR_ACTION
#   EXISTING_PR_NUMBER, EXISTING_PR_URL

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

SHOULD_OPEN_PR="${SHOULD_OPEN_PR:-false}"
NO_CHANGES="${NO_CHANGES:-}"
TREE_UNCHANGED="${TREE_UNCHANGED:-}"
PR_NUMBER="${PR_NUMBER:-}"
PR_URL="${PR_URL:-}"
PR_ACTION="${PR_ACTION:-created}"
EXISTING_PR_NUMBER="${EXISTING_PR_NUMBER:-}"
EXISTING_PR_URL="${EXISTING_PR_URL:-}"

if [ "$SHOULD_OPEN_PR" != "true" ] || [ "$NO_CHANGES" = "true" ]; then
  {
    echo "action=none"
    echo "pr_number="
    echo "pr_url="
  } >> "$GITHUB_OUTPUT"
elif [ "$TREE_UNCHANGED" = "true" ]; then
  {
    echo "action=up-to-date"
    echo "pr_number=$EXISTING_PR_NUMBER"
    echo "pr_url=$EXISTING_PR_URL"
  } >> "$GITHUB_OUTPUT"
else
  {
    echo "action=$PR_ACTION"
    echo "pr_number=$PR_NUMBER"
    echo "pr_url=$PR_URL"
  } >> "$GITHUB_OUTPUT"
fi
