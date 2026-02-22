#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016
# gemini.sh — Gemini CLI reviewer adapter

reviewer_name="gemini"

check_available() {
  check_cli gemini
}

run_review() {
  local diff_file="$1" out_file="$2"
  local log_dir="${CONFIG_DIR}/logs"
  mkdir -p "$log_dir"
  local raw_file="${log_dir}/gemini_raw.txt"
  local stderr_file="${log_dir}/gemini_stderr.txt"

  # Gemini CLI: positional prompt で呼び出し（-p/--prompt は deprecated）
  # stdin との併用不可のため、全プロンプトを1つの引数に結合
  gemini --sandbox \
    "$(build_system_prompt)

$(build_user_prompt "$diff_file")" \
    > "$raw_file" 2>"$stderr_file"

  # Gemini は構造化出力を保証しないため、JSON抽出を試みる
  # response フィールドに包まれている場合はそこから取得
  local content="$raw_file"
  if jq -e '.response' "$raw_file" >/dev/null 2>&1; then
    local extracted="${log_dir}/gemini_response.txt"
    jq -r '.response' "$raw_file" > "$extracted"
    content="$extracted"
  fi

  if jq -e '.issues' "$content" >/dev/null 2>&1; then
    cp "$content" "$out_file"
  else
    # Python brace-depth tracking で JSON 抽出（codex.sh パターン）
    local json_block=""

    # 1. ```json ブロック
    json_block=$(sed -n '/^```json/,/^```/{ /^```/d; p; }' "$content" 2>/dev/null) || true

    # 2. Python で堅牢にJSON抽出（末尾から逆方向にブレース対応で探索）
    if [[ -z "$json_block" ]] || ! echo "$json_block" | jq empty 2>/dev/null; then
      json_block=$(python3 -c "
import json, sys
text = open(sys.argv[1]).read()
last_close = text.rfind('}')
if last_close >= 0:
    depth = 0
    for i in range(last_close, -1, -1):
        if text[i] == '}': depth += 1
        elif text[i] == '{': depth -= 1
        if depth == 0:
            candidate = text[i:last_close+1]
            try:
                obj = json.loads(candidate)
                if 'issues' in obj:
                    json.dump(obj, sys.stdout)
                    sys.exit(0)
            except (json.JSONDecodeError, ValueError):
                pass
            break
" "$content" 2>/dev/null) || true
    fi

    if [[ -n "$json_block" ]] && echo "$json_block" | jq empty 2>/dev/null; then
      echo "$json_block" > "$out_file"
    else
      # フォールバック: LLMで正規化
      normalize_with_llm "$content" "$out_file" "gemini"
    fi
  fi
}
