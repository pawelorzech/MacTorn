# Plan: Drift-free countdowns (single source of truth = absolute end-timestamp)

## Context

User report: countdowns shown in the MacTorn menu bar and tabs **drift by ~30 s** vs. what Torn shows on the web. The reason is that for some domains we store the API's *relative* duration (e.g. `cooldowns.booster = 3600`) and then locally subtract `Date().timeIntervalSince(fetchTime)` every tick. Two sources of error compound:

1. **Mac clock ≠ Torn server clock.** `lastFetchTime` is captured with `Date()` on the Mac, but the duration the API returned was computed with the server's clock. Any NTP skew shows up as a constant offset that doesn't match torn.com.
2. **Truncation / re-fetch flicker.** The next poll returns a fresh server-side number, which can disagree with the locally extrapolated one by a second or three; over the lifetime of a long booster/travel that gap looks like ~30 s.

Torn already provides absolute Unix end-timestamps for the *important* countdowns — `travel.timestamp`, `status.until`, `chain.timeout`, `organizedcrime.time_ready`. The fix is to make absolute end-timestamps the *only* representation we keep on the model. Anything the API gives us as a duration gets converted at decode time into `endsAt = responseTimestamp + duration`, and every view computes remaining = `max(0, endsAt − now)`. No more "originalSeconds − elapsed" math.

We do this so that what MacTorn displays matches what torn.com displays to the second.

## What's already correct (do not touch the math)

| Domain | Field | File:Line |
|---|---|---|
| Travel arrival | `Travel.timestamp` (absolute) | `MacTorn/TornModels.swift:160-171` (`Travel.remainingSeconds`) |
| Hospital / jail | `Status.until` (absolute) | `MacTorn/TornModels.swift:299-302` (`Status.timeRemaining`) |
| User chain | `Chain.timeout` (absolute) | `MacTorn/TornModels.swift:322-325` (`Chain.timeoutRemaining`) |
| OC ready time | `OrganizedCrime.timeReady` (absolute) | `MacTorn/TornModels.swift:601` (decoded but currently unused for live tick) |

These use `Date().timeIntervalSince1970` against an absolute Torn timestamp — still subject to Mac↔server clock skew, but the skew is constant and matches what every other Mac app does. We will additionally **anchor on the server's response timestamp** (see step 1) so the displayed "remaining" matches torn.com exactly at the moment of fetch.

## What's broken (root causes)

1. **Cooldowns drift.** `Cooldowns.remainingSeconds(from: fetchTime)` (`MacTorn/TornModels.swift:111-120`) does `initial − elapsedSinceFetch`. This drives the menu-bar `.cooldown(...)` case (`MacTorn/AppState.swift:490`) and `LiveCooldownItem` in `MacTorn/Views/StatusView.swift:379-381`. **Fix: convert to `endsAt` at decode time.**
2. **OC crime timer drift.** `OCStatusRow` in `MacTorn/Views/FactionView.swift:166-168` does `crime.timeLeft − elapsedSinceFetch`. The model already has an absolute `OrganizedCrime.timeReady` (`MacTorn/TornModels.swift:601`). **Fix: switch the view to `timeReady`.**
3. **Faction chain bug — formats raw Unix epoch.** `MacTorn/Views/FactionView.swift:32` calls `formatTime(faction.chain.timeout)` on the absolute timestamp directly, treating it as seconds-of-duration. The number rendered is meaningless. **Fix: compute remaining live (TimelineView) using `FactionChain.timeout` as absolute, mirroring `ChainView`.**

## Out of scope (deliberately)

- **Bars `fulltime`** (energy / nerve / happy / life). The Torn API only returns relative seconds for these; no absolute alternative is documented. Drift here is small and not what the user complained about. Leaving as-is.
- **Chain `cooldown`** field on `Chain` (post-chain cooldown). Relative-only, low visibility, leave as-is.
- Replacing the countdown UI with a literal wall-clock end time ("lands at 14:32"). The user said the *math* is the problem, not the format. We keep "1m 23s" style; we just compute it from a single absolute anchor.

## Design

### 1. New invariant: every duration becomes `endsAt` at decode time

Add a single helper that captures the **server's response timestamp** (top-level `timestamp` field present on every Torn API response) and stores it alongside the parsed payload. Use it as the anchor for converting any relative duration → absolute Unix epoch. This eliminates Mac↔server clock skew at the moment of decode; from then on we only use `Date().timeIntervalSince1970` against absolute server-time anchors, exactly like the web client does.

- `TornResponse` already has `timestamp` decoded at the top level (verify in `MacTorn/TornModels.swift` — currently `Bar.ticktime`/`fulltime` exist, top-level `timestamp` may need adding to the user response struct). If missing, add `let serverTimestamp: Int?` keyed `"timestamp"` to `TornResponse`.
- In `AppState.fetchData()` (around `MacTorn/AppState.swift` where `lastFetchTime` is set), prefer `response.serverTimestamp` over `Date()` as the conversion anchor. Fall back to `Int(Date().timeIntervalSince1970)` if the field is absent.

### 2. Cooldowns: store `endsAt`, not `seconds`

Today (`MacTorn/TornModels.swift:88-128`):

```swift
struct Cooldowns: Codable {
    let drug: Int       // seconds remaining
    let booster: Int    // seconds remaining
    let medical: Int    // seconds remaining
}
extension Cooldowns {
    func remainingSeconds(kind:, from fetchTime: Date) -> Int { ... initial - elapsed ... }
}
```

Change to: keep the raw decoded values, but add a derived `CooldownEnds` struct computed once in `AppState` after fetch:

```swift
struct CooldownEnds {
    let drugEndsAt: Int      // 0 if not active
    let boosterEndsAt: Int
    let medicalEndsAt: Int
}
```

Built in `AppState.fetchData()` via `serverTimestamp + cooldowns.drug` (etc.). Stored on `AppState` as `@Published var cooldownEnds: CooldownEnds?`.

Update consumers:
- `MacTorn/AppState.swift:469-497` (`computeMenuBarDisplay`) — `.cooldown` case: read from `cooldownEnds`, compute `max(0, endsAt − now)`, pick soonest.
- `MacTorn/Views/StatusView.swift:215-217 / 379-381` (`LiveCooldownItem`) — receive `endsAt: Int` instead of `(originalSeconds, fetchTime)`. Inside `TimelineView(.periodic(...))`, compute `remaining = max(0, endsAt − Int(context.date.timeIntervalSince1970))`. Removes the `elapsedSinceFetch` math.

Replace, don't extend: delete `Cooldowns.remainingSeconds(kind:from:)` and `Cooldowns.soonestActive(from:)` once callers are migrated, so future code can't reach for the drift-prone path again.

### 3. OC crimes: use `timeReady` (already absolute)

`MacTorn/Views/FactionView.swift:166-168` (`OCStatusRow`):

```swift
// before
let elapsed = Int(context.date.timeIntervalSince(fetchTime))
let remaining = max(0, crime.timeLeft - elapsed)

// after
let remaining = max(0, crime.timeReady - Int(context.date.timeIntervalSince1970))
```

`OrganizedCrime.timeReady` exists at `MacTorn/TornModels.swift:601`. The `fetchTime` parameter on `OCStatusRow` becomes unused — drop it from the call site and the struct.

### 4. Faction chain bug fix

`MacTorn/Views/FactionView.swift:32` currently:

```swift
Text(formatTime(faction.chain.timeout))   // BUG: timeout is absolute Unix epoch
```

Wrap in `TimelineView(.periodic(from: .now, by: 1.0))` and compute `max(0, faction.chain.timeout − Int(context.date.timeIntervalSince1970))`, mirroring `MacTorn/Views/ChainView.swift:10-23`. Reuse the existing pattern verbatim — don't introduce a new helper.

### 5. No new abstractions

- Don't add a generic `Countdown` type. The four call sites are small and each has its own surrounding view; a shared type would obscure more than it saves.
- Don't add a global "ticker" service. Existing `liveTimerCancellable` (menu bar) and per-view `TimelineView.periodic` are fine; we're changing what they read, not how they tick.

## Files to modify

| File | Change |
|---|---|
| `MacTorn/TornModels.swift` | Add `serverTimestamp` to top-level user response if missing. Delete `Cooldowns.remainingSeconds(kind:from:)` + `Cooldowns.soonestActive(from:)` after migration. |
| `MacTorn/AppState.swift` | Use `response.serverTimestamp` as fetch anchor. Add `@Published var cooldownEnds: CooldownEnds?`. Rewrite `.cooldown` branch in `computeMenuBarDisplay()` to read `cooldownEnds`. |
| `MacTorn/Views/StatusView.swift` | Migrate `LiveCooldownItem` (and any callers around lines 215-217 / 379-381) to `endsAt: Int` API. |
| `MacTorn/Views/FactionView.swift` | Fix line 32 (faction chain countdown). Migrate `OCStatusRow` (lines 166-168) to `crime.timeReady`. |
| `MacTornTests/Fixtures/TornAPIFixtures.swift` | Ensure fixtures include top-level `timestamp` and `cooldowns` durations so the new conversion path is covered. |
| `MacTornTests/ViewModels/AppStateTests.swift` (or new) | Add a test: feed `validFullResponse` with `cooldowns.booster=3600` and a known server `timestamp`; assert `appState.cooldownEnds?.boosterEndsAt == serverTimestamp + 3600`. |

## Verification

End-to-end, in this order:

1. **Unit tests** — `make test`. New cooldown-conversion test must pass; existing model tests must still pass.
2. **Manual UI check** — `make build`, run the app with a real API key while the user has an active booster cooldown:
   - Menu-bar booster countdown should match torn.com `/preferences.php#tab=info` countdown to within 1 s and stay matched over a 5-minute window (previously drifted ~30 s).
   - In Faction tab, chain timeout should now display a sensible "Xm Ys" rather than a giant epoch number.
   - In Faction tab during an OC, the per-crime countdown should match the in-game OC panel.
3. **Drift soak** — leave the app open for ≥10 minutes during travel + active booster, compare to torn.com web. The two countdowns should never disagree by more than 1 s. (Travel was already correct; the soak is to confirm cooldowns now behave the same way.)
4. **Regression sweep** — hospital, jail, user-chain timeout (already correct) must continue to match torn.com. These weren't touched but they share the `Date().timeIntervalSince1970` baseline; confirming them rules out an accidental regression in `serverTimestamp` plumbing.
