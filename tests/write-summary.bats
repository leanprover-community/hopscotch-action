#!/usr/bin/env bats
# Unit tests for scripts/write-summary.sh — focused on the mode-aware
# "Automated fixes" guidance written to the job summary.

load helpers

setup() {
  setup_sandbox
  export DEP_NAME=mathlib
  export OUTCOME=incompatible
  export CULPRIT=3333333333333333333333333333333333333333
  export GIT_URL="https://github.com/leanprover-community/mathlib4"
}

teardown() { teardown_sandbox; }

@test "first-bad: proposed-but-unapplied fixes say run hopscotch fix apply" {
  export PIN_TO=first-bad PROPOSED_FIX_COUNT=2
  run "$SCRIPTS_DIR/write-summary.sh"
  [ "$status" -eq 0 ]
  grep -q "hopscotch fix apply" "$GITHUB_STEP_SUMMARY"
}

@test "last-good: proposed-but-unapplied fixes point at fix-PR mode, not bare fix apply" {
  # The bump pin is before the break, where applying wouldn't build.
  export PIN_TO=last-good PROPOSED_FIX_COUNT=2
  run "$SCRIPTS_DIR/write-summary.sh"
  [ "$status" -eq 0 ]
  grep -q "first-bad" "$GITHUB_STEP_SUMMARY"
  run grep -c "hopscotch fix apply" "$GITHUB_STEP_SUMMARY"
  [ "$output" = "0" ]
}

@test "applied fixes are reported as applied" {
  export PIN_TO=first-bad FIXES_APPLIED=true PROPOSED_FIX_COUNT=2
  run "$SCRIPTS_DIR/write-summary.sh"
  [ "$status" -eq 0 ]
  grep -q "Automated fixes:.*applied" "$GITHUB_STEP_SUMMARY"
}

@test "a non-build failure stage is surfaced" {
  export PIN_TO=last-good FAILURE_STAGE="lake test"
  run "$SCRIPTS_DIR/write-summary.sh"
  [ "$status" -eq 0 ]
  grep -Fq 'Failed at:' "$GITHUB_STEP_SUMMARY"
  grep -Fq 'lake test' "$GITHUB_STEP_SUMMARY"
}
