# MacTorn

A native macOS menu bar app for monitoring your **Torn** game status.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- 📊 **Live Status Bars** - Energy, Nerve, Happy, Life with color-coded progress
- ⏱️ **Cooldown Timers** - Drug, Medical, Booster countdowns with ready state
- ✈️ **Travel Monitoring** - Destination tracking with arrival countdown and abroad state
- 🔗 **Chain Timer** - Active chain counter with timeout warning + cooldown state
- 🏥 **Hospital/Jail Status** - Countdown to release
- 📨 **Unread Messages** - Inbox badge with one-click open
- 🔔 **Events Feed** - Recent activity at a glance
- 🔔 **Notifications** - Bars thresholds, cooldown ready, landing, chain expiring, and release
- ⚡ **Quick Links** - Grid of customizable Torn shortcuts (8 defaults)
- 🕒 **Refresh Control** - 15s/30s/60s/2m polling + manual refresh + last updated
- 🚀 **Launch at Login** - Start automatically with macOS

## Installation

1. Download the latest release from [Releases](https://github.com/pawelorzech/MacTorn/releases)
2. Unzip and drag `MacTorn.app` to your Applications folder
3. Open MacTorn from Applications
4. Enter your [Torn API Key](https://www.torn.com/preferences.php#tab=api)

> **Note**: If you download an unsigned build, macOS Gatekeeper will block it. Right-click the app and select "Open", or go to System Settings → Privacy & Security → Open Anyway.

## Requirements

- macOS 13.0 (Ventura) or later
- Torn API Key with access to: basic, bars, cooldowns, travel, profile, events, messages

## Configuration

### Refresh Interval
Choose polling frequency: 15s, 30s, 60s, or 120s

### Notifications
MacTorn sends notifications for bar thresholds, cooldown ready, landing, chain expiring, and release. Notification defaults are stored locally.

### Quick Links
8 preset shortcuts to common Torn pages (fully editable)

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
