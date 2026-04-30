# Changelog

All notable changes to MacTorn will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
