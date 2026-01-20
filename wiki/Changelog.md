# Changelog

All notable changes to MacTorn are documented here.

## [v1.4.4] - Latest

### Fixed
- Fixed watchlist item mutation to update via copy for proper SwiftUI state updates

## [v1.4.3]

### Changed
- Improved accessibility support and updated README documentation

## [v1.4.2]

### Added
- Universal Binary support for Intel (x86_64) and Apple Silicon (arm64) Macs

### Changed
- Cooldown labels now display as text instead of icons for better readability

## [v1.4.1]

### Fixed
- Resolved Credits view height being cut off in MenuBarExtra window
- Fixed SwiftUI constraint update loop in MenuBarExtra

## [v1.4]

### Added
- **Travel Tab** - Dedicated tab for travel management
  - Live countdown timer updating every second
  - Flight progress bar
  - Quick travel destination picker (all 11 Torn destinations)
  - Pre-arrival notifications (2min, 1min, 30sec, 10sec before landing)
  - Country flags for all destinations
- **Menu bar travel display** - Shows airplane + flag + countdown when flying (e.g., "✈️🇬🇧 5:32")

## [v1.3]

### Added
- Live countdown timers for cooldowns
- Credits page accessible from Settings

### Changed
- Optimized startup with non-blocking data fetching

## [v1.2.5]

### Added
- API usage disclosure in Settings (Torn API ToS compliance)

### Changed
- Life progress bar color changed to blue for better distinction

## [v1.2]

### Added
- **Watchlist feature** - Track item prices from Item Market
  - Uses Torn API v2 for market data
  - Shows lowest price and quantity
  - Price change indicators
  - Quick add from popular items list

### Changed
- Various UI improvements

## [v1.1]

### Added
- Update checker - Automatic notification when new version available
- Launch at Login option

### Improved
- Notification system reliability

## [v1.0]

### Initial Release

- **Status Tab** with:
  - Energy, Nerve, Happy, Life bars
  - Cooldown timers (Drug, Medical, Booster)
  - Hospital/Jail status badges
  - Unread messages badge
  - Chain timer
  - Events feed
  - 8 quick links

- **Money Tab** with:
  - Cash, Vault, Points, Tokens display
  - Quick action buttons

- **Attacks Tab** with:
  - Battle stats display
  - Recent attacks list

- **Faction Tab** with:
  - Faction info
  - Chain status
  - War status

- **Settings Tab** with:
  - API key management
  - Refresh interval selection
  - Appearance mode (System/Light/Dark)

- **Core Features**:
  - Menu bar app with dynamic icon
  - Configurable notifications
  - macOS 13.0+ support

---

## Version History Summary

| Version | Highlights |
|---------|-----------|
| v1.4.4 | Watchlist mutation fix |
| v1.4.3 | Accessibility improvements |
| v1.4.2 | Universal Binary support |
| v1.4.1 | UI bug fixes |
| v1.4 | Travel tab with live countdown |
| v1.3 | Live cooldown timers |
| v1.2.5 | API ToS compliance |
| v1.2 | Watchlist feature |
| v1.1 | Update checker |
| v1.0 | Initial release |

---

For the latest version, visit the [Releases page](https://github.com/pawelorzech/MacTorn/releases).
