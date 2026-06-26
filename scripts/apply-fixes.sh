#!/usr/bin/env bash
# Optionally fold hopscotch's automated import fixes into the working tree
# before the branch is committed, by running `hopscotch fix apply` against
# the run's own results.json (.lake/hopscotch/results.json).
#
# APPLY_FIXES selects how much to apply:
#   none      (default) — never touch source; detection is still reported.
#   boundary            — apply only the break-repairing proposals
#                         (`hopscotch fix apply --no-advisories`).
#   all                 — also apply deprecation-hygiene advisories
#                         (`hopscotch fix apply`).
#
# Why the mode matters. `fix apply` rewrites downstream imports against the
# pin currently in the manifest, so it is only safe where the rewrite
# actually builds:
#
#   * pin-to: first-bad — the manifest sits at the first-known-bad commit,
#     i.e. *at* the break, where the replacement modules a proposal names
#     already exist. Applying proposals here turns the reproduction PR into
#     a mergeable "fix breaking changes" PR. We apply on `incompatible`.
#
#   * pin-to: last-good — the manifest sits at the last-known-good commit
#     (before the break) on a stopped run, or at the target on a green run.
#     A boundary proposal rewrites an import to a module that does not exist
#     yet *before* the break, so applying proposals here would break the LKG
#     build. We therefore only fold in advisories (imports that build today),
#     and only on a fully-green run — where `proposedFixes` is empty so
#     `fix apply` touches advisories alone. This is the `all`-only,
#     green-only deprecation-hygiene case.
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
APPLY_FIXES="${APPLY_FIXES:-none}"
PIN_TO="${PIN_TO:-last-good}"
OUTCOME="${OUTCOME:-}"
PROPOSED_FIX_COUNT="${PROPOSED_FIX_COUNT:-0}"
DEPRECATED_IMPORT_COUNT="${DEPRECATED_IMPORT_COUNT:-0}"

emit() { echo "fixes_applied=$1" >> "$GITHUB_OUTPUT"; }

if [ "$APPLY_FIXES" = "none" ]; then
  emit false
  exit 0
fi

# Decide whether there is anything safe and useful to apply, and assemble
# the `fix apply` argument list.
APPLY_ARGS=(fix apply --project-dir "$PROJECT_DIR")
SHOULD_APPLY=false

case "$PIN_TO" in
  first-bad)
    # Manifest is at the FKB — proposals (and, for `all`, advisories) apply.
    if [ "$OUTCOME" = "incompatible" ]; then
      if [ "$APPLY_FIXES" = "boundary" ]; then
        APPLY_ARGS+=(--no-advisories)
        [ "$PROPOSED_FIX_COUNT" -gt 0 ] && SHOULD_APPLY=true
      else
        { [ "$PROPOSED_FIX_COUNT" -gt 0 ] || [ "$DEPRECATED_IMPORT_COUNT" -gt 0 ]; } \
          && SHOULD_APPLY=true
      fi
    fi
    ;;
  *)
    # last-good: only fold deprecation hygiene into a fully-green bump PR.
    if [ "$APPLY_FIXES" = "all" ] \
       && [ "$OUTCOME" = "passed" ] \
       && [ "$DEPRECATED_IMPORT_COUNT" -gt 0 ]; then
      SHOULD_APPLY=true
    fi
    ;;
esac

if [ "$SHOULD_APPLY" != "true" ]; then
  log "No automated fixes to apply for mode='${PIN_TO}', outcome='${OUTCOME}', apply-fixes='${APPLY_FIXES}'."
  emit false
  exit 0
fi

group "hopscotch fix apply"
set +e
hopscotch "${APPLY_ARGS[@]}"
APPLY_EXIT=$?
set -e
endgroup

if [ "$APPLY_EXIT" -ne 0 ]; then
  emit false
  die "hopscotch fix apply exited with code ${APPLY_EXIT}."
fi

log "Applied automated fixes (apply-fixes='${APPLY_FIXES}')."
emit true
