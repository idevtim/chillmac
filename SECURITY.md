# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.4.x   | :white_check_mark: |
| < 1.4   | :x:                |

Only the latest release receives security updates.

## Reporting a Vulnerability

**Please do not open a public issue for security vulnerabilities.**

Instead, email **security@idevtim.com** with:

- A description of the vulnerability
- Steps to reproduce
- Your ChillMac version and macOS version

You can expect an initial response within 48 hours. If the vulnerability is confirmed, a fix will be prioritized and released as soon as possible. You'll be credited in the release notes unless you prefer to remain anonymous.

## Scope

ChillMac includes a privileged helper daemon that runs as root and communicates over XPC. Security issues in the following areas are especially relevant:

- XPC connection validation and code signature checks
- SMC write operations via the helper daemon
- Privilege escalation through the helper
- Network requests (update checker)
