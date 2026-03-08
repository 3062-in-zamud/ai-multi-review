"""test_eval.py — unit tests for bin/ai-multi-review-eval"""

import importlib.machinery
import importlib.util
import json
import os
import sys
import tempfile
from pathlib import Path

import pytest

# Load module without .py extension using SourceFileLoader
_EVAL_PATH = Path(__file__).parent.parent / "bin" / "ai-multi-review-eval"

def _load_eval_module():
    loader = importlib.machinery.SourceFileLoader(
        "ai_multi_review_eval",
        str(_EVAL_PATH),
    )
    spec = importlib.util.spec_from_loader(loader.name, loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod

eval_mod = _load_eval_module()

evaluate = eval_mod.evaluate
generate_template = eval_mod.generate_template


# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

def _write_json(path: str, data: dict) -> None:
    with open(path, "w") as f:
        json.dump(data, f)


def _make_issues(issues: list[dict]) -> dict:
    return {"issues": issues}


def _make_verdict(verdicts: list[dict]) -> dict:
    return {"verdicts": verdicts}


# ──────────────────────────────────────────────
# class TestEvaluate
# ──────────────────────────────────────────────

class TestEvaluate:
    def test_perfect_precision(self, tmp_path):
        """All issues are true positives → precision 1.0"""
        issues = _make_issues([
            {"id": "B-1", "severity": "blocking", "file": "a.ts",
             "problem": "p1", "detected_by": ["claude"]},
            {"id": "A-1", "severity": "advisory", "file": "b.ts",
             "problem": "p2", "detected_by": ["codex"]},
        ])
        verdicts = _make_verdict([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "true_positive": True, "comment": ""},
            {"id": "A-1", "file": "b.ts", "problem": "p2", "true_positive": True, "comment": ""},
        ])

        issues_path = str(tmp_path / "issues.json")
        verdict_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)
        _write_json(verdict_path, verdicts)

        result = evaluate(issues_path, verdict_path)
        assert result["summary"]["precision"] == 1.0
        assert result["summary"]["fp_rate"] == 0.0
        assert result["summary"]["true_positives"] == 2
        assert result["summary"]["false_positives"] == 0

    def test_zero_precision(self, tmp_path):
        """All issues are false positives → precision 0.0"""
        issues = _make_issues([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "detected_by": ["claude"]},
        ])
        verdicts = _make_verdict([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "true_positive": False, "comment": ""},
        ])
        issues_path = str(tmp_path / "issues.json")
        verdict_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)
        _write_json(verdict_path, verdicts)

        result = evaluate(issues_path, verdict_path)
        assert result["summary"]["precision"] == 0.0
        assert result["summary"]["fp_rate"] == 1.0
        assert result["summary"]["false_positives"] == 1

    def test_mixed_precision(self, tmp_path):
        """2 TP + 2 FP → precision 0.5"""
        issues = _make_issues([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "detected_by": ["claude"]},
            {"id": "B-2", "file": "b.ts", "problem": "p2", "detected_by": ["claude"]},
            {"id": "A-1", "file": "c.ts", "problem": "p3", "detected_by": ["codex"]},
            {"id": "A-2", "file": "d.ts", "problem": "p4", "detected_by": ["codex"]},
        ])
        verdicts = _make_verdict([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "true_positive": True, "comment": ""},
            {"id": "B-2", "file": "b.ts", "problem": "p2", "true_positive": False, "comment": ""},
            {"id": "A-1", "file": "c.ts", "problem": "p3", "true_positive": True, "comment": ""},
            {"id": "A-2", "file": "d.ts", "problem": "p4", "true_positive": False, "comment": ""},
        ])
        issues_path = str(tmp_path / "issues.json")
        verdict_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)
        _write_json(verdict_path, verdicts)

        result = evaluate(issues_path, verdict_path)
        assert result["summary"]["precision"] == 0.5
        assert result["summary"]["fp_rate"] == 0.5
        assert result["summary"]["total_evaluated"] == 4

    def test_no_overlap_between_issues_and_verdict(self, tmp_path):
        """Issue IDs don't match any verdict → 0 evaluated"""
        issues = _make_issues([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "detected_by": ["claude"]},
        ])
        verdicts = _make_verdict([
            {"id": "X-99", "file": "x.ts", "problem": "px", "true_positive": True, "comment": ""},
        ])
        issues_path = str(tmp_path / "issues.json")
        verdict_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)
        _write_json(verdict_path, verdicts)

        result = evaluate(issues_path, verdict_path)
        assert result["summary"]["total_evaluated"] == 0
        assert result["summary"]["precision"] == 0.0

    def test_per_reviewer_statistics(self, tmp_path):
        """Per-reviewer stats are correctly split"""
        issues = _make_issues([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "detected_by": ["claude", "codex"]},
            {"id": "A-1", "file": "b.ts", "problem": "p2", "detected_by": ["codex"]},
        ])
        verdicts = _make_verdict([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "true_positive": True, "comment": ""},
            {"id": "A-1", "file": "b.ts", "problem": "p2", "true_positive": False, "comment": ""},
        ])
        issues_path = str(tmp_path / "issues.json")
        verdict_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)
        _write_json(verdict_path, verdicts)

        result = evaluate(issues_path, verdict_path)
        per = result["per_reviewer"]
        assert "claude" in per
        assert "codex" in per
        assert per["claude"]["precision"] == 1.0   # B-1 is TP
        assert per["codex"]["total"] == 2           # B-1 + A-1


class TestEdgeCases:
    def test_empty_issues(self, tmp_path):
        """Empty issues list → 0 evaluated"""
        issues = _make_issues([])
        verdicts = _make_verdict([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "true_positive": True, "comment": ""},
        ])
        issues_path = str(tmp_path / "issues.json")
        verdict_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)
        _write_json(verdict_path, verdicts)

        result = evaluate(issues_path, verdict_path)
        assert result["summary"]["total_evaluated"] == 0

    def test_verdict_with_null_true_positive_is_skipped(self, tmp_path):
        """Verdict with true_positive=None is excluded from evaluation"""
        issues = _make_issues([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "detected_by": ["claude"]},
            {"id": "A-1", "file": "b.ts", "problem": "p2", "detected_by": ["codex"]},
        ])
        verdicts = _make_verdict([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "true_positive": True, "comment": ""},
            {"id": "A-1", "file": "b.ts", "problem": "p2", "true_positive": None, "comment": ""},
        ])
        issues_path = str(tmp_path / "issues.json")
        verdict_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)
        _write_json(verdict_path, verdicts)

        result = evaluate(issues_path, verdict_path)
        # Only B-1 is evaluated (A-1 has None)
        assert result["summary"]["total_evaluated"] == 1

    def test_consensus_precision(self, tmp_path):
        """Issues detected by multiple reviewers have consensus metrics"""
        issues = _make_issues([
            # multi-reviewer
            {"id": "B-1", "file": "a.ts", "problem": "p1", "detected_by": ["claude", "codex"]},
            # single reviewer
            {"id": "A-1", "file": "b.ts", "problem": "p2", "detected_by": ["claude"]},
        ])
        verdicts = _make_verdict([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "true_positive": True, "comment": ""},
            {"id": "A-1", "file": "b.ts", "problem": "p2", "true_positive": False, "comment": ""},
        ])
        issues_path = str(tmp_path / "issues.json")
        verdict_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)
        _write_json(verdict_path, verdicts)

        result = evaluate(issues_path, verdict_path)
        c = result["consensus"]
        assert c["total"] == 1         # only B-1 is multi-reviewer
        assert c["true_positives"] == 1
        assert c["precision"] == 1.0

    def test_missing_detected_by_field(self, tmp_path):
        """Issues without detected_by don't crash"""
        issues = _make_issues([
            {"id": "B-1", "file": "a.ts", "problem": "p1"},  # no detected_by
        ])
        verdicts = _make_verdict([
            {"id": "B-1", "file": "a.ts", "problem": "p1", "true_positive": True, "comment": ""},
        ])
        issues_path = str(tmp_path / "issues.json")
        verdict_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)
        _write_json(verdict_path, verdicts)

        result = evaluate(issues_path, verdict_path)
        assert result["summary"]["true_positives"] == 1


class TestGenerateTemplate:
    def test_generates_valid_template(self, tmp_path):
        """generate_template creates a valid JSON file with verdicts"""
        issues = _make_issues([
            {"id": "B-1", "file": "a.ts", "problem": "Hardcoded key"},
            {"id": "A-1", "file": "b.ts", "problem": "Unused variable"},
        ])
        issues_path = str(tmp_path / "issues.json")
        output_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)

        generate_template(issues_path, output_path)

        assert os.path.exists(output_path)
        with open(output_path) as f:
            data = json.load(f)
        assert "verdicts" in data
        assert len(data["verdicts"]) == 2

    def test_template_has_null_true_positive(self, tmp_path):
        """Generated template has null true_positive (unreviewed)"""
        issues = _make_issues([
            {"id": "B-1", "file": "a.ts", "problem": "Some issue"},
        ])
        issues_path = str(tmp_path / "issues.json")
        output_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)

        generate_template(issues_path, output_path)

        with open(output_path) as f:
            data = json.load(f)
        assert data["verdicts"][0]["true_positive"] is None

    def test_empty_issues_template_does_not_crash(self, tmp_path):
        """generate_template with empty issues produces empty verdicts"""
        issues = _make_issues([])
        issues_path = str(tmp_path / "issues.json")
        output_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)

        generate_template(issues_path, output_path)

        with open(output_path) as f:
            data = json.load(f)
        assert data["verdicts"] == []

    def test_template_preserves_issue_id(self, tmp_path):
        """Template verdict id matches the issue id"""
        issues = _make_issues([
            {"id": "B-3", "file": "c.ts", "problem": "An issue"},
        ])
        issues_path = str(tmp_path / "issues.json")
        output_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)

        generate_template(issues_path, output_path)

        with open(output_path) as f:
            data = json.load(f)
        assert data["verdicts"][0]["id"] == "B-3"

    def test_template_truncates_long_problem_text(self, tmp_path):
        """Problem text longer than 100 chars is truncated in template"""
        long_problem = "x" * 200
        issues = _make_issues([
            {"id": "A-1", "file": "a.ts", "problem": long_problem},
        ])
        issues_path = str(tmp_path / "issues.json")
        output_path = str(tmp_path / "verdict.json")
        _write_json(issues_path, issues)

        generate_template(issues_path, output_path)

        with open(output_path) as f:
            data = json.load(f)
        assert len(data["verdicts"][0]["problem"]) == 100
