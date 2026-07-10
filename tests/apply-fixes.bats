#!/usr/bin/env bats
# Unit tests for scripts/apply-fixes.sh.

load helpers

setup() {
  setup_sandbox
  export PATH="$STUBS_DIR:$PATH"
  export PROJECT_DIR=.
  export HOPSCOTCH_STUB_LOG="$SANDBOX/hopscotch.log"
}

teardown() { teardown_sandbox; }

# Echo the recorded hopscotch argv (empty when it was never invoked).
called() { [ -f "$HOPSCOTCH_STUB_LOG" ] && cat "$HOPSCOTCH_STUB_LOG"; return 0; }

@test "apply-fixes=false → no-op, fixes_applied=false" {
  export APPLY_FIXES=false PIN_TO=first-bad OUTCOME=incompatible PROPOSED_FIX_COUNT=1
  run "$SCRIPTS_DIR/apply-fixes.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value fixes_applied)" = "false" ]
  [ ! -f "$HOPSCOTCH_STUB_LOG" ]
}

@test "first-bad + incompatible + a proposal → runs fix apply (advisories included)" {
  export APPLY_FIXES=true PIN_TO=first-bad OUTCOME=incompatible \
    PROPOSED_FIX_COUNT=1 DEPRECATED_IMPORT_COUNT=1
  run "$SCRIPTS_DIR/apply-fixes.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value fixes_applied)" = "true" ]
  [[ "$(called)" == *"fix apply"* ]]
  [[ "$(called)" != *"--no-advisories"* ]]
}

@test "first-bad + incompatible but no proposal (genuine break) → no-op" {
  export APPLY_FIXES=true PIN_TO=first-bad OUTCOME=incompatible \
    PROPOSED_FIX_COUNT=0 DEPRECATED_IMPORT_COUNT=1
  run "$SCRIPTS_DIR/apply-fixes.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value fixes_applied)" = "false" ]
  [ ! -f "$HOPSCOTCH_STUB_LOG" ]
}

@test "first-bad + passed → no-op (nothing to fix)" {
  export APPLY_FIXES=true PIN_TO=first-bad OUTCOME=passed PROPOSED_FIX_COUNT=0
  run "$SCRIPTS_DIR/apply-fixes.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value fixes_applied)" = "false" ]
  [ ! -f "$HOPSCOTCH_STUB_LOG" ]
}

@test "last-good + green + advisories → folds in deprecation hygiene" {
  export APPLY_FIXES=true PIN_TO=last-good OUTCOME=passed DEPRECATED_IMPORT_COUNT=2
  run "$SCRIPTS_DIR/apply-fixes.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value fixes_applied)" = "true" ]
  [[ "$(called)" == *"fix apply"* ]]
}

@test "last-good + stopped → never applies (premature-proposal guard)" {
  # The manifest sits at the LKG (before the break); applying a proposal
  # there would rewrite to a module that doesn't exist yet.
  export APPLY_FIXES=true PIN_TO=last-good OUTCOME=incompatible \
    PROPOSED_FIX_COUNT=1 DEPRECATED_IMPORT_COUNT=1
  run "$SCRIPTS_DIR/apply-fixes.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value fixes_applied)" = "false" ]
  [ ! -f "$HOPSCOTCH_STUB_LOG" ]
}

@test "last-good + green + no advisories → no-op" {
  export APPLY_FIXES=true PIN_TO=last-good OUTCOME=passed DEPRECATED_IMPORT_COUNT=0
  run "$SCRIPTS_DIR/apply-fixes.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value fixes_applied)" = "false" ]
  [ ! -f "$HOPSCOTCH_STUB_LOG" ]
}

@test "fix apply failure → step fails, fixes_applied=false" {
  export APPLY_FIXES=true PIN_TO=first-bad OUTCOME=incompatible PROPOSED_FIX_COUNT=1
  export HOPSCOTCH_STUB_EXIT=2
  run "$SCRIPTS_DIR/apply-fixes.sh"
  [ "$status" -ne 0 ]
  [ "$(output_value fixes_applied)" = "false" ]
}
