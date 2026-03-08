#!/usr/bin/env bats
# common.bats - unit tests for lib/common.sh

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  # source first (it sets CONFIG_FILE to real path), then override
  # shellcheck source=lib/common.sh
  source "$REPO_ROOT/lib/common.sh"

  export CONFIG_FILE="$BATS_TMPDIR/test_config.json"
  cat > "$CONFIG_FILE" <<'EOF'
{
  "merge": {
    "dedup_line_range": 5
  },
  "report": {
    "keep_history": 10
  }
}
EOF

  TEST_REPO="$BATS_TMPDIR/test_repo_$$"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO" || return
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
  git commit --allow-empty -m "init" -q
}

teardown() {
  rm -rf "$BATS_TMPDIR/test_repo_$$"
  rm -f "$CONFIG_FILE"
}

# --- run_with_timeout ---

@test "run_with_timeout: successful command returns exit code 0" {
  run run_with_timeout 5 true
  assert_success
}

@test "run_with_timeout: command output is correctly passed through" {
  run run_with_timeout 5 echo "hello world"
  assert_success
  assert_output "hello world"
}

@test "run_with_timeout: failing command returns non-zero exit code" {
  run run_with_timeout 5 false
  assert_failure
}

@test "run_with_timeout: timeout returns exit code 124" {
  run run_with_timeout 1 sleep 30
  assert_equal "$status" "124"
}

# --- log_* functions ---

@test "log_info outputs to stderr" {
  run bash -c "
    source '$REPO_ROOT/lib/common.sh'
    export CONFIG_FILE='$CONFIG_FILE'
    log_info 'test message' 2>&1
  "
  assert_success
  assert_output --partial "test message"
}

@test "log_error outputs to stderr" {
  run bash -c "
    source '$REPO_ROOT/lib/common.sh'
    export CONFIG_FILE='$CONFIG_FILE'
    log_error 'error message' 2>&1
  "
  assert_success
  assert_output --partial "error message"
}

@test "log_warn outputs to stderr" {
  run bash -c "
    source '$REPO_ROOT/lib/common.sh'
    export CONFIG_FILE='$CONFIG_FILE'
    log_warn 'warn message' 2>&1
  "
  assert_success
  assert_output --partial "warn message"
}

# --- config_get ---

@test "config_get returns value for existing key" {
  run config_get ".merge.dedup_line_range"
  assert_success
  assert_output "5"
}

@test "config_get returns default for missing key" {
  run config_get ".nonexistent.key" "default_value"
  assert_success
  assert_output "default_value"
}

# --- git operations ---

@test "get_project_name returns repository directory name" {
  cd "$BATS_TMPDIR/test_repo_$$"
  run get_project_name
  assert_success
  assert_output "test_repo_$$"
}

@test "get_branch_name returns non-empty branch name" {
  cd "$BATS_TMPDIR/test_repo_$$"
  run get_branch_name
  assert_success
  [[ -n "$output" ]]
}

# --- shorten_path ---

@test "shorten_path replaces HOME with tilde" {
  run shorten_path "$HOME/some/path"
  assert_success
  assert_output "~/some/path"
}

@test "shorten_path leaves non-HOME paths unchanged" {
  run shorten_path "/tmp/some/path"
  assert_success
  assert_output "/tmp/some/path"
}
