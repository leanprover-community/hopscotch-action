#!/usr/bin/env bash
# Optionally fold hopscotch's automated fixes into the working tree before
# the branch is committed, by running `hopscotch fix apply` against the run's
# own results.json (.lake/hopscotch/results.json). `fix apply` applies both
# the break-repairing proposals and the deprecation advisories (its default).
#
# APPLY_FIXES is a boolean: "false" (default) detects only — the findings are
# still reported, but no source is touched; "true" runs `hopscotch fix apply`
# wherever it is safe and has something to do.
#
# Why the mode matters. `fix apply` rewrites the workspace against the pin
# currently in the manifest, so it is only safe where the rewrite builds:
#
#   * pin-to: first-bad — the manifest sits at the first-known-bad commit,
#     i.e. *at* the break, where the replacement modules a proposal names
#     already exist. Applying here turns the reproduction PR into a mergeable
#     "fix breaking changes" PR. We apply on `incompatible`.
#
#   * pin-to: last-good — the manifest sits at the last-known-good commit
#     (before the break) on a stopped run, or at the target on a green run.
#     A proposal points at a module that does not exist yet *before* the
#     break, so applying on a stopped run would break the LKG build — we skip
#     it. On a fully-green run `proposedFixes` is empty, so `fix apply` folds
#     in only the advisories (which build today): deprecation hygiene on the
#     bump PR.
#
# Emits output: fixes_applied=true|false
#
# Required env:
#   APPLY_FIXES, PIN_TO, OUTCOME, PROJECT_DIR
# Optional env:
#   PROPOSED_FIX_COUNT, DEPRECATED_IMPORT_COUNT

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

: "${PROJECT_DIR:?}"
APPLY_FIXES="${APPLY_FIXES:-false}"
PIN_TO="${PIN_TO:-last-good}"
OUTCOME="${OUTCOME:-}"
PROPOSED_FIX_COUNT="${PROPOSED_FIX_COUNT:-0}"
DEPRECATED_IMPORT_COUNT="${DEPRECATED_IMPORT_COUNT:-0}"

emit() { echo "fixes_applied=$1" >> "$GITHUB_OUTPUT"; }

if [ "$APPLY_FIXES" != "true" ]; then
  emit false
  exit 0
fi

# Decide whether there is anything safe and useful to apply.
SHOULD_APPLY=false
case "$PIN_TO" in
  first-bad)
    # Manifest is at the FKB — apply when there is a break repair to make
    # (`fix apply` folds in any advisories alongside it). With no proposal
    # the break is a genuine removal; leave the reproduction PR untouched.
    if [ "$OUTCOME" = "incompatible" ] && [ "$PROPOSED_FIX_COUNT" -gt 0 ]; then
      SHOULD_APPLY=true
    fi
    ;;
  *)
    # last-good: only fold advisories into a fully-green bump PR (a proposal
    # would not build before the break, and a green run has none anyway).
    if [ "$OUTCOME" = "passed" ] && [ "$DEPRECATED_IMPORT_COUNT" -gt 0 ]; then
      SHOULD_APPLY=true
    fi
    ;;
esac

if [ "$SHOULD_APPLY" != "true" ]; then
  log "Nothing to apply for mode='${PIN_TO}', outcome='${OUTCOME}'."
  emit false
  exit 0
fi

group "hopscotch fix apply"
set +e
hopscotch fix apply --project-dir "$PROJECT_DIR"
APPLY_EXIT=$?
set -e
endgroup

if [ "$APPLY_EXIT" -ne 0 ]; then
  emit false
  die "hopscotch fix apply exited with code ${APPLY_EXIT}."
fi

log "Applied automated fixes."
emit true
