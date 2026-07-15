# Security Policy

MacTorn is a native macOS menu bar app that reads your Torn account data through the
official Torn API. It is **read-only** — it never performs actions in Torn — and it
keeps all data on your Mac.

## Supported versions

Security fixes are applied to the latest released version. There is no back-porting to
older versions; please update to the newest release before reporting an issue.

| Version | Supported |
| ------- | --------- |
| Latest release (see [CHANGELOG](CHANGELOG.md)) | ✅ |
| Older | ❌ — please update first |

## Reporting a vulnerability

Please report security issues **privately** — do not open a public GitHub issue for a
vulnerability.

- Preferred: [GitHub private vulnerability reporting](https://github.com/pawelorzech/MacTorn/security/advisories/new)
  (Security → Report a vulnerability).
- Alternatively: email **pawel@orzech.me** with `MacTorn security` in the subject.

Please include:

- affected version (from the app's About/Settings or the release tag),
- macOS version and architecture (Apple Silicon / Intel),
- a description of the issue and, where possible, steps to reproduce,
- the impact you believe it has.

**Do not include your Torn API key, full request URLs containing a `key`, or raw API
responses** in a report — they are secrets/PII. A redacted description is enough.

You can expect an acknowledgement within about a week. Fixes are prioritised by
severity; once a fix ships you'll be credited in the changelog unless you prefer to
remain anonymous.

## What MacTorn does to protect you

These properties are verified by the test suite and CI, and are covered in detail in
[`SECURITY_AUDIT.md`](SECURITY_AUDIT.md):

- **API key in the Keychain.** The key is stored in the macOS Keychain
  (`kSecClassGenericPassword`, accessible after first unlock), never in plaintext
  `UserDefaults`.
- **No secrets or PII in logs.** Request URLs are redacted to
  `scheme://host/path?[sorted-query-keys]` before logging — the key and query values
  never reach `os_log`. Player name, money and stats are never logged.
- **App Sandbox + Hardened Runtime.** The app runs sandboxed with only the
  `network.client` entitlement and Hardened Runtime enabled.
- **HTTPS only.** All traffic to `api.torn.com` uses TLS via the system trust store
  (ATS defaults; no arbitrary loads). Certificate pinning is intentionally **not**
  used (documented accepted risk F-05).
- **Untrusted-input handling.** Watchlist input is validated/clamped; server-supplied
  strings are sanitised (control chars stripped, length capped) before they appear in
  notifications; API error envelopes (v1 and v2) are surfaced, not swallowed.
- **Opt-in crash reporting.** Sentry is **off by default** and only enabled if you
  explicitly opt in. It is a separate, optional mechanism from anything above.

## Scope

In scope: the MacTorn app, its build/release tooling, and its CI workflows.

Out of scope: the Torn API itself and Torn's own infrastructure (report those to Torn),
and social-engineering or physical-access attacks. The audit assumes the
verified-absent attack surface listed in `SECURITY_AUDIT.md` §A (no URL schemes,
WebView, XPC, IPC, AppleScript, file-open handlers, or third-party runtime
dependencies beyond Sentry). Adding any of those requires a re-audit.
