#!/usr/bin/env bash
# aider.sh — Aider CLI reviewer adapter (EXPERIMENTAL)

reviewer_name="aider"

check_available() {
  check_cli aider
}

run_review() {
  local diff_file="$1" out_file="$2"
  # TODO: Implement aider CLI integration
  # aider supports --message for non-interactive mode
  # Example: aider --no-auto-commits --message "Review this diff: $(cat $diff_file)"
  log_warn "aider: adapter not yet implemented"
  echo '{"issues":[]}' > "$out_file"
}
