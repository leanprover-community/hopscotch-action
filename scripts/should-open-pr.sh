#!/usr/bin/env bash
# Decide whether to attempt opening a PR based on the hopscotch outcome,
# mode, and the `open-pr` input. Emits output `yes=true|false`.
#
# Behaviour by mode:
#   pin-to: last-good (bump PR) — open when pin moved, i.e.
#                                 outcome ∈ {passed, incompatible} AND
#                                 new_pin is non-empty AND
#                                 new_pin != previous_pin AND
#                                 new_pin != culprit (defensive — see below).
#   pin-to: first-bad (fix PR) — open when a culprit was identified, i.e.
#                                outcome = incompatible AND
#                                new_pin = culprit (manifest at the FKB).
#                                No PR on `passed` — the close-fix-prs step
#                                handles the recovery side instead.
#
# The `new_pin != culprit` guard in LKG mode catches a degenerate hopscotch
# exit state: when the bisect's lower endpoint itself fails re-verification,
# `--keep-last-good` has no LKG to restore to and silently leaves the
# manifest at the failing probe. Without the guard we'd publish a "bump PR"
# pointing at the FKB.
#
# Required env:
#   PIN_TO, OUTCOME, NEW_PIN, CULPRIT, PREVIOUS_PIN, OPEN_PR

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

PIN_TO="${PIN_TO:-last-good}"
OUTCOME="${OUTCOME:-}"
NEW_PIN="${NEW_PIN:-}"
CULPRIT="${CULPRIT:-}"
PREVIOUS_PIN="${PREVIOUS_PIN:-}"
OPEN_PR="${OPEN_PR:-false}"

YES=false
if [ "$OPEN_PR" = "true" ]; then
  if [ "$PIN_TO" = "first-bad" ]; then
    if [ "$OUTCOME" = "incompatible" ] && [ -n "$CULPRIT" ] && [ "$NEW_PIN" = "$CULPRIT" ]; then
      YES=true
    fi
  else
    if [ "$OUTCOME" != "skipped" ] \
       && [ "$OUTCOME" != "tool-error" ] \
       && [ -n "$NEW_PIN" ] \
       && [ "$NEW_PIN" != "$PREVIOUS_PIN" ] \
       && [ "$NEW_PIN" != "$CULPRIT" ]; then
      YES=true
    fi
  fi
fi

echo "yes=$YES" >> "$GITHUB_OUTPUT"
