#!/usr/bin/env bash
# shellcheck disable=SC2059,SC2088
set -euo pipefail

# install.sh — AI Multi Review セットアップスクリプト
# Usage: git clone <repo> ~/workspaces/ai-multi-review && bash ~/workspaces/ai-multi-review/install.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_NAME="ai-multi-review"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/${TOOL_NAME}"
REPO_URL="https://github.com/3062-in-zamud/ai-multi-review"
INSTALL_DIR="${INSTALL_DIR:-$HOME/workspaces/ai-multi-review}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

log_ok()   { printf "${GREEN}[✓]${RESET} %s\n" "$*"; }
log_warn() { printf "${YELLOW}[!]${RESET} %s\n" "$*"; }
log_info() { printf "${CYAN}[i]${RESET} %s\n" "$*"; }
log_err()  { printf "${RED}[✗]${RESET} %s\n" "$*"; }

echo ""
printf "${BOLD}━━━ AI Multi Review — Setup ━━━${RESET}\n\n"

# ━━━ ワンライナーモード検出とオートクローン ━━━
# stdin が TTY でない = curl | bash 経由
if [ ! -t 0 ]; then
  if [ -d "$CONFIG_DIR" ]; then
    log_info "アップグレードモード: git pull を実行します"
    git -C "$CONFIG_DIR" pull --ff-only
    SCRIPT_DIR="$CONFIG_DIR"
  else
    log_info "リポジトリをクローンします → $INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
    ln -sf "$INSTALL_DIR" "$CONFIG_DIR"
    SCRIPT_DIR="$INSTALL_DIR"
  fi
  echo ""
fi

# ━━━ portable sed -i ━━━
sed_inplace() {
  if [ "$(uname -s)" = "Darwin" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# ━━━ Phase 1: 必須ツール確認 ━━━
echo "Phase 1: 必須ツール確認"
echo ""

check_dependency() {
  local cmd="$1"
  if ! command -v "$cmd" &>/dev/null; then
    log_err "$cmd が見つかりません"
    case "$(uname -s)" in
      Darwin) echo "  → brew install $cmd" ;;
      Linux)  echo "  → sudo apt-get install $cmd  (Debian/Ubuntu)" ;;
    esac
    return 1
  fi
  log_ok "$cmd"
  return 0
}

MISSING_REQUIRED=0

for tool in jq git python3; do
  check_dependency "$tool" || MISSING_REQUIRED=1
done

if (( MISSING_REQUIRED )); then
  echo ""
  log_err "必須ツールが不足しています。インストールしてから再実行してください。"
  exit 1
fi

# ━━━ Phase 2: レビュアーCLI検出 ━━━
echo ""
echo "Phase 2: レビュアーCLI検出"
echo ""

# レビュアー定義: name|cli_command|install_hint|default_enabled
REVIEWERS=(
  "coderabbit|coderabbit|curl -fsSL https://cli.coderabbit.ai/install.sh \| sh|true"
  "claude|claude|npm i -g @anthropic-ai/claude-code|true"
  "codex|codex|npm i -g @openai/codex|true"
  "gemini|gemini|npm i -g @google/gemini-cli|false"
  "aider|aider|pip install aider-chat|false"
  "opencode|opencode|go install github.com/opencode-ai/opencode@latest|false"
  "gh-copilot|gh copilot|gh extension install github/gh-copilot|false"
)

printf "  ${BOLD}%-14s %-10s %-12s %s${RESET}\n" "Reviewer" "Status" "Default" "Install"
printf "  %-14s %-10s %-12s %s\n" "──────────" "────────" "──────────" "───────"

DETECTED_REVIEWERS=()

for entry in "${REVIEWERS[@]}"; do
  IFS='|' read -r name cli install_hint default_enabled <<< "$entry"

  # gh copilot は特殊: "gh copilot" としてチェック
  if [[ "$cli" == "gh copilot" ]]; then
    if command -v gh >/dev/null 2>&1 && gh copilot --help >/dev/null 2>&1; then
      status="${GREEN}found${RESET}"
      DETECTED_REVIEWERS+=("$name")
    else
      status="${DIM}not found${RESET}"
    fi
  else
    if command -v "$cli" >/dev/null 2>&1; then
      status="${GREEN}found${RESET}"
      DETECTED_REVIEWERS+=("$name")
    else
      status="${DIM}not found${RESET}"
    fi
  fi

  if [[ "$default_enabled" == "true" ]]; then
    default_label="enabled"
  else
    default_label="optional"
  fi

  printf "  %-14s %b  %-12s %s\n" "$name" "$status" "$default_label" "$install_hint"
done

# Codex 認証方式チェック
if command -v codex >/dev/null 2>&1; then
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    echo ""
    log_warn "Codex CLI が APIキー認証で設定されています（従量課金）"
    log_warn "ChatGPT Pro/Plus サブスクリプション内で利用するには:"
    echo "  codex login"
    echo "  （その後 OPENAI_API_KEY 環境変数を unset してください）"
  elif [[ -f "$HOME/.codex/auth.json" ]] && grep -q "api_key" "$HOME/.codex/auth.json" 2>/dev/null; then
    echo ""
    log_warn "Codex CLI が APIキー認証で設定されています（従量課金の可能性）"
    log_warn "ChatGPT Pro/Plus サブスクリプション内で利用するには:"
    echo "  codex login"
  fi
fi

echo ""
if (( ${#DETECTED_REVIEWERS[@]} == 0 )); then
  log_err "レビュアーCLIが1つも見つかりません。少なくとも1つをインストールしてください。"
fi
log_info "${#DETECTED_REVIEWERS[@]}/${#REVIEWERS[@]} レビュアーが利用可能"

# 対話的インストール提案（対話型端末のみ）
if [[ -t 0 ]]; then
  NOT_INSTALLED=()
  for entry in "${REVIEWERS[@]}"; do
    IFS='|' read -r name cli install_cmd default_enabled <<< "$entry"
    already_detected=false
    for detected in "${DETECTED_REVIEWERS[@]}"; do
      if [[ "$detected" == "$name" ]]; then
        already_detected=true
        break
      fi
    done
    if ! $already_detected; then
      NOT_INSTALLED+=("$entry")
    fi
  done

  if (( ${#NOT_INSTALLED[@]} > 0 )); then
    echo ""
    log_info "未インストールのレビュアーCLIがあります。インストールしますか？"
    echo ""
    for entry in "${NOT_INSTALLED[@]}"; do
      IFS='|' read -r name cli install_cmd default_enabled <<< "$entry"
      printf "  ${BOLD}%s${RESET}: %s\n" "$name" "$install_cmd"
      read -p "  Install ${name}? (y/N) " -r answer </dev/tty
      if [[ "$answer" =~ ^[Yy]$ ]]; then
        log_info "インストール中: ${name}"
        # パイプを含むコマンド用の特別処理
        case "$install_cmd" in
          *'| sh'*)
            # curl | sh パターン: URL を表示してから実行
            local_url=$(echo "$install_cmd" | grep -oE 'https?://[^ |]+')
            log_info "ダウンロード先: ${local_url}"
            if bash -c "$install_cmd" 2>&1; then
              log_ok "${name} をインストールしました"
              DETECTED_REVIEWERS+=("$name")
            else
              log_warn "${name} のインストールに失敗しました"
            fi
            ;;
          *)
            log_info "実行: ${install_cmd}"
            if bash -c "$install_cmd" 2>&1; then
              log_ok "${name} をインストールしました"
              DETECTED_REVIEWERS+=("$name")
            else
              log_warn "${name} のインストールに失敗しました"
            fi
            ;;
        esac
      fi
    done
    echo ""
    log_info "最終検出: ${#DETECTED_REVIEWERS[@]}/${#REVIEWERS[@]} レビュアーが利用可能"
  fi
fi

if (( ${#DETECTED_REVIEWERS[@]} == 0 )); then
  log_err "レビュアーCLIが1つも見つかりません。少なくとも1つをインストールしてください。"
  exit 1
fi

# ━━━ Phase 3: ~/.config symlink 設定 ━━━
echo ""
echo "Phase 3: config symlink 設定"
echo ""

if [[ -L "$CONFIG_DIR" ]]; then
  current_target=$(readlink "$CONFIG_DIR")
  if [[ "$current_target" == "$SCRIPT_DIR" ]]; then
    log_ok "symlink 既存: ${CONFIG_DIR} → ${SCRIPT_DIR}"
  else
    ln -sf "$SCRIPT_DIR" "$CONFIG_DIR"
    log_ok "symlink 更新: ${CONFIG_DIR} → ${SCRIPT_DIR}"
  fi
elif [[ -d "$CONFIG_DIR" ]]; then
  log_warn "${CONFIG_DIR} がディレクトリとして存在します。手動でsymlinkに変換してください:"
  echo "  rm -rf ${CONFIG_DIR} && ln -sf ${SCRIPT_DIR} ${CONFIG_DIR}"
else
  ln -sf "$SCRIPT_DIR" "$CONFIG_DIR"
  log_ok "symlink 作成: ${CONFIG_DIR} → ${SCRIPT_DIR}"
fi

# ━━━ Phase 4: ~/bin symlink + PATH 確認 ━━━
echo ""
echo "Phase 4: コマンドsymlink + PATH"
echo ""

BIN_DIR="$HOME/bin"
mkdir -p "$BIN_DIR"

# メインコマンド、短縮エイリアス、eval コマンドの symlink
for cmd_name in "${TOOL_NAME}" "${TOOL_NAME}-eval"; do
  local_symlink="${BIN_DIR}/${cmd_name}"
  local_target="${CONFIG_DIR}/bin/${cmd_name}"

  if [[ -L "$local_symlink" ]]; then
    if [[ "$(readlink "$local_symlink")" == "$local_target" ]]; then
      log_ok "symlink 既存: ${local_symlink}"
    else
      ln -sf "$local_target" "$local_symlink"
      log_ok "symlink 更新: ${local_symlink}"
    fi
  elif [[ -e "$local_symlink" ]]; then
    log_warn "${local_symlink} がファイルとして存在します。手動で確認してください。"
  else
    ln -s "$local_target" "$local_symlink"
    log_ok "symlink 作成: ${local_symlink}"
  fi
done

# amr 短縮エイリアス → ai-multi-review
local_amr="${BIN_DIR}/amr"
local_amr_target="${CONFIG_DIR}/bin/${TOOL_NAME}"
if [[ -L "$local_amr" ]]; then
  if [[ "$(readlink "$local_amr")" == "$local_amr_target" ]]; then
    log_ok "symlink 既存: ${local_amr} (短縮エイリアス)"
  else
    ln -sf "$local_amr_target" "$local_amr"
    log_ok "symlink 更新: ${local_amr} (短縮エイリアス)"
  fi
elif [[ -e "$local_amr" ]]; then
  log_warn "${local_amr} が既に存在します。amr エイリアスをスキップします。"
else
  ln -s "$local_amr_target" "$local_amr"
  log_ok "symlink 作成: ${local_amr} → ai-multi-review (短縮エイリアス)"
fi

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  log_warn "~/bin が PATH に含まれていません。以下を .zshrc / .bashrc に追加してください:"
  echo "  export PATH=\"\$HOME/bin:\$PATH\""
fi

# ━━━ Phase 5: config.json 生成 ━━━
echo ""
echo "Phase 5: config.json"
echo ""

CONFIG_FILE="${CONFIG_DIR}/config.json"

if [[ -f "$CONFIG_FILE" ]]; then
  log_ok "config.json 既存（既存設定を保持）"
  # 検出したが未登録のレビュアーを追加
  for name in "${DETECTED_REVIEWERS[@]}"; do
    if ! jq -e ".reviewers.\"${name}\"" "$CONFIG_FILE" >/dev/null 2>&1; then
      local_tmp=$(mktemp)
      jq --arg n "$name" '.reviewers[$n] = {"enabled": true, "timeout": 300}' "$CONFIG_FILE" > "$local_tmp" \
        && mv "$local_tmp" "$CONFIG_FILE"
      log_info "  ${name} を config.json に追加"
    fi
  done
else
  # 新規生成: 検出されたCLIのみenabled
  local_reviewers="{}"
  for entry in "${REVIEWERS[@]}"; do
    IFS='|' read -r name cli _ _ <<< "$entry"
    local_enabled="false"
    for detected in "${DETECTED_REVIEWERS[@]}"; do
      if [[ "$detected" == "$name" ]]; then
        local_enabled="true"
        break
      fi
    done

    # claude の追加設定
    if [[ "$name" == "claude" ]]; then
      local_reviewers=$(echo "$local_reviewers" | jq \
        --arg n "$name" --argjson e "$local_enabled" \
        '.[$n] = {"enabled": $e, "timeout": 300, "model": "sonnet", "max_budget_usd": 0.50}')
    elif [[ "$name" == "coderabbit" ]]; then
      local_reviewers=$(echo "$local_reviewers" | jq \
        --arg n "$name" --argjson e "$local_enabled" \
        '.[$n] = {"enabled": $e, "timeout": 180}')
    else
      local_reviewers=$(echo "$local_reviewers" | jq \
        --arg n "$name" --argjson e "$local_enabled" \
        '.[$n] = {"enabled": $e, "timeout": 300}')
    fi
  done

  jq -n --argjson reviewers "$local_reviewers" '{
    reviewers: $reviewers,
    defaults: { base_ref: "main" },
    merge: { dedup_line_range: 5 },
    report: { keep_history: 10, naming: "{project}_{branch}_{YYYYMMDD}_{HHmmss}", group_by: "project" }
  }' > "$CONFIG_FILE"
  log_ok "config.json を生成（検出済みCLIのみ enabled）"
fi

# ━━━ Phase 6: 実行権限 ━━━
echo ""
echo "Phase 6: 実行権限"
echo ""

chmod +x "${CONFIG_DIR}/bin/${TOOL_NAME}" 2>/dev/null && log_ok "bin/${TOOL_NAME}"
chmod +x "${CONFIG_DIR}/bin/${TOOL_NAME}-eval" 2>/dev/null && log_ok "bin/${TOOL_NAME}-eval"
for f in "${CONFIG_DIR}"/reviewers/*.sh; do
  [[ -f "$f" ]] && chmod +x "$f"
done
log_ok "reviewers/*.sh"

# ━━━ Phase 7: Claude Code / Codex コマンドテンプレート（オプション） ━━━
echo ""
echo "Phase 7: エディタ統合（オプション）"
echo ""

CLAUDE_CMD_DIR="$HOME/.claude/commands"
if [[ -d "$HOME/.claude" ]]; then
  mkdir -p "$CLAUDE_CMD_DIR"
  if [[ -f "${CLAUDE_CMD_DIR}/${TOOL_NAME}.md" ]]; then
    log_ok "Claude Code: ${TOOL_NAME}.md 既存"
  else
    cat > "${CLAUDE_CMD_DIR}/${TOOL_NAME}.md" << 'CMDEOF'
AI Multi Review を実行し、結果を報告してください。

## 手順

1. 以下のコマンドを Bash で実行:
   ```
   ~/.config/ai-multi-review/bin/ai-multi-review $ARGUMENTS
   ```

2. 実行結果（exit code とターミナル出力）を確認

3. レポートファイルが生成された場合、Read で内容を確認

4. blocking issues がある場合:
   - 各 issue の概要を簡潔に報告
   - `/fix-review latest` での修正を提案

5. blocking issues がない場合:
   - 「レビュー通過」と報告
   - advisory issues があれば簡潔にリスト表示

## 引数の例
- (引数なし): main との差分をレビュー
- `develop`: develop との差分
- `--reviewers claude,codex`: 特定レビュアーのみ
- `--no-block`: blocking判定なし
CMDEOF
    log_ok "Claude Code: ${TOOL_NAME}.md を生成"
  fi

  if [[ -f "${CLAUDE_CMD_DIR}/fix-review.md" ]]; then
    log_ok "Claude Code: fix-review.md 既存"
  else
    cat > "${CLAUDE_CMD_DIR}/fix-review.md" << 'CMDEOF'
引数 $ARGUMENTS で指定されたレビューレポートに基づき issues を修正してください。

## 引数の解決

- `latest` → 現プロジェクトの `~/.config/ai-multi-review/reports/{project}/latest.issues.json` を使用
  - `{project}` は `basename $(git rev-parse --show-toplevel)` で導出
- `.md` パス → 同名の `.issues.json` を自動探索して構造化データを利用
- `.issues.json` パス → 直接利用
- 引数なし → `latest` と同じ扱い

## フロー

1. レポート（.md）と issues JSON（.issues.json）を Read で読み込む
2. issues JSON から blocking → advisory の優先順で処理
3. 各 issue について:
   a. 該当ファイルの該当行を Read で確認
   b. recommendation に従い最小差分で Edit で修正
   c. 修正内容を簡潔に報告
4. 全 blocking issues 修正後、advisory issues も同様に修正
5. 修正サマリーを表示し、`ai-multi-review` 再実行を提案

## ルール

- recommendation に忠実に修正する（追加の改善は行わない）
- 修正箇所以外のコードは変更しない
- テストファイルが存在すればテスト実行で検証
- 修正に自信がない場合はユーザーに確認する
- 1つの issue を修正するごとに進捗を報告する
CMDEOF
    log_ok "Claude Code: fix-review.md を生成"
  fi
else
  log_info "Claude Code 未検出（~/.claude/ なし）— スキップ"
fi

# Codex instructions
CODEX_DIR="$HOME/.codex/instructions"
if [[ -d "$HOME/.codex" ]]; then
  mkdir -p "$CODEX_DIR"
  if [[ -f "${CODEX_DIR}/fix-review.md" ]]; then
    log_ok "Codex: fix-review.md 既存"
  else
    cat > "${CODEX_DIR}/fix-review.md" << 'CMDEOF'
以下のレビューレポートに記載された issues を修正してください。

## ルール
1. Blocking Issues を優先して修正
2. recommendation に従い最小差分で修正
3. 修正箇所以外のコードは変更しない
4. 各修正後に該当ファイルのテストを実行
5. 修正完了後、修正サマリーをJSON出力

出力スキーマ:
{
  "fixed": [{ "id": "B-1", "file": "...", "description": "修正内容" }],
  "skipped": [{ "id": "A-2", "reason": "理由" }]
}

レポート:
CMDEOF
    log_ok "Codex: fix-review.md を生成"
  fi
else
  log_info "Codex CLI 未検出（~/.codex/ なし）— スキップ"
fi

# ━━━ Phase 8: ディレクトリ作成 ━━━
mkdir -p "${CONFIG_DIR}/logs" "${CONFIG_DIR}/reports"

# ━━━ 完了サマリー ━━━
echo ""
printf "${BOLD}━━━ セットアップ完了 ━━━${RESET}\n\n"

echo "検出済みレビュアー:"
for name in "${DETECTED_REVIEWERS[@]}"; do
  printf "  ${GREEN}✓${RESET} %s\n" "$name"
done

echo ""
echo "使い方:"
echo "  amr                               # ai-multi-review の短縮コマンド"
echo "  amr --help                        # ヘルプ表示"
echo "  amr --reviewers claude            # 特定レビュアーのみ"
echo ""
echo "Claude Code から:"
echo "  /${TOOL_NAME}                     # レビュー実行"
echo "  /fix-review latest                # 最新レポートの修正"
echo ""
