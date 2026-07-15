---
project: MacTorn
task: Reliability + product quality audit (Etap A–L), staged
effort: E4
phase: verify
progress: stage-1 of program
mode: algorithm
started: 2026-07-15
updated: 2026-07-15
---

# MacTorn — Reliability & Product Audit ISA

> System-of-record for the multi-stage MacTorn quality program. The full audit brief
> (Etap A–L) is a multi-week program; this file tracks what has shipped and what is
> deferred, with reasons. **Stage 1** (this branch, `audit/reliability-product-pass`)
> delivered the reliability + correctness spine. Later stages append here.

## Problem

MacTorn is a mature (v1.9.2), well-tested (253 unit tests) menu-bar app, but three
structural weaknesses remain:

1. **Test non-determinism.** `AppState` hardcoded `UserDefaults.standard` at 20 sites,
   so parallel test runs raced on shared keys — one flaky failure on `main`
   (`testPriceThreshold_persistedWithWatchlist`), making the suite an unreliable gate.
2. **Untyped API surface.** Endpoints/selections and their budget characteristics live
   as scattered `TornAPI` builders and comments. Errors are surfaced as a string but
   not *classified*, so the app cannot react differently to a dead key vs. a transient
   backend blip vs. a per-category daily limit — and it never stops hammering a key
   that will never work.
3. **Notification duplication.** The chain-expiring alert fired on *every* poll while
   the timeout was under 60s (a burst of identical banners), with no persistent
   de-duplication.

Beyond these, the app is a 1,700-line `AppState` god object with no dedicated polling
coordinator, no diagnostics surface, and a 7-tab/320px navigation that is cramped.

## Vision

A menu-bar app you can trust to be quiet and correct: it alerts you exactly once per
real event, never burns your Torn API budget, stops cleanly when your key is wrong,
recovers on reconnect, and can prove all of that through an in-app diagnostics screen —
while a green, deterministic test suite gates every change.

## Out of Scope

- Writing to Torn (any action-taking) — MacTorn stays strictly read-only.
- Scraping Torn web pages — official API only.
- Certificate pinning for `api.torn.com` (documented accepted risk F-05).
- Requiring a paid Apple Developer ID for local development (F-04 accepted risk).
- A big-bang rewrite of `AppState` — decomposition is incremental, regression-tested.
- Guessing API response shapes for data the official endpoints don't provide — such
  gaps are documented and skipped, not fabricated.

## Principles

- **Determinism before features.** A test suite that isn't reliably green can't gate
  anything, so it is fixed first.
- **Single source of truth.** One typed registry drives requests, docs, the usage
  screen, and onboarding disclosure — not several hand-maintained lists.
- **Classify, then react.** An error's *type* (permanent key / rate limit / daily row
  limit / transient / transport) determines the response; a bare message does not.
- **Fire once per real event.** De-duplication is persistent (survives restart) and
  re-arms only when a genuinely new event begins.
- **No secrets or PII anywhere they can leak** — logs, notifications, diagnostics.

## Constraints

- Swift / SwiftUI, `MenuBarExtra`, macOS 14+, Universal Binary (arm64 + x86_64).
- App Sandbox + Hardened Runtime stay on; API key stays in Keychain; URLs stay redacted.
- Sentry remains opt-in.
- New source/test files must be wired into the (non-synchronized, objectVersion 56)
  `project.pbxproj` by hand.
- No behaviour change to existing features without a regression test.

## Goal

Ship the reliability + correctness spine (deterministic tests, typed API registry,
typed error taxonomy + backoff, persistent notification de-duplication with the chain
bug fixed, `SECURITY.md`) as green, tested, regression-safe commits on
`audit/reliability-product-pass`, and record the remaining Etap A–L program as a
tracked backlog with deferral reasons.

## Criteria

**Stage 1 — shipped (this branch):**

- [x] ISC-1: `AppState` takes an injectable `UserDefaults`; production uses `.standard`.
- [x] ISC-2: Every AppState-constructing test isolates its own suite; the previously
  flaky `testPriceThreshold_persistedWithWatchlist` passes under parallel testing.
- [x] ISC-3: Unit suite is green **and deterministic** across ≥8 parallel runners.
- [x] ISC-4: A typed `TornEndpoint` registry catalogs all 10 endpoints with version,
  path, selections, access level, purpose, cadence, data shape, record limit, cache
  policy, budget category, and critical/optional.
- [x] ISC-5: A contract test asserts every registry URL equals its legacy `TornAPI`
  builder (single source of truth, no drift).
- [x] ISC-6: The registry generates a README-ready markdown table + onboarding
  disclosure (selections list, required access level).
- [x] ISC-7: `TornAPIError` classifies Torn codes into permanent-key / insufficient-
  permissions / rate-limit / daily-row-limit / temporary-backend, plus offline /
  transport / malformed / cancelled.
- [x] ISC-8: `haltsAllRequests` is true for codes 2, 16, 18; `haltsCategoryOnly` is
  true for code 14 (and false for `haltsAllRequests`).
- [x] ISC-9: `RetryPolicy` implements the 2/5/15/30/60s ladder capped at 5 min, with
  bounded equal-jitter; delay never exceeds the cap.
- [x] ISC-10: `NotificationCoordinator` provides persistent edge-latch + epoch dedup
  that survives restart and re-arms on a new event.
- [x] ISC-11: The chain-expiring alert fires exactly once per crossing into the danger
  window and re-arms after a member hit — proven by an AppState-level regression test.
- [x] ISC-12: `SECURITY.md` exists with a private disclosure path and supported-version
  policy.
- [x] ISC-13: Anti: no test or log reveals the API key, full URLs, or player PII (the
  determinism refactor preserves the existing redaction; new error messages are
  sanitised + length-capped).
- [x] ISC-14: Anti: no existing feature behaviour changed without a regression test
  (253 prior tests still pass; chain path covered before change).

**Deferred — backlog (later stages, with reasons):**

- [x] ISC-15: Etap B — `tornAPIError(in:)` classifies the live v1/v2 error envelope; a
  permanent key/permission error (codes 2/16/18) now **halts polling** (`keyHalted`
  latch stops auto-restart on MenuBarExtra open) with a clear message, and clears when
  the key changes. Verified by `AppStateTests` (halt / no-restart / key-change-clears)
  and `TornAPIErrorTests` (envelope classification).
- [x] ISC-15.1: Etap B (category pause for error 14) — a daily-row-limit (code 14) on a
  row-based source now pauses **only that source** (keyed by endpoint id, not budget
  category, so `faction.news` pausing never stops the point-in-time `faction.basic` chain
  data) for a rolling 1 h window, re-arming off the injected `TimeSource`; bars/countdowns
  keep polling. Wired into `user.activity` and `faction.news` (the main poll's row sources).
  Verified by `AppStateTests` (`testDailyRowLimitPausesOnlyRowSources`,
  `testRowSourcePauseReArmsAfterWindow`).
- [x] ISC-16: Etap C — key validation/onboarding. Calls the official Torn v2 `/key/info`
  endpoint (shape verified against the live OpenAPI spec, not guessed) via
  `TornAPI.keyInfoURL` + a `key.info` registry entry. `TornKeyInfo` decodes access
  level/type, the owner's IDs, and the per-category available selections; `KeyValidator`
  maps that to per-endpoint availability using the registry as the source of truth.
  `AppState.validateKey()` fetches + classifies errors through `TornAPIError` (PII-free
  messages). SettingsView gains a **"Test Connection"** button whose result panel shows the
  real access type + player ID and, when the key is limited/Custom, exactly which features
  won't load. The API disclosure now states the required access level, that the key lives in
  the Keychain, that all data stays local, that Sentry is opt-in, and lists the requested
  selections **from the registry** (no hand-maintained drift) + the ToS link. Verified by
  `KeyValidationTests` (11: decode / validator / `validateKey` success+error+empty+reset) and
  the `testTestConnectionReportsAccess` UI test. *(Result panel not visually verified — logic
  + interaction only.)*
- [ ] ISC-16.1: Etap C (hard module gating) — the validation result *names* the blocked
  modules with a clear explanation, but tabs are not hard-removed/disabled from the bar.
  *(Deferred by choice: gating must be fail-open — a user may never run Test Connection, and
  key-info can be briefly unavailable — so hiding tabs on absent/stale key-info risks hiding
  features that actually work. The app already degrades gracefully (unavailable endpoints
  error-handle to empty state); the explicit "these won't load" list is the safe first step.
  Per-tab access banners driven by `keyInfo` are the natural follow-up.)*
- [x] ISC-17: Etap D (budget + reconnect) — `PollingCoordinator` measures requests/min,
  requests/day and rows/day/category against the registry, with a 60/min hard-cap gate
  (`canMakeRequest()`) wired into `fetchData` and `record()` at all 9 request sites; a
  shared injectable `TimeSource`; and immediate refresh on a down→up connectivity edge.
  Verified by `PollingCoordinatorTests` (11) + AppState budget/reconnect tests (3).
- [ ] ISC-17.1: Etap D (schedule ownership, D-02) — move the Combine poll timer, adaptive
  cadence and sleep/wake handling out of `AppState` into the coordinator so it owns the
  schedule, not just the accounting. *(Deferred: the high-regression-risk extraction; the
  measurable budget/reconnect wins land first without destabilising the poll loop.)*
- [ ] ISC-18: Etap E — route the remaining categories (cooldown ready, landing,
  release, OC ready, bounty, price alert, forum, bar threshold) through the
  coordinator's epoch dedup. *(Deferred: coordinator primitives are built + tested;
  this is mechanical wiring per category with a test each.)*
- [x] ISC-19: Etap F — Diagnostics screen (app/macOS/arch, network + notification
  permission, key present + required access, last refresh, request/record counters from
  PollingCoordinator, and per-endpoint outcome/latency/size from `EndpointHealthTracker`)
  reachable from Settings, with a **"Copy sanitized report"** that carries none of: key,
  full URLs, player name/ID, money, stats, faction/company names, or raw payloads.
  Verified by `DiagnosticsTests` (PII-safety of `sanitizedText()`).
- [x] ISC-19.1: Etap F (F-02) — endpoint health (outcome/latency/size) now recorded across
  the **continuous poll fan-out** (`faction.basic`, `user.activity`, `user.v2`,
  `faction.rankedwars`, `faction.news`), not just `user.fast`/`key.info`. Verified by
  `testFetchDataRecordsHealthForFanOutEndpoints`. *(Remaining: the event-driven endpoints —
  `market.item`, `forum.thread`/`threads`, `torn.stocks` — are per-item/rare and structurally
  different (loops, backoff); instrumenting them is low value and left as a small follow-up.)*
- [x] ISC-20: Etap G — deterministic UI-test harness + real UI tests + hardened CI.
  `--uitesting` builds `AppState` from fixtures/doubles (`FixtureNetworkSession` URL-routed
  canned JSON, isolated ephemeral `UserDefaults`, in-memory `KeychainStore` override,
  `UITestConnectivity`) and surfaces the MenuBarExtra content in a real window XCUITest can
  drive (accessory app promoted to a regular activation policy + explicit `openWindow`). Real
  UI tests: onboarding-without-key, tab navigation, invalid-key error surfacing (green ×4
  consecutive runs, deterministic). `continue-on-error` removed from the UI-tests job so it
  gates merges. Coverage gate (`scripts/coverage-gate.sh`, dependency-free `xccov`) enforces
  ≥80% line coverage on the reliability-critical modules — currently TornAPIError 99%,
  TornEndpoint 84%, PollingCoordinator 100%, NotificationCoordinator 100%, NextAction 97% —
  views excluded by design. All harness/fixture surface is DEBUG-gated (verified: no
  `TestPlayer`/`FixtureNetworkSession`/launch-arg strings in the Release binary). Verified by
  `MacTornUITests` (3) + `UITestHarnessTests` (7) + `make coverage-gate`. *(Views not visually
  verified — logic/interaction only, per the audit's visual caveat.)*
- [ ] ISC-20.1: Etap G (remaining UI scenarios, fake clock in UI harness) — offline→reconnect
  and chain-alert-no-duplicates are **not** driven through the UI. *(Deferred: reconnect is
  already proven by `PollingCoordinatorTests`/AppState reconnect tests, and chain-dedup by the
  `NotificationCoordinator` regression tests (ISC-11); a MenuBarExtra window can't reliably
  observe a system notification, so a UI test there would assert nothing new. The UI harness
  uses the real clock — current UI tests assert no absolute time — while `MutableTimeSource`
  stays wired for unit tests.)*
- [ ] ISC-20.2: Etap G (key-validation in the coverage gate) — add the ISC-16 key-info/
  validation module to `coverage-gate.sh` once Etap C lands. *(Deferred: the module does not
  exist yet; gating a non-existent file would just fail the build.)*
- [ ] ISC-21: Etap H — CI overhaul (current Xcode, required UI tests, archive smoke,
  coverage, SwiftLint, entitlements/codesign/lipo checks, Dependabot). *(Deferred:
  CI changes; `SECURITY.md` done.)*
- [ ] ISC-22: Etap I — extract `TornAPIClient`, `PollingCoordinator`,
  `NotificationCoordinator` (started), stores from `AppState`. *(Incremental;
  `NotificationCoordinator` extracted this stage.)*
- [x] ISC-23: Etap J — "Next Action" unified event timeline. A pure `NextActionEngine`
  turns a decoupled snapshot (bars-full / cooldowns / travel / hospital / jail /
  education / OC / chain / refills, as absolute Unix timestamps off the shared
  `TimeSource`) into a sorted, future-only, hide-filtered list; surfaced as a live
  count-down card at the top of the Status tab, with per-category show/hide in Settings.
  Verified by `NextActionTests` (ordering, future-only, hide, tie-break, refills-ready).
- [ ] ISC-23.1: Etap J (menu-bar variant, J-02) — show the next event in the menu bar
  with compact/verbose + icon/timer/value options. *(Deferred: the menu bar has its own
  `MenuBarDisplay` logic; integrating Next Action there is a separate change.)*
- [ ] ISC-24: Etap K — navigation/accessibility redesign (3–4 sections + More, reorder,
  VoiceOver, larger targets). *(Deferred UX work.)*
- [ ] ISC-25: Etap L — release engineering (Developer ID/notarization, SHA-256, Sparkle).
  **WON'T DO (2026-07-15, Paweł's decision):** Developer ID + notarization require a paid
  Apple Developer Program, which Paweł does not want (consistent with accepted risk F-04).
  The `release-signed` Makefile scaffold + ad-hoc Universal Release remain; revisit only
  if a paid program is ever set up. SHA-256 checksums of release artifacts could still be
  added cheaply if desired, but the signing/notarization core is out of scope.

## Test Strategy

| isc | type | check | threshold | tool |
| --- | --- | --- | --- | --- |
| ISC-2,3 | determinism | flaky test passes under parallelism | 100% green, ≥8 runners | `xcodebuild test` |
| ISC-4,5,6 | contract/unit | registry URL == TornAPI; metadata invariants | all pass | `TornEndpointTests` |
| ISC-7,8,9 | unit | code→class map, halt semantics, backoff bounds | all pass | `TornAPIErrorTests` |
| ISC-10,11 | unit + regression | dedup latch/epoch; chain fires once + re-arms | all pass | `NotificationCoordinatorTests` |
| ISC-12 | inspection | file exists, disclosure path present | present | `Read` |
| ISC-13 | inspection | no key/PII in new code paths | none | grep / review |
| ISC-14 | regression | prior suite still green | 253/253 | `xcodebuild test` |

## Features

| name | satisfies | depends_on | parallelizable |
| --- | --- | --- | --- |
| UserDefaults injection | ISC-1,2,3,14 | — | no (foundation) |
| TornEndpoint registry | ISC-4,5,6 | — | yes |
| TornAPIError + RetryPolicy | ISC-7,8,9 | — | yes |
| NotificationCoordinator + chain fix | ISC-10,11 | injection | yes |
| SECURITY.md | ISC-12 | — | yes |

## Decisions

- 2026-07-15: Scoped this session to the **reliability spine** (Paweł's choice among
  spine / Next-Action / architecture forks). Rationale: Torn-API correctness and
  security are already largely done (v1.9.x, F-01…F-12); the spine is the foundation
  every deferred stage builds on, is low regression-risk, and is fully testable.
- 2026-07-15: Registry kept as a *parallel* typed catalog cross-checked against
  `TornAPI` by a contract test, rather than immediately rewriting all `TornAPI` +
  AppState call sites. Reason: a full builder migration is a wider, riskier refactor;
  the contract test guarantees no drift in the meantime (ISC-15/A-02).
- 2026-07-15: Chain fix implemented via an edge-latch (arm when timeout ≥ threshold or
  chain inactive; fire on the falling edge into < threshold) rather than an epoch,
  because "re-arm when the danger clears" is exactly a rising-edge signal.
- 2026-07-15: `TornAPIError` classification built + tested but **not yet wired** into
  `AppState.fetchData`. Reason: changing the live error path safely needs its own
  regression harness; shipping the tested model now de-risks the wiring later (ISC-15).
- 2026-07-15: Voice/Pulse announcements from the Algorithm doctrine skipped — Pulse is
  permanently disabled in this environment (no `localhost:31337`).

## Changelog

- conjectured: the single flaky test was inherent test-order fragility.
  refuted_by: it only failed under *parallel* runners sharing `UserDefaults.standard`.
  learned: the root cause was production code (hardcoded global store), not the test;
  the fix is dependency injection, which also unblocks the Etap G fake-clock harness.
  criterion_now: ISC-1 (injectable defaults) precedes ISC-2/3 (isolated, green).

## Verification

- ISC-1: `Read` AppState.swift — `init(…, defaults: UserDefaults = .standard)`, 20
  sites route through `defaults`.
- ISC-2,3,14: `xcodebuild test -only-testing:MacTornTests` — green across 8 parallel
  runners; previously-flaky test passes. (See PR for full numbers.)
- ISC-4,5,6: `TornEndpointTests` (11 tests) pass — incl. URL-contract vs `TornAPI`.
- ISC-7,8,9: `TornAPIErrorTests` (17 tests) pass.
- ISC-10,11: `NotificationCoordinatorTests` (12 tests) pass — incl.
  `testChainAlertFiresOnceAcrossManySubThresholdPolls`.
- ISC-12: `SECURITY.md` present at repo root.
- ISC-15.1 / ISC-19.1: `AppStateTests` — `testDailyRowLimitPausesOnlyRowSources`,
  `testRowSourcePauseReArmsAfterWindow`, `testFetchDataRecordsHealthForFanOutEndpoints` green;
  full unit suite 352 green; Release Universal builds; coverage gate PASSED.
- ISC-16: `KeyValidationTests` (11) green — model decode against the verified `/key/info`
  schema, `KeyValidator` availability (full/Custom-missing-selection/empty-faction/
  parameterized), and `AppState.validateKey` (success / error-envelope / empty / key-change
  reset); `testTestConnectionReportsAccess` UI test green; registry contract still holds
  (`TornEndpointTests`, 11 endpoints incl. `key.info`).
- ISC-20: `xcodebuild test -only-testing:MacTornUITests` (3 UI tests) green ×4 consecutive
  runs; `-only-testing:MacTornTests/UITestHarnessTests` (7) green; `bash
  scripts/coverage-gate.sh TestResults.xcresult 80` → PASSED (critical modules 84–100%);
  Release Universal build (`arm64`+`x86_64`) succeeds and `strings` shows no fixture/harness
  surface.
