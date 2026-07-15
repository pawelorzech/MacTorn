# Changelog

All notable changes to MacTorn will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] — reliability & product audit (stage 1)

Branch `audit/reliability-product-pass`. First stage of the Etap A–L quality program;
the full plan and deferred backlog live in [`ISA.md`](ISA.md).

### Fixed
- **Chain-expiring notification fired on every poll.** While a chain's timeout was under
  60 s, "Chain Expiring! ⚠️" was re-sent on *every* refresh (a burst of identical
  banners). It now fires **exactly once** per crossing into the danger window and
  re-arms only after the chain leaves it (a member hits, the chain ends, or it drops),
  via a new persistent `NotificationCoordinator` whose de-dup survives an app restart.
- **Flaky unit test / non-deterministic suite.** `AppState` hardcoded
  `UserDefaults.standard`, so watchlist tests raced on the shared store under parallel
  execution (`testPriceThreshold_persistedWithWatchlist` failed intermittently on
  `main`). `AppState` now takes an injectable `UserDefaults`; each test isolates its own
  suite. The suite is green and deterministic across 8 parallel runners.

### Added
- **Typed Torn API registry** (`TornEndpoint` / `TornEndpointRegistry`): one catalog of
  all 10 endpoints (version, path, selections, access level, cadence, point-in-time vs
  row-based, record limit, cache policy, budget category, critical/optional). It drives
  request building, the README "API Data Usage" table and onboarding disclosure — a
  contract test pins every registry URL to its legacy `TornAPI` builder so they can't
  drift.
- **Typed error taxonomy** (`TornAPIError`): classifies Torn error codes (permanent key,
  insufficient permissions, rate limit, daily row limit, temporary backend) plus
  transport states (offline / transport / malformed / cancelled), with `haltsAllRequests`
  (codes 2/16/18) and `haltsCategoryOnly` (code 14) semantics and a `RetryPolicy`
  exponential backoff (2/5/15/30/60 s, capped at 5 min, jittered). Wiring into the live
  fetch path is deferred (ISA ISC-15).
- **`SECURITY.md`** — private vulnerability disclosure policy and supported-version note.
- **`ISA.md`** — system-of-record for the audit program with the full A–L backlog and
  deferral reasons.

### Added — Etap D (polling budget + reconnect)
- **API budget accounting** (`PollingCoordinator`): every request-issuing path records
  against a rolling requests/min + requests/day count and per-category rows/day (driven
  by the typed registry), with a conservative 60/min hard cap that no path bypasses. This
  makes the usage that caused error 14 (v1.9.2) measurable and bounded.
- **Immediate refresh on reconnect.** After a network outage, MacTorn refreshes once as
  soon as connectivity returns (on the genuine down→up edge) instead of waiting up to a
  full refresh interval.
- **Shared testable clock** (`TimeSource`) behind the budget windows — also the clock the
  upcoming "Next Action" timeline will use.
- The **15s** refresh option is now labelled **"15s aggressive"** with a note that Torn
  may serve cached data for ~30s, so 15s can spend API budget for no fresher data.

### Added — Etap F (diagnostics)
- **Diagnostics screen** (Settings → Diagnostics): app/macOS/architecture, network and
  notification-permission state, whether an API key is configured and the access level
  it needs, last successful refresh, live request/record budget counters, and
  per-endpoint outcome/latency/size.
- **"Copy sanitized report"** — a clipboard snapshot that is PII-safe by construction:
  it never contains the API key, full URLs, player name/ID, money, stats,
  faction/company names, or raw payloads.

### Added — Etap J (Next Action)
- **Next Action timeline.** A new card at the top of the Status tab shows the single
  soonest thing to happen — bars filling, cooldowns ending, travel landing, hospital/jail
  release, education finishing, OC becoming ready, chain timeout, or refills waiting —
  with a live countdown, plus the list of what follows. All times come from one shared,
  testable clock. Pick which categories appear in **Settings → Next Action**.

### Added — Etap G (deterministic UI tests + hardened CI)
- **Hermetic UI-test harness.** Launched with `--uitesting`, the app builds itself from
  fixtures and test doubles — a URL-routed fake network session, an isolated `UserDefaults`,
  an in-memory Keychain (so a UI test never touches your real Torn key), and controllable
  connectivity — and surfaces the menu-bar content in a real window the test runner can
  drive. Real UI tests now cover onboarding-without-a-key, tab navigation, and invalid-key
  error surfacing. This is developer-facing only: it is fully DEBUG-gated, so the Release
  app carries none of the fixture/harness code.
- **UI tests gate merges.** The CI UI-test job no longer swallows failures
  (`continue-on-error` removed).
- **Coverage gate.** CI fails if any reliability-critical module (API error taxonomy,
  endpoint registry, polling/notification coordinators, Next Action engine) drops below
  80% line coverage. SwiftUI views are excluded — they're validated by the UI-test suite.
  Also available locally via `make coverage-gate`.

### Changed — reliability closures (Etap B/F follow-ups)
- **A daily read-limit no longer stalls unrelated data.** If Torn returns "daily read limit
  reached" (error 14) for a row-based feed (activity, faction news), MacTorn now pauses just
  that feed for an hour and keeps everything else — bars, cooldowns, travel, the chain
  counter — updating live. Previously the whole faction/activity overlay could be affected.
- **Diagnostics now cover the whole poll.** Endpoint health (last outcome, latency, size) is
  recorded for every endpoint the app polls (faction, activity, v2 user, ranked wars, news),
  not only the fast user poll — so a "Copy sanitized report" is more useful when something's
  off. (Rarely-called market/forum/stocks calls are a small follow-up.)

### Added — Etap C (key validation & onboarding)
- **Test Connection.** Onboarding (Settings) gains a "Test Connection" button that checks
  your API key against Torn's official key-info endpoint and tells you exactly what it
  unlocks: your access type (e.g. Full Access), your player ID, and — if the key is Limited
  or Custom — precisely which features won't load. No more guessing why a tab is empty.
- **Clearer data & privacy disclosure.** The "API Data Usage & Privacy" section now states
  the required access level, that your key is stored in the macOS Keychain (never plaintext),
  that all Torn data stays on your Mac, that crash reporting is opt-in, and lists the exact
  selections requested — generated from the app's endpoint registry so it can't drift.

### Fixed — Etap B (stop retrying a dead key)
- **A bad or paused API key now halts polling** instead of retrying forever. When Torn
  returns a permanent key/permission error (codes 2 / 16 / 18), MacTorn stops the poll
  loop, shows the specific message, and stays stopped even when the menu re-opens —
  until you change the key. Previously it showed "API Error: …" and kept hammering the
  dead key every cycle. Transient errors (rate limit, backend) are unaffected.

### Notes
- 77 new unit tests since `main` (330 total, all green). The one existing test that
  encoded the old "keep retrying a dead key" behaviour was updated to the new halt
  contract; no other feature behaviour changed. CI's Release build was also un-broken
  (Xcode 16 for `Package.resolved` v3).

## [1.9.2] - 2026-07-15

### Fixed
- **"API Error: Daily read limit reached" (Torn error code 14).** MacTorn was tripping Torn's *per-category* cloud-data cap — 50,000 rows/day (rolling 24 h) for row-based categories like `events`, `attacks` and faction `news` — which is a completely separate limit from the 100-requests/minute rate limit (the app was never close to that one). The single `user/` poll bundled `events` **and** `attacks` (up to ~100 rows each, no `limit`) and ran every 30 s around the clock: ~288,000 rows/day/category, roughly 5–6× over the cap, so any one category alone would trip error 14. Faction `news` (every 60 s) piled on a second over-quota category.
  - The fast poll (refresh interval, default 30 s) now carries **only point-in-time selections** (`basic,bars,cooldowns,travel,profile,money,battlestats,properties,stocks`) — no row-based categories — so it can't touch the daily cap. All live bars, cooldown/travel countdowns and notifications are unchanged.
  - `events`, `messages` and `attacks` moved to a **separate slow call** (every 5 min) with a hard `limit=25`, and faction ranked-wars/news moved from a 60 s to a 5 min gate (also `limit=25`). Net: ~288k → ~7k rows/day/category, with comfortable headroom even at the 15 s refresh floor. Events/attacks/messages now refresh every few minutes instead of every 30 s — they're display-only, so no functional loss.

## [1.9.1] - 2026-07-03

### Performance
- **Throttle the heaviest faction API calls.** The ranked-war (~15 KB) and news (~23 KB) v2 calls added in 1.9.0 are the largest in a poll cycle and change slowly, but were fetched every poll — as often as every 15 s. A 60 s time-based gate now fetches them at most once per minute regardless of the refresh interval (still runs on the first poll so the Faction tab populates immediately), cutting ~150 KB/min of near-static traffic at the 15 s floor. No user-visible change.

## [1.9.0] - 2026-07-03

Audit of MacTorn's Torn API usage against the live v2 OpenAPI spec (6.0.0) and real API responses. API v1 is frozen (not sunset) — every selection MacTorn relies on still returns its v1 shape — but two selections had drifted out from under the client, and v2 opened up four new signals worth surfacing. Plan: `Plans/sprawd-czy-si-nie-ticklish-rivest.md`.

### Fixed
- **Faction Organized Crimes were silently empty.** After Torn made Organized Crimes 2.0 mandatory faction-wide (~Feb 2025), the v1 `faction/?selections=crimes` selection returns only frozen pre-migration OC-1.0 *history* (0 active crimes, newest from Feb 2025), and its `initiated` field flipped from Bool to Int — so the client's all-or-nothing decode dropped every crime. The test fixture used `"initiated": false` (a Bool), so the suite stayed falsely green. The dead OC-1.0 list is gone; the app now shows the player's **own current OC 2.0** via v2 `/user?selections=organizedcrime` — a "ready in Xh" timer, status, slots filled, and your own progress — verified against a live response.
- **Cooldown countdowns weren't anchored to server time.** The client anchored drug/medical/booster end-times on a top-level `timestamp` field, but the live v1 user root returns `server_time` (top-level `timestamp` only appears with the `timestamp` selection, which we don't request). So `serverTimestamp` was always nil and the countdowns silently fell back to the local Mac clock — defeating the clock-skew correction they were built for. Now decodes `server_time` with a legacy `timestamp` fallback.

### Added
- **Your Organized Crime 2.0 status** in the Faction tab: name, difficulty, live "ready in" countdown, slots filled, and your own progress bar — plus an OC-ready notification. The modern replacement for the removed faction OC-1.0 list.
- **Dailies card** in the Status tab: which daily refills (energy / nerve / token) you still have to claim, and a live completion timer for an in-progress education course.
- **Bounty-on-you alert.** A red badge in the Status tab and a notification when someone places a bounty on you (`/user?selections=bounties`).
- **Faction ranked war + news.** The Faction tab shows the active ranked war as a lead-vs-target progress bar (your faction vs the opponent) and a feed of recent faction news (`/v2/faction/rankedwars`, `/v2/faction/news?cat=main`).

All four user-side signals ride a single combined v2 `/user` call. Also hardened the test network mock against a data race on concurrent fetches. 253 unit tests, all green.

## [1.8.13] - 2026-06-04

### Fixed
- **Surface Torn API v2 errors on the market and forum endpoints instead of swallowing them.** The v2 endpoints (`/v2/market/{id}`, `/v2/forum/{id}/thread`, `/v2/forum/{id}/threads`) return errors as `{"code":Int,"error":String}` — `error` is a top-level string — per the official Torn OpenAPI spec. The client only recognised the legacy v1 envelope (`{"error":{"code","error"}}`), so every v2 API error (rate-limit code 5, incorrect key code 2, access-level-too-low, etc.) slipped through undetected: a rate-limited watchlist item showed up as "No listings", and a rate-limited forum check parsed into a bogus "Unknown" thread with post count 0, corrupting watch state. A new `tornAPIErrorMessage(in:)` helper recognises both envelopes and is now used at all six API error-parse sites. Added contract tests for both envelope shapes plus integration tests proving the market and forum paths surface v2 rate-limit / incorrect-key errors.

## [1.8.12] - 2026-05-25

### Fixed
- **Stop spamming Sentry with macOS "App Hanging" false positives.** Sentry-Cocoa enables `AppHangTracking` by default with a 2-second threshold. For a `MenuBarExtra` app that's whatever-it-wants-to-be most of the time, normal macOS scenes — display wake, fence creation in `+[CAFenceHandle newFenceFromDefaultServer]`, `CGSPostLocalNotification` in SkyLight — routinely block the main thread for >2 s and are captured as application errors. Both unresolved issues against 1.8.10/1.8.11 (MACTORN-2, MACTORN-3) had **zero in-app frames** — pure `mach_msg2_trap` → AppKit/QuartzCore/SkyLight system traces, nothing actionable in MacTorn code. Now `options.enableAppHangTracking = false`. Real crashes and explicit `SentrySDK.capture()` calls still report normally. Same noise-reduction rationale as v1.8.11's `enableCaptureFailedRequests = false`.

## [1.8.11] - 2026-05-12

### Fixed
- **Stop spamming Sentry with upstream Torn API 5xx errors.** Sentry-Cocoa 9.x defaults `enableCaptureFailedRequests` to `true`, which auto-captures any URLSession response with a 500–599 status as an application error. When Torn API returned 504 Gateway Timeout (upstream overload, not a MacTorn bug), Sentry reported it as a MacTorn error — 71 such events from 6 users landed against 1.8.10. Now `enableCaptureFailedRequests = false`. Crashes and explicit `SentrySDK.capture()` calls still report normally. The code change was present from commit `e54fc80`, but tag `v1.8.10` was cut before that commit, so the binary in users' hands didn't include it — `v1.8.11` is the actual rollout of the fix.

## [1.8.10] - 2026-04-30

### Fixed
- **Booster/drug/medical countdown no longer jumps on every poll.** v1.8.9 fixed the long-term clock-skew drift by storing absolute end-timestamps (`endsAt = serverTimestamp + duration`), but each ~30 s API poll still re-derived `endsAt` from a fresh integer-second `serverTimestamp` and integer-second `cooldowns.{kind}` pair. API rounding plus network-latency variance made the recomputed value wobble by ±1–3 s vs the previous one, which the menu bar rendered as a visible jump on every refresh. `CooldownEnds.merged(with:toleranceSeconds:)` now pins each `*EndsAt` across polls when the freshly computed value is within ±3 s; larger gaps are treated as a real cooldown reset (new booster/drug/medical) and adopt the new value. Transitions in/out of active (0 ↔ nonzero) are always immediate so the countdown starts/clears without delay. Travel/hospital/jail are unaffected — they already receive absolute Unix epochs from the API and don't have this jitter. Plan: `MacTorn/Plans/ca-y-czas-mam-taki-quiet-crescent.md`.

## [1.8.9] - 2026-04-30

### Fixed
- **Drift-free cooldown countdowns.** Booster/medical/drug countdowns previously drifted by ~30 s vs torn.com because we stored the API's *relative* duration and subtracted `Date().timeIntervalSince(fetchTime)` locally each tick — any Mac↔server clock skew compounded into a constant offset. Now we convert each cooldown into an absolute Unix end-timestamp at fetch time (`endsAt = serverTimestamp + duration`) and every view computes `max(0, endsAt − now)`. New `CooldownEnds` value type owns the conversion; `Cooldowns.soonestActive(from:)` was replaced with `CooldownEnds.soonestActive()`. Travel, hospital, jail, and chain countdowns already used absolute timestamps and are unchanged. Plan: `Plans/wszystkie-czasy-kt-re-s-dazzling-bumblebee.md`.
- Faction Chain timer: switched from a one-shot string render of `chain.timeout` to a per-second `TimelineView`, so the chain countdown now ticks live like every other countdown in the app.

### Added
- **Opt-in crash + error reporting via Sentry.** Off by default. After upgrading, users see a one-time prompt explaining the option; the toggle also lives in Settings (`Send crash reports`). When enabled, only crashes and unhandled errors are sent — no performance traces, no replays, no `sendDefaultPii`. URLs in events and breadcrumbs run through the existing `tornRedactedURL` so the Torn API key never leaves the device. Project: `mactorn` on `mactorn.sentry.io` (DE region).
- New `SentryManager` (`Utilities/SentryManager.swift`) that owns SDK lifecycle and PII scrubbing; new `SentryOptInPromptView` overlay shown once per upgrade.

## [1.8.8] - 2026-04-27

### Performance
- **Live timer no longer churns SwiftUI every second.** The 1 Hz countdown that drives the menu bar label and the travel countdown now skips `@Published`/Observation writes when the displayed value hasn't changed (e.g. cooldowns shown as `Hh Mm` only mutate every ~60 s). Removes per-second invalidation cascade across `MenuBarLabel`, header, and TravelView.
- **Polling no longer restarts on every menu open.** `MenuBarExtra` fires `onAppear` on each popover open; previously each open cancelled the timer and immediately re-fetched. `startPolling()` now no-ops when a timer is already running and the last fetch is < `refreshInterval / 2` old. `refreshNow()` keeps an explicit `force: true` bypass for the user-initiated refresh button. Same guard added to `startForumPolling()`.
- **Watchlist threshold notifications are now batched.** When the periodic watchlist refresh sees ≥ 2 items cross their price threshold in a single pass, a single summary notification (`"3 price alerts: Xanax, Plushie +1 more"`) is emitted instead of N separate banners. Single-item add-to-watchlist still fires individually.
- **Forum poll short-circuits unchanged threads.** `checkThreadForUpdates` returns early when the post count is unchanged since the last poll, skipping the notification path and the post-count write entirely.
- **Stocks metadata retry uses exponential backoff (60 s → 300 s → 1800 s cap).** Previously a persistent `torn/?selections=stocks` failure was retried on every 30 s main poll, burning API quota. Backoff resets on success.
- **Release build is now stripped end-to-end.** `SWIFT_OPTIMIZATION_LEVEL=-O`, `DEAD_CODE_STRIPPING=YES`, `DEPLOYMENT_POSTPROCESSING=YES`, `STRIP_INSTALLED_PRODUCT=YES`, `STRIP_STYLE=all` are now explicit on the project-level Release config (previously relying on Xcode defaults; `DEPLOYMENT_POSTPROCESSING` was off, so the binary that ended up in `build/Build/Products/Release/MacTorn.app` was not actually stripped on a plain `make release`).

### Changed
- **`AppState` migrated from `ObservableObject` + `@Published` to `@Observable` (Observation framework, macOS 14+).** SwiftUI now invalidates only the views that actually read a changed property — previously a single fetch cycle wrote 7 `@Published` properties and triggered 7 invalidation rounds across every view that observed `AppState`. All 11 views switched from `@EnvironmentObject` to `@Environment(AppState.self)`; `MacTornApp` switched from `@StateObject` to `@State`; `SettingsView` uses `@Bindable` to keep the existing `$appState.refreshInterval` Picker binding.
- `@AppStorage("refreshInterval")` and `@AppStorage("appearanceMode")` on `AppState` replaced with stored properties + `didSet` write-through to `UserDefaults` (required because `@AppStorage` is a SwiftUI property wrapper and doesn't compose with `@Observable`). Behavior unchanged: same UserDefaults keys, same defaults, persistence across launches preserved.

### Tests
- New `AppStatePerformanceTests` records `JSONDecoder` baselines via `XCTest.measure` for full-response and stocks-metadata parsing, plus a regression guard for the stocks backoff ladder.

## [1.8.7] - 2026-04-27

### Security
- **API key now stored in macOS Keychain** instead of plaintext UserDefaults (`~/Library/Preferences/com.mactorn.app.plist`). On first launch the app migrates any existing key automatically and clears the old plist entry. Service: `com.mactorn.app`, account: `apiKey`, accessible after first unlock.
- **Stop leaking the API key into `os_log`/Console.** All log statements that referenced a request URL now run through a redactor that emits `scheme://host/path?[sorted-query-keys]` with values dropped. The previous `url.absoluteString.prefix(80)` was exposing the 16-character key to anyone reading Console / sysdiagnose. Also removed raw API response and player-name diagnostic logs.
- **Hardened Runtime + App Sandbox + entitlements** enabled on Debug and Release. Network access is the only granted entitlement (`com.apple.security.network.client`).
- **TornAPI URL builders** now use `URLComponents` + `URLQueryItem` instead of string interpolation — keys with `&`, `=`, or whitespace are percent-encoded correctly.
- **Watchlist input clamped** at the trust boundary: `itemId` must be in `(0, 100000)`, `name` is trimmed and capped at 64 chars.
- **Notification text sanitized** centrally in `NotificationManager.send`/`scheduleNotification` — strips control characters, length-caps title (80) and body (200) so a MITM'd or compromised Torn API can't spoof multi-line notifications.
- **Decoder failures** at the outer envelope are now logged with key path + error class instead of being silently swallowed.
- **`.gitignore` hardened** against accidental commit of signing material (`*.p12`, `*.cer`, `*.mobileprovision`), `.env`, and release archives.
- **CI workflows:** added `concurrency:` groups to the Claude code-review workflows (least-privilege `permissions:` were already in place).

Full audit and per-finding breakdown: `SECURITY_AUDIT.md` in the repo root. Distribution model is unchanged (ad-hoc signed direct download — Gatekeeper warning on first launch is expected; right-click → Open).

## [1.8.6] - 2026-04-26

### Added
- **Dynamic menu bar status text** — the menu bar label now adapts to player state instead of always showing a static icon:
  - **Traveling** → ✈️ + country flag + remaining travel time *(unchanged)*
  - **Hospitalized abroad** → 🏥 + country flag + hospital countdown
  - **Hospitalized in Torn** → 🏥 + hospital countdown
  - **Jailed in Torn** → 🚓 + jail countdown
  - **Idle with active cooldowns** → soonest-expiring cooldown with type emoji: 💊 Drug, 🧪 Booster, 🩹 Medical
  - **Idle, no cooldowns** → falls back to the existing `bolt`/`bolt.fill`/`globe`/error icon
- Live 1-second countdown extended from travel-only to all of the above states; computed from server timestamps where available (`travel.timestamp`, `status.until`) and adjusted against the last fetch time for relative cooldown values.

### Changed
- `MenuBarLabel` is now a thin renderer over a centralized `MenuBarDisplay` enum on `AppState`, replacing the inline travel-only conditional. Priority order: traveling > hospital (abroad/home) > jail > soonest cooldown > fallback icon.

## [1.8.5] - 2026-04-18

### Fixed
- **Stocks metadata never loaded** — `startPolling()` fired before `apiKey` was hydrated from `@AppStorage`, the once-per-session flag flipped, and `fetchStocksMetadata` short-circuited forever. Replaced the flag with an idempotent check (`stocksMetadata.isEmpty && !apiKey.isEmpty`) that retries every poll tick until it succeeds.
- **Property "Upkeep" was misleading (round 2)** — verified against the real Torn API: `upkeep` is a per-day RATE that only applies when you currently reside in the property, not a debt. For properties owned but not lived in (`status: "Owned by them"`), the user pays $0 even though the field returns $100,000. Removed `upkeep` and `staff_cost` from the UI entirely; surface `status` instead.

### Changed
- Property cards now show `status` (e.g., "Owned by them") + `marketprice` + `cost` + happy bonus. "Rented" badge clarified as "Rented out" since it means rented to another player.


### Fixed
- **Stocks metadata parsing failed silently** — `torn/?selections=stocks` returns extra fields (`director`, `forecast`, `demand`, `benefit`, etc.) that broke the strict `Decodable` decoder. Replaced with `JSONSerialization`-based parser that tolerates unknown fields and reports the specific failure mode (network error vs API error vs missing key) to the log.
- **Property "Upkeep" was misleading** — Torn API's `upkeep` field is "money owed for upkeep" (accrued debt), not the upkeep rate. Relabeled to "Owed" in the Money tab and "Upkeep due" in the Properties tab, only shown when > 0.

## [1.8.3] - 2026-04-18

### Fixed
- **Stocks $0 cost basis** — `transactions` field comes back from Torn API as a dict keyed by transaction_id, not an array. The decoder silently swallowed the type mismatch via `try?` and returned $0 for every holding. Now decodes both shapes.
- **Properties section empty** — code mapped to a non-existent `money` field. Replaced with real Torn API fields: `cost`, `marketprice`, `upkeep`, and `rented` (with days remaining).

### Added
- **Stock names + market value** — fetches `torn/?selections=stocks` once per session and caches to UserDefaults. Each stock now shows its acronym + name and current market value (`shares × current_price`) instead of "Stock #N" with $0.
- **Property cost / upkeep / rent badge** — each property card now shows market price, weekly upkeep, purchase cost, and a "Rented Nd" badge when applicable.

### Internal
- `feedbackResponded*` now no-ops under XCTest so test runs don't open mail/forum.

## [1.8.2] - 2026-04-12

### Changed
- Removed faction forum auto-monitoring (Torn API does not expose private faction forum threads)
- Faction forum threads can still be watched by pasting their URL/ID manually
- Fixed "Faction Forum" quick link to correctly open the user's faction forum page

## [1.8.1] - 2026-04-12

### Fixed
- Fixed faction forum monitoring using wrong category ID (was using faction ID instead of discovering the actual forum category)
- Faction forum category is now discovered by matching faction name against forum categories API
- Toggling faction monitor off now resets cached data for clean rediscovery

## [1.8.0] - 2026-04-12

### Added
- Forum Watch tab — track Torn forum threads for new posts directly from the menu bar
- Add threads by pasting forum URL or thread ID
- Per-thread notification toggle (on = alerts, off = bookmark/shortcut only)
- Faction forum auto-monitoring — toggle to detect and notify about new faction forum threads
- Separate forum polling interval (2m / 3m / 5m), independent of main data refresh
- Click any watched thread to open it in your browser

## [1.7.1] - 2026-04-12

### Changed
- Return flight now shows 🏠 (home) instead of 🇺🇸 in menu bar when flying back to Torn

### Added
- Private Island setting — players with a private island can set 🏝️ as their return icon instead of 🏠

## [1.7.0] - 2026-04-11

### Added
- Bazaar price alerts — set price thresholds on watchlist items, get notified when price drops below
- Organized Crime timer — live countdown for active OCs in Faction tab with ready notification
- Net worth dashboard — enhanced Money tab showing cash, properties, and stock holdings breakdown
- TRI Hub quick link — one-click access to hub.tri.ovh from Quick Links

### Changed
- Money tab now shows comprehensive net worth with properties and stocks sections
- Faction API now fetches organized crime data
- User API now fetches stock holdings data
- Updated deployment target to macOS 14.0 (macOS 13 no longer receives security updates)

### Fixed
- Fixed deprecated onChange(of:) API usage for macOS 14+
- Fixed redundant await on @MainActor calls
- Fixed NetworkMonitor.shared nonisolated default parameter (Swift 6 preparation)

## [1.6.0] - 2026-03-14

### Added
- Cooldown quick action buttons: when a cooldown reaches Ready, the cell becomes a clickable button that opens the corresponding Torn Items page (drugs, medical, boosters/alcohol)
- New "Booster cooldown link" setting to choose between Boosters and Alcohol item page
- Accessibility support for cooldown action buttons (VoiceOver labels and hints)

## [1.5.1] - 2026-02-04

### Added
- Expanded browser support in browser picker with additional browser options

## [1.5.0] - 2026-02-04

### Added
- Preferred browser support for opening Torn links (system default browser selection)
- GitHub Actions integration with Claude Code for automated PR assistance and code review
- BrowserManager utility for managing browser preferences across the app

### Changed
- Improved link handling to respect user's default browser choice

## [1.4.7] - 2026-01-27

### Added
- In-app feedback prompt with smart timing (1 hour, 1 week, 1 month thresholds)
- Positive feedback links to Torn forums thread
- Negative feedback opens email for direct developer contact
- 5-minute cooldown between prompt dismissals
- Comprehensive test coverage for feedback logic

## [1.4.6] - 2025-01-25

### Fixed
- Fixed incorrect "Released" notification triggering when landing from travel
- "Released! 🎉 - You are now free" notification now only fires when released from Hospital or Jail, not when arriving from airplane travel

## [1.4.5] - 2025-01-25

### Fixed
- Improved travel timer accuracy by using API timestamp directly instead of calculating from fetch time offset
- Travel countdown now stays synchronized regardless of network delays or fetch timing

### Added
- Comprehensive test coverage for travel timer calculations

## [1.4.4] - Previous Release

### Fixed
- Resolve Swift concurrency errors by extracting MainActor functions
- Fix watchlist item mutation to update via copy

### Added
- Universal Binary support for Intel and Apple Silicon Macs
- Improved accessibility support
- Display cooldown labels as text instead of icons

## [1.4.3] - Earlier Release

### Added
- GitHub wiki documentation
- Migrated wiki to GitHub Wiki feature

## [1.4.2] - Earlier Release

### Changed
- Various bug fixes and improvements

## [1.4.1] - Earlier Release

### Changed
- Various bug fixes and improvements

## [1.4] - Initial Public Release

### Added
- Native macOS menu bar app for Torn game monitoring
- Status tab with live bars, cooldowns, and travel monitoring
- Travel tab with live countdown timer in menu bar
- Money tab with cash, vault, points display
- Attacks tab with battle stats and recent attacks
- Faction tab with chain status
- Watchlist tab for item price tracking
- Smart notifications for various game events
- Configurable refresh intervals
- Launch at login support
- Light and dark mode support
- Accessibility support with Reduce Transparency
