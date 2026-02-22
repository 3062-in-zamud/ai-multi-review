#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016
# codex.sh — Codex CLI レビュアーアダプタ

reviewer_name="codex"

check_available() {
  check_cli codex
}

run_review() {
  local diff_file="$1" out_file="$2"
  local log_dir="${CONFIG_DIR}/logs"
  mkdir -p "$log_dir"
  local raw_file="${log_dir}/codex_raw.txt"
  local stderr_file="${log_dir}/codex_stderr.txt"

  # P-1: ツール使用禁止プロンプトでエージェント動作を抑止
  # codex exec は stdin を受け取らないため、CLI引数でdiffを渡す
  codex exec --sandbox read-only \
    "$(build_system_prompt)

$(build_user_prompt "$diff_file")

重要: ファイルの読み込みやシェルコマンドの実行は行わず、以下のdiffの内容のみからレビューしてください。JSON形式で結果を出力してください。" \
    > "$raw_file" 2> >(grep -v 'declare -x \(AWS_\|SECRET\|TOKEN\|KEY\|PASSWORD\)' > "$stderr_file")

  # Codex は構造化出力を保証しないため、JSON抽出を試みる
  if jq empty "$raw_file" 2>/dev/null; then
    cp "$raw_file" "$out_file"
  else
    # P-3: JSON抽出ロジック改善
    local json_block=""

    # 1. ```json ブロック
    json_block=$(sed -n '/^```json/,/^```/{ /^```/d; p; }' "$raw_file" 2>/dev/null) || true

    # 2. Python で堅牢にJSON抽出（末尾から逆方向にブレース対応で探索）
    # Note: sed/tail -r による行ベース抽出はプロンプト内テンプレートを誤検出するため廃止
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
" "$raw_file" 2>/dev/null) || true
    fi

    if [[ -n "$json_block" ]] && echo "$json_block" | jq empty 2>/dev/null; then
      echo "$json_block" > "$out_file"
    else
      # フォールバック: LLMで正規化
      normalize_with_llm "$raw_file" "$out_file" "codex"
    fi
  fi

  # A-5: 出力サイズ警告
  local raw_size
  raw_size=$(wc -c < "$raw_file" | tr -d ' ')
  if (( raw_size > 100000 )); then
    log_warn "Codex: 出力が大きい（${raw_size} bytes）。エージェント動作を確認してください。"
  fi
}
