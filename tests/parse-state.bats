#!/usr/bin/env bats
# Unit tests for scripts/parse-state.sh.

load helpers

setup() {
  setup_sandbox
  mkdir -p .lake/hopscotch
  cp "$FIXTURES_DIR/lake-manifest.json" .
  export DEP_NAME=mathlib
  export PROJECT_DIR=.
  export MAX_WINDOW=3000
  export EXIT_CODE=0
}

teardown() { teardown_sandbox; }

@test "status=completed → outcome=passed, last_good=target" {
  cp "$FIXTURES_DIR/state-completed.json" .lake/hopscotch/state.json
  export PREVIOUS_PIN=aaaaaaa
  run "$SCRIPTS_DIR/parse-state.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value outcome)" = "passed" ]
  [ "$(output_value last_good_commit)" = "cccccccccccccccccccccccccccccccccccccccc" ]
  [ "$(output_value target_commit)" = "cccccccccccccccccccccccccccccccccccccccc" ]
  [ "$(output_value items_count)" = "3" ]
}

@test "status=completed + pin unchanged → outcome=skipped" {
  cp "$FIXTURES_DIR/state-completed.json" .lake/hopscotch/state.json
  # manifest pins mathlib to bbbb...; force state to end on the same sha.
  jq '.items = ["aaaa","bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"]' \
    .lake/hopscotch/state.json > .lake/hopscotch/state.json.tmp
  mv .lake/hopscotch/state.json.tmp .lake/hopscotch/state.json
  export PREVIOUS_PIN=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  run "$SCRIPTS_DIR/parse-state.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value outcome)" = "skipped" ]
}

@test "status=failed + runMode=bisect → culprit from knownBadIndex" {
  cp "$FIXTURES_DIR/state-failed-bisect.json" .lake/hopscotch/state.json
  export PREVIOUS_PIN=1111111111111111111111111111111111111111
  run "$SCRIPTS_DIR/parse-state.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value outcome)" = "incompatible" ]
  [ "$(output_value culprit_commit)" = "3333333333333333333333333333333333333333" ]
  [ "$(output_value last_good_commit)" = "2222222222222222222222222222222222222222" ]
}

@test "status=failed + runMode=linear → culprit from currentCommit" {
  cp "$FIXTURES_DIR/state-failed-linear.json" .lake/hopscotch/state.json
  export PREVIOUS_PIN=1111111111111111111111111111111111111111
  run "$SCRIPTS_DIR/parse-state.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value outcome)" = "incompatible" ]
  [ "$(output_value culprit_commit)" = "3333333333333333333333333333333333333333" ]
  [ "$(output_value last_good_commit)" = "2222222222222222222222222222222222222222" ]
}

@test "items.length > max_window → tool-error, exit 1" {
  cp "$FIXTURES_DIR/state-completed.json" .lake/hopscotch/state.json
  export PREVIOUS_PIN=aaaa
  export MAX_WINDOW=2
  run "$SCRIPTS_DIR/parse-state.sh"
  [ "$status" -eq 1 ]
  [ "$(output_value outcome)" = "tool-error" ]
}

@test "missing state.json → tool-error, exit 1" {
  export PREVIOUS_PIN=aaaa
  run "$SCRIPTS_DIR/parse-state.sh"
  [ "$status" -eq 1 ]
  [ "$(output_value outcome)" = "tool-error" ]
}

@test "new_pin reflects manifest rev after run" {
  cp "$FIXTURES_DIR/state-completed.json" .lake/hopscotch/state.json
  export PREVIOUS_PIN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  run "$SCRIPTS_DIR/parse-state.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value new_pin)" = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" ]
}
