# API Setup

MacTorn requires a Torn API key to fetch your game data. This guide explains how to generate a key and what data MacTorn accesses.

## Generating an API Key

### Step-by-Step

1. **Log into Torn** at https://www.torn.com
2. Go to **Settings** in the sidebar
3. Click the **API Keys** tab, or go directly to: https://www.torn.com/preferences.php#tab=api
4. Under "Create New Key":
   - Enter a name (e.g., "MacTorn")
   - Select access level (see below)
5. Click **Create**
6. **Copy the 16-character key** that appears

### Access Levels

Torn offers several API access levels:

| Level | Recommended | Notes |
|-------|-------------|-------|
| **Full Access** | Yes | Simplest option, works with all MacTorn features |
| **Limited Access** | Yes | Works if you select required permissions |
| **Custom** | Possible | Select specific permissions |

### Required Permissions

If using Limited or Custom access, MacTorn requires these selections:

| Permission | Used For |
|------------|----------|
| `basic` | Player name, ID, basic info |
| `bars` | Energy, Nerve, Happy, Life bars |
| `cooldowns` | Drug, Medical, Booster timers |
| `travel` | Travel status and destination |
| `profile` | Battle stats, faction info |
| `events` | Recent events feed |
| `messages` | Unread message count |
| `money` | Cash, vault, points, tokens |
| `battlestats` | Strength, Defense, Speed, Dexterity |
| `attacks` | Recent attack history |
| `properties` | Property information |

For watchlist functionality:
| Permission | Used For |
|------------|----------|
| `market` (v2) | Item prices from Item Market |

## Entering Your API Key in MacTorn

1. Click the MacTorn icon in your menu bar
2. Go to the **Settings** tab
3. Enter your API key in the text field
4. Click **Save & Connect**

MacTorn will immediately attempt to fetch your data. If successful, you'll see your status appear in the Status tab.

## API Data Usage Disclosure

In compliance with Torn's API Terms of Service, here is exactly what MacTorn accesses:

### User Endpoint (v1)

MacTorn calls the user endpoint with these selections:

```
/user/?selections=basic,bars,cooldowns,travel,profile,events,messages,money,battlestats,attacks,properties
```

**Purpose:** Display your player status, bars, cooldowns, travel info, faction, events, messages, finances, battle stats, and attacks.

### Faction Endpoint (v1)

When you have faction data:

```
/faction/?selections=basic,chain
```

**Purpose:** Display faction name, chain status, and war information.

### Market Endpoint (v2)

For watchlist items:

```
/v2/market/{itemId}?selections=itemmarket,bazaar
```

**Purpose:** Fetch current market prices for items you're watching.

## Security Best Practices

### Do

- **Use a dedicated key** for MacTorn that you can revoke if needed
- **Limit permissions** if you don't need all features
- **Keep your key private** - never share it

### Don't

- Don't use your main API key for third-party apps
- Don't share your API key with others
- Don't commit your key to git or public repositories

## Key Storage

MacTorn stores your API key locally using macOS's `UserDefaults` system. The key:

- Is stored on your Mac only
- Is **not** transmitted anywhere except to Torn's API
- Is **not** backed up to iCloud
- Can be removed by clearing MacTorn's preferences

## Revoking Access

If you need to stop MacTorn from accessing your Torn data:

1. Go to Torn API settings: https://www.torn.com/preferences.php#tab=api
2. Find your MacTorn key
3. Click **Delete** next to it

MacTorn will show an error state until a new valid key is entered.

## API Rate Limits

Torn's API has rate limits. MacTorn is designed to respect these:

- Default refresh is 30 seconds
- Minimum refresh is 15 seconds
- Each refresh makes 1-3 API calls depending on features used

If you're using multiple Torn apps, you may want to use longer refresh intervals.

---

**Next:** [[Configuration]] - Customize your settings
