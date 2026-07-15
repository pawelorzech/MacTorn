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

- [ ] ISC-15: Etap B/C — wire `TornAPIError` classification into the live fetch paths so
  a permanent key error stops polling and error 14 pauses only its category.
  *(Deferred: touches the live polling loop; needs its own regression harness around
  `AppState.fetchData` to change error handling safely. Typed model + classifier are
  ready and tested.)*
- [ ] ISC-16: Etap C — key validation/onboarding: call the key-info endpoint, show real
  permissions, disable modules without access, "Test connection". *(Deferred: new UI +
  a new endpoint; the registry already exposes required selections/level for the copy.)*
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
- [ ] ISC-19.1: Etap F (full instrumentation, F-02) — extend outcome/latency/size health
  to every endpoint (fast poll is the reference implementation); event-driven endpoints
  (market/forum/stocks) currently populate on first use. *(Deferred: mechanical per-site
  timing, low value vs. risk right now.)*
- [ ] ISC-20: Etap G — deterministic UI-test harness (`--uitesting`, fixture selection,
  fake clock/keychain/connectivity) + real UI tests; remove `continue-on-error` and
  `|| echo "optional"`; coverage gate ≥80% on critical modules. *(Deferred: large;
  the UserDefaults injection is the first brick.)*
- [ ] ISC-21: Etap H — CI overhaul (current Xcode, required UI tests, archive smoke,
  coverage, SwiftLint, entitlements/codesign/lipo checks, Dependabot). *(Deferred:
  CI changes; `SECURITY.md` done.)*
- [ ] ISC-22: Etap I — extract `TornAPIClient`, `PollingCoordinator`,
  `NotificationCoordinator` (started), stores from `AppState`. *(Incremental;
  `NotificationCoordinator` extracted this stage.)*
- [ ] ISC-23: Etap J — "Next Action" unified event timeline + menu-bar variant.
  *(Deferred product feature; depends on a shared testable clock.)*
- [ ] ISC-24: Etap K — navigation/accessibility redesign (3–4 sections + More, reorder,
  VoiceOver, larger targets). *(Deferred UX work.)*
- [ ] ISC-25: Etap L — release engineering (Developer ID/notarization optional via CI
  secrets, SHA-256, Sparkle). *(Deferred; `release-signed` scaffold already exists.)*

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
