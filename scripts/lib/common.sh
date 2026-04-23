#!/usr/bin/env bash
# Shared preamble and helpers. Source this from every script.
#
#   source "$(dirname "$0")/lib/common.sh"
#
# Sets strict mode and exposes tiny logging helpers.

set -euo pipefail

log()  { printf '%s\n' "$*" >&2; }
die()  { printf '::error::%s\n' "$*" >&2; exit 1; }
warn() { printf '::warning::%s\n' "$*" >&2; }

# group / endgroup emit GitHub Actions log-folding markers.
group()    { printf '::group::%s\n' "$*"; }
endgroup() { printf '::endgroup::\n'; }
