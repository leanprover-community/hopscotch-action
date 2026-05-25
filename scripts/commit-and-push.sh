#!/usr/bin/env bash
# Configure the git author, commit staged+unstaged changes, and push the
# branch. Pushes are force-pushes by default — branches managed by this
# action are owned by the action.
#
# Three short-circuits suppress the push (and signal downstream to skip
# the PR edit too):
#
#   1. Tree match. If the remote branch already has a commit whose tree
#      matches the one we just composed *and* an open PR points at that
#      branch, skip the push. Without this guard, sub-daily reruns
#      force-push a fresh-SHA / same-tree commit every tick and churn the
#      awaiting-merge PR with a CI rerun and a timeline event for no
#      actual change.
#
#   2. Maintainer-owned branch. The whole point of a fix PR is that a
#      maintainer can `gh pr checkout` it and push their fix on top — but
#      a follow-up action run would then `git push --force` over their
#      work. Mitigation: before pushing, look at the remote HEAD's
#      committer email. If it doesn't match GIT_USER_EMAIL (a maintainer
#      pushed), skip the push. The action's WIP commits on bot-owned
#      branches still get force-pushed normally because they were made by
#      the bot identity.
#
#      Caveats: this is a heuristic. Branches modified via a GitHub merge
#      / squash button get the actor's identity, which won't match
#      GIT_USER_EMAIL — that's the right call. Branches the maintainer
#      pushes commits to as the bot account (rare) will be incorrectly
#      treated as ours. Document accordingly.
#
#   3. No remote branch but a closed PR's branch was deleted (handled
#      naturally — REMOTE_TREE stays empty and we just push fresh).
#
# When a tree match exists but no open PR points at the branch
# (e.g. a closed PR's branch lingering), we still push so that the
# create-or-update-pr step can open a fresh PR for it.
#
# Push URL: uses an explicit `https://x-access-token:<token>@github.com/...`
# URL with PR_TOKEN (falls back to GH_TOKEN). The `actions/checkout`
# http.extraheader is unset around the push so the in-URL token actually
# takes effect — a trap restores it on any exit so a push failure can't
# leave the repo in a half-configured state. Pass a GitHub App
# installation token as PR_TOKEN to make the resulting PR trigger
# downstream workflows — the default GITHUB_TOKEN's pushes do not.
#
# Emits outputs: tree_unchanged, existing_pr_number, existing_pr_url
# (`tree_unchanged` is true whenever we skip the push — including the
# maintainer-owned case — so the downstream gate is uniform.)
#
# Required env:
#   BRANCH, COMMIT_MESSAGE, GH_TOKEN
# Optional env:
#   PR_TOKEN, GIT_USER_NAME, GIT_USER_EMAIL
#   PUSH_URL_OVERRIDE — test-only escape hatch. When set, replaces the
#                       in-URL-token GitHub URL. Tests point this at a
#                       local bare repo so the script can be exercised
#                       end-to-end without touching the network.

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
# token embedded in the push URL is the one actually used. Restored on
# any exit (including push failure) via the trap below.
OLD_HEADER=$(git config --local http.https://github.com/.extraheader || true)
git config --unset http.https://github.com/.extraheader || true

restore_header() {
  if [ -n "${OLD_HEADER:-}" ]; then
    git config --local http.https://github.com/.extraheader "$OLD_HEADER" 2>/dev/null || true
  fi
}
trap restore_header EXIT

PUSH_URL="${PUSH_URL_OVERRIDE:-https://x-access-token:${TOKEN}@github.com/${GITHUB_REPOSITORY}.git}"

git checkout -B "$BRANCH"
git add -A
git commit -m "$MSG"

LOCAL_TREE=$(git rev-parse 'HEAD^{tree}')

# Probe the remote branch's tree and committer, if the branch exists.
REMOTE_TREE=""
REMOTE_COMMITTER=""
if git ls-remote --exit-code --heads "$PUSH_URL" "$BRANCH" >/dev/null 2>&1; then
  git fetch --depth=1 "$PUSH_URL" "$BRANCH"
  REMOTE_TREE=$(git rev-parse 'FETCH_HEAD^{tree}')
  REMOTE_COMMITTER=$(git log -1 --format=%ce FETCH_HEAD 2>/dev/null || true)
fi

TREE_UNCHANGED=false
EXISTING_PR_NUMBER=""
EXISTING_PR_URL=""

lookup_open_pr() {
  GH_TOKEN="${GH_TOKEN:-$TOKEN}" gh pr list \
    --head "$BRANCH" \
    --state open \
    --json number,url \
    --jq '.[0] // empty' 2>/dev/null || true
}

if [ -n "$REMOTE_TREE" ] && [ "$LOCAL_TREE" = "$REMOTE_TREE" ]; then
  # Tree match alone isn't enough — only short-circuit when an open PR
  # points at the branch. Otherwise a leftover branch from a previously
  # closed PR would suppress opening a fresh one.
  existing=$(lookup_open_pr)
  if [ -n "$existing" ]; then
    EXISTING_PR_NUMBER=$(echo "$existing" | jq -r '.number')
    EXISTING_PR_URL=$(echo "$existing"    | jq -r '.url')
    TREE_UNCHANGED=true
    log "Remote '$BRANCH' already at tree $LOCAL_TREE with open PR #$EXISTING_PR_NUMBER — skipping force-push."
  fi
fi

# Maintainer-owned branch detection: only relevant when we'd otherwise
# force-push (TREE_UNCHANGED still false). If the remote HEAD's committer
# isn't us, someone else pushed commits on top of our last push — don't
# overwrite them.
if [ "$TREE_UNCHANGED" != "true" ] \
   && [ -n "$REMOTE_TREE" ] \
   && [ -n "$REMOTE_COMMITTER" ] \
   && [ "$REMOTE_COMMITTER" != "$GIT_USER_EMAIL" ]; then
  existing=$(lookup_open_pr)
  if [ -n "$existing" ]; then
    EXISTING_PR_NUMBER=$(echo "$existing" | jq -r '.number')
    EXISTING_PR_URL=$(echo "$existing"    | jq -r '.url')
  fi
  TREE_UNCHANGED=true
  log "Remote '$BRANCH' HEAD was committed by '$REMOTE_COMMITTER' (not us) — preserving maintainer commits, skipping force-push."
fi

if [ "$TREE_UNCHANGED" != "true" ]; then
  git push --force "$PUSH_URL" "$BRANCH"
fi

{
  echo "tree_unchanged=$TREE_UNCHANGED"
  echo "existing_pr_number=$EXISTING_PR_NUMBER"
  echo "existing_pr_url=$EXISTING_PR_URL"
} >> "$GITHUB_OUTPUT"
