#!/usr/bin/env bats
# Unit tests for scripts/run-hopscotch.sh — focused on argument assembly
# (verify steps, --keep-last-good by mode, extra-args). The `hopscotch` stub
# records its argv so we can assert on the `dep` invocation.

load helpers

setup() {
  setup_sandbox
  export PATH="$STUBS_DIR:$PATH"
  export DEP_NAME=mathlib
  export PROJECT_DIR=.
  export HOPSCOTCH_STUB_LOG="$SANDBOX/hopscotch.log"
}

teardown() { teardown_sandbox; }

# The argv of the `hopscotch dep ...` call (the stub also logs `clean`).
dep_call() { grep '^dep ' "$HOPSCOTCH_STUB_LOG"; }

@test "last-good mode passes --keep-last-good, no verify steps by default" {
  export PIN_TO=last-good
  run "$SCRIPTS_DIR/run-hopscotch.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value exit_code)" = "0" ]
  [[ "$(dep_call)" == *"--keep-last-good"* ]]
  [[ "$(dep_call)" != *"--test"* ]]
  [[ "$(dep_call)" != *"--lint"* ]]
}

@test "first-bad mode drops --keep-last-good" {
  export PIN_TO=first-bad
  run "$SCRIPTS_DIR/run-hopscotch.sh"
  [ "$status" -eq 0 ]
  [[ "$(dep_call)" != *"--keep-last-good"* ]]
}

@test "run-tests/run-lint add --test/--lint" {
  export PIN_TO=last-good RUN_TESTS=true RUN_LINT=true
  run "$SCRIPTS_DIR/run-hopscotch.sh"
  [ "$status" -eq 0 ]
  [[ "$(dep_call)" == *"--test"* ]]
  [[ "$(dep_call)" == *"--lint"* ]]
}

@test "build/test/lint args are forwarded" {
  export PIN_TO=last-good BUILD_ARGS=--wfail TEST_ARGS=--verbose LINT_ARGS=--update
  run "$SCRIPTS_DIR/run-hopscotch.sh"
  [ "$status" -eq 0 ]
  [[ "$(dep_call)" == *"--build-args --wfail"* ]]
  [[ "$(dep_call)" == *"--test-args --verbose"* ]]
  [[ "$(dep_call)" == *"--lint-args --update"* ]]
}

@test "extra-args are appended verbatim" {
  export PIN_TO=last-good
  export EXTRA_ARGS=$'--scan-mode linear\n--allow-dirty-workspace'
  run "$SCRIPTS_DIR/run-hopscotch.sh"
  [ "$status" -eq 0 ]
  [[ "$(dep_call)" == *"--scan-mode linear"* ]]
  [[ "$(dep_call)" == *"--allow-dirty-workspace"* ]]
}

@test "from/to refs are passed when set" {
  export PIN_TO=last-good FROM_REF=abc123 TO_REF=master
  run "$SCRIPTS_DIR/run-hopscotch.sh"
  [ "$status" -eq 0 ]
  [[ "$(dep_call)" == *"--from abc123"* ]]
  [[ "$(dep_call)" == *"--to master"* ]]
}

@test "hopscotch tool error (exit >=2) fails the step" {
  export PIN_TO=last-good HOPSCOTCH_STUB_EXIT=2
  run "$SCRIPTS_DIR/run-hopscotch.sh"
  [ "$status" -ne 0 ]
  [ "$(output_value exit_code)" = "2" ]
}

@test "boundary found (exit 1) does not fail the step" {
  export PIN_TO=last-good HOPSCOTCH_STUB_EXIT=1
  run "$SCRIPTS_DIR/run-hopscotch.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value exit_code)" = "1" ]
}
