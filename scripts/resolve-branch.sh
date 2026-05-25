#!/usr/bin/env bash
# Resolve the effective PR branch name from mode + input + culprit SHA.
#
# `pin-to: last-good` (the bump PR case): branch is literal — defaults to
# `hopscotch/bump`.
#
# `pin-to: first-bad` (the fix PR case): the input is treated as a prefix
# and the final branch is `<prefix>-<fkb-short7>` so fix PRs at different
# FKB SHAs occupy distinct branches and maintainer work on one isn't
# clobbered when the FKB advances. Defaults the prefix to `hopscotch/fix`.
# When there is no culprit (no FKB yet), emits the prefix unchanged — the
# step is harmless in that case because should-open-pr will already be
# false and the branch value is unused.
#
# Emits output: branch
#
# Required env:
#   PIN_TO            — "last-good" | "first-bad"
#   PR_BRANCH_INPUT   — user-supplied branch (or prefix), may be empty
#   CULPRIT           — FKB SHA (may be empty when not in fix mode)

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

PIN_TO="${PIN_TO:-last-good}"
PR_BRANCH_INPUT="${PR_BRANCH_INPUT:-}"
CULPRIT="${CULPRIT:-}"

if [ "$PIN_TO" = "first-bad" ]; then
  PREFIX="${PR_BRANCH_INPUT:-hopscotch/fix}"
  if [ -n "$CULPRIT" ]; then
    BRANCH="${PREFIX}-${CULPRIT:0:7}"
  else
    BRANCH="$PREFIX"
  fi
else
  BRANCH="${PR_BRANCH_INPUT:-hopscotch/bump}"
fi

echo "branch=$BRANCH" >> "$GITHUB_OUTPUT"
