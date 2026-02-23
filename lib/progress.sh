#!/usr/bin/env bash
# shellcheck disable=SC2059
# progress.sh — マルチラインライブプログレス表示

# ブレイユスピナー文字
SPINNER_CHARS=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# ヘッダーブロック表示
# 引数: project branch base_ref files added removed diff_mode diff_lines
print_header() {
  local project="$1" branch="$2" base_ref="$3"
  local files="$4" added="$5" removed="$6"
  local diff_mode="$7" diff_lines="$8"

  local mode_label
  case "$diff_mode" in
    commit)   mode_label="commit" ;;
    staged)   mode_label="staged" ;;
    unstaged) mode_label="unstaged" ;;
    *)        mode_label="$diff_mode" ;;
  esac

  printf "\n" >&2
  if is_tty; then
    printf "  ${BOLD}ai-multi-review${RESET}\n" >&2
    printf "  ${CYAN}%s${RESET} · ${CYAN}%s${RESET} → ${CYAN}%s${RESET} · %s files · ${GREEN}+%s${RESET}/${RED}-%s${RESET} · %s\n" \
      "$project" "$branch" "$base_ref" "$files" "$added" "$removed" "$mode_label" >&2
  else
    printf "  ai-multi-review\n" >&2
    printf "  %s · %s → %s · %s files · +%s/-%s · %s\n" \
      "$project" "$branch" "$base_ref" "$files" "$added" "$removed" "$mode_label" >&2
  fi

  if (( diff_lines > 1000 )); then
    if is_tty; then
      printf "  ${YELLOW}⚠ Large diff (%s lines)${RESET}\n" "$diff_lines" >&2
    else
      printf "  Warning: Large diff (%s lines)\n" "$diff_lines" >&2
    fi
  fi

  printf "\n" >&2
}

# 完了レビュアーの結果ラベルを生成
# .blocking / .advisory ファイルがあれば "N blocking  M advisory"、なければ引数のlabelをそのまま返す
_result_label() {
  local status_dir="$1" reviewer="$2" fallback_label="$3"
  local b=0 a=0
  if [[ -f "${status_dir}/${reviewer}.blocking" ]]; then
    b=$(cat "${status_dir}/${reviewer}.blocking")
  fi
  if [[ -f "${status_dir}/${reviewer}.advisory" ]]; then
    a=$(cat "${status_dir}/${reviewer}.advisory")
  fi
  if [[ "$b" == "0" && "$a" == "0" && ! -f "${status_dir}/${reviewer}.blocking" ]]; then
    echo "$fallback_label"
  else
    echo "${b} blocking  ${a} advisory"
  fi
}

# 全レビュアーの現在状態を1フレーム描画
# 引数: status_dir spin_idx reviewer1 [reviewer2 ...]
print_progress() {
  local status_dir="$1" spin_idx="$2"
  shift 2
  local reviewers=("$@")
  local now
  now=$(date +%s)

  for reviewer in "${reviewers[@]}"; do
    local status="running"
    [[ -f "${status_dir}/${reviewer}" ]] && status=$(cat "${status_dir}/${reviewer}")

    local elapsed=""
    if [[ -f "${status_dir}/${reviewer}.start" ]]; then
      local start_ts
      start_ts=$(cat "${status_dir}/${reviewer}.start")
      if [[ "$status" == "running" ]]; then
        elapsed="$(( now - start_ts ))s"
      elif [[ -f "${status_dir}/${reviewer}.end" ]]; then
        local end_ts
        end_ts=$(cat "${status_dir}/${reviewer}.end")
        elapsed="$(( end_ts - start_ts ))s"
      fi
    fi

    local icon label
    case "$status" in
      running)
        local spinner="${SPINNER_CHARS[$(( spin_idx % ${#SPINNER_CHARS[@]} ))]}"
        icon="${CYAN}${spinner}${RESET}"
        label="reviewing..."
        ;;
      completed)
        icon="${GREEN}✅${RESET}"
        label=$(_result_label "$status_dir" "$reviewer" "done")
        ;;
      timeout)
        icon="${YELLOW}⏰${RESET}"
        label=$(_result_label "$status_dir" "$reviewer" "timeout")
        ;;
      error)
        icon="${RED}❌${RESET}"
        label=$(_result_label "$status_dir" "$reviewer" "error")
        ;;
      skipped)
        icon="${DIM}⏭️${RESET}"
        label="skipped"
        ;;
      *)
        icon="?"
        label="$status"
        ;;
    esac

    printf "  %-12s %b %-26s %6s\033[K\n" "$reviewer" "$icon" "$label" "$elapsed" >&2
  done
}

# プログレス行をクリア
# 引数: num_lines
clear_progress() {
  local num_lines="$1"
  local i
  for (( i = 0; i < num_lines; i++ )); do
    printf "\033[A\033[K" >&2
  done
}

# ステータスファイルをポーリングしてプログレスを更新するループ
# 引数: status_dir pid_list reviewer_list
#   pid_list: "pid1:pid2:pid3" 形式
#   reviewer_list: "rev1:rev2:rev3" 形式
monitor_loop() {
  local status_dir="$1"
  local pid_list_str="$2"
  local reviewer_list_str="$3"

  IFS=':' read -ra pids <<< "$pid_list_str"
  IFS=':' read -ra reviewers <<< "$reviewer_list_str"

  local num_reviewers=${#reviewers[@]}
  local spin_idx=0

  if ! is_tty; then
    # 非TTY: 完了時に1行ずつ出力
    local completed_set=()
    while true; do
      local all_done=true
      for i in "${!reviewers[@]}"; do
        local reviewer="${reviewers[$i]}"
        local status="running"
        [[ -f "${status_dir}/${reviewer}" ]] && status=$(cat "${status_dir}/${reviewer}")

        if [[ "$status" != "running" ]]; then
          local already_reported=false
          for c in "${completed_set[@]:-}"; do
            [[ "$c" == "$reviewer" ]] && already_reported=true
          done
          if ! $already_reported; then
            local elapsed=""
            if [[ -f "${status_dir}/${reviewer}.start" && -f "${status_dir}/${reviewer}.end" ]]; then
              local s e
              s=$(cat "${status_dir}/${reviewer}.start")
              e=$(cat "${status_dir}/${reviewer}.end")
              elapsed=" ($(( e - s ))s)"
            fi
            local rlabel
            rlabel=$(_result_label "$status_dir" "$reviewer" "$status")
            printf "  [%s] %s  %s%s\n" "$status" "$reviewer" "$rlabel" "$elapsed" >&2
            completed_set+=("$reviewer")
          fi
        else
          all_done=false
        fi
      done

      $all_done && break
      sleep 0.5
    done
    for pid in "${pids[@]}"; do
      wait "$pid" 2>/dev/null || true
    done
    return
  fi

  # TTY: カーソルを非表示にしてマルチラインプログレス
  printf "\033[?25l" >&2
  # シグナル時にカーソルを復元
  trap 'printf "\033[?25h" >&2' RETURN

  # 初回描画
  print_progress "$status_dir" "$spin_idx" "${reviewers[@]}"

  while true; do
    sleep 0.2
    spin_idx=$(( spin_idx + 1 ))

    # カーソルを上に戻して再描画
    printf "\033[%dA" "$num_reviewers" >&2
    print_progress "$status_dir" "$spin_idx" "${reviewers[@]}"

    # 全完了チェック
    local all_done=true
    for reviewer in "${reviewers[@]}"; do
      local status="running"
      [[ -f "${status_dir}/${reviewer}" ]] && status=$(cat "${status_dir}/${reviewer}")
      if [[ "$status" == "running" ]]; then
        all_done=false
        break
      fi
    done

    $all_done && break
  done

  # 全PIDの完了を待つ
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # 最終確定表示に上書き
  printf "\033[%dA" "$num_reviewers" >&2
  print_progress "$status_dir" 0 "${reviewers[@]}"

  # カーソル復元
  printf "\033[?25h" >&2

  printf "\n" >&2
}
