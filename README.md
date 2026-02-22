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
- Unified Markdown report with blocking/advisory severity + confidence scoring
- JSON issues output for automated fix workflows
- Project-specific review rules (`.ai-multi-review/rules.md`)
- PR/ticket context injection (`--context`, `--context-file`)
- Prompt debugging with `--dry-run`
- Review quality evaluation (`ai-multi-review-eval`)
- Configurable timeouts, models, and budget limits per reviewer
- Interactive installer with auto-detection and optional CLI installation

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

The installer auto-detects installed CLIs, offers to install missing ones, and generates `config.json` accordingly.

### Usage

```bash
ai-multi-review                           # Review diff against main
ai-multi-review develop                   # Review diff against develop
ai-multi-review --reviewers claude        # Claude only
ai-multi-review --no-block                # Don't exit 1 on blocking issues
ai-multi-review --output report.md        # Custom output path
ai-multi-review --context "Fixes #42"     # Add PR context
ai-multi-review --context-file pr.md      # Context from file
ai-multi-review --dry-run                 # Show prompts without running LLMs
```

#### Diff Detection (automatic priority)

1. **Commit diff** (`BASE...HEAD`) — committed changes since base branch
2. **Staged changes** (`git add`) — if no commit diff
3. **Unstaged changes** — if nothing staged

### Project-Specific Rules

Create `.ai-multi-review/rules.md` in your repository to inject project-specific review rules:

```markdown
## Project Rules
- All API endpoints must validate input with zod schemas
- Database queries must use transactions for multi-table writes
- React components must not exceed 200 lines
```

Rules are automatically prepended to the system prompt for claude, codex, and gemini reviewers.

**Priority order:**
1. `.ai-multi-review/rules.md` (in repository — highest priority)
2. `~/.config/ai-multi-review/rules/{project-name}/rules.md` (user-local)
3. Default system prompt (always included)

**CodeRabbit note:** CodeRabbit uses its own prompt architecture. Configure rules via `.coderabbit.yaml` in your repository ([CodeRabbit docs](https://docs.coderabbit.ai/)).

### Context Injection

Provide change context (PR description, ticket info) to help reviewers understand intent:

```bash
# CLI argument
ai-multi-review --context "Fixes #42: Add rate limiting to API endpoints"

# From file
ai-multi-review --context-file .github/pull_request_template.md

# Auto-detected from .ai-multi-review/context.md
echo "This PR adds authentication middleware" > .ai-multi-review/context.md
ai-multi-review

# Git metadata (commit diff mode only)
# Automatically extracts "Fixes #", "Closes #", "Refs #" from commit messages
```

### Output Example

Terminal output:

```
━━━ AI Multi Review ━━━━━━━━━━━━━━━━━━
Repo: myapp | Branch: feature-auth → main
Files: 8 | Lines: +245/-32

  claude       ✅ 2 blocking, 1 advisory
  codex        ✅ 1 blocking, 2 advisory
  coderabbit   ✅ 0 blocking, 2 advisory

Verdict: ⚠️  2 blocking issue(s) (deduplicated)
Report: ~/.config/ai-multi-review/reports/myapp/myapp_feature-auth_20260220_143052.md
Issues: ~/.config/ai-multi-review/reports/myapp/myapp_feature-auth_20260220_143052.issues.json

Fix(Claude): /fix-review latest
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

See [`examples/sample-report.md`](examples/sample-report.md) and [`examples/sample-issues.json`](examples/sample-issues.json) for full output examples.

### Review Quality

#### Multi-LLM Advantage

Running multiple LLM reviewers catches issues that any single reviewer might miss:
- **Claude** excels at security analysis and complex logic review
- **Codex** is strong at identifying runtime errors and edge cases
- **CodeRabbit** focuses on code style and best practices
- **Gemini** provides broad coverage across categories

Issues detected by multiple reviewers (`high_confidence`) are statistically more likely to be true positives.

#### Confidence Scoring

Each issue includes a `confidence` level (high/medium/low) indicating how certain the reviewer is:
- **high**: Logically provable from the code
- **medium**: Strong evidence from context and patterns
- **low**: Possible issue requiring further investigation

When multiple reviewers agree, confidence is automatically elevated.

#### Recommended Workflow

1. **blocking + high confidence** → Fix immediately before merge
2. **blocking + low confidence** → Review manually, likely real issues
3. **advisory + high confidence** → Fix if time permits
4. **advisory + low confidence** → Treat as suggestions

#### Quality Evaluation

Measure your review quality over time with `ai-multi-review-eval`:

```bash
# Generate verdict template from a review
ai-multi-review-eval --generate-template issues.json -o verdict.json

# Fill in true_positive: true/false for each issue, then evaluate
ai-multi-review-eval issues.json verdict.json
```

Output includes Precision, False Positive Rate, per-reviewer accuracy, and multi-reviewer consensus rate.

### Cost

| Reviewer | Pricing Model | Typical Cost per Review |
|----------|---------------|------------------------|
| Claude Code | API usage (per-token) or Max/Pro subscription | $0.01–0.50 (model-dependent) |
| Codex CLI | ChatGPT Pro/Plus subscription (included) or API key (per-token) | Free with subscription, or $0.01–0.30 |
| CodeRabbit | Free for open source, paid plans for private repos | Free–$0.00 (open source) |
| Gemini CLI | Google AI Studio free tier or API key | Free tier available |

**Codex CLI tip:** Use `codex login` to authenticate with your ChatGPT subscription instead of an API key to avoid per-token charges. The installer will warn you if API key authentication is detected.

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
bin/
├── ai-multi-review          # Main entry point
└── ai-multi-review-eval     # Review quality evaluation (Python)
lib/
├── common.sh                # Git operations, config, timeout, prompt building
├── merge.sh                 # Cross-reviewer deduplication + confidence merge
├── report.sh                # Terminal + Markdown report generation
└── review-schema.json       # JSON output schema (with confidence)
prompts/
├── review-system.md         # System prompt (10 review criteria)
└── review-user.md           # User prompt (output schema)
reviewers/
├── claude.sh                # Claude Code adapter
├── codex.sh                 # OpenAI Codex adapter
├── coderabbit.sh            # CodeRabbit adapter
├── gemini.sh                # Gemini CLI adapter
├── aider.sh                 # Aider adapter (skeleton)
├── opencode.sh              # OpenCode adapter (skeleton)
└── gh-copilot.sh            # GitHub Copilot adapter (skeleton)
examples/
├── sample-report.md         # Full report example
├── sample-issues.json       # Issues JSON example
└── human-verdict-template.json  # Eval verdict template
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
- blocking/advisory の重要度 + confidence スコア付き統合Markdownレポート
- 自動修正ワークフロー用のJSON issues出力
- プロジェクト固有レビュールール（`.ai-multi-review/rules.md`）
- PR/チケット情報のコンテキスト注入（`--context`, `--context-file`）
- プロンプトデバッグ用 `--dry-run`
- レビュー品質評価ツール（`ai-multi-review-eval`）
- レビュアーごとのタイムアウト・モデル・予算上限設定
- CLI自動検出 + 対話的インストール提案付きインストーラー

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

インストーラーがインストール済みCLIを自動検出し、未インストールのCLIのインストールを提案、`config.json` を生成します。

### 使い方

```bash
ai-multi-review                           # main との差分をレビュー
ai-multi-review develop                   # develop との差分をレビュー
ai-multi-review --reviewers claude        # Claude のみ
ai-multi-review --no-block                # blocking でも exit 0
ai-multi-review --output report.md        # 出力先を指定
ai-multi-review --context "Fixes #42"     # PRコンテキスト付き
ai-multi-review --context-file pr.md      # ファイルからコンテキスト
ai-multi-review --dry-run                 # プロンプト確認（LLM実行なし）
```

#### diff検出（自動優先順位）

1. **コミット差分** (`BASE...HEAD`) — ベースブランチからのコミット済み変更
2. **ステージ済み変更** (`git add`) — コミット差分がない場合
3. **未ステージ変更** — ステージ済みもない場合

### プロジェクト固有ルール

リポジトリに `.ai-multi-review/rules.md` を作成すると、プロジェクト固有のレビュールールがプロンプトに自動注入されます:

```markdown
## プロジェクトルール
- 全APIエンドポイントで zod による入力バリデーション必須
- 複数テーブルへの書き込みはトランザクション必須
- Reactコンポーネントは200行以内
```

**優先順位:**
1. `.ai-multi-review/rules.md`（リポジトリ内・最優先）
2. `~/.config/ai-multi-review/rules/{project-name}/rules.md`（ユーザーローカル）
3. デフォルトシステムプロンプト（常に含まれる）

**CodeRabbit:** CodeRabbit は独自のプロンプト体系を使用するため、`.coderabbit.yaml` でルールを設定してください（[CodeRabbit docs](https://docs.coderabbit.ai/)）。

### コンテキスト注入

変更の意図（PR説明、チケット情報）をレビュアーに伝達:

```bash
# CLI引数
ai-multi-review --context "Fixes #42: APIエンドポイントにレート制限を追加"

# ファイルから
ai-multi-review --context-file .github/pull_request_template.md

# .ai-multi-review/context.md から自動読み込み
echo "認証ミドルウェアを追加するPR" > .ai-multi-review/context.md
ai-multi-review

# git metadata（コミット差分モードのみ）
# コミットメッセージから "Fixes #", "Closes #", "Refs #" を自動抽出
```

### 出力例

ターミナル出力:

```
━━━ AI Multi Review ━━━━━━━━━━━━━━━━━━
Repo: myapp | Branch: feature-auth → main
Files: 8 | Lines: +245/-32

  claude       ✅ 2 blocking, 1 advisory
  codex        ✅ 1 blocking, 2 advisory
  coderabbit   ✅ 0 blocking, 2 advisory

Verdict: ⚠️  2 blocking issue(s) (deduplicated)
Report: ~/.config/ai-multi-review/reports/myapp/myapp_feature-auth_20260220_143052.md
Issues: ~/.config/ai-multi-review/reports/myapp/myapp_feature-auth_20260220_143052.issues.json

Fix(Claude): /fix-review latest
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

詳細な出力例は [`examples/sample-report.md`](examples/sample-report.md)、[`examples/sample-issues.json`](examples/sample-issues.json) を参照。

### レビュー品質

#### 複数LLMの利点

複数のLLMレビュアーを実行することで、単一レビュアーの見落としを補完:
- **Claude**: セキュリティ分析と複雑なロジックレビューに強い
- **Codex**: ランタイムエラーとエッジケースの検出に強い
- **CodeRabbit**: コードスタイルとベストプラクティスに特化
- **Gemini**: カテゴリ横断で広範なカバレッジ

複数レビュアーが検出した問題（`high_confidence`）は、統計的に真陽性の確率が高くなります。

#### confidence スコア

各 issue に `confidence`（high/medium/low）が付与されます:
- **high**: コードの動作から論理的に証明可能
- **medium**: 文脈やパターンから高確率で推定
- **low**: 追加調査が必要な可能性レベル

複数レビュアーが合意した場合、confidence は自動的に1段階上昇します。

#### 推奨ワークフロー

1. **blocking + high confidence** → マージ前に必ず修正
2. **blocking + low confidence** → 手動確認（実際の問題である可能性が高い）
3. **advisory + high confidence** → 時間があれば修正
4. **advisory + low confidence** → 参考情報として扱う

#### 品質評価

`ai-multi-review-eval` でレビュー品質を定量測定:

```bash
# レビュー結果から判定テンプレートを生成
ai-multi-review-eval --generate-template issues.json -o verdict.json

# 各 issue の true_positive を true/false で記入後、評価実行
ai-multi-review-eval issues.json verdict.json
```

Precision、False Positive Rate、レビュアー別精度、複数レビュアー合意率が出力されます。

### コスト

| レビュアー | 課金体系 | 1回あたりの目安コスト |
|-----------|---------|---------------------|
| Claude Code | API従量課金 または Max/Proサブスクリプション | $0.01〜0.50（モデル依存） |
| Codex CLI | ChatGPT Pro/Plusサブスクリプション（含む）または APIキー従量課金 | サブスク内なら無料、APIキーなら $0.01〜0.30 |
| CodeRabbit | OSS無料、プライベートリポは有料プラン | OSS: 無料 |
| Gemini CLI | Google AI Studio 無料枠 または APIキー | 無料枠あり |

**Codex CLI のコツ:** `codex login` でChatGPTサブスクリプション認証を使用すると、APIキーの従量課金を回避できます。インストーラーはAPIキー認証を検出すると警告を表示します。

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
