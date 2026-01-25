# Changelog

All notable changes to MacTorn will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
