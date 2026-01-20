# Troubleshooting

This page covers common issues and their solutions.

## Can't Open MacTorn (Gatekeeper)

**Symptom:** "MacTorn can't be opened because it is from an unidentified developer"

**Cause:** macOS Gatekeeper blocks unsigned applications.

**Solution:**

**Method 1 - Right-Click Open:**
1. Right-click (or Control-click) on MacTorn.app
2. Select "Open" from the menu
3. Click "Open" in the dialog

**Method 2 - System Settings:**
1. Try opening MacTorn (it will be blocked)
2. Go to System Settings > Privacy & Security
3. Scroll to find the message about MacTorn
4. Click "Open Anyway"
5. Enter your password and click "Open"

## API Key Errors

### "Invalid API Key"

**Cause:** The key you entered is incorrect or has been revoked.

**Solution:**
1. Go to https://www.torn.com/preferences.php#tab=api
2. Verify your key exists and matches what you entered
3. If in doubt, create a new key
4. Copy the key carefully (16 characters)
5. Re-enter in MacTorn Settings

### "Insufficient Permissions"

**Cause:** Your API key doesn't have the required permissions.

**Solution:**
1. Create a new API key with "Full Access"
2. Or select these specific permissions:
   - basic, bars, cooldowns, travel, profile, events, messages, money, battlestats, attacks

### "API Request Failed"

**Cause:** Network issue or Torn API is down.

**Solution:**
1. Check your internet connection
2. Try visiting https://www.torn.com to verify Torn is accessible
3. Wait and try again - Torn API occasionally has downtime
4. Click "Refresh" or wait for next automatic refresh

## Menu Bar Icon Issues

### Icon Not Appearing

**Cause:** MacTorn may not have launched properly.

**Solution:**
1. Check if MacTorn is running (Activity Monitor)
2. Quit and relaunch MacTorn
3. Check System Settings > Control Center > Menu Bar Only to ensure there's space

### Wrong Icon Displayed

**Cause:** Normal behavior - icon changes based on status.

**Reference:**
- Bolt outline = Normal
- Bolt filled = Energy full
- Globe = Abroad
- Triangle = Error
- Airplane + timer = Traveling

## Notifications Not Working

### No Notifications Appear

**Cause:** macOS notification permissions.

**Solution:**
1. Open System Settings > Notifications
2. Find MacTorn in the list
3. Ensure "Allow Notifications" is ON
4. Set alert style to "Banners" or "Alerts"

### Notification Sound Missing

**Cause:** Sound disabled in notification settings.

**Solution:**
1. System Settings > Notifications > MacTorn
2. Enable "Play sound for notifications"

### Travel Alerts Not Working

**Cause:** Pre-arrival alerts may be disabled.

**Solution:**
1. Open MacTorn > Travel tab
2. Under "Pre-Arrival Alerts"
3. Enable the time intervals you want

## Data Not Updating

### Bars/Stats Stuck

**Cause:** Polling may have stopped or API error.

**Solution:**
1. Check the menu bar icon - triangle means error
2. Go to Settings and verify API key
3. Try changing refresh interval (triggers restart)
4. Quit and relaunch MacTorn

### Watchlist Prices Not Loading

**Cause:** API v2 permissions or item ID issues.

**Solution:**
1. Ensure your API key has market access
2. Click the refresh button in Watchlist tab
3. Remove and re-add items

## Performance Issues

### High CPU Usage

**Cause:** Rare, possibly rendering loop.

**Solution:**
1. Quit and relaunch MacTorn
2. Try a longer refresh interval (60s or 2m)
3. If persists, file a bug report

### App Feels Slow

**Cause:** Normal behavior during initial load.

**Solution:**
- MacTorn uses non-blocking data fetching
- UI should remain responsive
- First load may show empty data briefly

## Window Issues

### Window Won't Open

**Cause:** Window may be off-screen.

**Solution:**
1. Quit MacTorn
2. Run in Terminal: `defaults delete com.bombel.MacTorn`
3. Relaunch MacTorn

### Window Too Small/Cut Off

**Cause:** Display scaling issues.

**Solution:**
1. Try different appearance mode in Settings
2. Quit and relaunch

## Update Issues

### "New Version Available" but Can't Update

**Cause:** Manual update required.

**Solution:**
1. Click "Download Update" in Settings
2. Download the new version from GitHub
3. Quit MacTorn
4. Replace old .app with new one
5. Relaunch (may need Gatekeeper bypass again)

## Reporting Bugs

If your issue isn't listed here:

1. **Check GitHub Issues** - https://github.com/pawelorzech/MacTorn/issues
2. **Create New Issue** with:
   - macOS version
   - MacTorn version (found in Settings)
   - Steps to reproduce
   - Screenshots if applicable

---

**See Also:** [[FAQ]] for common questions
