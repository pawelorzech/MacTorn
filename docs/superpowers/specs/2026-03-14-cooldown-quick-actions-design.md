# Cooldown Quick Action Buttons — Design Spec

## Overview

When a cooldown (drug, medical, booster) reaches 0 ("Ready"), the cooldown cell transforms into a clickable button that opens the corresponding Items subsection on Torn's website. For the booster cooldown, the user can configure in Settings whether the link targets boosters or alcohol.

## UI Changes

### Cooldown Cells (`LiveCooldownItem` / `CooldownItem`)

Both views gain new optional parameters: `actionURL: URL?` and `actionLabel: String?`. The existing `icon` parameter remains unused (no change). Both views add `@Environment(\.reduceTransparency) private var reduceTransparency` to read the accessibility setting, consistent with how other views in the project access it.

When `remaining == 0` and `actionURL` is provided:

- **Background**: `Color.green.opacity(reduceTransparency ? 0.25 : 0.12)` fill
- **Border**: `Color.green.opacity(reduceTransparency ? 0.4 : 0.25)`, `cornerRadius(6)`
- **Action label**: Below "Ready" text, the `actionLabel` rendered in `.caption2` font at `opacity(0.7)`. The label includes a trailing arrow for visual display:
  - Drug: "Use Drug →"
  - Medical: "Use Medical →"
  - Booster: "Use Booster →" or "Use Alcohol →" (depending on setting)
- **Behavior**: Entire cell wrapped in a `Button` with `.buttonStyle(.plain)` that calls `BrowserManager.shared.open(url)`
- **Accessibility**: `.accessibilityLabel("Use \(label)")` (without the arrow) and `.accessibilityHint("Opens Torn items page in browser")`

When cooldown > 0 or no `actionURL`: no visual or behavioral change from current implementation.

`CooldownItem` (the non-live fallback used when `appState.lastUpdated` is nil) receives the same `actionURL`/`actionLabel` parameters and renders the button treatment identically when `seconds == 0`.

### Target URLs

| Cooldown | URL |
|----------|-----|
| Drug | `https://www.torn.com/item.php#drugs-items` |
| Medical | `https://www.torn.com/item.php#medical-items` |
| Booster (boosters) | `https://www.torn.com/item.php#boosters-items` |
| Booster (alcohol) | `https://www.torn.com/item.php#alcohol-items` |

### Settings

New option in `SettingsView`: **"Booster cooldown link"**

- `Picker` with two choices: "Boosters" (default), "Alcohol"
- Stored in `@AppStorage("boosterCooldownTarget")` as `String` — value `"boosters"` or `"alcohol"`
- Placed after the existing Reduce Transparency toggle in the settings layout
- Uses an icon following the existing HStack icon pattern (e.g., `"arrow.up.circle.fill"`)
- Always visible (does not depend on cooldown state or API connection)

## Data Flow

- Add `@AppStorage("boosterCooldownTarget") private var boosterCooldownTarget: String = "boosters"` as a property on `StatusView`
- `cooldownsSection` in `StatusView` constructs the URLs and labels:
  - Drug and Medical: static URLs and labels
  - Booster: reads `boosterCooldownTarget` to determine which URL and label to use
- `LiveCooldownItem` and `CooldownItem` receive `actionURL` and `actionLabel` as parameters — they don't read settings themselves
- URL opening is delegated to `BrowserManager.shared.open()` (respects preferred browser setting)

## Scope — What Does NOT Change

- Cooldown notifications in `AppState` — unchanged
- `AppState` logic — no modifications (feature is view-layer only)
- Quick Links section — unchanged
- Cooldown behavior when timer > 0 — unchanged
- The `icon` parameter on cooldown views — remains accepted but unused

## Visual Reference

Style C from brainstorming: entire cooldown cell becomes a clickable button with green background, border, and subtle action text when ready.
