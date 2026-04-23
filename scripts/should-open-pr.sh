#!/usr/bin/env bash
# Decide whether to attempt opening a bump PR based on the hopscotch outcome,
# pin movement, and the `open-pr` input. Emits output `yes=true|false`.
#
# This boolean is checked by several downstream steps — computing it once
# keeps their `if:` guards simple.
#
# Required env:
#   OUTCOME, NEW_PIN, PREVIOUS_PIN, OPEN_PR

source "$(dirname "$0")/lib/common.sh"

OUTCOME="${OUTCOME:-}"
NEW_PIN="${NEW_PIN:-}"
PREVIOUS_PIN="${PREVIOUS_PIN:-}"
OPEN_PR="${OPEN_PR:-false}"

YES=false
if [ "$OUTCOME" != "skipped" ] \
   && [ "$OUTCOME" != "tool-error" ] \
   && [ -n "$NEW_PIN" ] \
   && [ "$NEW_PIN" != "$PREVIOUS_PIN" ] \
   && [ "$OPEN_PR" = "true" ]; then
  YES=true
fi

echo "yes=$YES" >> "$GITHUB_OUTPUT"
