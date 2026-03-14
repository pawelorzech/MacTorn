# Cooldown Quick Action Buttons — Design Spec

## Overview

When a cooldown (drug, medical, booster) reaches 0 ("Ready"), the cooldown cell transforms into a clickable button that opens the corresponding Items subsection on Torn's website. For the booster cooldown, the user can configure in Settings whether the link targets boosters or alcohol.

## UI Changes

### Cooldown Cells (`LiveCooldownItem` / `CooldownItem`)

When `remaining == 0` and an `actionURL` is provided:

- **Background**: `Color.green.opacity(0.12)` fill
- **Border**: `Color.green.opacity(0.25)`, `cornerRadius(6)`
- **Action label**: Below "Ready" text, a subtle hint in `.caption2` font at `opacity(0.7)`:
  - Drug: "Use Drug →"
  - Medical: "Use Medical →"
  - Booster: "Use Booster →" or "Use Alcohol →" (depending on setting)
- **Behavior**: Entire cell is a `Button` that calls `BrowserManager.shared.open(url)`

When cooldown > 0 or no `actionURL`: no visual or behavioral change from current implementation.

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

## Data Flow

- `LiveCooldownItem` and `CooldownItem` gain a new optional parameter: `actionURL: URL?`
- `cooldownsSection` in `StatusView` constructs the URLs:
  - Drug and Medical: static URLs
  - Booster: reads `@AppStorage("boosterCooldownTarget")` to determine which URL to use
- URL opening is delegated to `BrowserManager.shared.open()` (respects preferred browser setting)

## Scope — What Does NOT Change

- Cooldown notifications in `AppState` — unchanged
- `AppState` logic — no modifications (feature is view-layer only)
- Quick Links section — unchanged
- Cooldown behavior when timer > 0 — unchanged
- `CooldownItem` fallback (no `fetchTime`) renders action button using same logic based on `seconds == 0`

## Visual Reference

Style C from brainstorming: entire cooldown cell becomes a clickable button with green background, border, and subtle action text when ready.
