#!/usr/bin/env bash
# Install elan (if missing), resolve the hopscotch version, detect the runner
# platform, download the correct release binary, and add it to PATH.
#
# Required env:
#   GH_TOKEN            — token for gh release lookups
#   HOPSCOTCH_VERSION   — release tag or "latest"

source "$(dirname "$0")/lib/common.sh"

: "${GH_TOKEN:?}"
: "${HOPSCOTCH_VERSION:?}"

# ---- elan -----------------------------------------------------------
if command -v elan &>/dev/null || [ -x "$HOME/.elan/bin/elan" ]; then
  log "elan already installed, skipping."
else
  group "Elan installation output"
  curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf \
    | sh -s -- -y --default-toolchain none
  endgroup
fi
echo "$HOME/.elan/bin" >> "$GITHUB_PATH"
"$HOME/.elan/bin/elan" --version

# ---- resolve version -----------------------------------------------
if [ "$HOPSCOTCH_VERSION" = "latest" ]; then
  VERSION=$(gh release view \
    --repo leanprover-community/hopscotch \
    --json tagName \
    --jq '.tagName')
  log "Resolved latest hopscotch version: $VERSION"
else
  VERSION="$HOPSCOTCH_VERSION"
fi

# ---- detect platform ------------------------------------------------
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
case "${OS}-${ARCH}" in
  linux-x86_64)          ASSET="hopscotch-linux-x86_64"  ; EXT="" ;;
  darwin-x86_64)         ASSET="hopscotch-macos-x86_64"  ; EXT="" ;;
  darwin-arm64)          ASSET="hopscotch-macos-arm64"   ; EXT="" ;;
  mingw*|cygwin*|msys*)  ASSET="hopscotch-windows-x86_64"; EXT=".exe" ;;
  *) die "Unsupported platform: ${OS}-${ARCH}" ;;
esac
INSTALL_NAME="hopscotch${EXT}"
log "Platform: ${OS}-${ARCH} → ${ASSET}"

# ---- download -------------------------------------------------------
mkdir -p "$HOME/.hopscotch-bin"
URL="https://github.com/leanprover-community/hopscotch/releases/download/${VERSION}/${ASSET}${EXT}"
log "Downloading $URL"
curl -fsSL "$URL" -o "$HOME/.hopscotch-bin/$INSTALL_NAME"
chmod +x "$HOME/.hopscotch-bin/$INSTALL_NAME"

# Ensure a canonical `hopscotch` name (strips .exe on Windows).
if [ -n "$EXT" ] && [ ! -f "$HOME/.hopscotch-bin/hopscotch" ]; then
  cp "$HOME/.hopscotch-bin/$INSTALL_NAME" "$HOME/.hopscotch-bin/hopscotch"
fi

echo "$HOME/.hopscotch-bin" >> "$GITHUB_PATH"
log "hopscotch $("$HOME/.hopscotch-bin/hopscotch" --version 2>/dev/null || echo '(version unknown)') installed."
