#!/usr/bin/env bash
# shellcheck disable=SC2034
# claude.sh — Claude CLI レビュアーアダプタ

reviewer_name="claude"

check_available() {
  check_cli claude
}

run_review() {
  local diff_file="$1" out_file="$2"
  local schema_file="${CONFIG_DIR}/lib/review-schema.json"
  local log_dir="${CONFIG_DIR}/logs"
  mkdir -p "$log_dir"
  local stderr_file="${log_dir}/claude_stderr.txt"

  local model
  model=$(config_get ".reviewers.claude.model" "sonnet")
  local budget
  budget=$(config_get ".reviewers.claude.max_budget_usd" "0.50")

  (
    # Claude Code セッション内からの呼び出し時にネスト回避
    [[ -n "${CLAUDECODE:-}" ]] && unset CLAUDECODE

    claude -p \
      --model "$model" \
      --output-format json \
      --json-schema "$(cat "$schema_file")" \
      --system-prompt "$(build_system_prompt)" \
      --max-budget-usd "$budget" \
      "$(build_user_prompt "$diff_file")"
  ) > "$out_file" 2>"$stderr_file"
}
