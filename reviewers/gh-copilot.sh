#!/usr/bin/env bash
# gh-copilot.sh — GitHub Copilot CLI reviewer adapter (EXPERIMENTAL)

reviewer_name="gh-copilot"

check_available() {
  command -v gh >/dev/null 2>&1 && gh copilot --help >/dev/null 2>&1
}

run_review() {
  local diff_file="$1" out_file="$2"
  # TODO: Implement gh copilot CLI integration
  # gh copilot suggest / gh copilot explain may be usable for review
  log_warn "gh-copilot: adapter not yet implemented"
  echo '{"issues":[]}' > "$out_file"
}
