#!/usr/bin/env bats
# Unit tests for scripts/parse-results.sh.

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

@test "fullySuccessful bisect → outcome=passed, last_good=lastSuccessfulCommit" {
  cp "$FIXTURES_DIR/results-fully-successful-bisect.json" .lake/hopscotch/results.json
  export PREVIOUS_PIN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value outcome)" = "passed" ]
  [ "$(output_value culprit_commit)" = "" ]
  [ "$(output_value last_good_commit)" = "cccccccccccccccccccccccccccccccccccccccc" ]
  [ "$(output_value target_commit)" = "cccccccccccccccccccccccccccccccccccccccc" ]
  [ "$(output_value items_count)" = "3" ]
}

@test "fullySuccessful + pin already at top → outcome=skipped" {
  cp "$FIXTURES_DIR/results-fully-successful-bisect.json" .lake/hopscotch/results.json
  # manifest pins mathlib to bbbb...; force results' top to match.
  jq '.items[-1] = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      | .lastSuccessfulCommit = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' \
    .lake/hopscotch/results.json > .lake/hopscotch/results.json.tmp
  mv .lake/hopscotch/results.json.tmp .lake/hopscotch/results.json
  export PREVIOUS_PIN=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value outcome)" = "skipped" ]
}

@test "stopped bisect → outcome=incompatible, culprit=firstFailingCommit" {
  cp "$FIXTURES_DIR/results-stopped-bisect.json" .lake/hopscotch/results.json
  export PREVIOUS_PIN=1111111111111111111111111111111111111111
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value outcome)" = "incompatible" ]
  [ "$(output_value culprit_commit)" = "3333333333333333333333333333333333333333" ]
  [ "$(output_value last_good_commit)" = "2222222222222222222222222222222222222222" ]
}

@test "stopped linear → outcome=incompatible, culprit=firstFailingCommit" {
  cp "$FIXTURES_DIR/results-stopped-linear.json" .lake/hopscotch/results.json
  export PREVIOUS_PIN=1111111111111111111111111111111111111111
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value outcome)" = "incompatible" ]
  [ "$(output_value culprit_commit)" = "3333333333333333333333333333333333333333" ]
  [ "$(output_value last_good_commit)" = "2222222222222222222222222222222222222222" ]
}

@test "items.length > max_window → tool-error, exit 1" {
  cp "$FIXTURES_DIR/results-fully-successful-bisect.json" .lake/hopscotch/results.json
  export PREVIOUS_PIN=aaaa
  export MAX_WINDOW=2
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 1 ]
  [ "$(output_value outcome)" = "tool-error" ]
}

@test "missing results.json → tool-error, exit 1" {
  export PREVIOUS_PIN=aaaa
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 1 ]
  [ "$(output_value outcome)" = "tool-error" ]
}

@test "unknown schemaVersion → tool-error, exit 1" {
  cp "$FIXTURES_DIR/results-fully-successful-bisect.json" .lake/hopscotch/results.json
  jq '.schemaVersion = 99' .lake/hopscotch/results.json > .lake/hopscotch/results.json.tmp
  mv .lake/hopscotch/results.json.tmp .lake/hopscotch/results.json
  export PREVIOUS_PIN=aaaa
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 1 ]
  [ "$(output_value outcome)" = "tool-error" ]
}

@test "older schemaVersion 1 is still accepted (back-compat)" {
  # A v1 output predates the autofix fields; they must default to empty.
  jq '.schemaVersion = 1 | del(.proposedFixes, .deprecatedImports, .detectionNotes)' \
    "$FIXTURES_DIR/results-stopped-bisect.json" > .lake/hopscotch/results.json
  export PREVIOUS_PIN=1111111111111111111111111111111111111111
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value outcome)" = "incompatible" ]
  [ "$(output_value proposed_fix_count)" = "0" ]
  [ "$(output_value deprecated_import_count)" = "0" ]
  [ "$(output_value detection_note_count)" = "0" ]
}

@test "non-terminal status (running) → tool-error, exit 1" {
  cp "$FIXTURES_DIR/results-fully-successful-bisect.json" .lake/hopscotch/results.json
  jq '.status = "running"' .lake/hopscotch/results.json > .lake/hopscotch/results.json.tmp
  mv .lake/hopscotch/results.json.tmp .lake/hopscotch/results.json
  export PREVIOUS_PIN=aaaa
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 1 ]
  [ "$(output_value outcome)" = "tool-error" ]
}

@test "new_pin reflects manifest rev after run" {
  cp "$FIXTURES_DIR/results-fully-successful-bisect.json" .lake/hopscotch/results.json
  export PREVIOUS_PIN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value new_pin)" = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" ]
}

# --- autofix detection outputs (schemaVersion 3) ---

@test "stopped bisect surfaces failure_stage and proposal counts" {
  cp "$FIXTURES_DIR/results-stopped-bisect.json" .lake/hopscotch/results.json
  export PREVIOUS_PIN=1111111111111111111111111111111111111111
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value failure_stage)" = "lake build" ]
  [ "$(output_value proposed_fix_count)" = "1" ]
  [ "$(output_value deprecated_import_count)" = "1" ]
  [ "$(output_value detection_note_count)" = "0" ]
}

@test "proposed_fixes_md renders the mapping from the tool's fields" {
  cp "$FIXTURES_DIR/results-stopped-bisect.json" .lake/hopscotch/results.json
  export PREVIOUS_PIN=1111111111111111111111111111111111111111
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 0 ]
  grep -Fq '`Mathlib.Topology.Algebra.Module.LinearMap` → `Mathlib.Topology.Algebra.Module.ContinuousLinearMap.Basic`, `Mathlib.Topology.Algebra.Module.ContinuousLinearMap.Idempotent`' \
    "$GITHUB_OUTPUT"
}

@test "deprecated_imports_md marks partial migrations" {
  cp "$FIXTURES_DIR/results-stopped-bisect.json" .lake/hopscotch/results.json
  export PREVIOUS_PIN=1111111111111111111111111111111111111111
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 0 ]
  grep -Fq '_[partial: shim also defines @[deprecated] aliases]_' "$GITHUB_OUTPUT"
}

@test "green run records a deprecation advisory, no proposal" {
  cp "$FIXTURES_DIR/results-fully-successful-bisect.json" .lake/hopscotch/results.json
  export PREVIOUS_PIN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value outcome)" = "passed" ]
  [ "$(output_value proposed_fix_count)" = "0" ]
  [ "$(output_value deprecated_import_count)" = "1" ]
}

@test "genuine removal records a detection note, no proposal" {
  cp "$FIXTURES_DIR/results-stopped-linear.json" .lake/hopscotch/results.json
  export PREVIOUS_PIN=1111111111111111111111111111111111111111
  run "$SCRIPTS_DIR/parse-results.sh"
  [ "$status" -eq 0 ]
  [ "$(output_value outcome)" = "incompatible" ]
  [ "$(output_value proposed_fix_count)" = "0" ]
  [ "$(output_value detection_note_count)" = "1" ]
  grep -Fq 'deleted upstream with no replacement shim' "$GITHUB_OUTPUT"
}
