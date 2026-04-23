#!/usr/bin/env bash
# Configure the github-actions bot identity, commit staged+unstaged changes,
# and force-push to the bump branch.
#
# Required env:
#   BRANCH, COMMIT_MESSAGE

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

: "${BRANCH:?}"

MSG="${COMMIT_MESSAGE:-chore: dependency update}"

git config user.name  "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout -B "$BRANCH"
git add -A
git commit -m "$MSG"
git push --force origin "$BRANCH"
