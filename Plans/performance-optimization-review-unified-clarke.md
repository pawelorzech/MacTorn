# MacTorn — Performance Optimization Review & Plan

## Context

MacTorn is a native macOS menu bar app (SwiftUI, `MenuBarExtra`) that polls Torn.com APIs and renders status, travel, money, attacks, faction, and watchlists. The audit framework in the prompt was written for web apps; this plan adapts it to the actual stack — **native macOS, single binary, no third-party SDKs, no CDN**. The audit is driven by what was found in the code, not by checklist items that don't apply.

Goal: identify perf hotspots that cause unnecessary CPU wake-ups, SwiftUI re-render fan-out, and redundant network/JSON work — then propose surgical fixes with measurable acceptance criteria. No rearchitecting; this codebase is fundamentally sound.

---

## Phase 1 — Discovery (verified, not guessed)

| Component | Version | Latest stable (2026-04) | Status |
|---|---|---|---|
| Swift toolchain | `SWIFT_VERSION = 5.0` (project setting) | Swift 6.x | ⚠️ Project still on Swift 5 language mode; toolchain itself is whichever Xcode ships |
| macOS deployment target | 14.0 (Sonoma) | 15.x (Sequoia) | ✅ Reasonable floor; raising to 14.0+ already done |
| App marketing version | 1.8.7 | — | ✅ |
| Build system | `xcodebuild` via `make`, code signing disabled (`-`) | — | ✅ Direct-distribution build |
| SPM dependencies | **none** | — | ✅ Zero third-party surface |
| Networking | `URLSession` via `NetworkSession` protocol | — | ✅ Injectable for tests |
| Persistence | `@AppStorage` + `UserDefaults` + Keychain (API key) | — | ✅ |
| Tests | XCTest (`MacTornTests`, `MacTornUITests`) | — | ⚠️ No perf/benchmark tests |

**Entry points:** `MacTorn/MacTornApp.swift` (`@main`, `MenuBarExtra` scene) → `Views/ContentView.swift` (tabs) → `ViewModels/AppState.swift` (orchestrator).

**External integrations:** none (no analytics, no crash reporter, no font CDN, no third-party scripts). The prompt's "third-party scripts" section is N/A.

---

## Phase 2 — Baseline measurement (commands to run BEFORE any change)

No metrics exist today. Establish baseline first, otherwise every claim of "faster" is unverifiable.

### Build perf
```bash
# Cold build time
make clean && time make build

# Release universal binary size
make release && du -sh build/dist/MacTorn.app build/dist/MacTorn.app/Contents/MacOS/MacTorn
file build/dist/MacTorn.app/Contents/MacOS/MacTorn   # confirm x86_64 + arm64
```

### Runtime CPU / energy (Instruments)
With the app launched against a real API key:
```bash
# CPU sampling, 60s, while traveling (live timer @ 1Hz active)
xcrun xctrace record --template 'Time Profiler' --time-limit 60s \
  --attach MacTorn --output baseline-cpu-traveling.trace

# Allocations + persistent footprint, 5 min normal idle
xcrun xctrace record --template 'Allocations' --time-limit 300s \
  --attach MacTorn --output baseline-allocs-idle.trace

# Energy / wakeups (use macOS' `Energy Log` template in Instruments GUI)
xcrun xctrace list templates | grep -i energy
```

Targets to inspect in trace:
- Main-thread time inside `AppState.tick()` per second
- `JSONDecoder.decode` cumulative time per 30 s poll cycle
- SwiftUI `_bodyAccessor` / `updateValue` calls per second on `MenuBarLabel`

### Network / fetch cycle
```bash
# Run app, inspect Console.app filtered to subsystem "MacTorn" (if logging exists)
log stream --predicate 'process == "MacTorn"' --info --debug

# Manual: count requests per cycle by tcpdump'ing api.torn.com
sudo tcpdump -i any -n 'host api.torn.com' -w torn-requests.pcap
# Open in Wireshark; expected per main poll: 1 user, 1 faction, 1 OC, N watchlist, M forum
```

### JSON decode profiling (unit-test microbench)
Add a perf XCTest using `measure { }` against fixtures in `MacTornTests/Fixtures/TornAPIFixtures.swift`:
```swift
func testDecodeFullResponsePerformance() {
    let data = TornAPIFixtures.validFullResponse.data(using: .utf8)!
    measure { _ = try? JSONDecoder().decode(TornResponse.self, from: data) }
}
```
Baseline number goes in commit message; re-run after each optimization.

### SwiftUI re-render counting
Temporary `Self._printChanges()` inside the `body` of `ContentView`, `MenuBarLabel`, `TravelView`, `WatchlistView` while traveling for 30 s. Capture log volume. Remove before merge.

---

## Phase 3 — Findings (file:line, verified)

Numbering matches the table in Phase 5.

### F1 — Live timer fans out into MenuBarLabel + multiple views at 1 Hz
`MacTorn/ViewModels/AppState.swift:377-385` — `Timer.publish(every: 1.0, on: .main, in: .common)` runs continuously while traveling / hospitalized / in jail / cooldown active. `tick()` writes `travelSecondsRemaining` and `menuBarDisplay` every second. Both are `@Published`. Observers: `MenuBarExtra` label (`MacTornApp.swift`), `TravelView`, header in `ContentView`. Even when the displayed seconds value hasn't changed (e.g. cooldowns shown as `Hh Mm`), the `@Published` write triggers SwiftUI invalidation.

### F2 — `manageLiveTimer()` may restart timer unnecessarily
`AppState.swift:358-367` — Called after every fetch. Logic is "if should run and cancellable nil, start". Code is correct, but `tick()` is called *before* the should-run check on each invocation, so a `tick` fires once per fetch even when no live state is active. Low impact, but noisy in profiles.

### F3 — Seven `@Published` writes per fetch cycle, no batching
`AppState.swift:948-1053` — Each successful poll writes `data`, `moneyData`, `battleStats`, `recentAttacks`, `propertiesData`, `stocksData`, `lastUpdated`, `lastFetchTime`. Each write triggers SwiftUI invalidation on every observer. Views observing `AppState` re-evaluate `body` 7+ times per fetch.

### F4 — No HTTP caching layer
`MacTorn/Networking/NetworkSession.swift` + `TornModels.swift` (`TornAPI` enum) — All requests bypass URL cache (the audit confirmed `.reloadIgnoringLocalAndRemoteCacheData` policy). Torn API does not return useful `ETag`/`Last-Modified` headers for the `user/?selections=...` endpoint, so true conditional GET is not possible — but the *menu reopen* path triggers `startPolling()` again and immediately re-fetches without a freshness check. See `Views/ContentView.swift:83-86`.

### F5 — Polling restarted on every menu open
`Views/ContentView.swift:83-86` — `.onAppear { appState.startPolling() ... }`. `MenuBarExtra` calls `onAppear` each time the popover opens. Inside `startPolling`, `timerCancellable?.cancel()` then re-creates the publisher. If user opens the menu 10× in 60 s, that's 10 poll restarts and 10 immediate fetches.

### F6 — Watchlist notifications not batched
`AppState.swift` watchlist loop (per audit, ~line 577-588) — Each item that crosses a threshold sends an immediate `UNUserNotification`. If the user has 10 items and 3 cross thresholds in the same poll, 3 notifications stack instead of one consolidated alert.

### F7 — Forum poll re-parses unchanged threads
`AppState.swift:704-728` — `withTaskGroup` is good, but the per-thread JSON is re-parsed every 180 s even when the post count hasn't changed since last poll. No in-memory `lastSeenPostCount` short-circuit before decode.

### F8 — Stocks metadata re-fetched on each poll if missing
`AppState.swift` — If the one-shot stocks metadata fetch failed at startup, the retry runs on every 30 s main poll. No backoff.

### F9 — Universal binary may be larger than necessary
No baseline measurement yet; needs `du -sh` from Phase 2. Strip dSYMs from distributed binary; `LD_GENERATE_MAP_FILE=NO` and `STRIP_INSTALLED_PRODUCT=YES` for Release.

### F10 — Swift 5 language mode
`SWIFT_VERSION = 5.0` in pbxproj. Swift 6 strict concurrency would surface several latent issues (e.g. `@MainActor` correctness in `AppState`) and enables better compiler optimizations. Larger change; flagged as strategic, not quick win.

---

## Phase 4 — Native-macOS technologies the app could adopt

Adapted from the prompt's web-tech list to the actual stack:

- **`AsyncTimerSequence` (macOS 13+)** — replace `Timer.publish` + Combine sink with `for await _ in Timer.publish(every: 1).values` inside a `Task { @MainActor in … }`. Smaller surface, cancellable via `Task.cancel()`.
- **`@Observable` macro (macOS 14+)** — drop-in replacement for `ObservableObject` + `@Published`. SwiftUI re-renders only views that actually read changed properties, eliminating most of F3's fan-out without code restructuring. Already targeting 14.0, so no platform bump needed. ([Apple docs — Observable](https://developer.apple.com/documentation/observation/observable))
- **`AsyncSequence` for fetch pipeline** — replace per-cycle Combine plumbing with `for await` loops; less ceremony, easier cancellation.
- **`URLSession.bytes(for:)` + streaming decode** — only worth it if a single response is big enough to matter; current responses are small JSON, skip.
- **`Logger` (os.log) with subsystem** — if not already used, enables `log stream` filtering for the perf measurement workflow.
- **`MetricKit` (`MXMetricManager`)** — built-in framework that delivers daily energy/CPU/launch reports for shipped apps. Worth wiring up for ongoing monitoring without third-party APM.
- **Build settings** — `SWIFT_OPTIMIZATION_LEVEL = -O` for Release, `SWIFT_COMPILATION_MODE = wholemodule`, `DEAD_CODE_STRIPPING = YES`. Verify they're already set; if not, this is a free win.

Skipped intentionally (don't apply): React Server Components, Edge runtime, ISR, image CDN, Brotli, HTTP/3, service workers, View Transitions API, Million.js — all web-only.

---

## Phase 5 — Action plan (sorted by impact / effort)

| # | Area | Problem | Solution | Expected impact | Effort | Risk | Priority |
|---|---|---|---|---|---|---|---|
| 1 | SwiftUI render | F1: 1 Hz `@Published` writes invalidate `MenuBarLabel` even when displayed string unchanged | In `tick()`, only write `menuBarDisplay` if new value `!=` old; same guard for `travelSecondsRemaining` | -50–80% main-thread wakeup work while traveling | S | Low | **P0** |
| 2 | SwiftUI render | F3: 7 sequential `@Published` writes per fetch cause 7 invalidation rounds | Migrate `AppState` from `ObservableObject` to `@Observable` macro (macOS 14+) | Removes most fan-out without changing call sites; only views reading the changed field re-render | M | Low–Medium (Swift 5/6 interop, @AppStorage interplay) | **P0** |
| 3 | Lifecycle | F5: poll restart on every menu open | Guard `startPolling()`: if a cancellable already exists and last fetch < `refreshInterval / 2`, do nothing. Add `lastPollStartedAt` | Eliminates redundant fetches when user toggles menu repeatedly | S | Low | **P0** |
| 4 | Notifications | F6: per-item watchlist notifications | Collect threshold-crossing items during the loop; emit one notification with summary ("3 items hit target") if ≥ 2, else single | Better UX + fewer wakeups | S | Low | **P1** |
| 5 | Forum | F7: re-parse threads with no change | Cache `lastPostCount` per thread in memory; skip JSON decode if `Content-Length` (or first/last byte) unchanged. Simpler: keep the cheap decode, but skip downstream notification logic | Mild CPU saving | S | Low | **P1** |
| 6 | Networking | F8: stocks metadata retried every 30 s | Add exponential backoff (60 s → 5 min → 30 min cap) after failure; reset on app restart | Avoids API quota burn | S | Low | **P1** |
| 7 | Build | F9: binary size unchecked | Measure with `du -sh`; verify `STRIP_INSTALLED_PRODUCT`, `DEAD_CODE_STRIPPING`, `SWIFT_OPTIMIZATION_LEVEL=-O`, `SWIFT_COMPILATION_MODE=wholemodule` for Release config | Smaller download, faster launch | S | Low | **P1** |
| 8 | Observability | No runtime perf telemetry | Wire `MXMetricManager` subscriber; log daily payloads via `Logger` | Free APM equivalent for shipped users | M | Low | **P2** |
| 9 | Tests | No perf regression guard | Add `XCTest.measure` benchmarks for `JSONDecoder` against `TornAPIFixtures`; one for full-response, one for watchlist | Prevents regressions in subsequent refactors | S | Low | **P2** |
| 10 | Code modernization | F10: Swift 5 language mode | Bump to Swift 6, fix strict concurrency warnings | Surfaces latent races, future-proofs codebase | L | Medium | **Strategic** |

### Top-10 quick wins (Sprint 1, ≤ 1 day each)
P0 #1 (tick equality guard), P0 #3 (poll-restart guard), P1 #4 (batched notifications), P1 #5 (forum short-circuit), P1 #6 (stocks backoff), P1 #7 (Release build flags audit), P2 #9 (perf XCTest), plus baseline measurement scripts (Phase 2). All small, low-risk, independently verifiable.

---

## Phase 6 — Roadmap

### Sprint 1 — Quick wins (≤ 1 day each)
| Item | Acceptance criterion (metric-based) |
|---|---|
| Baseline traces captured (Phase 2) | `baseline-cpu-traveling.trace` + `baseline-allocs-idle.trace` checked into `Plans/perf-baselines/` (or referenced) before any code change |
| #1 tick equality guard | In a 60 s `Time Profiler` run while traveling: `MenuBarLabel.body` evaluations ≤ 1 per second of *displayed* change (down from ≥ 1/s). Net main-thread time in `tick()` ≥ 30% lower |
| #3 poll-restart guard | Opening menu 5× in 10 s triggers ≤ 1 network request (verified via `tcpdump` of `api.torn.com`) |
| #4 batched watchlist notifications | When ≥ 2 items cross threshold in one poll, exactly 1 notification is delivered |
| #5 forum short-circuit | When no thread post counts changed, zero downstream notification work in trace |
| #6 stocks backoff | After forced stocks failure, retries follow 60 s → 300 s → 1800 s cap (asserted in unit test) |
| #7 Release build flags | `make release && du -sh build/dist/MacTorn.app/Contents/MacOS/MacTorn` shows ≤ baseline; `otool -L` clean |
| #9 perf XCTest baselines | `make test` records `JSONDecoder` baselines; commit message includes the numbers |

### Sprint 2–3 — Medium changes
| Item | Acceptance criterion |
|---|---|
| #2 `@Observable` migration | After migration, `Self._printChanges()` on `MenuBarLabel` shows ≤ 1 invalidation per actual `menuBarDisplay` value change (was 7+/poll). All existing tests pass; UI smoke test passes |
| #8 `MetricKit` wiring | First `MXMetricPayload` received and logged within 24 h of running on a real machine |

### Strategic (> 1 week)
| Item | Acceptance criterion |
|---|---|
| #10 Swift 6 strict concurrency | Project builds with `SWIFT_VERSION = 6.0` and `-strict-concurrency=complete`; zero new warnings; all tests pass on Intel + Apple Silicon |

---

## Critical files (paths to touch)

- `MacTorn/MacTorn/ViewModels/AppState.swift` — items #1, #2, #3, #4, #5, #6, #10 (1341 lines; the central file)
- `MacTorn/MacTorn/MacTornApp.swift` — item #2 (`@StateObject` → `@Bindable` after `@Observable` migration)
- `MacTorn/MacTorn/Views/ContentView.swift` — item #3 (`onAppear` guard)
- `MacTorn/MacTorn/Views/TravelView.swift`, `MenuBar*` related views — item #2 verification
- `MacTorn/MacTorn/Networking/NetworkSession.swift` — no change planned, but read during #3
- `MacTorn/MacTorn.xcodeproj/project.pbxproj` — item #7 (Release build flags), item #10 (Swift version)
- `MacTornTests/Fixtures/TornAPIFixtures.swift` — reused by #9 perf tests
- `MacTornTests/ViewModels/` — new perf test file under #9

## Existing patterns to reuse (don't reinvent)

- `NetworkSession` protocol + `MockNetworkSession` — reuse for any new test (#9)
- `TornAPIFixtures` — reuse for perf measurements; do **not** create a parallel fixture set
- `@AppStorage` for config — keep as-is; do not migrate config to a new system

---

## Verification plan (end-to-end)

After each Sprint 1 item:
1. `make test-all` — must pass (no behavior regression)
2. Re-run the matching baseline command from Phase 2 against the same scenario (traveling for #1, menu-toggling for #3, etc.); compare to saved baseline trace
3. Manual smoke: launch app with real API key, travel for 60 s, hospital state, idle, watchlist with ≥ 2 items at threshold — confirm UI behavior unchanged
4. Commit message includes before/after numbers

After Sprint 2 (`@Observable` migration):
1. All unit tests + UI tests pass
2. `Self._printChanges()` log diff before/after attached to PR
3. `xctrace` Allocations diff shows no leaks introduced

## Constraints honored

- No optimization proposed without a measurement step (Phase 2 first).
- No API contract changes (Torn API is external; we don't control it).
- No new dependencies (the project has zero SPM deps; this plan keeps it that way — `MetricKit` is in the SDK).
- Every recommendation cites a file:line or Apple docs reference.
- #10 (Swift 6) flagged as strategic and requiring buy-in before scheduling.

## Open questions (need product input before scheduling)

1. **#2 `@Observable` migration vs incremental fix to F3** — full migration is the right answer technically, but it touches every view. Acceptable to schedule as Sprint 2, or prefer a smaller patch (e.g. coalescing the 7 writes into a single `applyFetchResult(_:)` that does one `objectWillChange.send()`)?
2. **Notification batching (#4)** — does Paweł prefer one summary notification when multiple watchlist items hit, or keep per-item alerts for granularity?
3. **Stocks backoff cap (#6)** — is 30 min cap acceptable, or should the app stop retrying entirely after N failures and surface a UI hint?
