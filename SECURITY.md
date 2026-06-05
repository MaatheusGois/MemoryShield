# Security Policy

## Supported Versions

Only the latest released version of MemoryShield receives security fixes.

| Version | Supported |
| ------- | --------- |
| latest  | ✅        |
| older   | ❌        |

## Reporting a Vulnerability

If you believe you have found a security vulnerability in MemoryShield, please **do not open a public issue**. Instead:

1. Email the maintainer privately at **matheusgoiscampelo@gmail.com** with:
   - A description of the issue and its impact
   - Steps to reproduce (proof-of-concept welcome)
   - The affected version / commit
   - Your name and any disclosure preferences
2. You should receive an acknowledgement within **72 hours**.
3. We aim to provide an initial assessment within **7 days** and a fix or mitigation within **30 days** for confirmed issues, depending on severity and complexity.

Please give us a reasonable window to investigate and release a fix before disclosing publicly. Coordinated disclosure is appreciated and credit will be given in the release notes unless you prefer to remain anonymous.

## Scope

In scope:
- The MemoryShield macOS app source in this repository
- Build scripts (`Makefile`, `fastlane/`) that produce release artifacts

Out of scope:
- Vulnerabilities in macOS itself or in third-party tooling (Xcode, Fastlane, Ruby, Homebrew)
- Issues that require an already-compromised local account with admin privileges

## Hardening notes

MemoryShield uses `kill(2)` on user processes when auto-kill is enabled. It never escalates privileges and does not touch processes outside the invoking user's session. If you spot a way for an unprivileged caller to influence which PID is targeted, that is in scope.
