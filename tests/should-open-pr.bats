#!/usr/bin/env bats
# Unit tests for scripts/should-open-pr.sh.

load helpers

setup() { setup_sandbox; }
teardown() { teardown_sandbox; }

# --- last-good mode (default) ---

@test "last-good: passed + pin moved → yes" {
  export PIN_TO=last-good
  export OUTCOME=passed
  export NEW_PIN=bbbb
  export PREVIOUS_PIN=aaaa
  export OPEN_PR=true
  run "$SCRIPTS_DIR/should-open-pr.sh"
  [ "$(output_value yes)" = "true" ]
}

@test "last-good: incompatible + pin moved → yes" {
  export PIN_TO=last-good
  export OUTCOME=incompatible
  export NEW_PIN=bbbb
  export PREVIOUS_PIN=aaaa
  export OPEN_PR=true
  run "$SCRIPTS_DIR/should-open-pr.sh"
  [ "$(output_value yes)" = "true" ]
}

@test "last-good: passed + pin unchanged → no" {
  export PIN_TO=last-good
  export OUTCOME=passed
  export NEW_PIN=aaaa
  export PREVIOUS_PIN=aaaa
  export OPEN_PR=true
  run "$SCRIPTS_DIR/should-open-pr.sh"
  [ "$(output_value yes)" = "false" ]
}

@test "last-good: skipped → no" {
  export PIN_TO=last-good
  export OUTCOME=skipped
  export NEW_PIN=bbbb
  export PREVIOUS_PIN=aaaa
  export OPEN_PR=true
  run "$SCRIPTS_DIR/should-open-pr.sh"
  [ "$(output_value yes)" = "false" ]
}

@test "last-good: tool-error → no" {
  export PIN_TO=last-good
  export OUTCOME=tool-error
  export NEW_PIN=bbbb
  export PREVIOUS_PIN=aaaa
  export OPEN_PR=true
  run "$SCRIPTS_DIR/should-open-pr.sh"
  [ "$(output_value yes)" = "false" ]
}

@test "last-good: open-pr=false suppresses everything" {
  export PIN_TO=last-good
  export OUTCOME=incompatible
  export NEW_PIN=bbbb
  export PREVIOUS_PIN=aaaa
  export OPEN_PR=false
  run "$SCRIPTS_DIR/should-open-pr.sh"
  [ "$(output_value yes)" = "false" ]
}

@test "last-good: degenerate — manifest at culprit (no LKG found) → no" {
  # If the bisect's lower endpoint itself failed re-verification,
  # --keep-last-good has no LKG to restore to and the manifest is left at
  # the FKB. Don't publish a "bump PR" pointing at a failing commit.
  export PIN_TO=last-good
  export OUTCOME=incompatible
  export NEW_PIN=cccc
  export CULPRIT=cccc
  export PREVIOUS_PIN=aaaa
  export OPEN_PR=true
  run "$SCRIPTS_DIR/should-open-pr.sh"
  [ "$(output_value yes)" = "false" ]
}

# --- first-bad mode ---

@test "first-bad: incompatible + manifest at FKB → yes" {
  export PIN_TO=first-bad
  export OUTCOME=incompatible
  export NEW_PIN=cccc
  export CULPRIT=cccc
  export PREVIOUS_PIN=aaaa
  export OPEN_PR=true
  run "$SCRIPTS_DIR/should-open-pr.sh"
  [ "$(output_value yes)" = "true" ]
}

@test "first-bad: passed → no (close-fix-prs handles recovery)" {
  export PIN_TO=first-bad
  export OUTCOME=passed
  export NEW_PIN=bbbb
  export CULPRIT=""
  export PREVIOUS_PIN=aaaa
  export OPEN_PR=true
  run "$SCRIPTS_DIR/should-open-pr.sh"
  [ "$(output_value yes)" = "false" ]
}

@test "first-bad: incompatible but manifest not at FKB → no" {
  # Defensive: if hopscotch left the manifest somewhere unexpected, don't
  # push a mis-pinned fix PR.
  export PIN_TO=first-bad
  export OUTCOME=incompatible
  export NEW_PIN=bbbb
  export CULPRIT=cccc
  export PREVIOUS_PIN=aaaa
  export OPEN_PR=true
  run "$SCRIPTS_DIR/should-open-pr.sh"
  [ "$(output_value yes)" = "false" ]
}

@test "first-bad: skipped → no" {
  export PIN_TO=first-bad
  export OUTCOME=skipped
  export NEW_PIN=bbbb
  export CULPRIT=cccc
  export PREVIOUS_PIN=aaaa
  export OPEN_PR=true
  run "$SCRIPTS_DIR/should-open-pr.sh"
  [ "$(output_value yes)" = "false" ]
}

@test "first-bad: open-pr=false suppresses everything" {
  export PIN_TO=first-bad
  export OUTCOME=incompatible
  export NEW_PIN=cccc
  export CULPRIT=cccc
  export PREVIOUS_PIN=aaaa
  export OPEN_PR=false
  run "$SCRIPTS_DIR/should-open-pr.sh"
  [ "$(output_value yes)" = "false" ]
}
