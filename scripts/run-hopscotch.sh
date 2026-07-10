#!/usr/bin/env bash
# Clean any stale session, then run `hopscotch dep`.
#
# EXTRA_ARGS may be single-line or multi-line; each line is word-split on
# whitespace. Multi-line is purely ergonomic — it lets users group related
# flags across lines without quoting.
#
# PIN_TO controls whether the manifest ends at the last-known-good or the
# first-known-bad commit when an incompatibility is found:
#   last-good (default) — pass `--keep-last-good` so the bisect terminates
#                         with the manifest at the LKG.
#   first-bad           — drop `--keep-last-good` so the manifest is left
#                         at the FKB when one is identified, suitable for
#                         a fix-PR branch that reproduces the break.
#
# Exit codes:
#   0  — all commits passed
#   1  — culprit / boundary found  (NOT a step failure)
#   2+ — tool error (propagated; makes the step fail)
#
# The optional `--test` / `--lint` verify steps and their `--*-args`
# counterparts are driven by RUN_TESTS / RUN_LINT / BUILD_ARGS / TEST_ARGS /
# LINT_ARGS. hopscotch whitespace-splits each `--*-args` string itself, so we
# pass the whole value as a single argument.
#
# Emits output: exit_code
#
# Required env:
#   DEP_NAME, FROM_REF, TO_REF, PROJECT_DIR, EXTRA_ARGS, GITHUB_TOKEN, PIN_TO
# Optional env:
#   RUN_TESTS, RUN_LINT, BUILD_ARGS, TEST_ARGS, LINT_ARGS

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

: "${DEP_NAME:?}"
: "${PROJECT_DIR:?}"
FROM_REF="${FROM_REF:-}"
TO_REF="${TO_REF:-}"
EXTRA_ARGS="${EXTRA_ARGS:-}"
PIN_TO="${PIN_TO:-last-good}"
RUN_TESTS="${RUN_TESTS:-false}"
RUN_LINT="${RUN_LINT:-false}"
BUILD_ARGS="${BUILD_ARGS:-}"
TEST_ARGS="${TEST_ARGS:-}"
LINT_ARGS="${LINT_ARGS:-}"

# Clean any stale session from a previous run.
hopscotch clean --project-dir "$PROJECT_DIR" 2>/dev/null || true

ARGS=(dep "$DEP_NAME"
      --project-dir "$PROJECT_DIR")
if [ "$PIN_TO" != "first-bad" ]; then
  ARGS+=(--keep-last-good)
fi
[ -n "$FROM_REF" ] && ARGS+=(--from "$FROM_REF")
[ -n "$TO_REF"   ] && ARGS+=(--to "$TO_REF")

# Optional verify steps and their lake argument strings.
[ "$RUN_TESTS" = "true" ] && ARGS+=(--test)
[ "$RUN_LINT"  = "true" ] && ARGS+=(--lint)
[ -n "$BUILD_ARGS" ] && ARGS+=(--build-args "$BUILD_ARGS")
[ -n "$TEST_ARGS"  ] && ARGS+=(--test-args "$TEST_ARGS")
[ -n "$LINT_ARGS"  ] && ARGS+=(--lint-args "$LINT_ARGS")

# Word-split each line of EXTRA_ARGS. Empty lines ignored.
while IFS= read -r line; do
  [ -z "$line" ] && continue
  # shellcheck disable=SC2206
  tokens=($line)
  ARGS+=("${tokens[@]}")
done <<< "$EXTRA_ARGS"

group "hopscotch output"
set +e
hopscotch "${ARGS[@]}"
EXIT_CODE=$?
set -e
endgroup

echo "exit_code=$EXIT_CODE" >> "$GITHUB_OUTPUT"

if [ "$EXIT_CODE" -ge 2 ]; then
  die "hopscotch exited with error code $EXIT_CODE (tool error)."
fi
