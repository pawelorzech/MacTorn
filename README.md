# MacTorn
Menu bar companion for the Torn game on macOS. It polls the Torn API and surfaces your current bars, cooldowns, and travel status in a lightweight menu bar window.

## Features
- Menu bar status window with energy, nerve, happy, and life bars.
- Cooldown timers for drug, medical, and booster.
- Travel status with remaining time and destination.
- Local notifications when bars fill, cooldowns end, or you land.
- Quick links grid for Torn pages with editable labels and URLs.
- Launch at login toggle.

## Requirements
- macOS 13.0 or later.
- A Torn API key.

## Setup
1. Open the app and paste your Torn API key.
2. Click "Save & Connect".
3. (Optional) Enable "Launch at Login" and edit Quick Links.

Get an API key from `https://www.torn.com/preferences.php#tab=api`.

## Build and Run
1. Open `MacTorn/MacTorn.xcodeproj` in Xcode.
2. Select the MacTorn scheme.
3. Run the app (it appears in the menu bar).

## Notes
- The app polls the Torn API every 30 seconds.
- Your API key and Quick Links are stored locally in `UserDefaults`.
