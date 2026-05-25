#!/usr/bin/env bats
# Unit tests for scripts/resolve-branch.sh.

load helpers

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

@test "last-good mode uses input verbatim" {
  export PIN_TO=last-good
  export PR_BRANCH_INPUT=hopscotch/bump
  export CULPRIT=""
  run "$SCRIPTS_DIR/resolve-branch.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value branch)" = "hopscotch/bump" ]
}

@test "last-good mode falls back to default when input is empty" {
  export PIN_TO=last-good
  export PR_BRANCH_INPUT=""
  export CULPRIT=""
  run "$SCRIPTS_DIR/resolve-branch.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value branch)" = "hopscotch/bump" ]
}

@test "first-bad mode appends short SHA to default prefix" {
  export PIN_TO=first-bad
  export PR_BRANCH_INPUT=""
  export CULPRIT=abc1234ffffffffffffffffffffffffffffffff
  run "$SCRIPTS_DIR/resolve-branch.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value branch)" = "hopscotch/fix-abc1234" ]
}

@test "first-bad mode appends short SHA to custom prefix" {
  export PIN_TO=first-bad
  export PR_BRANCH_INPUT=my-prefix/fix
  export CULPRIT=deadbeefcafebabefeedfacefeedfaceabcabc01
  run "$SCRIPTS_DIR/resolve-branch.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value branch)" = "my-prefix/fix-deadbee" ]
}

@test "first-bad mode without culprit emits the prefix unchanged" {
  # Step still runs even when culprit is empty; should-open-pr is the
  # actual gate.
  export PIN_TO=first-bad
  export PR_BRANCH_INPUT=""
  export CULPRIT=""
  run "$SCRIPTS_DIR/resolve-branch.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value branch)" = "hopscotch/fix" ]
}
