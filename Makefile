SHELL := bash
.PHONY: lint test check

BATS    := test/test_helper/bats-core/bin/bats
SHELL_SRCS := bin/ai-multi-review \
              lib/common.sh lib/merge.sh lib/report.sh lib/progress.sh \
              reviewers/claude.sh reviewers/codex.sh reviewers/coderabbit.sh \
              reviewers/gemini.sh reviewers/aider.sh reviewers/opencode.sh \
              reviewers/gh-copilot.sh \
              install.sh

lint:
	shellcheck $(SHELL_SRCS)

test:
	$(BATS) test/merge.bats test/common.bats test/report.bats
	python3 -m pytest test/test_eval.py -v

check: lint test

.DEFAULT_GOAL := check
