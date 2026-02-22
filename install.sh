#!/usr/bin/env bash
set -euo pipefail

# install.sh — Triple Review System セットアップスクリプト
# Usage: bash ~/.config/triple-review/install.sh

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/triple-review"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log_ok()   { printf "${GREEN}[✓]${RESET} %s\n" "$*"; }
log_warn() { printf "${YELLOW}[!]${RESET} %s\n" "$*"; }
log_info() { printf "${CYAN}[i]${RESET} %s\n" "$*"; }
log_err()  { printf "${RED}[✗]${RESET} %s\n" "$*"; }

echo ""
printf "${BOLD}━━━ Triple Review System — Setup ━━━${RESET}\n\n"

# ━━━ 1. 必須コマンド確認 ━━━
echo "📋 必須ツール確認..."

if ! command -v jq >/dev/null 2>&1; then
  log_err "jq が必要です: brew install jq"
  exit 1
fi
log_ok "jq"

if ! command -v git >/dev/null 2>&1; then
  log_err "git が必要です"
  exit 1
fi
log_ok "git"

if ! command -v python3 >/dev/null 2>&1; then
  log_err "python3 が必要です（JSON抽出に使用）"
  exit 1
fi
log_ok "python3"

# ━━━ 2. レビュアーCLI確認 ━━━
echo ""
echo "📋 レビュアーCLI確認..."

AVAILABLE=0

if command -v claude >/dev/null 2>&1; then
  log_ok "claude CLI $(claude --version 2>/dev/null || echo '(version unknown)')"
  AVAILABLE=$((AVAILABLE + 1))
else
  log_warn "claude CLI 未インストール: npm install -g @anthropic-ai/claude-code"
fi

if command -v codex >/dev/null 2>&1; then
  log_ok "codex CLI $(codex --version 2>/dev/null || echo '(version unknown)')"
  AVAILABLE=$((AVAILABLE + 1))
else
  log_warn "codex CLI 未インストール: npm install -g @openai/codex"
fi

if command -v coderabbit >/dev/null 2>&1; then
  log_ok "coderabbit CLI"
  AVAILABLE=$((AVAILABLE + 1))
else
  log_warn "coderabbit CLI 未インストール: curl -fsSL https://cli.coderabbit.ai/install.sh | sh"
fi

if (( AVAILABLE == 0 )); then
  log_err "少なくとも1つのレビュアーCLIが必要です"
  exit 1
fi

log_info "${AVAILABLE}/3 レビュアーが利用可能"

# ━━━ 3. ディレクトリ作成 ━━━
echo ""
echo "📁 ディレクトリセットアップ..."

mkdir -p "${CONFIG_DIR}"/{bin,reviewers,lib,prompts,reports,logs}
log_ok "ディレクトリ構造"

# ━━━ 4. PATH設定（~/bin → symlink） ━━━
echo ""
echo "🔗 PATH設定..."

BIN_DIR="$HOME/bin"
mkdir -p "$BIN_DIR"

SYMLINK="${BIN_DIR}/triple-review"
TARGET="${CONFIG_DIR}/bin/triple-review"

if [[ -L "$SYMLINK" ]]; then
  if [[ "$(readlink "$SYMLINK")" == "$TARGET" ]]; then
    log_ok "symlink 既存: ${SYMLINK} → ${TARGET}"
  else
    ln -sf "$TARGET" "$SYMLINK"
    log_ok "symlink 更新: ${SYMLINK} → ${TARGET}"
  fi
elif [[ -e "$SYMLINK" ]]; then
  log_warn "${SYMLINK} がファイルとして存在します。手動で確認してください。"
else
  ln -s "$TARGET" "$SYMLINK"
  log_ok "symlink 作成: ${SYMLINK} → ${TARGET}"
fi

# PATHに ~/bin が含まれているか確認
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
  log_warn "~/bin が PATH に含まれていません。以下を .zshrc / .bashrc に追加してください:"
  echo "  export PATH=\"\$HOME/bin:\$PATH\""
fi

# ━━━ 5. Claude Code commands symlink ━━━
echo ""
echo "🔗 Claude Code コマンド設定..."

CLAUDE_CMD_DIR="$HOME/.claude/commands"
mkdir -p "$CLAUDE_CMD_DIR"

# triple-review.md と fix-review.md が存在するか確認
for cmd_file in triple-review.md fix-review.md; do
  if [[ -f "${CLAUDE_CMD_DIR}/${cmd_file}" ]]; then
    log_ok "${cmd_file} 既存"
  else
    log_warn "${cmd_file} が ${CLAUDE_CMD_DIR}/ にありません（別途作成が必要）"
  fi
done

# ━━━ 6. config.json 確認 ━━━
echo ""
echo "⚙️  設定ファイル確認..."

if [[ -f "${CONFIG_DIR}/config.json" ]]; then
  log_ok "config.json 既存"
else
  log_warn "config.json が見つかりません。デフォルト設定を生成してください。"
fi

# ━━━ 7. 実行権限 ━━━
chmod +x "${CONFIG_DIR}/bin/triple-review" 2>/dev/null && log_ok "実行権限設定"

# ━━━ 完了 ━━━
echo ""
printf "${BOLD}━━━ セットアップ完了 ━━━${RESET}\n\n"
echo "使い方:"
echo "  triple-review                  # git リポジトリ内で実行"
echo "  triple-review --help           # ヘルプ表示"
echo ""
echo "Claude Code から:"
echo "  /triple-review                 # レビュー実行"
echo "  /fix-review latest             # 最新レポートの修正"
echo ""
