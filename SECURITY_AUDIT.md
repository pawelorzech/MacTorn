# MacTorn — Security Audit (2026-04-27)

Auditor: in-session security review (read-only static analysis + surgical fixes).
Scope: branch `main`, HEAD `245228d` (v1.8.6).
Plan: `Plans/prompt-security-audit-wise-pearl.md`.

## TL;DR

| ID   | Severity      | Title                                                     | Status |
| ---- | ------------- | --------------------------------------------------------- | ------ |
| F-01 | Critical      | API key in plaintext UserDefaults                         | Fixed  |
| F-02 | Critical      | API key leaks into `os_log` via `url.absoluteString.prefix(80)` | Fixed  |
| F-03 | High          | Hardened Runtime disabled, no entitlements                | Fixed  |
| F-04 | High          | Ad-hoc signed releases, no Developer ID                   | Accepted risk — `release-signed` target ready in Makefile; user opted not to enroll separate paid Apple Developer Program ($99/yr). Cocolab cert exists but user prefers to keep MacTorn unaffiliated. Revisit if/when a personal Apple Developer Program is set up. |
| F-05 | High          | No certificate pinning for `api.torn.com`                 | Accepted risk (deferred) |
| F-06 | Medium        | String-interpolated URLs in `TornAPI`                     | Fixed  |
| F-07 | Medium        | No input validation on watchlist `itemId` / `name`        | Fixed  |
| F-08 | Low           | Notification body uses unsanitized server fields          | Fixed  |
| F-09 | Low           | Outer `JSONDecoder` errors swallowed silently             | Fixed  |
| F-10 | Informational | `.gitignore` doesn't exclude signing material / `.env`    | Fixed  |
| F-11 | Informational | Claude workflows had scoped permissions but no concurrency | Fixed  |
| F-12 | Informational | No auto-update channel                                    | Out of scope |

All fixes are committed under this audit. 156 unit tests pass after changes (`make test`). Release build still compiles, codesign confirms `flags=0x10002(adhoc,runtime)` (Hardened Runtime on) and embedded entitlements (sandbox + `network.client`).

## A. Recon — architecture & trust boundaries

```
┌─────────────────────────────────────────────────────────────────┐
│  MacTorn.app  (LSUIElement, MenuBarExtra)                       │
│                                                                 │
│  ┌────────────┐    ┌─────────────────┐    ┌──────────────────┐  │
│  │ SettingsView│──▶│ AppState        │──▶│ NetworkSession    │  │
│  │ (input key) │   │ @MainActor      │    │ (URLSession or    │  │
│  └────────────┘    │ KeychainStore   │    │  injected mock)   │  │
│                    └─────────────────┘    └────────┬─────────┘  │
│                                                    │            │
│                    ┌─────────────────┐              │            │
│                    │ NotificationMgr  │              │            │
│                    │ (sanitized text) │              │            │
│                    └─────────────────┘              │            │
└────────────────────────────────────────────────────┼────────────┘
                                                     │ HTTPS
                                                     ▼
                                              api.torn.com (TLS 1.2+,
                                              system trust store,
                                              no pinning — F-05 accepted)
```

Trust boundaries:
1. **User input → app state.** Settings input is the only place a user types into the app. The pasted Torn API key is the only secret; the watchlist `itemId`/`name` are also user input. Input is validated/clamped at this boundary (F-07).
2. **Torn API → app state.** All response data is treated as untrusted. Decoder errors are surfaced (F-09); strings rendered to user UI (notifications) are sanitized for length + control chars (F-08).
3. **App → log subsystem.** `os_log` output may be captured by Console.app, sysdiagnose, or remote diagnostic tooling. The redactor (F-02) ensures URLs (which contain the API key) and identifying PII (player name) never reach logs.
4. **App → keychain / preferences.** API key lives in Keychain (`kSecClassGenericPassword`, accessible after first unlock) — F-01. Non-secret prefs (refresh interval, watchlist, appearance) remain in UserDefaults.

Verified-absent attack surface (whole categories that simply do not apply):
- No URL schemes, deep links, AppleEvents handlers
- No WebView (`WKWebView`/`SFSafariViewController`)
- No XPC, Mach ports, distributed notifications, local listener
- No subprocess spawning, AppleScript, NSTask
- No file open handlers, drag-and-drop receivers, pasteboard reads
- No third-party Swift Package Manager / CocoaPods / Carthage / vendored framework dependencies
- No iCloud sync of UserDefaults (`NSUbiquitousKeyValueStore`)
- No backend, no DB, no auth flow we control — entire OWASP web baseline (SQLi/SSRF/CSRF/GraphQL/JWT/OAuth/etc.) is N/A

If a future contributor adds any of the above, the audit must be re-run for that path.

## B. Static analysis tools attempted

| Tool        | Status                  |
| ----------- | ----------------------- |
| gitleaks    | Not installed locally; manual `grep` on history performed instead — no real secrets found |
| trufflehog  | Not installed; entropy scan deferred to CI hardening (Phase G recommendation) |
| semgrep     | Not installed; manual review of all `print/NSLog/os_log/Logger`, `try?`, `as!`, `unsafeBitCast`, `URL(string:`, `apiKey`, `key=` matches in Swift sources |
| codesign    | Run on Release artifact post-fix — confirms `flags=0x10002(adhoc,runtime)` and embedded entitlements |

Recommendation: add `gitleaks` and `semgrep --config p/swift` to the existing `tests.yml` workflow (Phase G).

## C. Findings

Format per finding:
- **Severity** / **CWE**
- **File:line**
- **Evidence** (code snippet quoted from pre-fix)
- **Reproduction** (PoC command, where applicable)
- **Impact**
- **Fix** (file + change description, link to commit / current state)
- **Verification** (test or command)
- **Defense in depth**

---

### F-01  API key stored in plaintext UserDefaults  *(Critical, CWE-312, CWE-522)*

**File:** `MacTorn/MacTorn/ViewModels/AppState.swift:26` (pre-fix).
**Evidence:**
```swift
@AppStorage("apiKey") var apiKey: String = ""
```
**Reproduction:** With the previous build installed and an API key configured:
```
$ plutil -p ~/Library/Preferences/com.mactorn.app.plist | grep -i apikey
"apiKey" => "AbCdEfGhIjKlMnOp"
```
Any unprivileged process running as the user can read this — no auth prompt, no Keychain dialog.
**Impact:** Full read access to the user's Torn account (faction data, money, properties, stats, attack history) for an attacker with local user-level access (malware, shoulder-surf, stolen unlocked Mac).
**Fix:** Replaced `@AppStorage` with a `@Published var apiKey` whose `didSet` writes through to a Keychain-backed store (`KeychainStore` in `AppState.swift`, lines ~10–95). Items use `kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlock`, service `com.mactorn.app`, account `apiKey`. On `init`, any pre-existing `apiKey` in UserDefaults is migrated and the UserDefaults entry removed (idempotent, safe to run every launch).
**Verification:**
- `KeychainStoreTests.testKeychain_setAndGetRoundtrip` and friends (added in `MacTornTests/Models/TornResponseTests.swift`) — pass.
- After running the app once with a key configured: `plutil -p ~/Library/Preferences/com.mactorn.app.plist | grep -i key` is empty; `security find-generic-password -s com.mactorn.app -a apiKey -w` returns the key.
**Defense in depth:** `kSecAttrAccessibleAfterFirstUnlock` ensures the keychain is locked when the user is logged out. If we later add `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, an attacker cannot extract the keychain via a sysdiagnose / iCloud Keychain backup path.

---

### F-02  API key leaks into `os_log` via `url.absoluteString.prefix(80)`  *(Critical, CWE-532)*

**File:** `MacTorn/MacTorn/ViewModels/AppState.swift:760` (pre-fix), and a related raw-response log at `:794`, plus a player-name log at `:929`.
**Evidence:**
```swift
logger.info("Starting data fetch from: \(url.absoluteString.prefix(80))...")
// and:
logger.debug("Raw API response: \(jsonString.prefix(500))")
// and:
logger.info("Parsed data - Name: \(decoded.name ?? "nil"), Life: ...")
```
The Torn API request URL is `https://api.torn.com/user/?selections=basic,bars,...&key=<KEY>`. The base path + selections fits well under 80 characters, so the 16-char API key lands in the prefix. The `Raw API response` log dumps the first 500 chars of the JSON response, which contains player name, money, stats, attack history.
**Reproduction:** With pre-fix build:
```
$ log stream --predicate 'subsystem CONTAINS "MacTorn"' --info --debug
... Starting data fetch from: https://api.torn.com/user/?selections=...&key=AbCdEfGh ...
... Raw API response: {"player_id":..., "name": "PlayerName", "money": ..., ...}
```
Console.app, `log show --last`, and any sysdiagnose tarball would all expose these.
**Impact:** Same as F-01 — full account credential disclosure — but via a different channel (logs / diagnostic capture). PII (name, money) also leaks.
**Fix:**
- Added `tornRedactedURL(_:)` in `MacTorn/MacTorn/Models/TornModels.swift` (after `TornAPI`). Returns `scheme://host/path?[sorted-query-keys]` — values are dropped entirely.
- Replaced the leaky URL log call at `AppState.swift:760` with `logger.info("Starting data fetch from: \(tornRedactedURL(url))")`.
- Replaced the raw-JSON log at `AppState.swift:794` with a size + top-level keys summary.
- Removed the player-name log at `:929`; non-identifying state and life remain for diagnostics.
**Verification:** `TornRedactedURLTests` (5 tests in `MacTornTests/Models/TornResponseTests.swift`) — pass. Smoke check after fix:
```
$ log stream --predicate 'subsystem == "com.mactorn.app"' --info --debug | head -5
... Starting data fetch from: https://api.torn.com/user?[key,selections]
... API response: 8217 bytes, keys=[attacks,bars,battlestats,cooldowns,...]
... Parsed data — Life: 1000/1000, State: Okay
```
No 16-char tokens in the stream.
**Defense in depth:** The redactor is the canonical API; all future log calls touching URLs must use it. Consider adding a `semgrep` rule `pattern: $LOGGER.$M("...$ANY... \(url.absoluteString)$ANY...)` to `tests.yml` to fail CI on regressions.

---

### F-03  Hardened Runtime disabled, no entitlements  *(High, CWE-693)*

**File:** `MacTorn/MacTorn.xcodeproj/project.pbxproj` (Debug + Release configs for the app target, pre-fix).
**Evidence:**
```
CODE_SIGN_ENTITLEMENTS = "";
ENABLE_HARDENED_RUNTIME = NO;
```
**Impact:** Without Hardened Runtime, the binary is opted out of macOS process protections (no library-validation, allow-unsigned-executable-memory implicitly true, etc.). Without an `App Sandbox` entitlement, the app has the full ambient permission of the user — it can read files outside the app's container, talk to any process, and so on.
**Fix:**
- Created `MacTorn/MacTorn/MacTorn.entitlements` with `com.apple.security.app-sandbox = true` and `com.apple.security.network.client = true`.
- Updated both Debug and Release build configs to set `CODE_SIGN_ENTITLEMENTS = MacTorn/MacTorn.entitlements` and `ENABLE_HARDENED_RUNTIME = YES`.
**Verification:**
```
$ codesign -dvv build/Build/Products/Release/MacTorn.app
CodeDirectory ... flags=0x10002(adhoc,runtime) ...
$ codesign -d --entitlements - build/Build/Products/Release/MacTorn.app
... com.apple.security.app-sandbox = true ...
... com.apple.security.network.client = true ...
```
`make test` (156 tests) and `make release` both pass with the new settings — the test target inherits the entitlements via `BUNDLE_LOADER` and works under sandbox.
**Defense in depth:** Periodically run `codesign -d --entitlements - <app>` in CI and assert no `disable-library-validation`, `disable-executable-page-protection`, `cs.allow-jit`, `cs.allow-unsigned-executable-memory`, or `automation.apple-events` entitlements have crept in.

---

### F-04  Ad-hoc signed releases, no Developer ID  *(High, CWE-345 — accepted risk)*

**File:** `Makefile` (pre-fix).
**Evidence:** `release` target uses `CODE_SIGN_IDENTITY="-"`. Distributed `MacTorn-1.5.1.zip` (committed in git) is ad-hoc signed.
**Impact:** Users can't verify the publisher; Gatekeeper warns on first run; tampering between build and download is undetectable.
**Status:** Accepted risk (user decision, 2026-04-27).
**Why deferred:** Developer ID Application certificates require a **paid** Apple Developer Program ($99/yr). The user has access to a Cocolab corporate Developer Program but prefers to keep MacTorn unaffiliated with that legal entity — and does not currently want to enroll a separate personal program just for this app. Without Developer ID, signing meaningfully (and notarization on top of that) is not achievable.
**What we did anyway:** Added a `release-signed` target in `Makefile` that takes a `DEVELOPER_ID` env var and signs with `--options=runtime --timestamp`. The infrastructure is ready; only the cert is missing. If the user later decides to enroll, the only step is:
```
make release-signed DEVELOPER_ID="Developer ID Application: NAME (TEAMID)"
```
**Mitigations remaining in place:**
- Hardened Runtime is on (F-03), so library-injection / unsigned-memory attack surface is reduced even on ad-hoc binaries.
- App Sandbox is enabled (F-03), capping what a tampered binary can do post-launch.
- Distribution via GitHub Releases over HTTPS — TLS integrity from build machine to user.
- Users get a clear Gatekeeper warning, which is itself a (weak but non-zero) signal.
**Re-open trigger:** If a paid Apple Developer Program (personal or new entity) is set up. Also re-open if the threat model expands (e.g., wider distribution / non-technical user base).

---

### F-05  No certificate pinning for api.torn.com  *(High, CWE-295 — accepted risk, deferred)*

**Impact:** A compromised/rogue CA, or a local MITM proxy with an installed CA cert, can intercept TLS to api.torn.com and read the API key in plaintext (URL query string).
**Decision:** **Defer.** Pinning Torn's leaf cert risks app breakage on rotation; pinning the issuing intermediate (Cloudflare) is more robust but still couples to operational decisions outside our control. There is no published Torn pinning policy. Re-evaluate if Torn ever offers a stable cert / public key.
**Mitigations already in place:** HTTPS-only, system trust store (TLS 1.2+ enforced by ATS defaults — no `NSAllowsArbitraryLoads` in `Info.plist`).

---

### F-06  String-interpolated URLs  *(Medium, CWE-20)*

**File:** `MacTorn/MacTorn/Models/TornModels.swift:953-984` (pre-fix).
**Evidence:**
```swift
URL(string: "\(baseURL)?selections=\(selections)&key=\(apiKey)")
```
A pasted API key containing `&`, `=`, or whitespace produces a malformed URL with no encoding error. `itemId` and `threadId` are typed `Int` so they are not exploitable as injection vectors, but the pattern is fragile.
**Fix:** Migrated all six TornAPI URL builders to a private `build(_:query:)` helper that uses `URLComponents` + `URLQueryItem` with proper percent-encoding.
**Verification:** `TornAPIURLBuilderTests` (4 tests) — pass. Notably `testURL_percentEncodesKeyWithReservedChars` proves a key like `"ab&cd=ef gh"` round-trips through the `key` query item exactly.

---

### F-07  No input validation on watchlist `itemId` / `name`  *(Medium, CWE-20)*

**File:** `MacTorn/MacTorn/ViewModels/AppState.swift:344` (pre-fix).
**Evidence:** `addToWatchlist(itemId:name:)` accepts any `Int` and any `String`, persists both to UserDefaults, and reuses the values in API URL paths and notification text.
**Fix:** Reject `itemId <= 0` and `itemId >= 100_000` (Torn item IDs are positive, currently <100k); trim and 64-char-cap `name`.
**Verification:** `AppStateWatchlistTests.testAddToWatchlist_rejectsZeroAndNegativeIds`, `_rejectsImplausiblyLargeIds`, `_trimsAndCapsName` — pass.

---

### F-08  Notification body uses unsanitized server fields  *(Low — defense in depth)*

**File:** `MacTorn/MacTorn/ViewModels/AppState.swift:241, 466, 640, 1055` (pre-fix).
**Evidence:** Server-supplied strings (`travel.destination`, `item.name`, forum thread title) are interpolated directly into `UNNotificationContent.body`. Not exploitable as XSS (UNNotification renders plaintext), but a MITM or compromised Torn API can spoof multi-line / oversized notifications.
**Fix:** Centralized in `NotificationManager.send` and `.scheduleNotification` — both now run user-visible strings through `NotificationManager.sanitize(_:maxLength:)` which strips control characters and caps length (80 for title, 200 for body). Single chokepoint, every existing call site benefits without per-call changes.
**Verification:** `NotificationSanitizerTests` (3 tests) — pass.

---

### F-09  Outer `JSONDecoder` errors swallowed silently  *(Low — diagnostic-only)*

**File:** `MacTorn/MacTorn/ViewModels/AppState.swift:841` (pre-fix).
**Evidence:** `let decodedTornResponse = try? JSONDecoder().decode(TornResponse.self, from: data)` — every decode failure becomes `nil` with no log entry.
**Fix:** Replaced with explicit `do { try ... } catch DecodingError.{keyNotFound, typeMismatch, valueNotFound, …}` blocks, each logging the error class + JSON key path (NEVER values, since values are PII).
**Note:** The many `try?` patterns in `TornModels.swift` (`TornModels.swift:381-411` etc.) are deliberate defensive defaults for optional API fields — kept as-is. F-09 is specifically about the outer envelope decode.
**Verification:** Existing `TornResponseTests` continue to pass; no new test added because the change is observability-only.

---

### F-10  `.gitignore` doesn't exclude signing material / `.env`  *(Informational)*

**File:** `.gitignore`.
**Fix:** Added explicit lines for `*.p12`, `*.cer`, `*.pem`, `*.key`, `*.mobileprovision`, `*.provisionprofile`, `.env`, `.env.*`, `*.xcarchive`, `*.zip`, `*.dmg`, `*.pkg`, `ExportOptions.plist`. History was not rewritten — `MacTorn-1.5.1.zip` and historical `.DS_Store` entries remain in past commits but no new entries can sneak in.

---

### F-11  Claude workflows had scoped permissions but no concurrency  *(Informational)*

**File:** `.github/workflows/claude.yml`, `.github/workflows/claude-code-review.yml`.
**Note:** Both workflows already used least-privilege `permissions:` blocks (read-only on contents/PRs/issues, `id-token: write` for OIDC). Neither uses `pull_request_target`. No real vulnerability; the original plan called this informational.
**Fix:** Added `concurrency:` group to both — prevents duplicate runs on rapid event bursts. `claude-code-review.yml` cancels in-progress (per-PR review supersedes earlier ones); `claude.yml` does not cancel (preserves per-comment responsiveness).

---

### F-12  No auto-update channel  *(Informational, out of scope)*

Manual download model means users may run vulnerable old builds indefinitely. Adding Sparkle / Squirrel.Mac is a separate product decision. Flagged for the roadmap.

## D. Threat model — STRIDE-lite

**Spoofing**
- *Notification spoofing:* a MITM can inject arbitrary text into Torn API responses, causing fake "Landed in X" or "Forum: Y" notifications. F-08 caps length and strips control chars, limiting impact to text spoofing only.
- *Distribution spoofing:* without notarization (F-04 partial), a tampered .zip cannot be distinguished from genuine — users have no Apple chain-of-trust signal. Mitigated when F-04 follow-up adds notarytool.

**Tampering**
- *Binary tampering:* Hardened Runtime (F-03) blocks library injection / unsigned-memory execution. Without notarization, post-build tampering of the .zip is detected only by user vigilance (re-checking codesign manually). Notarization closes this gap.
- *Plist tampering:* with F-01 fixed, the app's UserDefaults plist no longer holds the secret. Tampering with non-secret prefs (refresh interval, watchlist) cannot escalate.

**Repudiation** — N/A. No multi-user audit log requirement; the app is single-user, no shared state.

**Information disclosure**
- *Local credential theft:* plaintext key in UserDefaults — closed by F-01 (Keychain).
- *Diagnostic capture:* API key + PII in os_log — closed by F-02 (redactor).
- *Network capture:* unrelated CA / MITM with installed cert — partially open (F-05 deferred). Only system-trust-store CAs apply; HTTPS + ATS defaults are in place.

**Denial of service** — Torn API rate-limit handling: `AppState.fetchData` checks for HTTP error codes and surfaces `errorMsg`. There is no exponential backoff; bursts of "Refresh" clicks could trigger 429s. Out of scope for a security audit but worth noting (low severity, self-DoS only).

**Elevation of privilege** — N/A. Runs as user; no helper tool, no SUID, no XPC.

## E. Verification matrix

| Fix  | Verification command / test                                                                     | Pass |
| ---- | ----------------------------------------------------------------------------------------------- | ---- |
| F-01 | `KeychainStoreTests.*`; `plutil -p ~/Library/Preferences/com.mactorn.app.plist` shows no `apiKey` | ✓    |
| F-02 | `TornRedactedURLTests.*`; `log stream` smoke check for 16-char tokens                           | ✓    |
| F-03 | `codesign -d --entitlements -` on Release artifact shows sandbox + network.client; `flags=...,runtime` | ✓    |
| F-04 | Accepted risk — `release-signed` target exists, no cert available; ad-hoc release continues to work | n/a    |
| F-06 | `TornAPIURLBuilderTests.*`                                                                      | ✓    |
| F-07 | `AppStateWatchlistTests.testAddToWatchlist_rejects*`                                            | ✓    |
| F-08 | `NotificationSanitizerTests.*`                                                                  | ✓    |
| F-09 | Existing `TornResponseTests.*` still pass (no behavior regression)                              | ✓    |
| F-10 | `git check-ignore -v *.p12 *.env` returns matches                                               | ✓    |
| F-11 | `.github/workflows/*.yml` contain `concurrency:` blocks                                          | ✓    |

Full suite: **156 unit tests pass** (`make test` → `** TEST SUCCEEDED **`).

## F. Defense in depth — recommended follow-ups

1. **CI secret/SAST scan.** Add `gitleaks detect --source . --redact` and `semgrep --config p/swift --config p/security-audit` as steps in `.github/workflows/tests.yml`. `gitleaks` blocks on finding; `semgrep` advisory.
2. **Developer ID + notarization for releases.** Requires paid Apple Developer Program. When/if enrolled, generate a Developer ID Application cert, run `make release-signed DEVELOPER_ID=...`, then add `xcrun notarytool submit ... --wait` + `xcrun stapler staple` to the target. Closes F-04 fully.
3. **`SECURITY.md`** with disclosure contact + supported versions.
4. **Re-audit trigger.** This audit assumes the verified-absent attack surface listed in §A. Adding URL schemes, WebView, XPC, IPC, AppleScript, file open handlers, drag-and-drop, or any third-party dependency requires re-running the relevant sections.

## G. What was NOT done (deliberately)

- F-05 cert pinning — accepted risk.
- F-12 auto-update — out of scope (product roadmap).
- Git history rewrite to drop `MacTorn-1.5.1.zip` and historical `.DS_Store` — would break clones for no real benefit (no real secrets in those blobs).
- Architecture refactor of `AppState` (still ~1100 lines, single class) — out of scope per "surgical fixes only" guidance.
- Test target file split / new test files — kept tests piggybacked on `TornResponseTests.swift` to avoid `pbxproj` edits beyond the entitlements path.
