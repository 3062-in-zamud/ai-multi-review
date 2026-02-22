以下の git diff をレビューし、結果をJSON形式で出力してください。
issuesが無い場合は空配列を返してください。

出力スキーマ:
{
  "issues": [
    {
      "severity": "blocking または advisory",
      "category": "security|correctness|perf|maintainability|testing|style",
      "file": "ファイルパス",
      "lines": "開始行-終了行",
      "problem": "問題の簡潔な説明",
      "recommendation": "具体的な修正案"
    }
  ]
}

diff:
