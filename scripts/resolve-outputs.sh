#!/usr/bin/env bash
# Consolidate the final PR output triple (action, number, url) depending on
# whether a PR was attempted and whether there were actual changes to push.
#
# Required env:
#   SHOULD_OPEN_PR     ("true" / "false")
#   NO_CHANGES         ("true" / "false")
#   PR_NUMBER, PR_URL, PR_ACTION

source "$(dirname "$0")/lib/common.sh"

SHOULD_OPEN_PR="${SHOULD_OPEN_PR:-false}"
NO_CHANGES="${NO_CHANGES:-}"
PR_NUMBER="${PR_NUMBER:-}"
PR_URL="${PR_URL:-}"
PR_ACTION="${PR_ACTION:-created}"

if [ "$SHOULD_OPEN_PR" != "true" ] || [ "$NO_CHANGES" = "true" ]; then
  {
    echo "action=none"
    echo "pr_number="
    echo "pr_url="
  } >> "$GITHUB_OUTPUT"
else
  {
    echo "action=$PR_ACTION"
    echo "pr_number=$PR_NUMBER"
    echo "pr_url=$PR_URL"
  } >> "$GITHUB_OUTPUT"
fi
