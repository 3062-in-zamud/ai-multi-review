# ai-multi-review

[![Version](https://img.shields.io/badge/version-v0.1.0-blue)](https://github.com/3062-in-zamud/ai-multi-review/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

🇯🇵 [日本語版はこちら](README.ja.md)

Pre-PR code review with multiple LLM CLIs in parallel. Run several AI reviewers against your diff, deduplicate findings, and get a unified report — all before opening a pull request.

<!-- TODO: asciinema demo -->

## Features

- Parallel execution of multiple LLM code reviewers
- Automatic diff detection (commit diff > staged > unstaged)
- Cross-reviewer deduplication with configurable line-range tolerance
- Unified Markdown report with blocking/advisory severity + confidence scoring
- JSON issues output for automated fix workflows
- Project-specific review rules (`.ai-multi-review/rules.md`)
- PR/ticket context injection (`--context`, `--context-file`)
- Prompt debugging with `--dry-run`
- Review quality evaluation (`ai-multi-review-eval`)
- Configurable timeouts, models, and budget limits per reviewer
- Interactive installer with auto-detection and optional CLI installation

## Supported Reviewers

| Reviewer | CLI | Default | Status |
|----------|-----|---------|--------|
| CodeRabbit | `coderabbit` | enabled | stable |
| Claude Code | `claude` | enabled | stable |
| OpenAI Codex | `codex` | enabled | stable |
| Gemini CLI | `gemini` | disabled | stable |
| Aider | `aider` | disabled | skeleton |
| OpenCode | `opencode` | disabled | skeleton |
| GitHub Copilot | `gh copilot` | disabled | skeleton |

**skeleton** = adapter interface only, not yet tested with actual CLI.

## Requirements

- bash 4.0+, git, jq, python3
- At least one reviewer CLI installed:
  - [Claude Code](https://claude.ai/code) (`claude`)
  - [OpenAI Codex CLI](https://github.com/openai/codex) (`codex`)
  - [CodeRabbit CLI](https://coderabbit.ai/) (`coderabbit`) — free for open source
  - [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`gemini`)

## Quick Start

```bash
# 1. Clone
git clone https://github.com/3062-in-zamud/ai-multi-review.git ~/workspaces/ai-multi-review

# 2. Install (interactive setup)
bash ~/workspaces/ai-multi-review/install.sh

# 3. Run in any git repo
cd your-project
ai-multi-review
```

The installer auto-detects installed CLIs, offers to install missing ones, and generates `config.json` accordingly.

## Usage

```bash
ai-multi-review                           # Review diff against main
ai-multi-review develop                   # Review diff against develop
ai-multi-review --reviewers claude        # Claude only
ai-multi-review --no-block                # Don't exit 1 on blocking issues
ai-multi-review --output report.md        # Custom output path
ai-multi-review --context "Fixes #42"     # Add PR context
ai-multi-review --context-file pr.md      # Context from file
ai-multi-review --dry-run                 # Show prompts without running LLMs
```

#### Diff Detection (automatic priority)

1. **Commit diff** (`BASE...HEAD`) — committed changes since base branch
2. **Staged changes** (`git add`) — if no commit diff
3. **Unstaged changes** — if nothing staged

## Project-Specific Rules

Create `.ai-multi-review/rules.md` in your repository to inject project-specific review rules:

```markdown
## Project Rules
- All API endpoints must validate input with zod schemas
- Database queries must use transactions for multi-table writes
- React components must not exceed 200 lines
```

Rules are automatically prepended to the system prompt for claude, codex, and gemini reviewers.

**Priority order:**
1. `.ai-multi-review/rules.md` (in repository — highest priority)
2. `~/.config/ai-multi-review/rules/{project-name}/rules.md` (user-local)
3. Default system prompt (always included)

**CodeRabbit note:** CodeRabbit uses its own prompt architecture. Configure rules via `.coderabbit.yaml` in your repository ([CodeRabbit docs](https://docs.coderabbit.ai/)).

## Context Injection

Provide change context (PR description, ticket info) to help reviewers understand intent:

```bash
# CLI argument
ai-multi-review --context "Fixes #42: Add rate limiting to API endpoints"

# From file
ai-multi-review --context-file .github/pull_request_template.md

# Auto-detected from .ai-multi-review/context.md
echo "This PR adds authentication middleware" > .ai-multi-review/context.md
ai-multi-review

# Git metadata (commit diff mode only)
# Automatically extracts "Fixes #", "Closes #", "Refs #" from commit messages
```

## Output Example

Terminal output:

```
━━━ AI Multi Review ━━━━━━━━━━━━━━━━━━
Repo: myapp | Branch: feature-auth → main
Files: 8 | Lines: +245/-32

  claude       ✅ 2 blocking, 1 advisory
  codex        ✅ 1 blocking, 2 advisory
  coderabbit   ✅ 0 blocking, 2 advisory

Verdict: ⚠️  2 blocking issue(s) (deduplicated)
Report: ~/.config/ai-multi-review/reports/myapp/myapp_feature-auth_20260220_143052.md
Issues: ~/.config/ai-multi-review/reports/myapp/myapp_feature-auth_20260220_143052.issues.json

Fix(Claude): /fix-review latest
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

See [`examples/sample-report.md`](examples/sample-report.md) and [`examples/sample-issues.json`](examples/sample-issues.json) for full output examples.

## Review Quality

### Multi-LLM Advantage

Running multiple LLM reviewers catches issues that any single reviewer might miss:
- **Claude** excels at security analysis and complex logic review
- **Codex** is strong at identifying runtime errors and edge cases
- **CodeRabbit** focuses on code style and best practices
- **Gemini** provides broad coverage across categories

Issues detected by multiple reviewers (`high_confidence`) are statistically more likely to be true positives.

### Confidence Scoring

Each issue includes a `confidence` level (high/medium/low) indicating how certain the reviewer is:
- **high**: Logically provable from the code
- **medium**: Strong evidence from context and patterns
- **low**: Possible issue requiring further investigation

When multiple reviewers agree, confidence is automatically elevated.

### Recommended Workflow

1. **blocking + high confidence** → Fix immediately before merge
2. **blocking + low confidence** → Review manually, likely real issues
3. **advisory + high confidence** → Fix if time permits
4. **advisory + low confidence** → Treat as suggestions

### Quality Evaluation

Measure your review quality over time with `ai-multi-review-eval`:

```bash
# Generate verdict template from a review
ai-multi-review-eval --generate-template issues.json -o verdict.json

# Fill in true_positive: true/false for each issue, then evaluate
ai-multi-review-eval issues.json verdict.json
```

Output includes Precision, False Positive Rate, per-reviewer accuracy, and multi-reviewer consensus rate.

## Cost

| Reviewer | Pricing Model | Typical Cost per Review |
|----------|---------------|------------------------|
| Claude Code | API usage (per-token) or Max/Pro subscription | $0.01–0.50 (model-dependent) |
| Codex CLI | ChatGPT Pro/Plus subscription (included) or API key (per-token) | Free with subscription, or $0.01–0.30 |
| CodeRabbit | Free for open source, paid plans for private repos | Free–$0.00 (open source) |
| Gemini CLI | Google AI Studio free tier or API key | Free tier available |

**Codex CLI tip:** Use `codex login` to authenticate with your ChatGPT subscription instead of an API key to avoid per-token charges. The installer will warn you if API key authentication is detected.

## Configuration

Edit `~/.config/ai-multi-review/config.json`:

```json
{
  "reviewers": {
    "coderabbit": { "enabled": true, "timeout": 180 },
    "claude": { "enabled": true, "timeout": 300, "model": "sonnet", "max_budget_usd": 0.50 },
    "codex": { "enabled": true, "timeout": 300 },
    "gemini": { "enabled": false, "timeout": 300 }
  },
  "defaults": { "base_ref": "main" },
  "merge": { "dedup_line_range": 5 },
  "report": { "keep_history": 10 }
}
```

| Setting | Description |
|---------|-------------|
| `enabled` | Skip this reviewer when `false` |
| `timeout` | Per-reviewer timeout in seconds |
| `model` | Claude model (`sonnet` / `haiku` / `opus`) |
| `max_budget_usd` | Claude per-run cost cap |
| `base_ref` | Default comparison branch |
| `dedup_line_range` | Line range tolerance for deduplication (±N) |
| `keep_history` | Reports to keep per project |

## Architecture

```
bin/
├── ai-multi-review          # Main entry point
└── ai-multi-review-eval     # Review quality evaluation (Python)
lib/
├── common.sh                # Git operations, config, timeout, prompt building
├── merge.sh                 # Cross-reviewer deduplication + confidence merge
├── report.sh                # Terminal + Markdown report generation
└── review-schema.json       # JSON output schema (with confidence)
prompts/
├── review-system.md         # System prompt (10 review criteria)
└── review-user.md           # User prompt (output schema)
reviewers/
├── claude.sh                # Claude Code adapter
├── codex.sh                 # OpenAI Codex adapter
├── coderabbit.sh            # CodeRabbit adapter
├── gemini.sh                # Gemini CLI adapter
├── aider.sh                 # Aider adapter (skeleton)
├── opencode.sh              # OpenCode adapter (skeleton)
└── gh-copilot.sh            # GitHub Copilot adapter (skeleton)
examples/
├── sample-report.md         # Full report example
├── sample-issues.json       # Issues JSON example
└── human-verdict-template.json  # Eval verdict template
```

## Editor Integration

### Claude Code

```
/ai-multi-review              # Run review
/fix-review latest             # Fix issues from latest report
```

### Codex CLI

```bash
codex exec "$(cat ~/.codex/instructions/fix-review.md) $(cat path/to/issues.json)"
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add a new reviewer or contribute code.

## License

MIT
