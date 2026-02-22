#!/usr/bin/env bash
# shellcheck disable=SC2034
# opencode.sh — OpenCode CLI reviewer adapter (EXPERIMENTAL)

reviewer_name="opencode"

check_available() {
  check_cli opencode
}

run_review() {
  local diff_file="$1" out_file="$2"
  # TODO: Implement opencode CLI integration
  # OpenCode CLI interface TBD — check latest docs at github.com/opencode-ai/opencode
  log_warn "opencode: adapter not yet implemented"
  echo '{"issues":[]}' > "$out_file"
}
