#!/usr/bin/env bash
# Helpers for building PR/issue bodies and working with `gh` labels.
# Source after lib/common.sh.

# Extract "owner/repo" from any common GitHub URL form:
#   https://github.com/owner/repo        → owner/repo
#   https://github.com/owner/repo.git    → owner/repo
#   git@github.com:owner/repo.git        → owner/repo
# Anything without "github.com" returns empty.
repo_from_git_url() {
  local url="$1"
  if [[ "$url" != *github.com* ]]; then
    return 0
  fi
  # Two-stage extract keeps the regex POSIX-ERE portable (BSD sed rejects
  # non-greedy quantifiers like `+?`). First stage pulls owner/repo[.git],
  # second stage strips the optional .git.
  echo "$url" \
    | sed -E 's|.*github\.com[:/]([^/]+)/([^/]+)$|\1/\2|' \
    | sed -E 's|\.git$||'
}

# Markdown link to a commit. Falls back to `<short>` when no git_url, and "—" when sha is empty.
#   commit_link <sha> <git_url>
commit_link() {
  local sha="${1:-}" git_url="${2:-}"
  if [ -z "$sha" ]; then
    echo "—"
    return 0
  fi
  local short="${sha:0:7}"
  local repo
  repo=$(repo_from_git_url "$git_url")
  if [ -n "$repo" ]; then
    echo "[\`${short}\`](https://github.com/${repo}/commit/${sha})"
  else
    echo "\`${short}\`"
  fi
}

# Idempotently create a label. Swallows the "already exists" failure.
#   ensure_label <name> [color] [description]
ensure_label() {
  local name="$1" color="${2:-eec9fd}" description="${3:-}"
  if [ -n "$description" ]; then
    gh label create "$name" --color "$color" --description "$description" >/dev/null 2>&1 || true
  else
    gh label create "$name" --color "$color" >/dev/null 2>&1 || true
  fi
}

# Parse a comma-separated label list. For each non-empty trimmed entry, call
# ensure_label and emit "--label <name>" tokens on stdout, one per line.
# Callers should collect into an array with `mapfile`.
parse_labels_csv() {
  local csv="${1:-}"
  [ -z "$csv" ] && return 0
  local IFS=','
  read -ra entries <<< "$csv"
  for entry in "${entries[@]}"; do
    local trimmed="${entry#"${entry%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    if [ -n "$trimmed" ]; then
      ensure_label "$trimmed"
      printf -- '--label\n%s\n' "$trimmed"
    fi
  done
}
