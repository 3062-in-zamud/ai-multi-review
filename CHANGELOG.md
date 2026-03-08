# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-02-22

### Added
- Multi-LLM parallel code review (Claude, Codex, CodeRabbit, Gemini)
- Automatic diff detection (commit > staged > unstaged)
- Cross-reviewer deduplication with ±5 line tolerance
- Blocking/advisory severity with confidence scoring
- Markdown + JSON report generation
- Project-specific rules injection (`.ai-multi-review/rules.md`)
- PR/ticket context injection (`--context`, `--context-file`)
- Review quality evaluation tool (`ai-multi-review-eval`)
- Bilingual EN/JA support
- Interactive installer (`install.sh`)
- Skeleton adapters for Aider, OpenCode, GitHub Copilot

### Changed
- Renamed from `triple-review` to `ai-multi-review`

[Unreleased]: https://github.com/yourusername/ai-multi-review/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/yourusername/ai-multi-review/releases/tag/v0.1.0
