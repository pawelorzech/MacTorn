# Prompt audit — MacTorn agent surface

Last verified: c71ee24 | 2026-09-25

Run via `/claude-api prompt-audit`. **Status: all hunks applied 2026-09-25.** F10 uses hdiutil UDZO (confirmed by Paweł). F12: CLAUDE.md stays local and gitignored (Paweł's call), so F1–F4, F13 and F14 were applied to the local file only.

## Assumptions

- **Scope:** the whole repo's prompt surface. MacTorn has no Anthropic SDK or request-building code (`com.openai.atlas` in `BrowserManager.swift` is a browser bundle ID, not a provider). So the surface is four agent-instruction files:
  - `CLAUDE.md` (gitignored: no blame history, and CI agents never see it)
  - `.claude/commands/new-version.md` (tracked; it came from the Android command in 63cef35 and was fixed in 6c4639b and d39b26e)
  - `.github/workflows/claude.yml`, `.github/workflows/claude-code-review.yml`
- **Target model:** the model Claude Code runs these files with, which is Claude Opus 5.5 in this session. Nothing in the repo pins a model.
- **Group 4 (request config)** does not apply because the repo has no API calls.

## Summary

| Group | Findings |
|---|---|
| 1 — Dated prompt text | 1 (pressure language, new-version.md) |
| 2 — Brittle skill files | 7 (4 stale facts in CLAUDE.md, recency-trap line, history note, wrong artefact claim) |
| 3 — Tool/contract | 2 (allowed-tools mismatch, underspecified install step) |
| 4 — Request config | n/a |
| Flag-only | 3 |

The three findings that matter most:

1. **`CLAUDE.md:83` says the API key is stored in `@AppStorage`.** It is actually in the Keychain (`KeychainStore`, `AccountSessionStore.swift:104`). An agent that trusts this line could write key-handling code against UserDefaults. This is security-relevant drift.
2. **In `new-version.md`, `allowed-tools` doesn't cover the commands the steps require.** Step 2 needs `git show` and `grep`, step 8 needs `shasum`, and step 10 needs a copy into `/Applications`. The release will stall on permission prompts partway through, or those steps will be skipped silently.
3. **`new-version.md:59-66` says `make release` produces a "zipped/DMG artefact".** It doesn't: `make release` only builds `DerivedData/Release/Build/Products/Release/MacTorn.app`. No script in the repo makes the DMG, but v1.15.0 shipped `MacTorn-v1.15.0.dmg` plus `.sha256`. The step describes an artefact that no command creates.

## Findings

| # | Location | Evidence | Pattern | Why obsolete / wrong | Conf. | Action |
|---|---|---|---|---|---|---|
| F1 | `CLAUDE.md:83` | "`@AppStorage` for API key" | G2 volatile specifics | Key moved to Keychain (`KeychainStore`); the context now misleads on a security boundary | High (verified) | rewrite |
| F2 | `CLAUDE.md:47` | "Also contains `TornAPI` enum with endpoint configurations" | G2 volatile specifics; duplicates that disagree (keep-list #8 exception) | `TornAPI` exists only as a test shim (`MacTornTests/Models/TornEndpointTests.swift:6`); contradicts L87, which names `TornEndpointRegistry` as the single source of truth | High (verified) | rewrite |
| F3 | `CLAUDE.md:82` | "separate `travelTimerCancellable`" | G2 volatile specifics | Symbol doesn't exist; the 1 s timer is `liveTimerCancellable`, driven by `manageLiveTimer()` in `AppState+LiveNextAction.swift` | High (verified) | rewrite |
| F4 | `CLAUDE.md:43-61, 75` | AppState "central state manager…"; Views list; `validFullResponse` | G2 volatile specifics | AppState is split across 9 `AppState+*.swift` extensions plus 6 services/stores (`FactionService`, `UserSnapshotService`, `MarketWatchService`, `ForumWatchService`, `CompanionStore`, `AccountSessionStore`); the map omits Stocks/Properties/ForumWatch/Diagnostics/Credits/Companion views; the test snippet references `validFullResponse` as a property, but it is a function (`validFullResponse()`), so the snippet doesn't compile | High (verified) | rewrite |
| F5 | `new-version.md:32-41` | "**MANDATORY** … every single release, with no exceptions. This is not optional and not 'only if it feels like a big release' … do not repeat that … in **every** build configuration" | G1a pressure language; G1c repetition (restates L21-26) | The constraint is real and has a reason (Diagnostics `build`). Stacked emphasis on current models over-applies and sets an anxious register; the reason alone carries the rule. The verification script stays verbatim (fragile op, keep-list #3) | Medium | rewrite |
| F6 | `new-version.md:36-37` | "It has been left at `1` across releases before (GitHub issue #57) — do not repeat that." | G2 history narratives | The rule's authority is the check below it, not the incident | Medium | remove (folded into F5 hunk) |
| F7 | `new-version.md:44` | "# All six occurrences must agree" | G2 volatile specifics | pbxproj has **8** `CURRENT_PROJECT_VERSION` lines today; the script is count-agnostic (`sort -u`), only the comment is wrong | High (verified) | rewrite (in F5 hunk) |
| F8 | `new-version.md:17` | "**This is a Swift / Xcode project. There are no Gradle files.**" | G2 recency trap; G1c prohibition that anchors | Patch for the Android-derived original (63cef35). With the pbxproj location stated right below, the Gradle negation only plants the wrong idea | Medium | rewrite |
| F9 | `new-version.md:2` | `allowed-tools: … Bash(git push:*), Bash(gh release:*), Bash(make:*)` | G3 contract mismatch | Steps need `git show`, `grep`, `shasum`, `hdiutil`, `ditto`, which aren't allowed, so the command stalls or skips steps | High (verified) | add |
| F10 | `new-version.md:58-68` | "the zipped/DMG release artefact produced by `make release`" | G2 volatile specifics; G2 wrong degrees of freedom | `make release` yields a bare `.app`; the DMG + `.sha256` sidecar are produced by an undocumented manual step | High (verified) | rewrite |
| F11 | `new-version.md:69-70` | "**Replace the local install too.** … otherwise the user keeps running the old build." | G2 wrong degrees of freedom | Fragile, destructive op (overwrites `/Applications/MacTorn.app`) given as intent with no command; the reason is good, the mechanism is missing | Medium | add |
| F12 | `CLAUDE.md` (whole file) | `.gitignore:75` ignores `CLAUDE.md` | out of scope (architecture) | The `@claude` and code-review workflows check out the repo without it, so CI agents never see the Torn API rules (row-cap, chain-on-faction, 403≠bad key). This may be deliberate | — | flag |
| F13 | `CLAUDE.md:11-32` | Build Commands lists 7 of ~22 Make targets | idiom | Missing `coverage-gate`, `verify-release`, `quick-test`; could point at `make help` instead. Not a dated pattern | Low | flag |
| F14 | `CLAUDE.md:16,19` | `make test-ui`, `make test-all` listed with no caveat | keep-list #11 (re-baseline adds text) | The "XCUITest steals focus, ask first" rule lives only in the release command, so a normal session can run UI tests unprompted. One added line would fix it | Low | flag |

### Deliberately kept

- **The CLAUDE.md Torn API section (L85-106).** Every "must" has a reason, and the claims check out against the code: `liveChain` and `factionService` exist, and `TornEndpointRegistry` generates the README table. This is context only the author has.
- **`new-version.md:54-56`, the `test-ui` prohibition.** It is a reasoned constraint (focus stealing) against a failure that still happens.
- **The `new-version.md` step 8 rationale** (not notarised, issue #59). It is the reason for the constraint, not archaeology.
- **The numbered release steps.** Order matters here (tag → build → checksum → publish), so this is keep-list #3.
- **The `new-version.md` frontmatter `description`.** It is trigger text (keep-list #6).
- **Both workflows.** `claude.yml` has no prompt. `claude-code-review.yml`'s prompt is a bare slash command. The long comment blocks in both never reach the model. The workflow surface is clean.

## Proposed diff

One hunk per finding. Nothing is applied. The DMG command in F10 is an **assumption** (standard `hdiutil` UDZO): replace it with whatever produced `MacTorn-v1.15.0.dmg`.

### F1 — CLAUDE.md:83

```diff
-4. **State Persistence**: Uses `@AppStorage` for API key, refresh interval, appearance mode; `UserDefaults` for notification rules and watchlist
+4. **State Persistence**: The API key lives in the Keychain (`KeychainStore`, `AccountSessionStore.swift`) — never UserDefaults/`@AppStorage`. `@AppStorage` holds UI preferences (refresh interval, appearance mode); `UserDefaults` holds notification rules and the watchlist.
```

### F2 — CLAUDE.md:47

```diff
-- `TornModels.swift` - All data models including `TornResponse`, `Bar`, `Travel`, `Status`, `Chain`, `WatchlistItem`, etc. Also contains `TornAPI` enum with endpoint configurations.
+- `TornModels.swift` - Data models including `TornResponse`, `Bar`, `Travel`, `Status`, `Chain`, `WatchlistItem`. Endpoint configuration lives in `Networking/TornEndpoint.swift` (see Torn API below).
```

### F3 — CLAUDE.md:82

```diff
-3. **Live Countdown**: Travel timer updates every second independently of API polling using separate `travelTimerCancellable`
+3. **Live Countdown**: A 1-second `liveTimerCancellable` (`manageLiveTimer()` in `AppState+LiveNextAction.swift`) ticks countdowns independently of API polling, and runs only while something needs it (e.g. travelling).
```

### F4 — CLAUDE.md:43-44, 49-52, 75

```diff
 **ViewModels**
-- `AppState.swift` - Central state manager using `@MainActor`. Handles API polling, data parsing, notification scheduling, and watchlist management. Uses dependency injection via `NetworkSession` protocol for testability.
+- `AppState.swift` - Central `@MainActor` state, split by concern into `AppState+*.swift` extensions (polling/user fetch, faction fetch, market/forum, notifications, persistence/stocks, live timer, widgets, item catalog). Takes a `NetworkSession` for testability.
+- Services owned by AppState: `UserSnapshotService`, `FactionService`, `MarketWatchService`, `ForumWatchService`, `CompanionStore`, `AccountSessionStore` (accounts + Keychain).
```

```diff
 **Views** (in `Views/`)
 - `ContentView.swift` - Main tab container
-- Tab views: `StatusView`, `TravelView`, `MoneyView`, `AttacksView`, `FactionView`, `WatchlistView`, `SettingsView`
+- Tab views: `StatusView`, `TravelView`, `MoneyView`, `AttacksView`, `FactionView`, `WatchlistView`, `StocksView`, `PropertiesView`, `ForumWatchView`, `SettingsView` (plus `DiagnosticsView`, `CreditsView`, `CompanionViews`)
 - Components: `ProgressBarView`, `StatusBadgesView`, `ChainView`, `EventsView`
```

```diff
-try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse)
+try mockSession.setSuccessResponse(json: TornAPIFixtures.validFullResponse())
```

### F5 + F6 + F7 — new-version.md:32-51

```diff
-2. **MANDATORY — bump `CURRENT_PROJECT_VERSION` too, every single release, with no
-   exceptions.** This is not optional and not "only if it feels like a big
-   release": it is the build number `Diagnostics` reports as `build`, and it is
-   the only thing that distinguishes two builds of the *same* marketing version
-   in a bug report. It has been left at `1` across releases before (GitHub
-   issue #57) — do not repeat that. Increment it (e.g. by 1, or to match the
-   running release count) in **every** build configuration in `project.pbxproj`.
-   Verify before moving on — this check must stay valid for *every* future
-   release, so compare against the previous commit rather than a hardcoded
-   number:
+2. Bump `CURRENT_PROJECT_VERSION` on every release, in every build configuration
+   (usually +1). It's the `build` that `Diagnostics` reports — the only way to
+   tell two builds of the same marketing version apart in a bug report. Verify
+   against HEAD before moving on:
 
    ```sh
-   # All six occurrences must agree with each other, and the value must be
-   # strictly greater than the one currently on HEAD.
+   # All occurrences must agree, and the value must exceed the one on HEAD.
```

### F8 — new-version.md:17-18

```diff
-**This is a Swift / Xcode project. There are no Gradle files.** The version lives in
-`MacTorn/MacTorn.xcodeproj/project.pbxproj`:
+The version lives in `MacTorn/MacTorn.xcodeproj/project.pbxproj`:
```

### F9 — new-version.md:2

```diff
-allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git tag:*), Bash(git push:*), Bash(gh release:*), Bash(make:*)
+allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*), Bash(git tag:*), Bash(git push:*), Bash(git show:*), Bash(git diff:*), Bash(git branch:*), Bash(git log:*), Bash(grep:*), Bash(gh release:*), Bash(make:*), Bash(hdiutil create:*), Bash(shasum:*), Bash(ditto:*)
```

### F10 — new-version.md:58-68

```diff
-7. Build the distributable: `make release` then `make verify-release`.
-8. **Compute and publish the SHA-256 checksum of the release artefact.** MacTorn
-   is not notarized or signed with a paid Developer ID (deliberate, out of
-   scope — see GitHub issue #59), so a checksum is the only thing a user can
-   verify a download against. Run `shasum -a 256` against the zipped/DMG
-   release artefact produced by `make release` and paste the resulting hash
-   into the GitHub release notes, e.g.:
-   `shasum -a 256 <path-to-release-artifact>`
-   Label it clearly in the release notes, e.g. `SHA-256: <hash>`.
-9. Publish the GitHub release with `gh release create`, including the SHA-256
-   line from step 8 in the release body.
+7. Build and verify: `make release` then `make verify-release`. This produces
+   `DerivedData/Release/Build/Products/Release/MacTorn.app` — not a DMG.
+8. Package and checksum. MacTorn is not notarized or Developer-ID signed
+   (deliberate — issue #59), so the checksum is the only thing a user can verify
+   a download against:
+
+   ```sh
+   hdiutil create -volname MacTorn -srcfolder DerivedData/Release/Build/Products/Release/MacTorn.app -ov -format UDZO MacTorn-vX.Y.Z.dmg
+   shasum -a 256 MacTorn-vX.Y.Z.dmg | tee MacTorn-vX.Y.Z.dmg.sha256
+   ```
+9. `gh release create vX.Y.Z MacTorn-vX.Y.Z.dmg MacTorn-vX.Y.Z.dmg.sha256` with
+   `SHA-256: <hash>` in the release body.
```

### F11 — new-version.md:69-70

```diff
-10. **Replace the local install too.** Every published release must also replace
-    the copy in `/Applications`, otherwise the user keeps running the old build.
+10. Replace the local install, otherwise the user keeps running the old build.
+    Quit the running app first, then:
+    `ditto DerivedData/Release/Build/Products/Release/MacTorn.app /Applications/MacTorn.app`
```

## Verify before taking hunks

- **F10:** first confirm how v1.15.0's DMG was actually made (volume name, layout, any `/Applications` symlink). The `hdiutil` line is a reasonable default, not the recorded procedure.
- **F9:** run `/new-version` once in a normal-permission session to confirm the command no longer prompts partway through.
- **F1–F4:** these are factual corrections. `rg` each new symbol after applying.
- **Out-of-scope drift found in passing:** the `UITestSupport.swift:33` comment places `KeychainStore` in `AppState.swift`, but it lives in `AccountSessionStore.swift`.
