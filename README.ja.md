# ai-multi-review

[![Version](https://img.shields.io/badge/version-v0.1.0-blue)](https://github.com/3062-in-zamud/ai-multi-review/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

🇬🇧 [English README](README.md)

PR作成前に複数のLLM CLIを並列実行してコードレビューを行い、結果を重複除去した統合レポートとして出力するツールです。

<!-- TODO: asciinema デモ -->

## 機能

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

## 対応レビュアー

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

## 必要環境

- bash 4.0+, git, jq, python3
- 以下のうち少なくとも1つのレビュアーCLIがインストール済みであること:
  - [Claude Code](https://claude.ai/code) (`claude`)
  - [OpenAI Codex CLI](https://github.com/openai/codex) (`codex`)
  - [CodeRabbit CLI](https://coderabbit.ai/) (`coderabbit`) — OSSは無料
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`)

## クイックスタート

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

## 使い方

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

## プロジェクト固有ルール

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

## コンテキスト注入

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

## 出力例

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

## レビュー品質

### 複数LLMの利点

複数のLLMレビュアーを実行することで、単一レビュアーの見落としを補完:
- **Claude**: セキュリティ分析と複雑なロジックレビューに強い
- **Codex**: ランタイムエラーとエッジケースの検出に強い
- **CodeRabbit**: コードスタイルとベストプラクティスに特化
- **Gemini**: カテゴリ横断で広範なカバレッジ

複数レビュアーが検出した問題（`high_confidence`）は、統計的に真陽性の確率が高くなります。

### confidence スコア

各 issue に `confidence`（high/medium/low）が付与されます:
- **high**: コードの動作から論理的に証明可能
- **medium**: 文脈やパターンから高確率で推定
- **low**: 追加調査が必要な可能性レベル

複数レビュアーが合意した場合、confidence は自動的に1段階上昇します。

### 推奨ワークフロー

1. **blocking + high confidence** → マージ前に必ず修正
2. **blocking + low confidence** → 手動確認（実際の問題である可能性が高い）
3. **advisory + high confidence** → 時間があれば修正
4. **advisory + low confidence** → 参考情報として扱う

### 品質評価

`ai-multi-review-eval` でレビュー品質を定量測定:

```bash
# レビュー結果から判定テンプレートを生成
ai-multi-review-eval --generate-template issues.json -o verdict.json

# 各 issue の true_positive を true/false で記入後、評価実行
ai-multi-review-eval issues.json verdict.json
```

Precision、False Positive Rate、レビュアー別精度、複数レビュアー合意率が出力されます。

## コスト

| レビュアー | 課金体系 | 1回あたりの目安コスト |
|-----------|---------|---------------------|
| Claude Code | API従量課金 または Max/Proサブスクリプション | $0.01〜0.50（モデル依存） |
| Codex CLI | ChatGPT Pro/Plusサブスクリプション（含む）または APIキー従量課金 | サブスク内なら無料、APIキーなら $0.01〜0.30 |
| CodeRabbit | OSS無料、プライベートリポは有料プラン | OSS: 無料 |
| Gemini CLI | Google AI Studio 無料枠 または APIキー | 無料枠あり |

**Codex CLI のコツ:** `codex login` でChatGPTサブスクリプション認証を使用すると、APIキーの従量課金を回避できます。インストーラーはAPIキー認証を検出すると警告を表示します。

## 設定

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

## アーキテクチャ

```
bin/
├── ai-multi-review          # メインエントリポイント
└── ai-multi-review-eval     # レビュー品質評価（Python）
lib/
├── common.sh                # Git操作、設定、タイムアウト、プロンプト構築
├── merge.sh                 # レビュアー間重複除去 + confidence マージ
├── report.sh                # ターミナル + Markdown レポート生成
└── review-schema.json       # JSON出力スキーマ（confidence付き）
prompts/
├── review-system.md         # システムプロンプト（10のレビュー基準）
└── review-user.md           # ユーザープロンプト（出力スキーマ）
reviewers/
├── claude.sh                # Claude Code アダプタ
├── codex.sh                 # OpenAI Codex アダプタ
├── coderabbit.sh            # CodeRabbit アダプタ
├── gemini.sh                # Gemini CLI アダプタ
├── aider.sh                 # Aider アダプタ（スケルトン）
├── opencode.sh              # OpenCode アダプタ（スケルトン）
└── gh-copilot.sh            # GitHub Copilot アダプタ（スケルトン）
examples/
├── sample-report.md         # レポート出力例
├── sample-issues.json       # Issues JSON 出力例
└── human-verdict-template.json  # 評価判定テンプレート
```

## エディタ連携

### Claude Code

```
/ai-multi-review              # レビュー実行
/fix-review latest             # 最新レポートの指摘を修正
```

### Codex CLI

```bash
codex exec "$(cat ~/.codex/instructions/fix-review.md) $(cat path/to/issues.json)"
```

## コントリビューション

新しいレビュアーの追加やコード貢献の方法は [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

## ライセンス

MIT
