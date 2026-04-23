#!/usr/bin/env bash
# Detect whether the working tree has uncommitted changes (staged or unstaged).
# Emits output: no_changes=true|false

source "$(dirname "$0")/lib/common.sh"

if git diff --quiet && git diff --cached --quiet; then
  log "No file changes detected — nothing to commit."
  echo "no_changes=true" >> "$GITHUB_OUTPUT"
else
  echo "no_changes=false" >> "$GITHUB_OUTPUT"
fi
