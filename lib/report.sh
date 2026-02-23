#!/usr/bin/env bash
# shellcheck disable=SC2059,SC2034
# report.sh — レビューレポート生成（ターミナル表示 + Markdownファイル）

# ターミナルにサマリーを表示
# レビュアーテーブルはプログレス表示で既出のため、ここでは verdict 以降のみ
print_terminal_summary() {
  local project="$1" branch="$2" base_ref="$3"
  local files="$4" added="$5" removed="$6"
  local report_path="$7" issues_path="$8"
  local merged_json="$9"
  shift 9
  local reviewer_statuses="$1"
  local status_dir="${2:-}"
  local total_start_time="${3:-}"

  local blocking advisory
  read -r blocking advisory <<< "$(get_stats "$merged_json")"

  local bar="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if is_tty; then
    printf "${BOLD}%s${RESET}\n\n" "$bar" >&2
  else
    printf "----------------------------------------------\n\n" >&2
  fi

  # Verdict
  if (( blocking > 0 )); then
    if is_tty; then
      printf "  ${YELLOW}⚠️  Verdict: %d blocking issue(s)${RESET} (deduplicated)\n" "$blocking" >&2
    else
      printf "  Warning: %d blocking issue(s) (deduplicated)\n" "$blocking" >&2
    fi
  else
    if is_tty; then
      printf "  ${GREEN}✅ Verdict: No blocking issues${RESET}\n" >&2
    else
      printf "  OK: No blocking issues\n" >&2
    fi
  fi

  printf "\n" >&2

  # Blocking issues プレビュー（最大3件）
  if (( blocking > 0 )); then
    local preview
    preview=$(echo "$merged_json" | jq -r '
      [.issues[] | select(.severity == "blocking")] |
      to_entries | .[0:3][] |
      "  B-\(.key + 1)  \(.value.category // "unknown") · \(.value.file):\(.value.lines // "?")\n       \(.value.problem // "" | .[0:80])"
    ' 2>/dev/null)

    if [[ -n "$preview" ]]; then
      printf "%s\n" "$preview" >&2
      if (( blocking > 3 )); then
        printf "  ... and %d more\n" "$(( blocking - 3 ))" >&2
      fi
      printf "\n" >&2
    fi
  fi

  # Report / Fix パス
  local short_report
  short_report=$(shorten_path "$report_path")

  if is_tty; then
    printf "  Report  ${DIM}%s${RESET}\n" "$short_report" >&2
  else
    printf "  Report  %s\n" "$short_report" >&2
  fi

  if (( blocking > 0 )); then
    if is_tty; then
      printf "  Fix     ${CYAN}/fix-review latest${RESET}  ← blocking issues を自動修正\n" >&2
    else
      printf "  Fix     /fix-review latest  <- blocking issues を自動修正\n" >&2
    fi
  fi

  printf "\n" >&2

  # フッター罫線 + Total
  local total_elapsed=""
  if [[ -n "$total_start_time" ]]; then
    local now
    now=$(date +%s)
    total_elapsed="Total: $(( now - total_start_time ))s"
  fi

  if is_tty; then
    printf "${BOLD}%s${RESET}\n" "$bar" >&2
    if [[ -n "$total_elapsed" ]]; then
      printf "%*s\n" 46 "$total_elapsed" >&2
    fi
  else
    printf "----------------------------------------------\n" >&2
    if [[ -n "$total_elapsed" ]]; then
      printf "%*s\n" 46 "$total_elapsed" >&2
    fi
  fi

  printf "\n" >&2
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
# AI Multi Review Report
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
      (if .value.high_confidence then " (high confidence)" else "" end) +
      (if .value.confidence then " | confidence: \(.value.confidence)" else "" end) + "\n" +
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
      (if .value.high_confidence then " (high confidence)" else "" end) +
      (if .value.confidence then " | confidence: \(.value.confidence)" else "" end) + "\n" +
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
