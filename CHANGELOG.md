# Changelog

All notable changes to MacTorn will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
