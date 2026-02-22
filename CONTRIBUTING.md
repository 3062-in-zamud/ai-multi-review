# Contributing to ai-multi-review

**[English](#english)** | **[日本語](#日本語)**

---

## English

### Adding a New Reviewer

Each reviewer is a self-contained bash script in `reviewers/`. To add a new one:

#### 1. Create the adapter

Create `reviewers/<name>.sh` with this interface:

```bash
#!/usr/bin/env bash
# <name>.sh — <Name> CLI reviewer adapter

reviewer_name="<name>"

check_available() {
  check_cli <cli-command>
}

run_review() {
  local diff_file="$1" out_file="$2"
  # Call the CLI and write JSON to $out_file
  # Must match the schema in lib/review-schema.json
}
```

#### 2. Required functions

| Function | Purpose |
|----------|---------|
| `check_available()` | Return 0 if the CLI is installed, 1 otherwise |
| `run_review()` | Run the review and write JSON output to `$out_file` |

#### 3. Output schema

The output must be valid JSON matching `lib/review-schema.json`:

```json
{
  "issues": [
    {
      "severity": "blocking",
      "category": "security",
      "file": "src/auth.ts",
      "lines": "42-45",
      "problem": "SQL injection vulnerability",
      "recommendation": "Use parameterized queries"
    }
  ]
}
```

**severity**: `blocking` (must fix before merge) or `advisory` (recommended fix)

**category**: `security` | `correctness` | `perf` | `maintainability` | `testing` | `style`

#### 4. Available helpers

From `lib/common.sh` (auto-sourced):

| Helper | Usage |
|--------|-------|
| `check_cli <name>` | Check if a CLI command exists |
| `config_get <jq-path> [default]` | Read from config.json |
| `normalize_with_llm <input> <output> <source>` | Convert freetext to JSON via Claude haiku |
| `log_info`, `log_warn`, `log_error` | Colored logging to stderr |

#### 5. JSON extraction pattern

If the CLI doesn't guarantee JSON output, use the Python brace-depth extraction pattern (see `reviewers/codex.sh` or `reviewers/gemini.sh`):

```bash
# Try ```json block first
json_block=$(sed -n '/^```json/,/^```/{ /^```/d; p; }' "$raw_file") || true

# Fallback: Python brace-depth tracking
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
            except: pass
            break
" "$raw_file") || true
fi

# Final fallback: LLM normalization
if [[ -z "$json_block" ]]; then
  normalize_with_llm "$raw_file" "$out_file" "<name>"
fi
```

#### 6. Register in config.json

Add the reviewer to `config.json`:

```json
"<name>": { "enabled": false, "timeout": 300 }
```

#### 7. Update install.sh

Add an entry to the `REVIEWERS` array in `install.sh`:

```bash
"<name>|<cli-command>|<install-command>|false"
```

Format: `name|cli_command|install_hint|default_enabled`

### Testing

```bash
# Run with your new reviewer only
ai-multi-review --reviewers <name>

# Check that JSON output is valid
jq . ~/.config/ai-multi-review/logs/<name>_raw.txt
```

### Code Style

- Use `set -euo pipefail` in all scripts
- Log to stderr (stdout is for data)
- Use `|| true` for commands that may fail under `set -e`
- No `eval` — use arrays and direct invocation
- macOS compatible (no GNU-only tools like `tac`, `timeout`)

---

## 日本語

### 新しいレビュアーの追加方法

各レビュアーは `reviewers/` ディレクトリ内の独立した bash スクリプトです。

#### 1. アダプタを作成

`reviewers/<name>.sh` を以下のインターフェースで作成:

```bash
#!/usr/bin/env bash
# <name>.sh — <Name> CLI レビュアーアダプタ

reviewer_name="<name>"

check_available() {
  check_cli <cliコマンド>
}

run_review() {
  local diff_file="$1" out_file="$2"
  # CLIを呼び出し、JSONを $out_file に書き込む
  # lib/review-schema.json のスキーマに準拠すること
}
```

#### 2. 必須関数

| 関数 | 目的 |
|------|------|
| `check_available()` | CLIがインストール済みなら0を返す |
| `run_review()` | レビューを実行し、JSONを `$out_file` に出力 |

#### 3. 出力スキーマ

出力は `lib/review-schema.json` に準拠した有効なJSONであること:

```json
{
  "issues": [
    {
      "severity": "blocking",
      "category": "security",
      "file": "src/auth.ts",
      "lines": "42-45",
      "problem": "SQLインジェクション脆弱性",
      "recommendation": "パラメタライズドクエリを使用"
    }
  ]
}
```

**severity**: `blocking`（マージ前に修正必須）または `advisory`（修正推奨）

**category**: `security` | `correctness` | `perf` | `maintainability` | `testing` | `style`

#### 4. 利用可能なヘルパー関数

`lib/common.sh` から自動読み込み:

| ヘルパー | 用途 |
|---------|------|
| `check_cli <name>` | CLIコマンドの存在チェック |
| `config_get <jqパス> [デフォルト]` | config.json からの値取得 |
| `normalize_with_llm <入力> <出力> <ソース名>` | フリーテキストをClaude haikuでJSON変換 |
| `log_info`, `log_warn`, `log_error` | 色付きログ出力（stderr） |

#### 5. JSON抽出パターン

CLIがJSON出力を保証しない場合、Python brace-depth抽出パターンを使用（`reviewers/codex.sh` や `reviewers/gemini.sh` を参照）:

1. ` ```json ` ブロックを試行
2. Python でブレース深度追跡によるJSON抽出（末尾から逆方向探索）
3. 最終フォールバック: `normalize_with_llm` でLLM変換

#### 6. config.json への登録

```json
"<name>": { "enabled": false, "timeout": 300 }
```

#### 7. install.sh の更新

`REVIEWERS` 配列にエントリを追加:

```bash
"<name>|<cliコマンド>|<インストールコマンド>|false"
```

形式: `name|cli_command|install_hint|default_enabled`

### テスト

```bash
# 新しいレビュアーのみで実行
ai-multi-review --reviewers <name>

# JSON出力が有効か確認
jq . ~/.config/ai-multi-review/logs/<name>_raw.txt
```

### コードスタイル

- 全スクリプトで `set -euo pipefail` を使用
- ログは stderr に出力（stdout はデータ用）
- `set -e` 下で失敗しうるコマンドには `|| true` を付与
- `eval` 禁止 — 配列と直接呼び出しを使用
- macOS互換（`tac`, `timeout` 等のGNU専用ツール不可）
