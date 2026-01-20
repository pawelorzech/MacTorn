# Getting Started

This guide will help you set up MacTorn and understand its basic features.

## Step 1: Get Your Torn API Key

To use MacTorn, you need a Torn API key. See [[API-Setup]] for detailed instructions, or follow these quick steps:

1. Log into [Torn](https://www.torn.com)
2. Go to **Settings** > **API Keys** or directly visit: https://www.torn.com/preferences.php#tab=api
3. Create a new key with **Full Access** or select the required permissions
4. Copy the generated 16-character key

## Step 2: Configure MacTorn

1. Click the MacTorn icon in your menu bar (bolt icon)
2. Navigate to the **Settings** tab (gear icon)
3. Paste your API key in the **Torn API Key** field
4. Click **Save & Connect**

MacTorn will immediately start fetching your Torn data.

## Understanding the Menu Bar Icon

The menu bar icon changes based on your status:

| Icon | Status |
|------|--------|
| Bolt outline | Normal (energy not full) |
| Bolt filled | Energy is full |
| Globe | Currently abroad |
| Warning triangle | Error (API issue) |
| Airplane + flag + timer | Currently traveling (e.g., "✈️🇬🇧 5:32") |

## Basic Navigation

MacTorn organizes information into tabs. Click the menu bar icon to open the window, then use the tab bar at the bottom:

### Tab Overview

| Tab | Icon | Purpose |
|-----|------|---------|
| **Status** | Bolt | Energy, Nerve, Happy, Life bars, cooldowns, events |
| **Travel** | Airplane | Travel status, destination picker, pre-arrival alerts |
| **Money** | Dollar | Cash, vault, points, tokens, quick actions |
| **Attacks** | Crosshairs | Battle stats, recent attacks |
| **Faction** | Building | Faction info, chain status, war status |
| **Watchlist** | Chart | Item price tracking |
| **Settings** | Gear | API key, refresh interval, appearance |

## Using Quick Links

The Status tab includes 8 customizable quick links for fast access to common Torn pages:

- Gym, Items, Properties
- Missions, Crimes, Jail
- Hospital, Casino

Click any quick link to open that page in your default browser.

## Notifications

MacTorn can send macOS notifications for important events:

- Energy/Nerve thresholds reached
- Cooldowns ready
- Travel landing
- Chain expiring
- Hospital/Jail release

Configure notification rules in the Settings tab or see [[Configuration]] for details.

## Refresh Interval

By default, MacTorn fetches data every 30 seconds. You can change this in Settings:

- **15s** - Most frequent updates
- **30s** - Balanced (default)
- **60s** - Less frequent
- **2m** - Minimal API usage

## Tips for New Users

1. **Enable Launch at Login** - Find this in Settings to have MacTorn start with your Mac
2. **Set up Watchlist** - Track item prices you care about in the Watchlist tab
3. **Configure Travel Alerts** - Enable pre-arrival notifications in the Travel tab so you don't miss your landing
4. **Check Events** - The Status tab shows recent events so you don't miss attacks or messages

---

**Next:** [[Features]] - Explore all features in detail
