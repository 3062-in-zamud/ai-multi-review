# ai-multi-review

**[English](#english)** | **[日本語](#日本語)**

---

## English

Pre-PR code review with multiple LLM CLIs in parallel. Run several AI reviewers against your diff, deduplicate findings, and get a unified report — all before opening a pull request.

### Supported Reviewers

| Reviewer | CLI | Default | Status |
|----------|-----|---------|--------|
| CodeRabbit | `coderabbit` | enabled | stable |
| Claude Code | `claude` | enabled | stable |
| OpenAI Codex | `codex` | enabled | stable |
| Gemini CLI | `gemini` | disabled | stable |
| Aider | `aider` | disabled | skeleton |
| OpenCode | `opencode` | disabled | skeleton |
| GitHub Copilot | `gh copilot` | disabled | skeleton |

**skeleton** = adapter interface only, not yet tested with actual CLI.

### Features

- Parallel execution of multiple LLM code reviewers
- Automatic diff detection (commit diff > staged > unstaged)
- Cross-reviewer deduplication with configurable line-range tolerance
- Unified Markdown report with blocking/advisory severity
- JSON issues output for automated fix workflows
- Configurable timeouts, models, and budget limits per reviewer
- Interactive installer with auto-detection

### Quick Start

```bash
# 1. Clone
git clone https://github.com/3062-in-zamud/ai-multi-review.git ~/workspaces/ai-multi-review

# 2. Install (interactive setup)
bash ~/workspaces/ai-multi-review/install.sh

# 3. Run in any git repo
cd your-project
ai-multi-review
```

The installer auto-detects installed CLIs and generates `config.json` accordingly.

### Usage

```bash
ai-multi-review                        # Review diff against main
ai-multi-review develop                # Review diff against develop
ai-multi-review --reviewers claude     # Claude only
ai-multi-review --no-block             # Don't exit 1 on blocking issues
ai-multi-review --output report.md     # Custom output path
```

#### Diff Detection (automatic priority)

1. **Commit diff** (`BASE...HEAD`) — committed changes since base branch
2. **Staged changes** (`git add`) — if no commit diff
3. **Unstaged changes** — if nothing staged

### Configuration

Edit `~/.config/ai-multi-review/config.json`:

```json
{
  "reviewers": {
    "coderabbit": { "enabled": true, "timeout": 180 },
    "claude": { "enabled": true, "timeout": 300, "model": "sonnet", "max_budget_usd": 0.50 },
    "codex": { "enabled": true, "timeout": 300 },
    "gemini": { "enabled": false, "timeout": 300 }
  },
  "defaults": { "base_ref": "main" },
  "merge": { "dedup_line_range": 5 },
  "report": { "keep_history": 10 }
}
```

| Setting | Description |
|---------|-------------|
| `enabled` | Skip this reviewer when `false` |
| `timeout` | Per-reviewer timeout in seconds |
| `model` | Claude model (`sonnet` / `haiku` / `opus`) |
| `max_budget_usd` | Claude per-run cost cap |
| `base_ref` | Default comparison branch |
| `dedup_line_range` | Line range tolerance for deduplication (±N) |
| `keep_history` | Reports to keep per project |

### Architecture

```
bin/ai-multi-review          # Main entry point
lib/
├── common.sh                # Git operations, config, timeout, CLI checks
├── merge.sh                 # Cross-reviewer deduplication
├── report.sh                # Terminal + Markdown report generation
└── review-schema.json       # JSON output schema
prompts/
├── review-system.md         # System prompt (review criteria)
└── review-user.md           # User prompt (output schema)
reviewers/
├── claude.sh                # Claude Code adapter
├── codex.sh                 # OpenAI Codex adapter
├── coderabbit.sh            # CodeRabbit adapter
├── gemini.sh                # Gemini CLI adapter
├── aider.sh                 # Aider adapter (skeleton)
├── opencode.sh              # OpenCode adapter (skeleton)
└── gh-copilot.sh            # GitHub Copilot adapter (skeleton)
```

### Editor Integration

#### Claude Code

```
/ai-multi-review              # Run review
/fix-review latest             # Fix issues from latest report
```

#### Codex CLI

```bash
codex exec "$(cat ~/.codex/instructions/fix-review.md) $(cat path/to/issues.json)"
```

---

## 日本語

PR作成前に複数のLLM CLIを並列実行してコードレビューを行い、結果を重複除去した統合レポートとして出力するツールです。

### 対応レビュアー

| レビュアー | CLI | デフォルト | 状態 |
|-----------|-----|-----------|------|
| CodeRabbit | `coderabbit` | 有効 | 安定版 |
| Claude Code | `claude` | 有効 | 安定版 |
| OpenAI Codex | `codex` | 有効 | 安定版 |
| Gemini CLI | `gemini` | 無効 | 安定版 |
| Aider | `aider` | 無効 | スケルトン |
| OpenCode | `opencode` | 無効 | スケルトン |
| GitHub Copilot | `gh copilot` | 無効 | スケルトン |

**スケルトン** = アダプタのインターフェースのみ。実CLIでの動作確認は未実施。

### 機能

- 複数LLMレビュアーの並列実行
- 自動diff検出（コミット差分 > ステージ済み > 未ステージ）
- レビュアー間の重複除去（行範囲のトレランス設定可能）
- blocking/advisory の重要度付き統合Markdownレポート
- 自動修正ワークフロー用のJSON issues出力
- レビュアーごとのタイムアウト・モデル・予算上限設定
- CLI自動検出付きインタラクティブインストーラー

### クイックスタート

```bash
# 1. クローン
git clone https://github.com/3062-in-zamud/ai-multi-review.git ~/workspaces/ai-multi-review

# 2. セットアップ（インタラクティブ）
bash ~/workspaces/ai-multi-review/install.sh

# 3. git リポジトリ内で実行
cd your-project
ai-multi-review
```

インストーラーがインストール済みCLIを自動検出し、`config.json` を生成します。

### 使い方

```bash
ai-multi-review                        # main との差分をレビュー
ai-multi-review develop                # develop との差分をレビュー
ai-multi-review --reviewers claude     # Claude のみ
ai-multi-review --no-block             # blocking でも exit 0
ai-multi-review --output report.md     # 出力先を指定
```

#### diff検出（自動優先順位）

1. **コミット差分** (`BASE...HEAD`) — ベースブランチからのコミット済み変更
2. **ステージ済み変更** (`git add`) — コミット差分がない場合
3. **未ステージ変更** — ステージ済みもない場合

### 設定

`~/.config/ai-multi-review/config.json` を編集:

```json
{
  "reviewers": {
    "coderabbit": { "enabled": true, "timeout": 180 },
    "claude": { "enabled": true, "timeout": 300, "model": "sonnet", "max_budget_usd": 0.50 },
    "codex": { "enabled": true, "timeout": 300 },
    "gemini": { "enabled": false, "timeout": 300 }
  },
  "defaults": { "base_ref": "main" },
  "merge": { "dedup_line_range": 5 },
  "report": { "keep_history": 10 }
}
```

| 設定 | 説明 |
|------|------|
| `enabled` | `false` でそのレビュアーをスキップ |
| `timeout` | レビュアーごとのタイムアウト（秒） |
| `model` | Claude のモデル（`sonnet` / `haiku` / `opus`） |
| `max_budget_usd` | Claude の1回あたりコスト上限 |
| `base_ref` | デフォルトの比較ブランチ |
| `dedup_line_range` | 重複判定の行範囲トレランス（±N行） |
| `keep_history` | プロジェクトごとに保持するレポート数 |

### エディタ連携

#### Claude Code

```
/ai-multi-review              # レビュー実行
/fix-review latest             # 最新レポートの指摘を修正
```

#### Codex CLI

```bash
codex exec "$(cat ~/.codex/instructions/fix-review.md) $(cat path/to/issues.json)"
```

---

## License

MIT
