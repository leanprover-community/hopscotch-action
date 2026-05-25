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

@test "commit subject from gh api is included in pr body" {
  export GH_STUB_MODE=commit-subject
  export OUTCOME=passed
  export CULPRIT=""
  run "$SCRIPTS_DIR/compose-pr-content.sh"
  [ "$status" -eq 0 ]
  grep -q "Fake commit subject line" "$GITHUB_OUTPUT"
}

@test "commit count from gh api is included in pr body" {
  export GH_STUB_MODE=commit-subject
  export OUTCOME=passed
  export CULPRIT=""
  run "$SCRIPTS_DIR/compose-pr-content.sh"
  [ "$status" -eq 0 ]
  grep -q "This bump advances the dependency by 7 commits" "$GITHUB_OUTPUT"
}

@test "missing commit count is omitted from pr body" {
  export GH_STUB_MODE=empty
  export OUTCOME=passed
  export CULPRIT=""
  run "$SCRIPTS_DIR/compose-pr-content.sh"
  [ "$status" -eq 0 ]
  run grep -c "This bump advances the dependency by" "$GITHUB_OUTPUT"
  [ "$output" = "0" ]
}

# --- first-bad / fix-PR mode ---

@test "first-bad: title uses fix: prefix and FKB short" {
  export GH_STUB_MODE=empty
  export PIN_TO=first-bad
  export OUTCOME=incompatible
  export CULPRIT=$NEW_PIN
  run "$SCRIPTS_DIR/compose-pr-content.sh"
  [ "$status" -eq 0 ]
  local title
  title=$(output_value pr_title)
  [[ "$title" == fix:* ]]
  [[ "$title" == *"mathlib"* ]]
  [[ "$title" == *"ddddddd"* ]]
}

@test "first-bad: body explains the reproduction goal" {
  export GH_STUB_MODE=empty
  export PIN_TO=first-bad
  export OUTCOME=incompatible
  export CULPRIT=$NEW_PIN
  run "$SCRIPTS_DIR/compose-pr-content.sh"
  [ "$status" -eq 0 ]
  grep -q "first-known-bad commit" "$GITHUB_OUTPUT"
  grep -q "reproduce the break" "$GITHUB_OUTPUT"
}

@test "first-bad: omits the LKG-mode 'Previously at' line" {
  export GH_STUB_MODE=empty
  export PIN_TO=first-bad
  export OUTCOME=incompatible
  export CULPRIT=$NEW_PIN
  run "$SCRIPTS_DIR/compose-pr-content.sh"
  [ "$status" -eq 0 ]
  run grep -c "Previously at" "$GITHUB_OUTPUT"
  [ "$output" = "0" ]
}

@test "first-bad: includes LKG link when available" {
  export GH_STUB_MODE=empty
  export PIN_TO=first-bad
  export OUTCOME=incompatible
  export CULPRIT=$NEW_PIN
  export LAST_GOOD=ffffffffffffffffffffffffffffffffffffffff
  run "$SCRIPTS_DIR/compose-pr-content.sh"
  [ "$status" -eq 0 ]
  grep -q "Last-known-good" "$GITHUB_OUTPUT"
  grep -q "fffffff" "$GITHUB_OUTPUT"
}
