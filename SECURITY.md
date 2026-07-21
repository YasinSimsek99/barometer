# Security Policy

## Supported versions

Barometer is pre-1.0. Security fixes are applied to the latest tagged release and `master`.

## Reporting a vulnerability

Do not open a public issue containing exploit details, sensitive paths, settings, or Claude data. Use GitHub’s **Security → Report a vulnerability** private reporting form for this repository.

Include:

- the affected commit or version;
- the macOS and Claude Code versions;
- a minimal reproduction using synthetic data;
- impact and any suggested mitigation.

Do not include real prompts, transcripts, tokens, cookies, or account data. We aim to acknowledge a report within seven days. Timelines for fixes and disclosure will be coordinated with the reporter.

## Security invariants

- No Claude credential, cookie, OAuth token, or API key is requested or read.
- No network request is made by the running application or bridge.
- Only sanitized rate-limit percentages, reset times, and capture metadata may be persisted.
- Installation never uses `sudo`, clears quarantine attributes, or disables Gatekeeper.
- Source installations refuse to run as root and launch-at-login uses only the current user's LaunchAgents directory.
- Disconnect never overwrites a status-line configuration it does not own.
- Signing certificates and notarization credentials are stored only as encrypted CI secrets or in the maintainer's local keychain; they are never committed, logged, or embedded in shipped artifacts.

These invariants are release blockers. A pull request that changes one must update the threat model and receive explicit security review.
