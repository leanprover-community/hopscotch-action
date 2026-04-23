#!/usr/bin/env bash
# Clean any stale session, then run `hopscotch dep`.
#
# EXTRA_ARGS may be single-line or multi-line; each line is word-split on
# whitespace. Multi-line is purely ergonomic — it lets users group related
# flags across lines without quoting.
#
# Exit codes:
#   0  — all commits passed
#   1  — culprit / boundary found  (NOT a step failure)
#   2+ — tool error (propagated; makes the step fail)
#
# Emits output: exit_code
#
# Required env:
#   DEP_NAME, FROM_REF, TO_REF, PROJECT_DIR, EXTRA_ARGS, GITHUB_TOKEN

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

: "${DEP_NAME:?}"
: "${PROJECT_DIR:?}"
FROM_REF="${FROM_REF:-}"
TO_REF="${TO_REF:-}"
EXTRA_ARGS="${EXTRA_ARGS:-}"

# Clean any stale session from a previous run.
hopscotch clean --project-dir "$PROJECT_DIR" 2>/dev/null || true

ARGS=(dep "$DEP_NAME"
      --project-dir "$PROJECT_DIR"
      --keep-last-good)
[ -n "$FROM_REF" ] && ARGS+=(--from "$FROM_REF")
[ -n "$TO_REF"   ] && ARGS+=(--to "$TO_REF")

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
