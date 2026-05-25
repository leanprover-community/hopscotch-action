#!/usr/bin/env bats
# Unit tests for scripts/close-fix-prs.sh.
#
# All gh calls are driven by the PATH-shadowed stub at tests/stubs/gh.
# GH_STUB_PR_LIST seeds the JSON returned by `gh pr list`. GH_STUB_LOG
# is a path the stub appends `comment <num> <body>` / `close <num>`
# lines to, which we then inspect.

load helpers

setup() {
  setup_sandbox
  export PATH="$STUBS_DIR:$PATH"
  export GH_STUB_LOG="$SANDBOX/gh-actions.log"
  : > "$GH_STUB_LOG"
  export GITHUB_SERVER_URL=https://github.com
  export GITHUB_REPOSITORY=fake/repo
  export GITHUB_RUN_ID=42
}

teardown() { teardown_sandbox; }

# Convenience: grep the stub log.
log_count() { grep -cE "^$1" "$GH_STUB_LOG" || true; }

# --- skipped / tool-error → noop ---

@test "skipped outcome is a no-op" {
  export OUTCOME=skipped
  export CULPRIT=""
  export CURRENT_BRANCH="hopscotch/fix-abc1234"
  export GH_STUB_PR_LIST='[{"number":7,"headRefName":"hopscotch/fix-abc1234","url":"u"}]'
  run "$SCRIPTS_DIR/close-fix-prs.sh"
  [ "$status" -eq 0 ]
  [ "$(log_count close)" = "0" ]
  [ "$(log_count comment)" = "0" ]
}

@test "tool-error outcome is a no-op" {
  export OUTCOME=tool-error
  export CULPRIT=""
  export CURRENT_BRANCH=""
  export GH_STUB_PR_LIST='[{"number":7,"headRefName":"x","url":"u"}]'
  run "$SCRIPTS_DIR/close-fix-prs.sh"
  [ "$status" -eq 0 ]
  [ "$(log_count close)" = "0" ]
}

# --- incompatible + no culprit (defensive guard) ---

@test "incompatible with empty culprit aborts before touching PRs" {
  export OUTCOME=incompatible
  export CULPRIT=""
  export CURRENT_BRANCH="hopscotch/fix-abc1234"
  export GH_STUB_PR_LIST='[{"number":7,"headRefName":"hopscotch/fix-deadbee","url":"u"}]'
  run "$SCRIPTS_DIR/close-fix-prs.sh"
  [ "$status" -eq 0 ]
  [ "$(log_count close)" = "0" ]
}

# --- passed → close everything ---

@test "passed + no open fix PRs is a no-op" {
  export OUTCOME=passed
  export CULPRIT=""
  export CURRENT_BRANCH=""
  export GH_STUB_PR_LIST='[]'
  run "$SCRIPTS_DIR/close-fix-prs.sh"
  [ "$status" -eq 0 ]
  [ "$(log_count close)" = "0" ]
}

@test "passed + one open fix PR: comment + close it" {
  export OUTCOME=passed
  export CULPRIT=""
  export CURRENT_BRANCH=""
  export GH_STUB_PR_LIST='[{"number":7,"headRefName":"hopscotch/fix-abc1234","url":"https://github.com/x/y/pull/7"}]'
  run "$SCRIPTS_DIR/close-fix-prs.sh"
  [ "$status" -eq 0 ]
  [ "$(log_count close)" = "1" ]
  grep -q "^close 7$" "$GH_STUB_LOG"
  grep -q "^comment 7" "$GH_STUB_LOG"
  grep -q "Regression resolved" "$GH_STUB_LOG"
}

@test "passed + multiple open fix PRs: each is closed" {
  export OUTCOME=passed
  export CULPRIT=""
  export CURRENT_BRANCH=""
  export GH_STUB_PR_LIST='[
    {"number":7,"headRefName":"hopscotch/fix-abc1234","url":"u1"},
    {"number":8,"headRefName":"hopscotch/fix-deadbee","url":"u2"}
  ]'
  run "$SCRIPTS_DIR/close-fix-prs.sh"
  [ "$status" -eq 0 ]
  [ "$(log_count close)" = "2" ]
  grep -q "^close 7$" "$GH_STUB_LOG"
  grep -q "^close 8$" "$GH_STUB_LOG"
}

# --- incompatible → keep current FKB, close stale ones ---

@test "incompatible + PR on current FKB branch: keep" {
  export OUTCOME=incompatible
  export CULPRIT=abc1234ffffffffffffffffffffffffffffffff
  export CURRENT_BRANCH="hopscotch/fix-abc1234"
  export GIT_URL="https://github.com/leanprover-community/mathlib4"
  export GH_STUB_PR_LIST='[{"number":7,"headRefName":"hopscotch/fix-abc1234","url":"u"}]'
  run "$SCRIPTS_DIR/close-fix-prs.sh"
  [ "$status" -eq 0 ]
  [ "$(log_count close)" = "0" ]
}

@test "incompatible + PR on prior FKB branch: comment + close (stale)" {
  export OUTCOME=incompatible
  export CULPRIT=abc1234ffffffffffffffffffffffffffffffff
  export CURRENT_BRANCH="hopscotch/fix-abc1234"
  export GIT_URL="https://github.com/leanprover-community/mathlib4"
  export GH_STUB_PR_LIST='[{"number":9,"headRefName":"hopscotch/fix-deadbee","url":"u9"}]'
  run "$SCRIPTS_DIR/close-fix-prs.sh"
  [ "$status" -eq 0 ]
  [ "$(log_count close)" = "1" ]
  grep -q "^close 9$" "$GH_STUB_LOG"
  grep -q "first-known-bad commit has advanced" "$GH_STUB_LOG"
  grep -q "abc1234" "$GH_STUB_LOG"
}

@test "incompatible + mix of current + stale: only stale is closed" {
  export OUTCOME=incompatible
  export CULPRIT=abc1234ffffffffffffffffffffffffffffffff
  export CURRENT_BRANCH="hopscotch/fix-abc1234"
  export GIT_URL="https://github.com/leanprover-community/mathlib4"
  export GH_STUB_PR_LIST='[
    {"number":7,"headRefName":"hopscotch/fix-abc1234","url":"u1"},
    {"number":9,"headRefName":"hopscotch/fix-deadbee","url":"u2"}
  ]'
  run "$SCRIPTS_DIR/close-fix-prs.sh"
  [ "$status" -eq 0 ]
  [ "$(log_count close)" = "1" ]
  grep -q "^close 9$" "$GH_STUB_LOG"
  ! grep -q "^close 7$" "$GH_STUB_LOG"
}
