# Security Policy

## Supported Versions

| Version | Supported |
|---|---|
| v0.1.x | Yes |
| < v0.1.0 | No |

## Reporting a Vulnerability

1. Do not disclose vulnerabilities in public issues.
2. Use GitHub Security Advisory draft first.
3. If advisory is unavailable, contact maintainers through organization channels with:
   - impact summary
   - reproduction steps
   - affected scripts/versions
   - mitigation suggestion

We will acknowledge within 3 business days and provide a triage plan.

## Security Baseline

1. Avoid embedding any real host credential in scripts or docs.
2. Keep sample paths generic placeholders.
3. Prefer non-admin SSH account for daily operations.
4. Review command safety before batch execution.
