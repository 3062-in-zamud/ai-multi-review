#!/usr/bin/env bats
# report.bats - unit tests for lib/report.sh

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  # source first, then override CONFIG_FILE
  # shellcheck source=lib/common.sh
  source "$REPO_ROOT/lib/common.sh"
  # shellcheck source=lib/merge.sh
  source "$REPO_ROOT/lib/merge.sh"
  # shellcheck source=lib/report.sh
  source "$REPO_ROOT/lib/report.sh"

  export CONFIG_FILE="$BATS_TMPDIR/test_config.json"
  cat > "$CONFIG_FILE" <<'EOF'
{
  "merge": { "dedup_line_range": 5 },
  "report": { "keep_history": 10 }
}
EOF
}

teardown() {
  rm -f "$CONFIG_FILE"
}

BLOCKING_JSON='{"issues":[{"severity":"blocking","category":"secrets","file":"src/config.ts","lines":"10-10","problem":"Hardcoded API key","recommendation":"Use env var","detected_by":["claude"],"high_confidence":false}]}'
ADVISORY_JSON='{"issues":[{"severity":"advisory","category":"style","file":"src/app.ts","lines":"20-20","problem":"Unused variable","recommendation":"Remove it","detected_by":["codex"],"high_confidence":false}]}'
EMPTY_JSON='{"issues":[]}'
MIXED_JSON='{"issues":[{"severity":"blocking","category":"secrets","file":"src/config.ts","lines":"10-10","problem":"API key","recommendation":"Use env","detected_by":["claude","codex"],"high_confidence":true},{"severity":"advisory","category":"style","file":"src/app.ts","lines":"20-20","problem":"Unused var","recommendation":"Remove","detected_by":["claude"],"high_confidence":false}]}'

# --- generate_markdown_report ---

@test "generate_markdown_report includes main heading" {
  run generate_markdown_report "test_report" "myproject" "main" "origin/main" \
    3 50 10 "$EMPTY_JSON" ""
  assert_success
  assert_output --partial "# AI Multi Review Report"
}

@test "generate_markdown_report shows PASS when no issues" {
  run generate_markdown_report "test_report" "myproject" "main" "origin/main" \
    0 0 0 "$EMPTY_JSON" ""
  assert_success
  assert_output --partial "PASS"
}

@test "generate_markdown_report shows WARNING when blocking issues exist" {
  run generate_markdown_report "test_report" "myproject" "main" "origin/main" \
    3 50 10 "$BLOCKING_JSON" ""
  assert_success
  assert_output --partial "WARNING"
}

@test "generate_markdown_report includes Blocking Issues section" {
  run generate_markdown_report "test_report" "myproject" "main" "origin/main" \
    3 50 10 "$BLOCKING_JSON" ""
  assert_success
  assert_output --partial "## Blocking Issues"
}

@test "generate_markdown_report includes Advisory Issues section" {
  run generate_markdown_report "test_report" "myproject" "main" "origin/main" \
    2 30 5 "$ADVISORY_JSON" ""
  assert_success
  assert_output --partial "## Advisory Issues"
}

@test "generate_markdown_report omits Advisory section when none exist" {
  run generate_markdown_report "test_report" "myproject" "main" "origin/main" \
    3 50 10 "$BLOCKING_JSON" ""
  assert_success
  refute_output --partial "## Advisory Issues"
}

@test "generate_markdown_report includes Per-Reviewer Detail table" {
  run generate_markdown_report "test_report" "myproject" "main" "origin/main" \
    0 0 0 "$EMPTY_JSON" ""
  assert_success
  assert_output --partial "## Per-Reviewer Detail"
}

@test "generate_markdown_report includes project name" {
  run generate_markdown_report "test_report" "my-awesome-project" "feat/test" "main" \
    0 0 0 "$EMPTY_JSON" ""
  assert_success
  assert_output --partial "my-awesome-project"
}

@test "generate_markdown_report marks high_confidence issues" {
  run generate_markdown_report "test_report" "myproject" "main" "origin/main" \
    2 50 10 "$MIXED_JSON" ""
  assert_success
  assert_output --partial "high confidence"
}

# --- generate_issues_json ---

@test "generate_issues_json outputs valid JSON" {
  run generate_issues_json "$BLOCKING_JSON"
  assert_success
  echo "$output" | jq empty
}

@test "generate_issues_json assigns B-N ID to blocking issue" {
  run generate_issues_json "$BLOCKING_JSON"
  assert_success
  id=$(echo "$output" | jq -r '.issues[0].id')
  assert_equal "$id" "B-1"
}

@test "generate_issues_json assigns A-N ID to advisory issue" {
  run generate_issues_json "$ADVISORY_JSON"
  assert_success
  id=$(echo "$output" | jq -r '.issues[0].id')
  assert_equal "$id" "A-1"
}

@test "generate_issues_json puts blocking before advisory" {
  run generate_issues_json "$MIXED_JSON"
  assert_success
  first_id=$(echo "$output" | jq -r '.issues[0].id')
  assert_equal "$first_id" "B-1"
}

@test "generate_issues_json returns valid JSON for empty input" {
  run generate_issues_json "$EMPTY_JSON"
  assert_success
  count=$(echo "$output" | jq '.issues | length')
  assert_equal "$count" "0"
}

# --- get_stats ---

@test "get_stats counts blocking and advisory" {
  run get_stats "$MIXED_JSON"
  assert_success
  assert_output "1 1"
}

@test "get_stats returns 0 0 for empty issues" {
  run get_stats "$EMPTY_JSON"
  assert_success
  assert_output "0 0"
}
