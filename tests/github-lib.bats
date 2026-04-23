#!/usr/bin/env bats
# Unit tests for scripts/lib/github.sh helpers.

load helpers

setup() {
  # shellcheck source=/dev/null
  source "$SCRIPTS_DIR/lib/common.sh" 2>/dev/null || true
  # shellcheck source=/dev/null
  source "$SCRIPTS_DIR/lib/github.sh"
}

@test "repo_from_git_url: https URL" {
  run repo_from_git_url "https://github.com/owner/repo"
  [ "$output" = "owner/repo" ]
}

@test "repo_from_git_url: https URL with .git suffix" {
  run repo_from_git_url "https://github.com/owner/repo.git"
  [ "$output" = "owner/repo" ]
}

@test "repo_from_git_url: ssh URL with .git suffix" {
  run repo_from_git_url "git@github.com:owner/repo.git"
  [ "$output" = "owner/repo" ]
}

@test "repo_from_git_url: non-github URL returns empty" {
  run repo_from_git_url "https://gitlab.example.com/owner/repo.git"
  [ -z "$output" ]
}

@test "repo_from_git_url: empty input returns empty" {
  run repo_from_git_url ""
  [ -z "$output" ]
}

@test "commit_link: with git_url produces markdown link" {
  run commit_link "abcdef0123456789" "https://github.com/owner/repo"
  [ "$output" = "[\`abcdef0\`](https://github.com/owner/repo/commit/abcdef0123456789)" ]
}

@test "commit_link: without git_url produces bare short sha" {
  run commit_link "abcdef0123456789" ""
  [ "$output" = "\`abcdef0\`" ]
}

@test "commit_link: empty sha produces em-dash" {
  run commit_link "" "https://github.com/owner/repo"
  [ "$output" = "—" ]
}

@test "parse_labels_csv: single label emits --label and the name" {
  # Mock gh so ensure_label inside parse_labels_csv is a no-op.
  PATH="$STUBS_DIR:$PATH" run parse_labels_csv "bug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--label"* ]]
  [[ "$output" == *"bug"* ]]
}

@test "parse_labels_csv: multiple labels with spaces are trimmed" {
  PATH="$STUBS_DIR:$PATH" run parse_labels_csv " bug , enhancement "
  [ "$status" -eq 0 ]
  # Two --label tokens and two names; all whitespace-stripped.
  local label_count name_count
  label_count=$(echo "$output" | grep -c -- "^--label$")
  [ "$label_count" = "2" ]
  echo "$output" | grep -Fxq "bug"
  echo "$output" | grep -Fxq "enhancement"
}

@test "parse_labels_csv: empty input produces no output" {
  PATH="$STUBS_DIR:$PATH" run parse_labels_csv ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "parse_labels_csv: empty entries skipped" {
  PATH="$STUBS_DIR:$PATH" run parse_labels_csv "bug,,enhancement"
  [ "$status" -eq 0 ]
  local label_count
  label_count=$(echo "$output" | grep -c -- "^--label$")
  [ "$label_count" = "2" ]
}
