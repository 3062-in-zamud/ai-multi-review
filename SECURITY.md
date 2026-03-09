# Security Policy

## Supported Versions

Only the latest release is actively supported with security fixes.

| Version | Supported |
|---------|-----------|
| latest  | ✅ |
| older   | ❌ |

## Reporting a Vulnerability

Please use [GitHub Security Advisories](https://github.com/3062-in-zamud/ai-multi-review/security/advisories/new) to report vulnerabilities **privately**.
Alternatively, you may contact the maintainer directly at 3062.in.zamud@gmail.com.

Do not report security issues through public GitHub Issues.

**Response timeline:**
- Acknowledgement: within 48 hours
- Resolution: within 30 days

## Security Considerations

ai-multi-review sends your code diff to external LLM APIs (e.g., Claude, Gemini, OpenAI) for review. Be aware of the following:

- **Do not use ai-multi-review on diffs containing secrets**, credentials, or sensitive personal data.
- Review the [diff preview with `--dry-run`](README.md) before sending to LLMs if you are unsure what will be transmitted.
- Each configured reviewer's API terms of service governs how your code is handled by that provider.
