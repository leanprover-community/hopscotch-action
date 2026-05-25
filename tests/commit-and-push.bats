#!/usr/bin/env bats
# Integration tests for scripts/commit-and-push.sh.
#
# Each test sets up a real working tree + a bare repo to act as "the
# remote". The script's push URL is redirected at the bare repo via
# PUSH_URL_OVERRIDE so we exercise the full code path (real `git push`,
# real `git ls-remote`, real `git fetch`) without touching the network.
#
# `gh pr list` is driven by the stub in tests/stubs/gh, seeded via
# GH_STUB_PR_LIST.

load helpers

# Make a fresh working tree and bare "remote" inside the sandbox.
#   $1 — branch name
# Sets: $LOCAL, $REMOTE, $GIT_USER_EMAIL_DEFAULT
setup_repos() {
  LOCAL="$SANDBOX/local"
  REMOTE="$SANDBOX/remote.git"

  git init --quiet -b main "$LOCAL"
  cd "$LOCAL"
  # Seed an initial commit so HEAD exists.
  git config user.name  "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  echo "initial" > seed.txt
  git add seed.txt
  git commit --quiet -m "initial"

  git init --quiet --bare "$REMOTE"
}

# Push a commit to the remote branch from a given identity. Sets the
# remote to a state where the action would later need to overwrite (or
# preserve) commits.
#   $1 — branch
#   $2 — committer name
#   $3 — committer email
#   $4 — file content
seed_remote_branch() {
  local branch="$1" name="$2" email="$3" content="$4"
  local seed_dir="$SANDBOX/seed-$RANDOM"

  git clone --quiet "$REMOTE" "$seed_dir"
  pushd "$seed_dir" >/dev/null
  git config user.name  "$name"
  git config user.email "$email"
  # Replace seed.txt so the remote's tree differs from the eventual
  # local-script-built tree unless callers match it.
  echo "$content" > seed.txt
  git add seed.txt
  git commit --quiet -m "seed: $name"
  git push --quiet origin HEAD:"$branch"
  popd >/dev/null
}

setup() {
  setup_sandbox
  export PATH="$STUBS_DIR:$PATH"
  setup_repos
  # Default: no open PR.
  export GH_STUB_PR_LIST='[]'
  # The script reads GITHUB_REPOSITORY only to build the default push
  # URL; with PUSH_URL_OVERRIDE this is unused, but keep it set for
  # realism.
  export GITHUB_REPOSITORY=fake/repo
  export GH_TOKEN=fake-token
  export PUSH_URL_OVERRIDE="$REMOTE"
  export BRANCH=hopscotch/fix-abc1234
  export COMMIT_MESSAGE="chore: test commit"
}

teardown() { teardown_sandbox; }

# --- core push paths ---

@test "no remote branch yet: pushes the new branch" {
  cd "$LOCAL"
  echo "new content" > seed.txt
  run "$SCRIPTS_DIR/commit-and-push.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value tree_unchanged)" = "false" ]
  # Verify the branch landed on the remote.
  run git --git-dir="$REMOTE" rev-parse --verify "$BRANCH"
  [ "$status" -eq 0 ]
}

@test "remote tree matches and an open PR points at the branch: skip push" {
  seed_remote_branch "$BRANCH" "github-actions[bot]" \
    "41898282+github-actions[bot]@users.noreply.github.com" "shared content"
  cd "$LOCAL"
  echo "shared content" > seed.txt
  export GH_STUB_PR_LIST='[{"number":7,"url":"https://github.com/x/y/pull/7"}]'
  run "$SCRIPTS_DIR/commit-and-push.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value tree_unchanged)" = "true" ]
  [ "$(output_value existing_pr_number)" = "7" ]
  [ "$(output_value existing_pr_url)" = "https://github.com/x/y/pull/7" ]
}

@test "remote tree matches but no open PR: still pushes (so a new PR can be opened)" {
  seed_remote_branch "$BRANCH" "github-actions[bot]" \
    "41898282+github-actions[bot]@users.noreply.github.com" "shared content"
  cd "$LOCAL"
  echo "shared content" > seed.txt
  export GH_STUB_PR_LIST='[]'
  run "$SCRIPTS_DIR/commit-and-push.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value tree_unchanged)" = "false" ]
}

# --- maintainer-WIP protection ---

@test "maintainer commit on remote (different committer email): skip push" {
  seed_remote_branch "$BRANCH" "Maintainer" "maintainer@example.com" "maintainer's WIP"
  cd "$LOCAL"
  echo "action-side update" > seed.txt
  export GH_STUB_PR_LIST='[{"number":7,"url":"https://github.com/x/y/pull/7"}]'
  run "$SCRIPTS_DIR/commit-and-push.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value tree_unchanged)" = "true" ]
  [ "$(output_value existing_pr_number)" = "7" ]
  # Maintainer's commit is preserved.
  remote_tree=$(git --git-dir="$REMOTE" log -1 --format=%T "$BRANCH")
  local_tree=$(cd "$LOCAL" && git rev-parse 'HEAD^{tree}')
  [ "$remote_tree" != "$local_tree" ]
}

@test "bot commit on remote, different tree: force-pushes (no maintainer to preserve)" {
  seed_remote_branch "$BRANCH" "github-actions[bot]" \
    "41898282+github-actions[bot]@users.noreply.github.com" "stale bot content"
  cd "$LOCAL"
  echo "new bot content" > seed.txt
  export GH_STUB_PR_LIST='[{"number":7,"url":"https://github.com/x/y/pull/7"}]'
  run "$SCRIPTS_DIR/commit-and-push.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value tree_unchanged)" = "false" ]
  # Remote tree now matches what we just built locally.
  remote_tree=$(git --git-dir="$REMOTE" log -1 --format=%T "$BRANCH")
  local_tree=$(cd "$LOCAL" && git rev-parse 'HEAD^{tree}')
  [ "$remote_tree" = "$local_tree" ]
}

@test "custom GIT_USER_EMAIL: maintainer detection uses the configured identity" {
  export GIT_USER_NAME="custom-bot"
  export GIT_USER_EMAIL="bot@my-org.example"
  seed_remote_branch "$BRANCH" "custom-bot" "bot@my-org.example" "stale"
  cd "$LOCAL"
  echo "new" > seed.txt
  export GH_STUB_PR_LIST='[{"number":7,"url":"u"}]'
  run "$SCRIPTS_DIR/commit-and-push.sh"
  [ "$status" -eq 0 ]
  # Bot-owned even though the email is custom — should push.
  [ "$(output_value tree_unchanged)" = "false" ]
}

# --- token required ---

@test "missing both PR_TOKEN and GH_TOKEN: aborts with an error" {
  unset GH_TOKEN
  unset PR_TOKEN
  cd "$LOCAL"
  echo "x" > seed.txt
  run "$SCRIPTS_DIR/commit-and-push.sh"
  [ "$status" -ne 0 ]
}
