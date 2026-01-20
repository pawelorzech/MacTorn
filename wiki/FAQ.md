# Frequently Asked Questions

## General

### What is MacTorn?

MacTorn is a native macOS menu bar application that monitors your Torn game status. It displays energy bars, travel timers, chain status, and more without requiring a browser tab.

### Is MacTorn free?

Yes, MacTorn is free and open source under the MIT License.

### Does MacTorn work on Windows/Linux?

No, MacTorn is a native macOS application and only works on Macs running macOS 13.0 or later.

### Does MacTorn work on Intel Macs?

Yes! MacTorn is a Universal Binary that runs natively on both Intel (x86_64) and Apple Silicon (arm64) Macs.

## Installation

### Why can't I open the app?

macOS Gatekeeper blocks unsigned apps. Right-click the app and select "Open", or go to System Settings > Privacy & Security and click "Open Anyway".

See [[Troubleshooting]] for detailed steps.

### Where do I download MacTorn?

Download from the [GitHub Releases page](https://github.com/pawelorzech/MacTorn/releases).

### How do I update MacTorn?

When a new version is available, you'll see a notification in the Settings tab. Click "Download Update" to get the latest version from GitHub, then replace your old app with the new one.

## API & Security

### Is my API key safe?

Yes. Your API key is:
- Stored locally on your Mac only
- Never transmitted anywhere except to Torn's official API
- Not synced to iCloud or any cloud service

### What API permissions does MacTorn need?

For full functionality: basic, bars, cooldowns, travel, profile, events, messages, money, battlestats, attacks, properties, and market access.

You can use "Full Access" or select specific permissions. See [[API-Setup]] for details.

### Can MacTorn perform actions on my account?

No. MacTorn is read-only. It can only view your data - it cannot attack, travel, buy items, or perform any actions on your behalf.

### Does MacTorn violate Torn's rules?

No. MacTorn uses Torn's official public API as intended. It follows all API terms of service.

## Features

### How often does MacTorn update data?

By default, every 30 seconds. You can change this to 15s, 60s, or 2m in Settings.

### How do I get notifications?

MacTorn sends notifications through macOS. Ensure notifications are enabled in System Settings > Notifications > MacTorn.

### Why is the travel countdown in my menu bar?

When you're traveling, MacTorn shows a live countdown (e.g., "✈️🇬🇧 5:32") so you can always see when you'll land without opening the app.

### Can I track custom items in the watchlist?

Currently, the watchlist offers preset popular items. Custom item IDs may be added in future versions.

### Does MacTorn show chain alerts?

Yes. When your faction has an active chain, MacTorn displays the chain count and timeout timer in the Status tab.

## Troubleshooting

### Why do I see a warning triangle icon?

The triangle icon indicates an error, usually an API issue. Open MacTorn and check the Settings tab for error messages.

### Notifications aren't working. Why?

1. Check macOS notification settings (System Settings > Notifications > MacTorn)
2. Ensure notifications are allowed
3. For travel alerts, enable them in the Travel tab

### The app is using a lot of battery/CPU. Is this normal?

No. MacTorn should use minimal resources. Try quitting and relaunching. If the issue persists, please file a bug report.

### How do I completely remove MacTorn?

1. Quit MacTorn
2. Delete MacTorn.app from Applications
3. (Optional) Clear preferences: `defaults delete com.bombel.MacTorn` in Terminal

## Support

### How do I report a bug?

File an issue on [GitHub](https://github.com/pawelorzech/MacTorn/issues) with:
- Your macOS version
- MacTorn version
- Steps to reproduce
- Screenshots if helpful

### How can I support the developer?

Send some Xanax or cash to **bombel** [[2362436](https://www.torn.com/profiles.php?XID=2362436)] in-game!

### Is there a Discord or community?

Currently, support is through GitHub issues. Join the Torn Discord if you want to discuss with other players.

---

**See Also:** [[Troubleshooting]] for detailed solutions
