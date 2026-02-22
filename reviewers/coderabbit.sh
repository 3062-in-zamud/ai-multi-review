#!/usr/bin/env bash
# coderabbit.sh — CodeRabbit CLI レビュアーアダプタ

reviewer_name="coderabbit"

check_available() {
  check_cli coderabbit
}

run_review() {
  local diff_file="$1" out_file="$2"
  local log_dir="${CONFIG_DIR}/logs"
  mkdir -p "$log_dir"
  local raw_file="${log_dir}/coderabbit_raw.txt"
  local stderr_file="${log_dir}/coderabbit_stderr.txt"

  # CodeRabbit CLI: --prompt-only で簡潔な出力を取得
  coderabbit review --prompt-only < "$diff_file" \
    > "$raw_file" 2>"$stderr_file"

  if [[ ! -s "$raw_file" ]]; then
    log_warn "CodeRabbit: 出力が空です（stderr: $(head -3 "$stderr_file" 2>/dev/null)）"
    echo '{"issues":[]}' > "$out_file"
    return 0
  fi

  # テキスト出力をシンプルなJSON変換（LLM不要）
  parse_coderabbit_output "$raw_file" "$out_file"
}

# CodeRabbit のテキスト出力を正規化JSONに変換
# フォーマット: "File: ...\nLine: ...\nType: ...\nComment: ..."
parse_coderabbit_output() {
  local raw_file="$1" out_file="$2"

  python3 -c "
import json, re, sys

text = open(sys.argv[1]).read()
issues = []
blocks = text.split('=' * 76)

for block in blocks:
    block = block.strip()
    if not block:
        continue

    file_match = re.search(r'File:\s*(.+)', block)
    line_match = re.search(r'Line:\s*(.+)', block)
    type_match = re.search(r'Type:\s*(.+)', block)
    comment_match = re.search(r'Comment:\s*\n?([\s\S]*?)(?:\n\nPrompt for AI Agent:|$)', block)

    if not file_match:
        continue

    file_path = file_match.group(1).strip()
    lines = line_match.group(1).strip().replace(' to ', '-') if line_match else ''
    issue_type = type_match.group(1).strip() if type_match else 'unknown'
    comment = comment_match.group(1).strip() if comment_match else ''

    # severity判定
    severity = 'blocking' if issue_type in ('bug', 'security', 'error') else 'advisory'

    # category判定
    category_map = {
        'bug': 'correctness', 'error': 'correctness',
        'security': 'security',
        'performance': 'perf',
        'potential_issue': 'correctness',
        'improvement': 'maintainability',
        'style': 'style',
    }
    category = category_map.get(issue_type, 'maintainability')

    # comment を problem と recommendation に分割
    parts = comment.split('\n\n', 1)
    problem = parts[0][:200] if parts else comment[:200]
    recommendation = parts[1][:200] if len(parts) > 1 else ''

    issues.append({
        'severity': severity,
        'category': category,
        'file': file_path,
        'lines': lines,
        'problem': problem,
        'recommendation': recommendation
    })

json.dump({'issues': issues}, sys.stdout, ensure_ascii=False)
" "$raw_file" > "$out_file" 2>/dev/null

  # Python が失敗した場合のフォールバック
  if [[ ! -s "$out_file" ]] || ! jq empty "$out_file" 2>/dev/null; then
    log_warn "CodeRabbit: テキストパースに失敗（LLMフォールバック）"
    normalize_with_llm "$raw_file" "$out_file" "coderabbit"
  fi
}
