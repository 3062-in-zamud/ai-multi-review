#!/usr/bin/env bash
# common.sh — ai-multi-review 共通関数

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/ai-multi-review"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# 色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ━━━ ユーティリティ ━━━

log_info()    { printf "${BLUE}[info]${RESET} %s\n" "$*" >&2; }
log_success() { printf "${GREEN}[done]${RESET} %s\n" "$*" >&2; }
log_warn()    { printf "${YELLOW}[warn]${RESET} %s\n" "$*" >&2; }
log_error()   { printf "${RED}[error]${RESET} %s\n" "$*" >&2; }

die() { log_error "$@"; exit 1; }

# config.json からキーを取得（jq 必須）
config_get() {
  local key="$1" default="${2:-}"
  local val
  val=$(jq -r "$key // empty" "$CONFIG_FILE" 2>/dev/null)
  echo "${val:-$default}"
}

# ━━━ Git 操作 ━━━

require_git_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "git リポジトリ内で実行してください"
}

get_project_name() {
  basename "$(git rev-parse --show-toplevel)"
}

get_branch_name() {
  git branch --show-current | tr '/' '-'
}

# diff モード判定: コミット差分があればそれを使い、なければ作業ツリーの変更を使う
# DIFF_MODE グローバル変数をセットする
detect_diff_mode() {
  local base_ref="$1"
  if ! git diff --quiet "${base_ref}...HEAD" 2>/dev/null; then
    DIFF_MODE="commit"
  elif ! git diff --cached --quiet 2>/dev/null; then
    DIFF_MODE="staged"
  elif ! git diff --quiet 2>/dev/null; then
    DIFF_MODE="unstaged"
  else
    DIFF_MODE="none"
  fi
}

get_diff() {
  local base_ref="$1"
  case "${DIFF_MODE}" in
    commit)   git diff "${base_ref}...HEAD" ;;
    staged)   git diff --cached ;;
    unstaged) git diff ;;
    *)        echo "" ;;
  esac
}

get_diff_stat() {
  local base_ref="$1"
  case "${DIFF_MODE}" in
    commit)   git diff --stat "${base_ref}...HEAD" ;;
    staged)   git diff --cached --stat ;;
    unstaged) git diff --stat ;;
  esac
}

get_diff_numstat() {
  local base_ref="$1"
  local added=0 removed=0 files=0
  local numstat_output
  case "${DIFF_MODE}" in
    commit)   numstat_output=$(git diff --numstat "${base_ref}...HEAD") ;;
    staged)   numstat_output=$(git diff --cached --numstat) ;;
    unstaged) numstat_output=$(git diff --numstat) ;;
    *)        echo "0 0 0"; return ;;
  esac
  while IFS=$'\t' read -r a r _; do
    [[ -z "$a" || "$a" == "-" ]] && continue
    added=$((added + a))
    removed=$((removed + r))
    files=$((files + 1))
  done <<< "$numstat_output"
  echo "${files} ${added} ${removed}"
}

get_diff_mode_label() {
  case "${DIFF_MODE}" in
    commit)   echo "commit diff (${1}...HEAD)" ;;
    staged)   echo "staged changes" ;;
    unstaged) echo "unstaged changes" ;;
    *)        echo "no changes" ;;
  esac
}

# ━━━ タイムアウト制御（macOS互換） ━━━

# bash & + sleep + kill パターン（timeout コマンド不要、eval不使用）
run_with_timeout() {
  local timeout_sec="$1"
  shift

  "$@" &
  local cmd_pid=$!

  (
    trap 'kill "$sleep_pid" 2>/dev/null; exit' TERM
    sleep "$timeout_sec" &
    sleep_pid=$!
    wait "$sleep_pid" 2>/dev/null
    kill "$cmd_pid" 2>/dev/null
  ) &
  local watchdog_pid=$!

  local exit_code
  if wait "$cmd_pid" 2>/dev/null; then
    exit_code=0
  else
    exit_code=$?
    if (( exit_code == 137 || exit_code == 143 )); then
      exit_code=124  # GNU timeout互換: タイムアウト
    fi
  fi

  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null
  return "$exit_code"
}

# ━━━ レビュアー管理 ━━━

# 有効なレビュアー一覧を取得
get_enabled_reviewers() {
  local filter="${1:-}"
  local all_reviewers
  all_reviewers=$(jq -r '.reviewers | to_entries[] | select(.value.enabled == true) | .key' "$CONFIG_FILE" 2>/dev/null)

  if [[ -n "$filter" ]]; then
    local filtered=""
    for r in $(echo "$filter" | tr ',' ' '); do
      if echo "$all_reviewers" | grep -qx "$r"; then
        filtered="${filtered}${filtered:+ }${r}"
      else
        log_warn "不明なレビュアー: $r（スキップ）"
      fi
    done
    echo "$filtered"
  else
    echo "$all_reviewers"
  fi
}

# レビュアーのタイムアウト値を取得
get_reviewer_timeout() {
  local reviewer="$1"
  config_get ".reviewers.${reviewer}.timeout" "120"
}

# ━━━ CLI存在チェック ━━━

check_cli() {
  local name="$1"
  command -v "$name" >/dev/null 2>&1
}

# ━━━ レポートパス ━━━

get_report_dir() {
  local project
  project=$(get_project_name)
  echo "${CONFIG_DIR}/reports/${project}"
}

get_report_name() {
  local project branch timestamp
  project=$(get_project_name)
  branch=$(get_branch_name)
  timestamp=$(date +%Y%m%d_%H%M%S)
  echo "${project}_${branch}_${timestamp}"
}

# latest symlink を更新
update_latest_symlink() {
  local report_dir="$1" report_name="$2"
  ln -sf "${report_name}.md" "${report_dir}/latest.md"
  ln -sf "${report_name}.issues.json" "${report_dir}/latest.issues.json"
}

# ━━━ レポートローテーション ━━━

rotate_reports() {
  local report_dir="$1"
  local keep
  keep=$(config_get ".report.keep_history" "10")

  # .md ファイルを古い順に取得し、keep件より多ければ削除
  local count
  count=$(find "$report_dir" -maxdepth 1 -name '*.md' ! -name 'latest.md' -type f | wc -l | tr -d ' ')

  if (( count > keep )); then
    local to_delete=$((count - keep))
    find "$report_dir" -maxdepth 1 -name '*.md' ! -name 'latest.md' -type f -print0 \
      | xargs -0 ls -t \
      | tail -n "$to_delete" \
      | while read -r md_file; do
          local json_file="${md_file%.md}.issues.json"
          rm -f "$md_file" "$json_file"
        done
  fi
}

# ━━━ JSON正規化（LLMフォールバック） ━━━

# CodeRabbit等のフリーテキスト出力をJSON正規化する
# Claude haiku で変換（低コスト）
normalize_with_llm() {
  local input_file="$1" output_file="$2" source_name="$3"
  local schema_file="${CONFIG_DIR}/lib/review-schema.json"

  # 入力が巨大な場合は先頭 + 末尾のみを送信
  local input_size
  input_size=$(wc -c < "$input_file" | tr -d ' ')
  if (( input_size > 50000 )); then
    local trimmed_file="${input_file}.trimmed"
    { head -100 "$input_file"; echo "... (truncated) ..."; tail -200 "$input_file"; } > "$trimmed_file"
    input_file="$trimmed_file"
  fi

  if ! check_cli claude; then
    # Claude CLI がなければフォールバック: 空issues
    log_warn "claude CLI不在のため ${source_name} の正規化をスキップ"
    echo '{"issues":[]}' > "$output_file"
    return 0
  fi

  local prompt
  prompt="以下のコードレビュー結果をJSON形式に変換してください。issuesが無い場合は空配列を返してください。

出力スキーマ:
$(cat "$schema_file")

レビュー結果:
$(cat "$input_file")"

  (
    [[ -n "${CLAUDECODE:-}" ]] && unset CLAUDECODE
    claude -p \
      --model haiku \
      --no-session-persistence \
      --output-format json \
      --json-schema "$(cat "$schema_file")" \
      "$prompt"
  ) > "$output_file" 2>/dev/null || {
    log_warn "${source_name} の正規化に失敗（生テキストを保持）"
    echo '{"issues":[]}' > "$output_file"
  }
}
