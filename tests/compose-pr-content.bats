#!/usr/bin/env bats
# Unit tests for scripts/compose-pr-content.sh.

load helpers

setup() {
  setup_sandbox
  export PATH="$STUBS_DIR:$PATH"
  export DEP_NAME=mathlib
  export NEW_PIN=dddddddddddddddddddddddddddddddddddddddd
  export PREVIOUS_PIN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  export GIT_URL="https://github.com/leanprover-community/mathlib4"
  export GITHUB_SERVER_URL=https://github.com
  export GITHUB_REPOSITORY=fake/repo
  export GITHUB_RUN_ID=42
}

teardown() { teardown_sandbox; }

@test "title and body include the dep name and short sha" {
  export GH_STUB_MODE=empty
  export OUTCOME=passed
  export CULPRIT=""
  run "$SCRIPTS_DIR/compose-pr-content.sh"
  [ "$status" -eq 0 ]
  local title
  title=$(output_value pr_title)
  [[ "$title" == *"mathlib"* ]]
  [[ "$title" == *"ddddddd"* ]]
  grep -q "ddddddd" "$GITHUB_OUTPUT"
}

@test "incompatible outcome with culprit adds the breaking-commit note" {
  export GH_STUB_MODE=empty
  export OUTCOME=incompatible
  export CULPRIT=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
  run "$SCRIPTS_DIR/compose-pr-content.sh"
  [ "$status" -eq 0 ]
  grep -q "first known breaking commit" "$GITHUB_OUTPUT"
  grep -q "eeeeeee" "$GITHUB_OUTPUT"
}

@test "passed outcome omits the culprit note" {
  export GH_STUB_MODE=empty
  export OUTCOME=passed
  export CULPRIT=""
  run "$SCRIPTS_DIR/compose-pr-content.sh"
  [ "$status" -eq 0 ]
  run grep -c "first known breaking commit" "$GITHUB_OUTPUT"
  [ "$output" = "0" ]
}

@test "commit subject from gh api is included in title and body" {
  export GH_STUB_MODE=commit-subject
  export OUTCOME=passed
  export CULPRIT=""
  run "$SCRIPTS_DIR/compose-pr-content.sh"
  [ "$status" -eq 0 ]
  grep -q "Fake commit subject line" "$GITHUB_OUTPUT"
}
