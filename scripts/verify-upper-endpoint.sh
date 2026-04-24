#!/usr/bin/env bash
# Verify the upper endpoint of the bisect window before the full bisect run.
# Runs hopscotch in linear mode over a single-commit window (target^ → target).
# If the endpoint passes, the downstream is already healthy and the bisect can
# be skipped entirely.
#
# Emits outputs:
#   upper_endpoint_sha — the resolved target SHA when it passes; empty otherwise
#
# Required env:
#   DEP_NAME, PROJECT_DIR, GIT_URL, TO_REF

# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

: "${DEP_NAME:?}"
: "${PROJECT_DIR:?}"
GIT_URL="${GIT_URL:-}"
TO_REF="${TO_REF:-}"

# Resolve TO_REF to a concrete SHA so we can address its parent commit.
# If TO_REF is empty, fall back to the upstream default-branch HEAD.
if [ -n "$TO_REF" ]; then
  UPPER_SHA=$(git ls-remote "$GIT_URL" "$TO_REF" | cut -f1 | head -1)
  # ls-remote matches ref names, not raw SHAs — if nothing came back, assume
  # TO_REF is already a full SHA.
  [ -z "$UPPER_SHA" ] && UPPER_SHA="$TO_REF"
else
  UPPER_SHA=$(git ls-remote "$GIT_URL" HEAD | cut -f1 | head -1)
fi

if [ -z "$UPPER_SHA" ]; then
  die "Could not resolve upper endpoint ref: '${TO_REF:-HEAD}'."
fi

log "Verifying upper endpoint ${UPPER_SHA} before bisect..."

group "hopscotch verify-upper output"
set +e
hopscotch dep "$DEP_NAME" \
  --project-dir "$PROJECT_DIR" \
  --from "${UPPER_SHA}^" \
  --to  "$UPPER_SHA" \
  --scan-mode linear
VERIFY_EXIT=$?
set -e
endgroup

# Restore the working tree: hopscotch rewrites lake-manifest.json during the
# probe, which would cause the main bisect run to fail with "dirty workspace".
git -C "$PROJECT_DIR" restore .

if [ "$VERIFY_EXIT" -eq 0 ]; then
  log "Upper endpoint passes — downstream is healthy; bisect skipped."
  echo "upper_endpoint_sha=$UPPER_SHA" >> "$GITHUB_OUTPUT"
elif [ "$VERIFY_EXIT" -eq 1 ]; then
  log "Upper endpoint fails — proceeding with bisect."
  echo "upper_endpoint_sha=" >> "$GITHUB_OUTPUT"
else
  die "hopscotch exited with error code $VERIFY_EXIT during endpoint verification."
fi
