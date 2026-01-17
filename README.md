# MacTorn

A native macOS menu bar app for monitoring your **Torn** game status.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- 📊 **Live Status Bars** - Energy, Nerve, Happy, Life with color-coded progress
- ⏱️ **Cooldown Timers** - Drug, Medical, Booster countdowns
- ✈️ **Travel Monitoring** - Destination tracking with arrival countdown
- 🔗 **Chain Timer** - Active chain counter with timeout warning
- 🏥 **Hospital/Jail Status** - Countdown to release
- 📨 **Unread Messages** - Quick access to inbox
- 🔔 **Events Feed** - Recent activity at a glance
- 🔔 **Smart Notifications** - Custom threshold alerts with sound options
- ⚡ **Quick Links** - 8 configurable shortcuts to Torn pages
- 🚀 **Launch at Login** - Start automatically with macOS

## Installation

1. Download the latest release from [Releases](https://github.com/pawelorzech/MacTorn/releases)
2. Unzip and drag `MacTorn.app` to your Applications folder
3. Open MacTorn from Applications
4. Enter your [Torn API Key](https://www.torn.com/preferences.php#tab=api)

> **Note**: On first launch, macOS may show a security warning. Right-click the app and select "Open" to bypass.

## Requirements

- macOS 13.0 (Ventura) or later
- Torn API Key with access to: basic, bars, cooldowns, travel, profile, events, messages

## Configuration

### Refresh Interval
Choose polling frequency: 15s, 30s, 60s, or 120s

### Notification Rules
Customize when to receive alerts:
- Energy/Nerve/Happy/Life at specific thresholds
- Sound selection per notification type

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
