#!/usr/bin/env bash
# Shared bats helpers.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SCRIPTS_DIR="$REPO_ROOT/scripts"
FIXTURES_DIR="$BATS_TEST_DIRNAME/fixtures"
STUBS_DIR="$BATS_TEST_DIRNAME/stubs"

# Create an isolated sandbox with its own GITHUB_OUTPUT file and cwd.
#
#   setup_sandbox            — sets $SANDBOX, $GITHUB_OUTPUT, changes cwd
setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  export SANDBOX
  export GITHUB_OUTPUT="$SANDBOX/out"
  export GITHUB_STEP_SUMMARY="$SANDBOX/summary"
  : > "$GITHUB_OUTPUT"
  : > "$GITHUB_STEP_SUMMARY"
  cd "$SANDBOX"
}

teardown_sandbox() {
  [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"
}

# Read a value from $GITHUB_OUTPUT (simple key=value; no heredocs).
output_value() {
  local key="$1"
  grep -E "^${key}=" "$GITHUB_OUTPUT" | head -1 | cut -d= -f2-
}

# Check that $GITHUB_OUTPUT contains a specific line.
output_has_line() {
  grep -Fxq "$1" "$GITHUB_OUTPUT"
}
