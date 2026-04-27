# MacTorn Security Audit — Plan

## Context

User pasted a generic web/mobile/API pentest prompt. **MacTorn is a native macOS SwiftUI menu bar app with no server, no DB, no auth flow we control** — it's a desktop client that holds a long-lived Torn.com API key and talks to `api.torn.com`. The threat model is fundamentally narrower than the OWASP web baseline.

**Goal:** end up with an app that is hardened against realistic threats for its actual shape — local credential theft, log/diagnostics leakage, MITM, supply-chain weakness, distribution tampering — and document each finding with a PoC-style reproduction, surgical fix, and verification step.

The Explore phase already produced findings and severities; this plan defines the execution order and the per-finding output format.

## Scope

### In scope (applicable to a native macOS client)
1. Local credential storage (Keychain vs UserDefaults)
2. Log hygiene / diagnostics leakage
3. Network: HTTPS posture, ATS, certificate pinning (optional)
4. Input validation at trust boundaries (Torn API responses, watchlist input)
5. Code signing, notarization, Hardened Runtime, App Sandbox, entitlements
6. Dependency / supply chain (currently zero third-party deps)
7. CI/CD: workflow secrets, `pull_request_target` abuse, artifact signing
8. Repository hygiene: `.gitignore`, committed binaries, secret scanning of full git history
9. Update channel integrity (no auto-update today — distribution tampering risk)
10. URL handler / IPC surface (currently empty — confirm and gate)

### Out of scope (prompt sections not applicable to MacTorn)
SQL/NoSQL/LDAP/XPath/template/ORM injection, SSRF, CSRF, GraphQL, WebSocket auth, OAuth/OIDC/JWT, OWASP API Top 10 (server-side), GDPR data subject flows, K8s/Docker/Helm hardening, WAF/CDN, multi-tenant isolation, mass assignment, deserialization gadgets (we use `JSONDecoder` over JSON only). These will be explicitly listed as "N/A — no server" in the report rather than silently skipped.

## Methodology

Adapt OWASP MASVS (desktop-relevant subset) + Apple Platform Security guide + CWE Top 25 (memory/credential subset). Per-finding format:

```
### F-NN  <Title>
Severity: Critical | High | Medium | Low | Informational
CWE: CWE-NNN
File: path:line
Evidence: <quoted code snippet or shell output>
Reproduction: <minimal PoC — shell command, plutil dump, log capture, etc.>
Impact: <what an attacker gets>
Fix: <surgical patch — exact API to use, exact file to change, NO rearchitecture>
Verification: <command/test that proves the fix and absence of regression>
Defense in depth: <optional second layer>
```

## Findings already mapped (from Phase 1 Explore)

These are confirmed by the Explore agents with file:line refs. The execution phase will write them up in the format above and produce fixes.

### Critical

- **F-01  API key stored in plaintext UserDefaults** — `MacTorn/MacTorn/ViewModels/AppState.swift:26` uses `@AppStorage("apiKey")`. Lands in `~/Library/Preferences/com.mactorn.app.plist`, readable via `plutil -p` without prompts. CWE-312, CWE-522. Fix: migrate to Keychain via a small `KeychainStore` wrapper around `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete` with `kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlock`. Wrap in an `@Observable` (or property wrapper) bridge so SwiftUI bindings still work. Migrate-on-launch from UserDefaults, then wipe the UserDefaults key.

- **F-02  API key leaks into os_log via URL prefix(80)** — `MacTorn/MacTorn/ViewModels/AppState.swift:759` logs `url.absoluteString.prefix(80)`. Torn API keys are 16 chars, the base URL `https://api.torn.com/user/?selections=...&key=` is comfortably under 64 chars, so the key lands in the log. CWE-532. Fix: log only the path + selections, never `absoluteString`. Helper: `func redact(_ url: URL) -> String` that takes `host + path + sorted query keys without values`. Replace at every log site that touches a URL (AppState lines 759, 780, 604, 668, plus anywhere `error` is logged with the request URL).

### High

- **F-03  No Hardened Runtime / App Sandbox / entitlements** — `MacTorn.xcodeproj/project.pbxproj` sets `ENABLE_HARDENED_RUNTIME = NO`; no `.entitlements` file exists. CWE-693. Fix: enable Hardened Runtime (Release at minimum), add `MacTorn.entitlements` with App Sandbox + `com.apple.security.network.client` only, and (only if Sandbox + Keychain interaction is verified working) enable sandbox. If sandbox breaks Keychain across launches, document the trade-off and ship Hardened Runtime alone first, sandbox in a follow-up.

- **F-04  Ad-hoc signed releases, no Developer ID** — `Makefile` uses `CODE_SIGN_IDENTITY="-"`. Direct-download distribution means users get Gatekeeper warnings AND can't verify publisher. CWE-345. **Confirmed scope:** Developer ID signing only, **no notarization** (user does not have App Store Connect API key for `notarytool`). Fix: add a `release-signed` target that uses `CODE_SIGN_IDENTITY="Developer ID Application: ..."` + `--options runtime` (Hardened Runtime, see F-03). Document the cert lookup in `new-version` skill. Keep ad-hoc target for local dev. **Caveat to document in README:** without notarization, Gatekeeper on Sequoia+ will still warn on first-launch; users must right-click → Open. This is an improvement over ad-hoc (publisher is verifiable) but not the full fix. Add notarization as a follow-up once API key is available.

- **F-05  No certificate pinning for api.torn.com** — system trust store only; a compromised CA or local MITM proxy (Charles, mitmproxy with installed CA) sees plaintext API key. CWE-295. Fix proposal (defense in depth, not blocking): implement `URLSessionDelegate.urlSession(_:didReceive:completionHandler:)` with public-key pinning against Torn's leaf SPKI. Risk: Torn rotates cert → app breaks. Mitigation: pin the issuing intermediate (Cloudflare/Let's Encrypt) instead of leaf, ship with two pins, plus a kill-switch via build flag. **Recommend: defer; document as "accepted risk" in this audit and revisit if Torn ever offers a stable cert/intermediate.**

### Medium

- **F-06  String-interpolated URLs** — `MacTorn/MacTorn/Models/TornModels.swift:960-985` builds URLs with `\(apiKey)`, `\(itemId)`, `\(threadId)`, `\(selections)`. `itemId` and `threadId` are `Int` (low risk). `apiKey` is user-provided plaintext (could contain `&`, spaces if pasted with whitespace). CWE-20. Fix: use `URLComponents` + `URLQueryItem`. Adds proper percent-encoding, kills any chance of query-pollution if a key is pasted with junk.

- **F-07  No input validation on watchlist `itemId`** — `AppState.swift:344 addToWatchlist(itemId:name:)` takes any `Int` and any `String`, persists to UserDefaults, and reuses in API URLs. Fix: clamp `itemId` to plausible Torn item-id range (Torn item IDs are positive and <100000 today) and trim/length-cap `name` (e.g., 64 chars).

- **F-08  Notification body uses unsanitized server fields** — `AppState.swift:241, 466, 640, 1055` interpolate `travel.destination`, `item.name`, forum `title` directly into `UNNotificationContent.body`. Not exploitable as XSS (UNNotification renders plaintext) but a MITM or compromised Torn API can spoof local notifications. CWE-79 variant (low). Fix: length-cap (e.g., 200 chars), strip control characters, and prefer fixed prefixes (`"Travel:"`, `"Forum:"`) before any server-supplied substring.

### Low / Informational

- **F-09  `JSONDecoder` errors swallowed with `try?`** — `AppState.swift:839-841` uses `try? JSONDecoder().decode(...)` for the main user response. Failures appear as silent no-data states, not security holes, but mask malformed responses. Fix: log decode error class + JSON keys (NEVER values), surface a "stale data" indicator.

- **F-10  `.DS_Store` and old release zip in history** — `git log` shows `.DS_Store` and `MacTorn-1.5.1.zip` were committed; current `.gitignore` excludes future ones. Fix: leave history alone (rewriting history breaks downloaded clones); add explicit lines for `*.p12`, `*.cer`, `*.mobileprovision`, `.env`, `*.xcarchive` to `.gitignore` for future hygiene.

- **F-11  CI workflows use Claude OAuth token** — `.github/workflows/claude.yml`, `claude-code-review.yml` use `${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}`. Triggers are `issue_comment`, `pull_request_review`, `issues`, `pull_request` (NOT `pull_request_target`, confirmed). Acceptable. Informational only — recommend `permissions: contents: read` minimum and `concurrency` group.

- **F-12  No auto-update channel** — manual download. Not a finding per se, but means users may run vulnerable old versions indefinitely. Out of scope for this audit; flag for product roadmap.

### Verified non-issues (explicit "no" answers — silence is worse than confirmation)

- No URL schemes, deep links, AppleEvents handlers, WebView, XPC, NSDistributedNotifications, local listener, drag-and-drop, pasteboard reads, subprocess spawning. Confirmed by Explore agent. → Whole categories of macOS attack surface are absent. Document this so future contributors know adding any of these reopens the audit.
- Zero third-party Swift Package Manager / CocoaPods / Carthage / vendored framework dependencies. Confirmed (no `Package.swift`, no `Podfile`). → Supply-chain attack surface is essentially the Xcode toolchain + system frameworks.
- All API URLs HTTPS; no `NSAllowsArbitraryLoads`. → Baseline transport security in place.

## Phased execution

**Phase A — Recon write-up.** Emit a one-page architecture + trust-boundary diagram (in markdown) so the rest of the report has a shared vocabulary. Inputs: this plan + the three Explore reports.

**Phase B — Static analysis pass.** Tools to run (read-only):
- `gitleaks detect --source . --no-banner` (full history, including blobs)
- `trufflehog filesystem .` for entropy-based detection
- `semgrep --config p/swift --config p/security-audit` for Swift static rules
- `xcrun swift-format lint --strict` (style, not security, but flags some footguns)
- `codesign -dvvv` + `spctl --assess --verbose` against the latest release artifact (if reachable)
- Manual `grep -rn` for: `print(`, `NSLog`, `os_log`, `Logger.*\.(info\|debug\|error)`, `try?`, `as!`, `unsafeBitCast`, `withUnsafeBytes`, `URLSession`, `apiKey`, `key=`, `Bearer`.

**Phase C — Per-finding write-up.** For each F-NN above, produce the structured block (Severity / CWE / File / Evidence / Reproduction / Impact / Fix / Verification / Defense in depth).

**Phase D — Threat model (STRIDE-lite).** One paragraph each for Spoofing (notification spoofing, distribution spoofing), Tampering (binary tampering, plist tampering), Repudiation (N/A — no audit log requirement), Information disclosure (key in defaults, key in logs, key in URL — covered by F-01/F-02), DoS (Torn API rate-limit handling — confirm exponential backoff exists; if not, F-13), Elevation of privilege (N/A — runs as user, no helper).

**Phase E — Fix execution.** Order by severity, smallest blast radius first. **Surgical edits only — do not rearchitect AppState, do not collapse files, do not touch view-layer code unless directly leaking data.** Each fix is one PR-sized commit. **Confirmed scope: execute all fixes except F-05.**

1. F-02 redact-URL helper + replace log sites (single helper, mechanical replace) — lowest risk
2. F-06 URLComponents migration in `TornAPI` enum (5 functions, isolated)
3. F-07 watchlist input clamps (one function)
4. F-08 notification body sanitization helper + 4 replace sites
5. F-09 surface decode errors via `try ... catch` + structured log
6. F-10 `.gitignore` additions
7. F-11 add `permissions: contents: read` + `concurrency` group to Claude workflows
8. F-01 `KeychainStore` + migration shim — bigger, last among code changes because it touches the SwiftUI binding pattern
9. F-03 entitlements file + Hardened Runtime build setting (Release config first; Debug optional)
10. F-04 `release-signed` Makefile target — Developer ID Application **only**, no notarytool. User confirmed they have the cert but not the API key. Add a `make release-signed DEVELOPER_ID="Developer ID Application: NAME (TEAMID)"` invocation; codesign with `--options runtime --timestamp`. Document in README that first-launch Gatekeeper warning still applies until notarization is added.

F-05 (cert pinning) deferred — document as accepted risk.

**Phase F — Verification matrix.** For each fix:
- F-01: `plutil -p ~/Library/Preferences/com.mactorn.app.plist | grep -i key` → empty. `security find-generic-password -s com.mactorn.app -a apiKey` → present. App still polls successfully.
- F-02: `log stream --predicate 'subsystem CONTAINS "MacTorn"' --info --debug` while polling → no API key substring in any line. Add a unit test that takes a known key, runs the redactor, asserts the key is not in the output.
- F-03: `codesign -d --entitlements - /Applications/MacTorn.app` shows sandbox + network.client; `codesign -dvv` shows runtime flag set.
- F-04: `codesign -dvv build/MacTorn.app` shows `Authority=Developer ID Application: ...` (not `Authority=-`). `spctl --assess --verbose=4` will report `rejected (the code is signed but no notarization)` — this is **expected** given the no-notarytool decision; document the expected output rather than treating it as a regression.
- F-06: unit test that passes a key containing `&`, `=`, ` ` and asserts the resulting URL parses cleanly with the original key in the `key` query item.
- F-07: unit test rejecting itemId ≤ 0 and ≥ 100000, accepting valid range.
- F-08: unit test feeding a destination string with newlines / 500 chars / control bytes; assert notification body is single-line and ≤200 chars.

**Phase G — Defense in depth checklist.** After fixes:
- Add a `SECURITY.md` with disclosure contact + supported versions.
- Add a CI step `gitleaks` + `semgrep` on every PR (block-on-finding for `gitleaks`, advisory for `semgrep`).
- Add `Package.resolved` once any first dep is added (currently none → no-op today).
- Document the Keychain access group in CLAUDE.md so future test code uses the test-only group, not the prod one.

## Critical files

Reference (read-only during analysis, edited only in Phase E):

- `MacTorn/MacTorn/ViewModels/AppState.swift` — main mutation site (F-01, F-02, F-07, F-09)
- `MacTorn/MacTorn/Models/TornModels.swift:953-985` — URL builders (F-06)
- `MacTorn/MacTorn/Utilities/NotificationManager.swift` + AppState notification call sites — F-08
- `MacTorn/MacTorn/Info.plist` — F-03
- `MacTorn/MacTorn.xcodeproj/project.pbxproj` — F-03 (`ENABLE_HARDENED_RUNTIME`)
- `Makefile` — F-04 (release-signed target)
- `.gitignore` — F-10
- `.github/workflows/*.yml` — F-11
- (new) `MacTorn/MacTorn/Utilities/KeychainStore.swift` — F-01
- (new) `MacTorn/MacTorn/Utilities/URLRedactor.swift` — F-02
- (new) `MacTorn/MacTorn.entitlements` — F-03
- (new) `SECURITY.md` — Phase G

## Reusable existing utilities

- `NetworkSession` protocol (`MacTorn/MacTorn/Networking/NetworkSession.swift`) — already provides DI seam; no need to add abstractions for testing the redactor or URL builder.
- `MockNetworkSession` (`MacTornTests/Mocks/`) — verification tests can reuse.
- `TornAPIFixtures` (`MacTornTests/Fixtures/`) — fixture base for malformed-response decode tests.

## Verification (end-to-end)

```
make clean && make test            # unit tests, including new redactor/keychain/url tests
make release                       # ad-hoc dev build still works
# After F-04 lands, on a Mac with Developer ID cert:
make release-signed
codesign -dvv build/MacTorn.app
spctl --assess --verbose=4 build/MacTorn.app   # expect: accepted; source=Notarized Developer ID
xcrun stapler validate build/MacTorn.app       # expect: validated
# Smoke run:
open build/MacTorn.app
log stream --predicate 'subsystem == "com.mactorn"' --info --debug \
  | grep -E '[A-Za-z0-9]{16}' || echo "no 16-char tokens in logs ✓"
plutil -p ~/Library/Preferences/com.mactorn.app.plist | grep -i 'key' \
  && echo "FAIL: secret in defaults" || echo "✓ no secret in defaults"
security find-generic-password -s com.mactorn.app -a apiKey -w >/dev/null \
  && echo "✓ secret in keychain" || echo "FAIL: secret not in keychain"
```

## What this plan deliberately does NOT do

- Rewrite AppState into a different architecture (MVVM-C, TCA, etc.) — out of scope, would violate "surgical fixes only".
- Add cert pinning (F-05) — accepted risk, documented.
- Add an auto-update channel (F-12) — separate product decision.
- Rewrite git history to remove the legacy `MacTorn-1.5.1.zip` — would break existing clones for nobody's net benefit.
- Add Sparkle/Squirrel — see F-12.
- Touch any UI/view-layer code beyond the four notification body call sites.

## Note on prompt truncation

Your pasted prompt cuts off at "**FORMAT WYJŚCIOWY (per znalezisko)**" — the per-finding output format wasn't shown. I've adopted the format above (Severity / CWE / File / Evidence / Reproduction / Impact / Fix / Verification / Defense in depth). If you have a specific template, paste it and I'll swap.
