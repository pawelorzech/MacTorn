# Configuration

MacTorn offers several configuration options to customize your experience. All settings are found in the **Settings** tab.

## Refresh Interval

Control how often MacTorn fetches data from Torn's API.

| Interval | Best For |
|----------|----------|
| **15 seconds** | Active players who need real-time updates |
| **30 seconds** | Balanced usage (default) |
| **60 seconds** | Casual monitoring |
| **2 minutes** | Minimal API usage, background monitoring |

**Note:** Shorter intervals use more API calls. If you use multiple Torn apps, consider longer intervals to avoid rate limits.

### Changing Refresh Interval

1. Open MacTorn (click menu bar icon)
2. Go to **Settings** tab
3. Click your preferred interval in the segmented control

The change takes effect immediately.

## Appearance Mode

Choose how MacTorn appears:

| Mode | Behavior |
|------|----------|
| **System** | Follows macOS appearance (Light/Dark) |
| **Light** | Always use light theme |
| **Dark** | Always use dark theme |

### Setting Appearance

1. Open MacTorn
2. Go to **Settings** tab
3. Select your preferred mode from the picker

## Accessibility Settings

### Reduce Transparency

When enabled, MacTorn uses solid backgrounds instead of translucent materials. This improves readability for users who prefer less visual complexity.

**To enable:**
1. Open MacTorn Settings
2. Toggle **Reduce Transparency** ON

**System-wide setting:** MacTorn also respects the macOS "Reduce Transparency" setting found in System Settings > Accessibility > Display.

## Launch at Login

Start MacTorn automatically when you log into your Mac.

**To enable:**
1. Open MacTorn Settings
2. Toggle **Launch at Login** ON

MacTorn will now appear in your menu bar after every restart/login.

## Notification Settings

MacTorn can send macOS notifications for various events.

### Available Notifications

| Notification | When Triggered |
|--------------|----------------|
| Energy threshold | Energy reaches a certain level |
| Nerve threshold | Nerve reaches a certain level |
| Cooldown ready | Drug/Medical/Booster cooldown completes |
| Travel landing | Arriving at destination |
| Chain expiring | Chain timer running low |
| Hospital release | Released from hospital |
| Jail release | Released from jail |

### Travel Pre-Arrival Alerts

Configure notifications before landing (found in Travel tab):

| Alert | When |
|-------|------|
| 2 minutes | 2 minutes before arrival |
| 1 minute | 1 minute before arrival |
| 30 seconds | 30 seconds before arrival |
| 10 seconds | 10 seconds before arrival |

Enable/disable each independently in the Travel tab under "Pre-Arrival Alerts".

### Enabling macOS Notifications

For MacTorn notifications to appear, ensure they're enabled in macOS:

1. Open **System Settings**
2. Go to **Notifications**
3. Find **MacTorn** in the list
4. Ensure **Allow Notifications** is ON
5. Configure banner style, sounds, etc. as desired

## Watchlist Configuration

The Watchlist tab tracks item prices from Torn's Item Market.

### Adding Items

1. Go to **Watchlist** tab
2. Click the **+** button
3. Select an item from the preset list:
   - Xanax
   - FHC (Feathery Hotel Coupon)
   - Donator Pack
   - Drug Pack
   - Energy Drink
   - First Aid Kit

### Removing Items

Click the **x** button next to any watched item to remove it.

### Manual Refresh

Click the refresh icon (circular arrow) in the Watchlist header to manually update prices.

## Quick Links

The Status tab includes 8 quick links. Currently these are preset to common Torn pages:

- Gym
- Items
- Properties
- Missions
- Crimes
- Jail
- Hospital
- Casino

## Data Storage

MacTorn stores configuration locally:

| Data | Storage Method |
|------|----------------|
| API Key | UserDefaults (local) |
| Refresh Interval | UserDefaults |
| Appearance Mode | UserDefaults |
| Reduce Transparency | UserDefaults |
| Launch at Login | macOS SMAppService |
| Notification Rules | UserDefaults |
| Watchlist Items | UserDefaults |

**Privacy:** No data is sent anywhere except to Torn's API servers.

## Resetting Configuration

To reset all settings to defaults:

1. Quit MacTorn
2. Open Terminal
3. Run: `defaults delete com.bombel.MacTorn`
4. Relaunch MacTorn

---

**Next:** [[Troubleshooting]] - Solutions to common issues
