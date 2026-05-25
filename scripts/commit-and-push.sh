#!/usr/bin/env bash
# Configure the git author, commit staged+unstaged changes, and push the
# branch. Pushes are force-pushes by default — branches managed by this
# action are owned by the action.
#
# Idempotency on unchanged input: if the remote branch already has a commit
# whose tree matches the one we just composed *and* an open PR points at
# that branch, skip the force-push (and signal downstream to skip the PR
# edit too). Without this guard, sub-daily reruns force-push a fresh-SHA
# / same-tree commit every tick and churn the awaiting-merge PR with a CI
# rerun and a timeline event for no actual change. The local commit is
# still made so we have a concrete tree to compare against; if the
# comparison says "no push needed" the local commit is simply discarded
# when the runner exits.
#
# When the remote tree matches but no open PR exists (e.g. a closed PR's
# branch was left around), we still push so a fresh PR can be opened.
#
# Push URL: uses an explicit `https://x-access-token:<token>@github.com/...`
# URL with PR_TOKEN (falls back to GH_TOKEN). The `actions/checkout`
# http.extraheader is unset around the push so the in-URL token actually
# takes effect, then restored after. Pass a GitHub App installation token
# as PR_TOKEN to make the resulting PR trigger downstream workflows — the
# default GITHUB_TOKEN's pushes do not.
#
# Emits outputs: tree_unchanged, existing_pr_number, existing_pr_url
#
# Required env:
#   BRANCH, COMMIT_MESSAGE, GH_TOKEN
# Optional env:
#   PR_TOKEN, GIT_USER_NAME, GIT_USER_EMAIL

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

: "${BRANCH:?}"

MSG="${COMMIT_MESSAGE:-chore: dependency update}"
GIT_USER_NAME="${GIT_USER_NAME:-github-actions[bot]}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"

TOKEN="${PR_TOKEN:-${GH_TOKEN:-}}"
if [ -z "$TOKEN" ]; then
  die "no token available for git push (set pr-token or github-token)."
fi

git config user.name  "$GIT_USER_NAME"
git config user.email "$GIT_USER_EMAIL"

# Save and unset the actions/checkout-installed credential header so the
# token embedded in the push URL is the one actually used. Restored at the
# end of the script.
OLD_HEADER=$(git config --local http.https://github.com/.extraheader || true)
git config --unset http.https://github.com/.extraheader || true

PUSH_URL="https://x-access-token:${TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

git checkout -B "$BRANCH"
git add -A
git commit -m "$MSG"

LOCAL_TREE=$(git rev-parse 'HEAD^{tree}')

# Probe the remote branch's tree, if the branch exists.
REMOTE_TREE=""
if git ls-remote --exit-code --heads "$PUSH_URL" "$BRANCH" >/dev/null 2>&1; then
  git fetch --depth=1 "$PUSH_URL" "$BRANCH"
  REMOTE_TREE=$(git rev-parse 'FETCH_HEAD^{tree}')
fi

TREE_UNCHANGED=false
EXISTING_PR_NUMBER=""
EXISTING_PR_URL=""
if [ -n "$REMOTE_TREE" ] && [ "$LOCAL_TREE" = "$REMOTE_TREE" ]; then
  # Tree match alone isn't enough — only short-circuit when an open PR
  # points at the branch. Otherwise a leftover branch from a previously
  # closed PR would suppress opening a fresh one.
  existing=$(GH_TOKEN="${GH_TOKEN:-$TOKEN}" gh pr list \
    --head "$BRANCH" \
    --state open \
    --json number,url \
    --jq '.[0] // empty' 2>/dev/null || true)
  if [ -n "$existing" ]; then
    EXISTING_PR_NUMBER=$(echo "$existing" | jq -r '.number')
    EXISTING_PR_URL=$(echo "$existing"    | jq -r '.url')
    TREE_UNCHANGED=true
  fi
fi

if [ "$TREE_UNCHANGED" = "true" ]; then
  log "Remote '$BRANCH' already at tree $LOCAL_TREE with open PR #$EXISTING_PR_NUMBER — skipping force-push."
else
  git push --force "$PUSH_URL" "$BRANCH"
fi

{
  echo "tree_unchanged=$TREE_UNCHANGED"
  echo "existing_pr_number=$EXISTING_PR_NUMBER"
  echo "existing_pr_url=$EXISTING_PR_URL"
} >> "$GITHUB_OUTPUT"

if [ -n "$OLD_HEADER" ]; then
  git config --local http.https://github.com/.extraheader "$OLD_HEADER"
fi
