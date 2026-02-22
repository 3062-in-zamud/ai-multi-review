#!/usr/bin/env bash
# merge.sh — レビュー結果の統合・重複除去

# 3つのレビュー結果JSONを統合し、重複除去した結果を出力
# 引数: result_dir（各レビュアーの .json が格納されたディレクトリ）
# 出力: stdout に統合JSON
merge_results() {
  local result_dir="$1"
  local dedup_range
  dedup_range=$(config_get ".merge.dedup_line_range" "5")
  # 数値であることを保証
  [[ "$dedup_range" =~ ^[0-9]+$ ]] || dedup_range=5

  # 全レビュアーの issues を収集（source情報を付与）
  local merged_json='{"issues":[]}'

  for json_file in "${result_dir}"/*.json; do
    [[ -f "$json_file" ]] || continue

    # JSONとして有効か確認
    if ! jq empty "$json_file" 2>/dev/null; then
      continue
    fi

    local rname
    rname=$(basename "$json_file" .json)

    # 各issueにdetected_byフィールドを追加
    local annotated
    annotated=$(jq --arg src "$rname" '
      .issues // [] | map(. + {"detected_by": [$src]})
    ' "$json_file" 2>/dev/null) || continue

    # B-7: annotated が有効なJSON配列か確認し、エラーを隠蔽しない
    if [[ -n "$annotated" ]] && echo "$annotated" | jq empty 2>/dev/null; then
      local new_merged tmpfile
      tmpfile=$(mktemp)
      echo "$annotated" > "$tmpfile"
      if new_merged=$(echo "$merged_json" | jq --slurpfile new "$tmpfile" '.issues += $new[0]'); then
        merged_json="$new_merged"
      else
        log_warn "jq merge failed for ${rname}"
      fi
      rm -f "$tmpfile"
    fi
  done

  # issues が空なら重複除去をスキップ
  local issue_count
  issue_count=$(echo "$merged_json" | jq '.issues | length' 2>/dev/null || echo "0")

  if (( issue_count == 0 )); then
    echo "$merged_json"
    return
  fi

  # 重複除去
  echo "$merged_json" | jq --argjson range "$dedup_range" '
    # B-5: 空文字列の lines に対応
    def line_start:
      (.lines // "") as $l |
      if ($l | length) > 0 and ($l | split("-")[0] | test("^[0-9]+$"))
      then ($l | split("-")[0] | tonumber)
      else 0
      end;

    # A-2: abs イディオム改善
    def abs: if . < 0 then -. else . end;

    # B-6: null の file/category で誤マージしない
    def is_duplicate(a; b):
      (a.file != null) and (b.file != null)
      and a.file == b.file
      and a.category == b.category
      and (((a | line_start) - (b | line_start)) | abs <= $range);

    # B-12: .problem / .recommendation の null 対応
    def merge_pair(a; b):
      {
        severity: (if a.severity == "blocking" or b.severity == "blocking" then "blocking" else "advisory" end),
        category: (a.category // b.category),
        file: a.file,
        lines: (if ((a.problem // "") | length) >= ((b.problem // "") | length) then a.lines else b.lines end),
        problem: (if ((a.problem // "") | length) >= ((b.problem // "") | length) then (a.problem // "") else (b.problem // "") end),
        recommendation: (if ((a.recommendation // "") | length) >= ((b.recommendation // "") | length) then (a.recommendation // "") else (b.recommendation // "") end),
        detected_by: (a.detected_by + b.detected_by | unique),
        high_confidence: ((a.detected_by + b.detected_by | unique | length) > 1)
      };

    .issues as $all |
    reduce range(0; $all | length) as $i (
      [];
      . as $acc |
      $all[$i] as $curr |
      if any(.[]; is_duplicate(.; $curr))
      then
        map(
          if is_duplicate(.; $curr)
          then merge_pair(.; $curr)
          else . end
        )
      else
        . + [$curr + {high_confidence: false}]
      end
    ) |
    {issues: .}
  ' 2>/dev/null || echo "$merged_json"
}

# 統計情報を取得
get_stats() {
  local merged_json="$1"
  local blocking advisory
  blocking=$(echo "$merged_json" | jq '[(.issues // [])[] | select(.severity == "blocking")] | length' 2>/dev/null || echo "0")
  advisory=$(echo "$merged_json" | jq '[(.issues // [])[] | select(.severity == "advisory")] | length' 2>/dev/null || echo "0")
  echo "${blocking} ${advisory}"
}
