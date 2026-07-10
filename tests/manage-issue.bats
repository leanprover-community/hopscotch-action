#!/usr/bin/env bats
# Unit tests for scripts/manage-issue.sh — focused on the automated-fix
# detection block and failure-stage note woven into the tracking issue.
# The `gh` stub records the issue body so we can assert on its content.

load helpers

setup() {
  setup_sandbox
  export PATH="$STUBS_DIR:$PATH"
  export DEP_NAME=mathlib
  export GIT_URL="https://github.com/leanprover-community/mathlib4"
  export GH_STUB_MODE=empty
  export GH_STUB_ISSUE_LIST='[]'          # no existing issue → create path
  export GH_STUB_LOG="$SANDBOX/gh.log"
  export GITHUB_REPOSITORY=fake/repo
  export GITHUB_SHA=dddddddddddddddddddddddddddddddddddddddd
  export GITHUB_SERVER_URL=https://github.com
  export GITHUB_RUN_ID=42
  export CULPRIT=3333333333333333333333333333333333333333
  export LAST_GOOD=2222222222222222222222222222222222222222
}

teardown() { teardown_sandbox; }

@test "incompatible with a proposal advertises the automated fix" {
  export OUTCOME=incompatible
  export PROPOSED_FIX_COUNT=1
  export PROPOSED_FIXES_MD='- `Demo.Old` → `Demo.New`'
  run "$SCRIPTS_DIR/manage-issue.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value issue_number)" = "123" ]
  grep -q "An automated fix is available" "$GH_STUB_LOG"
  grep -Fq -- '- `Demo.Old` → `Demo.New`' "$GH_STUB_LOG"
  grep -q "ready-to-merge fix PR" "$GH_STUB_LOG"
}

@test "incompatible without a proposal shows the genuine-removal note" {
  export OUTCOME=incompatible
  export PROPOSED_FIX_COUNT=0
  export DETECTION_NOTES_MD='- Demo.Gone deleted with no replacement shim'
  run "$SCRIPTS_DIR/manage-issue.sh"
  [ "$status" -eq 0 ]
  grep -q "No automated fix found" "$GH_STUB_LOG"
  grep -q "no replacement shim" "$GH_STUB_LOG"
}

@test "non-build failure stage is noted in the issue" {
  export OUTCOME=incompatible
  export FAILURE_STAGE="lake test"
  run "$SCRIPTS_DIR/manage-issue.sh"
  [ "$status" -eq 0 ]
  grep -Fq 'failed at `lake test`' "$GH_STUB_LOG"
}

@test "no detection results → no fix block in the body" {
  export OUTCOME=incompatible
  run "$SCRIPTS_DIR/manage-issue.sh"
  [ "$status" -eq 0 ]
  run grep -cE "automated fix|No automated fix found" "$GH_STUB_LOG"
  [ "$output" = "0" ]
}
