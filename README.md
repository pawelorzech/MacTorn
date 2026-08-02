# MacTorn

A native macOS menu bar app for monitoring your **Torn** game status.

![macOS](https://img.shields.io/badge/macOS-14.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![Universal](https://img.shields.io/badge/Universal-Intel%20%2B%20Apple%20Silicon-purple)
![License](https://img.shields.io/badge/License-MIT-green)

<p align="center">
  <img src="app_light_1.png" alt="MacTorn Light Mode" width="320">
  &nbsp;&nbsp;
  <img src="app_dark_1.png" alt="MacTorn Dark Mode" width="320">
</p>

## Documentation

For detailed documentation, visit the [MacTorn Wiki](https://github.com/pawelorzech/MacTorn/wiki).
For community discussion and feedback, see the [Torn forums thread](https://www.torn.com/forums.php#/p=threads&f=67&t=16532308).

## Features

### 📊 Status Tab
- Live Energy, Nerve, Happy, Life bars with color-coded progress
- Cooldown timers (Drug, Medical, Booster) with quick action buttons when ready
- Daily refills remaining (energy/nerve) and in-progress education timer
- Bounties-on-you badge (count + total reward)
- Travel monitoring with arrival countdown
- Chain timer with timeout warning
- Hospital/Jail status badges
- Unread messages badge
- Events feed
- 8 quick links

### ✈️ Travel Tab
- **Live countdown timer** in menu bar during flight (✈️🏠 5:32)
- Flight status with progress bar
- Quick travel destination picker (all 11 Torn destinations)
- Pre-arrival notifications (configurable: 2min, 1min, 30sec, 10sec)
- Country flags for all destinations

### 💰 Account
- **Money**: Cash, Vault, Cayman, total tracked net worth, and quick actions
- **Properties**: Dedicated property cards with market value, cost, happy, and rental status
- **Stocks**: Dedicated, scrollable holdings list with market value and cost basis
- **Faction**: Faction status, chain, Organized Crime, wars, news, and armory actions
- Quick actions: Send Money, Bazaar, Bank

### ⚔️ Attacks Tab
- Battle stats (Strength, Defense, Speed, Dexterity)
- Recent attacks with W/L results
- Quick actions: Attack, Hospital, Bounties

### 🏢 Faction Tab
- Faction info and chain status
- **Organized Crime timer** with live countdown and READY notifications
- War status display
- Armory quick-use buttons

### 📈 Watchlist Tab
- Track item prices (Latest API v2 support)
- **Price alerts**: Set a threshold and get notified when price drops below it
- Displays lowest market price AND quantity (e.g., `$4.2M x12`)
- Price change indicators
- Add/remove items from watchlist

### 💬 Forum Watch Tab
- Watch specific forum threads for new posts (including faction forum threads)
- Add threads by URL or thread ID
- Per-thread notification toggle (alerts or bookmark-only mode)
- Configurable polling interval (2m / 3m / 5m)

### ⚙️ General
- **🔄 Update Checker**: Automatically notifies you when a new version is available on GitHub.
- **🔔 Smart Notifications**: Alerts for bar thresholds, cooldown ready, landing, chain expiring, Organized Crime ready, and release.
- **🕒 Configurable Refresh**: Intervals (15s/30s/60s/2m).
- **🩺 Diagnostics Screen**: Settings → Diagnostics shows live API request/row budgets, driven by the same endpoint registry as the table below.
- **🐞 Opt-in Crash Reporting**: Off by default. Powered by Sentry with PII scrubbing; enable it in Settings. See [`SECURITY.md`](SECURITY.md).
- **🚀 Launch at Login**: Start seamlessly with macOS.
- **⚡️ Optimized Startup**: Non-blocking data fetching for instant UI responsiveness.

## Accessibility

MacTorn respects macOS accessibility settings:

- **Reduce Transparency**: Follows System Settings → Accessibility → Display → Reduce transparency automatically, switching to solid backgrounds. Settings also has an "Always reduce transparency" switch to force it on regardless of the system setting.
- **Reduce Motion**: Panel and undo-banner animations are suppressed when System Settings → Accessibility → Display → Reduce motion is on.
- **VoiceOver**: The menu bar label announces its meaning ("Traveling to Japan, arriving in 2 minutes 35 seconds") rather than reading out the raw emoji, and progress bars expose a label plus a percentage value.
- **Light & Dark Mode**: Full support for both appearance modes with optimized contrast
- **Color-coded indicators**: Status bars and badges use distinct colors that work well in both modes

Accessibility work in progress — not yet complete: several module tabs (Attacks, Faction, Money, Properties, Stocks) still expose their rows as unlabelled elements, and attack results are conveyed by icon and colour without a text equivalent. See `AUDIT_REPORT.md`.

## Installation

1. Download the latest release from [Releases](https://github.com/pawelorzech/MacTorn/releases)
2. Open the DMG and drag `MacTorn.app` to your Applications folder
3. Open MacTorn from Applications
4. Enter your [Torn API Key](https://www.torn.com/preferences.php#tab=api)

> **Note**: If you download an unsigned build, macOS Gatekeeper may block it. Right-click the app and select "Open", or go to System Settings → Privacy & Security → Open Anyway.

### Verifying your download

MacTorn is **not** notarized or signed with a paid Apple Developer ID (a deliberate
tradeoff — that program costs money and this is a free hobby project), so macOS
itself won't vouch for the binary the way it does for signed, notarized apps. A
SHA-256 checksum lets you confirm
the file you downloaded is byte-for-byte the one published in the release, without
relying on Gatekeeper:

1. Copy the `SHA-256` hash listed in the [release notes](https://github.com/pawelorzech/MacTorn/releases) for the version you downloaded.
2. Run this in Terminal against the file you downloaded:
   ```
   shasum -a 256 ~/Downloads/MacTorn.dmg
   ```
3. Compare the printed hash to the one in the release notes — they must match exactly.

This does **not** replace notarization: it proves the file wasn't corrupted or swapped
in transit, not that Apple has vetted the publisher.

## Requirements

- macOS 14.0 (Sonoma) or later
- **Universal Binary**: Supports both Intel (x86_64) and Apple Silicon (arm64) Macs
- Torn API Key with **Limited Access** or higher (read-only). The exact selections MacTorn requests are listed in [API Data Usage](#api-data-usage) below.

## API Data Usage

In compliance with the [Torn API Terms of Service](https://www.torn.com/api.html), the
table below shows every Torn API endpoint MacTorn calls and why. It is generated from
the typed endpoint registry (`MacTorn/Networking/TornEndpoint.swift`,
`TornEndpointRegistry.markdownTable()`) — the single source of truth that also builds
the requests and the onboarding disclosure, so this list can't drift from what the app
actually does.

**Data shape** distinguishes *point-in-time* snapshots (bars, money, cooldowns — safe
to poll frequently) from *row-based* cloud data (events, attacks, news, forum posts),
which counts against Torn's 50,000-rows/day-per-category cap (error code 14). Row-based
calls are throttled and hard-limited to stay well under that cap.

| Endpoint | API | Selections | Data | Cadence | Rows/call | Budget | Critical | Purpose |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| User (fast poll) | v1 | basic, bars, cooldowns, travel, profile, money, battlestats, properties, stocks | point-in-time | Every refresh interval (default 30s; 15s aggressive) | — | core | yes | Live Energy/Nerve/Happy/Life bars, drug/medical/booster cooldowns, travel status, money & net worth, battle stats, properties and stock holdings. |
| User v2 (combined) | v2 | organizedcrime, refills, education, bounties | point-in-time | Every refresh interval (rides the fast poll) | — | core | no | Own Organized Crime 2.0 status, daily refills remaining, in-progress education timer, and bounties placed on you. |
| User activity | v1 | events, messages, attacks | row-based | ≥5 min (self-throttled; hard row limit) | 25 | activity | no | Events feed, unread message count and recent attacks (display-only). |
| Faction basic + chain | v1 | basic, chain | point-in-time | Every refresh interval (rides the fast poll) | — | faction | no | Faction identity and the live chain counter/timeout that drives the chain-expiring alert. |
| Faction ranked wars | v2 | — | point-in-time | ≥5 min (throttled — large, slow-changing payload) | — | faction | no | Active ranked war progress (your faction vs. the opponent). |
| Faction news | v2 | — | row-based | ≥5 min (throttled; hard row limit) | 25 | faction | no | Recent faction news feed. |
| Item market | v2 | itemmarket, bazaar | point-in-time | Watchlist refresh (manual + on price-alert timer) | — | market | no | Lowest item-market listings for each watchlist item, used to drive price alerts. |
| Stock metadata | v1 | stocks | point-in-time | Rarely (cached; refreshed on demand) | — | metadata | no | Global stock names/acronyms used to label the user's stock holdings (slow-changing reference data). |
| Forum thread | v2 | — | row-based | Forum poll (opt-in feature) | 20 | forum | no | Post count of a watched forum thread, to alert on new replies. |
| Forum category threads | v2 | — | row-based | Forum poll (opt-in feature) | 20 | forum | no | Thread list of a watched forum category, to alert on new threads. |
| Key info | v2 | — | point-in-time | On demand (Test Connection / key change) | — | core | no | One-off validation of the API key: its access level/type, the owner's ID, and which selections it can read — used by onboarding's Test Connection. Never polled. |

Your API key needs **Limited Access** or higher. Everything above is **read-only** —
MacTorn never performs actions in Torn. See [`SECURITY.md`](SECURITY.md) for how your
key and data are protected.

## Configuration

### Refresh Interval
Choose polling frequency: 15s, 30s, 60s, or 120s

### Notifications
MacTorn sends notifications for bar thresholds, cooldown ready, landing, chain expiring, Organized Crime ready, and release. Notification defaults are stored locally.

### Updates
The app checks for updates automatically on startup. If a new version is available, you'll see a notification in the **Settings** tab.

## Building from Source

```bash
git clone https://github.com/pawelorzech/MacTorn.git
cd MacTorn/MacTorn
open MacTorn.xcodeproj
```

Press `Cmd + R` to build and run.

## Support the Developer

If you find MacTorn useful, send some Xanax or cash to **bombel** [[2362436](https://www.torn.com/profiles.php?XID=2362436)]!

## License

MIT License - see [LICENSE](LICENSE) for details.

---

Made with ⚡ for the Torn community
