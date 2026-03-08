#!/usr/bin/env bats
# merge.bats - unit tests for lib/merge.sh

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
FIXTURES="$BATS_TEST_DIRNAME/fixtures"

setup() {
  # source first (sets CONFIG_FILE to real path), then override
  # shellcheck source=lib/common.sh
  source "$REPO_ROOT/lib/common.sh"
  # shellcheck source=lib/merge.sh
  source "$REPO_ROOT/lib/merge.sh"

  export CONFIG_FILE="$BATS_TMPDIR/test_config.json"
  cat > "$CONFIG_FILE" <<'EOF'
{
  "merge": {
    "dedup_line_range": 5
  }
}
EOF

  export RESULT_DIR="$BATS_TMPDIR/results"
  mkdir -p "$RESULT_DIR"
}

teardown() {
  rm -rf "$RESULT_DIR"
  rm -f "$CONFIG_FILE"
}

# --- basic cases ---

@test "empty result_dir returns empty issues array" {
  run merge_results "$RESULT_DIR"
  assert_success
  result_issues=$(echo "$output" | jq '.issues | length')
  assert_equal "$result_issues" "0"
}

@test "invalid JSON file is skipped" {
  echo "not json" > "$RESULT_DIR/bad.json"
  run merge_results "$RESULT_DIR"
  assert_success
  result_issues=$(echo "$output" | jq '.issues | length')
  assert_equal "$result_issues" "0"
}

@test "single reviewer issues are returned as-is" {
  cp "$FIXTURES/issues_single.json" "$RESULT_DIR/claude.json"
  run merge_results "$RESULT_DIR"
  assert_success
  result_issues=$(echo "$output" | jq '.issues | length')
  assert_equal "$result_issues" "1"
}

@test "reviewer name is added to detected_by" {
  cp "$FIXTURES/issues_single.json" "$RESULT_DIR/claude.json"
  run merge_results "$RESULT_DIR"
  assert_success
  detected=$(echo "$output" | jq -r '.issues[0].detected_by[0]')
  assert_equal "$detected" "claude"
}

@test "empty issues file returns zero count" {
  cp "$FIXTURES/issues_empty.json" "$RESULT_DIR/claude.json"
  run merge_results "$RESULT_DIR"
  assert_success
  result_issues=$(echo "$output" | jq '.issues | length')
  assert_equal "$result_issues" "0"
}

# --- null file/category handling ---

@test "null file issue is preserved without erroneous merge" {
  cp "$FIXTURES/issues_null.json" "$RESULT_DIR/claude.json"
  run merge_results "$RESULT_DIR"
  assert_success
  result_issues=$(echo "$output" | jq '.issues | length')
  assert_equal "$result_issues" "2"
}

@test "null file issue is not merged with valid issue" {
  cp "$FIXTURES/issues_null.json" "$RESULT_DIR/claude.json"
  run merge_results "$RESULT_DIR"
  assert_success
  null_count=$(echo "$output" | jq '[.issues[] | select(.file == null)] | length')
  assert_equal "$null_count" "1"
}

# --- deduplication ---

@test "issues in same file+category within line range are merged to one" {
  cp "$FIXTURES/issues_duplicate.json" "$RESULT_DIR/claude.json"
  run merge_results "$RESULT_DIR"
  assert_success
  # lines 42 and 44 are within range=5, should merge to 1
  result_issues=$(echo "$output" | jq '.issues | length')
  assert_equal "$result_issues" "1"
}

@test "blocking severity is preferred when merging" {
  cp "$FIXTURES/issues_duplicate.json" "$RESULT_DIR/claude.json"
  run merge_results "$RESULT_DIR"
  assert_success
  severity=$(echo "$output" | jq -r '.issues[0].severity')
  assert_equal "$severity" "blocking"
}

@test "issues beyond line range are not deduplicated" {
  cat > "$RESULT_DIR/claude.json" <<'EOF'
{
  "issues": [
    {
      "severity": "advisory",
      "category": "style",
      "file": "src/app.ts",
      "lines": "10-10",
      "problem": "Issue at line 10",
      "recommendation": "Fix"
    },
    {
      "severity": "advisory",
      "category": "style",
      "file": "src/app.ts",
      "lines": "50-50",
      "problem": "Issue at line 50",
      "recommendation": "Fix"
    }
  ]
}
EOF
  run merge_results "$RESULT_DIR"
  assert_success
  result_issues=$(echo "$output" | jq '.issues | length')
  assert_equal "$result_issues" "2"
}

# --- multi-reviewer / confidence ---

@test "high_confidence is true when multiple reviewers detect nearby issue" {
  cat > "$RESULT_DIR/claude.json" <<'EOF'
{
  "issues": [
    {
      "severity": "blocking",
      "category": "authz",
      "file": "src/api.ts",
      "lines": "100-100",
      "problem": "Missing auth middleware",
      "recommendation": "Add requireAuth"
    }
  ]
}
EOF
  cat > "$RESULT_DIR/codex.json" <<'EOF'
{
  "issues": [
    {
      "severity": "blocking",
      "category": "authz",
      "file": "src/api.ts",
      "lines": "102-102",
      "problem": "Missing auth middleware (codex)",
      "recommendation": "Add requireAuth middleware"
    }
  ]
}
EOF
  run merge_results "$RESULT_DIR"
  assert_success
  high_conf=$(echo "$output" | jq '.issues[0].high_confidence')
  assert_equal "$high_conf" "true"
}

@test "detected_by is uniquely merged from multiple reviewers" {
  cat > "$RESULT_DIR/claude.json" <<'EOF'
{
  "issues": [
    {
      "severity": "blocking",
      "category": "secrets",
      "file": "src/config.ts",
      "lines": "10-10",
      "problem": "API key",
      "recommendation": "Use env var"
    }
  ]
}
EOF
  cat > "$RESULT_DIR/codex.json" <<'EOF'
{
  "issues": [
    {
      "severity": "blocking",
      "category": "secrets",
      "file": "src/config.ts",
      "lines": "11-11",
      "problem": "Hardcoded key",
      "recommendation": "Move to env"
    }
  ]
}
EOF
  run merge_results "$RESULT_DIR"
  assert_success
  detected_count=$(echo "$output" | jq '.issues[0].detected_by | length')
  assert_equal "$detected_count" "2"
}

@test "confidence is promoted by one level when two reviewers agree" {
  cat > "$RESULT_DIR/claude.json" <<'EOF'
{
  "issues": [
    {
      "severity": "advisory",
      "category": "style",
      "file": "src/app.ts",
      "lines": "20-20",
      "problem": "Style issue",
      "recommendation": "Fix style",
      "confidence": "medium"
    }
  ]
}
EOF
  cat > "$RESULT_DIR/codex.json" <<'EOF'
{
  "issues": [
    {
      "severity": "advisory",
      "category": "style",
      "file": "src/app.ts",
      "lines": "22-22",
      "problem": "Style issue detected",
      "recommendation": "Fix style",
      "confidence": "medium"
    }
  ]
}
EOF
  run merge_results "$RESULT_DIR"
  assert_success
  # medium(2) + 1 = high(3)
  confidence=$(echo "$output" | jq -r '.issues[0].confidence')
  assert_equal "$confidence" "high"
}

@test "high_confidence is false for single reviewer" {
  cp "$FIXTURES/issues_single.json" "$RESULT_DIR/claude.json"
  run merge_results "$RESULT_DIR"
  assert_success
  high_conf=$(echo "$output" | jq '.issues[0].high_confidence')
  assert_equal "$high_conf" "false"
}

# --- get_stats ---

@test "get_stats counts blocking and advisory correctly" {
  local merged_json='{"issues":[{"severity":"blocking"},{"severity":"advisory"},{"severity":"advisory"}]}'
  run get_stats "$merged_json"
  assert_success
  assert_output "1 2"
}

@test "get_stats returns 0 0 for empty issues" {
  run get_stats '{"issues":[]}'
  assert_success
  assert_output "0 0"
}
