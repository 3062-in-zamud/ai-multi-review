#!/usr/bin/env bash
# report.sh — レビューレポート生成（ターミナル表示 + Markdownファイル）

# ターミナルにサマリーを表示
print_terminal_summary() {
  local project="$1" branch="$2" base_ref="$3"
  local files="$4" added="$5" removed="$6"
  local report_path="$7" issues_path="$8"
  local merged_json="$9"
  shift 9
  # $1=reviewer_statuses (reviewer:status:blocking:advisory 形式、改行区切り)
  local reviewer_statuses="$1"

  local blocking advisory
  read -r blocking advisory <<< "$(get_stats "$merged_json")"

  printf "\n${BOLD}━━━ Triple Review ━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "Repo: ${CYAN}%s${RESET} | Branch: ${CYAN}%s${RESET} → ${CYAN}%s${RESET}\n" "$project" "$branch" "$base_ref"
  printf "Files: ${BOLD}%s${RESET} | Lines: ${GREEN}+%s${RESET}/${RED}-%s${RESET}\n\n" "$files" "$added" "$removed"

  # 各レビュアーの状態
  while IFS=: read -r name status r_blocking r_advisory; do
    [[ -z "$name" ]] && continue
    local icon
    case "$status" in
      completed) icon="${GREEN}✅${RESET}" ;;
      skipped)   icon="${DIM}⏭️${RESET}" ;;
      timeout)   icon="${YELLOW}⏰${RESET}" ;;
      error)     icon="${RED}❌${RESET}" ;;
    esac
    printf "  %-12s %b %s blocking, %s advisory\n" "$name" "$icon" "${r_blocking:-0}" "${r_advisory:-0}"
  done <<< "$reviewer_statuses"

  printf "\n"

  if (( blocking > 0 )); then
    printf "Verdict: ${RED}⚠️  %d blocking issue(s)${RESET} (deduplicated)\n" "$blocking"
  else
    printf "Verdict: ${GREEN}✅ No blocking issues${RESET}\n"
  fi

  printf "Report: ${DIM}%s${RESET}\n" "$report_path"
  printf "Issues: ${DIM}%s${RESET}\n\n" "$issues_path"

  if (( blocking > 0 )); then
    printf "Fix(Claude): ${CYAN}/fix-review latest${RESET}\n"
    printf "Fix(Codex):  ${CYAN}codex exec \"\$(cat ~/.codex/instructions/fix-review.md) \$(cat %s)\"${RESET}\n" "$issues_path"
  fi

  printf "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n\n"
}

# Markdownレポートを生成
generate_markdown_report() {
  local report_name="$1" project="$2" branch="$3" base_ref="$4"
  local files="$5" added="$6" removed="$7"
  local merged_json="$8"
  shift 8
  local reviewer_statuses="$1"
  local date_str
  date_str=$(date '+%Y-%m-%d %H:%M:%S')

  local blocking advisory
  read -r blocking advisory <<< "$(get_stats "$merged_json")"

  local verdict
  if (( blocking > 0 )); then
    verdict="WARNING - ${blocking} blocking issue(s)"
  else
    verdict="PASS - No blocking issues"
  fi

  cat <<REPORT_EOF
# Triple Review Report
- **Report**: \`${report_name}\`
- **Date**: ${date_str}
- **Repo**: ${project}
- **Branch**: ${branch} → ${base_ref}
- **Base**: ${base_ref}
- **Files**: ${files} changed | **Lines**: +${added}/-${removed}

## Verdict: ${verdict}

---

REPORT_EOF

  # Blocking Issues
  if (( blocking > 0 )); then
    echo "## Blocking Issues"
    echo ""
    echo "$merged_json" | jq -r '
      [.issues[] | select(.severity == "blocking")] |
      to_entries[] |
      "### [B-\(.key + 1)] \(.value.category // "unknown") - \(.value.file):\(.value.lines // "?")\n" +
      "- **Detected by**: \(.value.detected_by | join(", "))" +
      (if .value.high_confidence then " (high confidence)" else "" end) + "\n" +
      "- **Problem**: \(.value.problem)\n" +
      "- **Recommendation**: \(.value.recommendation)\n"
    '
  fi

  # Advisory Issues
  if (( advisory > 0 )); then
    echo "## Advisory Issues"
    echo ""
    echo "$merged_json" | jq -r '
      [.issues[] | select(.severity == "advisory")] |
      to_entries[] |
      "### [A-\(.key + 1)] \(.value.category // "unknown") - \(.value.file):\(.value.lines // "?")\n" +
      "- **Detected by**: \(.value.detected_by | join(", "))" +
      (if .value.high_confidence then " (high confidence)" else "" end) + "\n" +
      "- **Problem**: \(.value.problem)\n" +
      "- **Recommendation**: \(.value.recommendation)\n"
    '
  fi

  # Per-Reviewer Detail
  echo "## Per-Reviewer Detail"
  echo ""
  echo "| Reviewer | Blocking | Advisory | Status |"
  echo "|----------|----------|----------|--------|"

  while IFS=: read -r name status r_blocking r_advisory; do
    [[ -z "$name" ]] && continue
    printf "| %s | %s | %s | %s |\n" "$name" "${r_blocking:-0}" "${r_advisory:-0}" "$status"
  done <<< "$reviewer_statuses"

  printf "| **Total** | **%s** | **%s** | - |\n" "$blocking" "$advisory"
}

# issues.json を生成（fix-review用、IDフィールド付き）
generate_issues_json() {
  local merged_json="$1"

  echo "$merged_json" | jq '
    # B-8: null の issues に対応
    .issues = (.issues // []) |
    .issues |= (
      [
        [.[] | select(.severity == "blocking")] | to_entries | map(.value + {id: "B-\(.key + 1)"}),
        [.[] | select(.severity == "advisory")] | to_entries | map(.value + {id: "A-\(.key + 1)"})
      ] | add // []
    )
  '
}
