# Changelog

All notable changes to MacTorn will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.12.4] — 2026-08-26 — the panel fits its window again

Collects everything that landed after 1.12.3, most of it defects the audits
found in fixes 1.12.0 through 1.12.3 had shipped.

### Fixed
- **The panel stopped short of the bottom of its own window.** Settings was
  locked to 500pt and Status capped its scroll area at 480pt, while the window is
  640. Content could not reach the bottom edge, the footer sat wherever the
  content happened to end with dead space beneath it, and the cue that a view
  scrolls — content running to the edge and being clipped there — was gone. Both
  now fill the height available, and the footer is pinned to the bottom.
- **"Commands" was larger than the buttons beside it.** A menu takes its font
  from its control size rather than from the font its surroundings set.
- **A superseded first fetch could unprotect a live one**, and an account change
  left the previous account's polling timer running, which also let a key change
  within half a refresh interval skip the permissions check entirely.
- **The forum watch could announce old threads as new after upgrading.** A
  category that had been seeded while empty was re-seeded silently, swallowing
  the first thread posted to it.
- **A long forum listing could announce the same threads every poll, forever.**
  The request asks for 20 rows, but what a server returns is not a guarantee, and
  a listing longer than the remembered set made the page and its eviction cap
  oscillate. Listings are now capped well below that ceiling.
- **A transient key error no longer re-announces every bounty on you.**
- **The popular-items grid is back.** 1.12.0 hid it once the item catalog
  loaded; in 1.11.1 those six items were the entire way to add anything, so
  opening the panel cold gave a blank field where clickable items used to be.

### Changed
- **Adding a field to a stored setting no longer wipes it.** Notification rules,
  travel alerts, watched threads and custom shortcuts decode field by field now,
  so a blob written by an older build still loads instead of being replaced by
  defaults. This mattered more than it sounds: notification rules are keyed by
  display strings, so editing one of those strings was a schema change.

### Quality
- 690 unit tests passed, up from 671.
- Layout verified by eye on a Release build; XCUITest cannot run on the machine
  this was cut from, so CI is the check for the UI suite.


## [1.12.3] — 2026-08-26 — the first poll, properly this time

1.12.2 claimed that MacTorn reads your key's permissions before its first request.
That was true only while Torn answered faster than one refresh interval.

### Fixed
- **A slow permissions check let the first poll go out unnarrowed anyway.** 1.12.2 started
  the repeating timer before that first request, and the timer does not wait for anything.
  If Torn took longer than your refresh interval to answer — a cold connection at the
  15-second setting is enough — a tick fired exactly the request the wait exists to
  prevent. The timer now starts immediately, as it always did, and the poll itself is what
  waits.
- **A second start could skip the wait entirely.** The guard against loading your key's
  permissions twice also let every caller after the first carry straight on to fetching.
- **A first poll left waiting could outlive the account it belonged to**, and resume into
  an app that had already stopped polling.

### Quality
- 676 unit tests passed, up from 671.
- Seven of the new tests exist because this ordering has now been got wrong twice, in
  opposite directions. The first attempt at this fix withheld the polling timer until the
  first fetch finished, which closed the hole and opened two worse ones — an existing test
  caught it, and the suite now states the invariant three ways.


## [1.12.2] — 2026-08-26 — what the audits found

Three independent reviews of 1.12.0 and 1.12.1 reported after those releases shipped.
Everything below is a defect in something 1.12.0 introduced.

### Fixed
- **Adding a watchlist item by name only worked with the mouse.** Typing "Xanax" and
  pressing Return, with the matching row rendered directly below the field, answered
  "Enter a positive item ID." Return and the Add button now commit the top match. A name
  that matches nothing says so instead of collapsing the panel to a bare field.
- **The forum category watch announced old threads as new.** Torn returns one page of 20
  threads, not the whole category, and MacTorn replaced its memory with each page. A
  thread that scrolled below the cut was forgotten, so the next reply that bumped it back
  to the top arrived as "New forum thread" for a months-old conversation. In a busy
  category that was the normal case, not an edge case. The list is now cumulative.
- **Changing the watched category could produce a burst of notifications.** A listing
  already in flight landed afterwards and filed the old category's threads under the new
  one, so the next check found nothing familiar and announced a whole page. Remembered
  threads are now tied to the category they came from.
- **The forum alert toggle could be on while watching nothing.** Turning it on without
  filling in a category ID left it silently inert. It now says so.
- **Requests that can never succeed are no longer retried forever.** A deleted forum
  thread or a watchlist entry holding a dead item id answers with the same error every
  poll; MacTorn was not recording those, so it asked again every few minutes indefinitely.
- **A key that gained access kept being treated as if it had not.** MacTorn read your
  key's permissions once per launch and never again, so joining a faction mid-session left
  the chain alert switched off until you restarted the app. It re-reads hourly now. A
  single failed read at launch no longer disarms the permission checks for the session.
- **Selection narrowing now actually happens on the poll it exists for.** 1.12.0 started
  the permissions read alongside the first poll rather than before it, so that poll always
  asked for everything.
- **A transient key error no longer re-announces every bounty on you** once polling
  recovers.
- **Forum thread titles are length-capped before they are stored**, matching the rule
  watchlist names already follow.
- **Diagnostics names endpoints in words.** The "Not being requested" list showed
  `faction.basic` beside a plain-English reason.
- **The Status badge row no longer renders empty**, leaving a gap where nothing is waiting.

### Quality
- 671 unit tests passed, up from 663.
- One test in the 1.12.0 suite was asserting the forum bug as correct behaviour. It is
  rewritten, along with the comment above it that described a limit the code never used.


## [1.12.1] — 2026-08-26 — hostile-response hardening

Follow-up to 1.12.0 from an independent security review of that release.

### Fixed
- **A crafted Torn response could forge a second paragraph in a notification.** MacTorn
  strips control characters from every server string before it reaches a notification or
  an error message, and that was doing less than it looked like: Apple's
  `CharacterSet.controlCharacters` is Unicode categories Cc and Cf, which leaves U+2028
  LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR untouched. Both render as hard line
  breaks. A forum thread title becomes the entire notification body, so two of them
  bought an attacker a second paragraph reading as though MacTorn had written it. Both
  sanitizers now strip everything that ends a line.
- **The item catalog could write unbounded server text into your watchlist.** Names typed
  into the watchlist were trimmed and capped at 64 characters; names arriving from Torn's
  catalog were not, and the backfill wrote them straight into stored data. One rule now
  covers both, and the catalog itself is bounded.
- **The "Download Update" button only opens a github.com link.** The URL behind it comes
  from the GitHub API, and MacTorn checked the scheme but not the host.
- **Crash reports drop request headers.** The API key moved into an `Authorization`
  header in 1.12.0, and the Sentry scrubber only knew about the URL and query string.
  Nothing attaches headers today, but that was resting on an SDK internal rather than on
  anything MacTorn controls.

### Quality
- 15 regression tests, including the crafted-forum-title case written out as the attack
  it closes.


## [1.12.0] — 2026-08-26 — a better Torn API citizen

### Added
- **Search Torn's item catalog by name.** Adding a watchlist entry used to mean knowing
  its numeric item ID and typing the name yourself. Type "xanax", pick it from the
  matches, and it lands correctly labelled. Entries you added earlier as `Item #206` get
  relabelled once the catalog loads. Names you chose yourself stay as you wrote them. The
  catalog is cached for a week, and everything still works before it arrives.
- **Virus programming countdown.** The virus you are writing now shows up on the Next
  Action timeline beside education, Organized Crime and the bars, with a notification when
  it finishes.
- **Awards and competitions in the Status badges.** The unread-messages badge became a row
  of four counters: waiting messages, events, awards and open competitions. These are the
  same numbers Torn shows in its own header. Awards and competitions had no place in
  MacTorn before.
- **Watch a whole forum category for new threads.** Turn it on in Settings, give it a
  category ID, and MacTorn tells you when a thread appears that was not there before. The
  first check only learns which threads already exist, so switching it on does not produce
  a hundred notifications about months-old conversations.
- **Diagnostics explains what is not being requested.** A new section lists every endpoint
  MacTorn is skipping on purpose and why: a key without the right permission, no faction,
  a daily read limit still cooling off.

### Changed
- **MacTorn reads your key's permissions and asks only for what it can get.** It used to
  fire every request regardless. If you have no faction, that meant a call for faction
  data every thirty seconds, forever, purely to be told no. Those calls are gone.
- **A request naming several selections gets trimmed instead of rejected.** Torn refuses an
  entire request if it names one selection your key cannot read. Asking a Minimal-access
  key for battle stats therefore cost you the bars, the cooldowns and the travel timer in
  the same call. MacTorn now asks for the readable ones and shows what comes back.
- **The unread count is current instead of five minutes old**, and it costs nothing. It
  moved off a row-based call that spends against Torn's daily read limit and onto the
  point-in-time counter that rides the poll MacTorn already makes.
- **Every request identifies itself as `MacTorn` in your key log**, so you can pick its
  traffic out from every other tool you have handed the same key. API v2 requests send the
  key in an `Authorization` header instead of the URL.

### Fixed
- **A spell in federal jail no longer looks like a broken key.** Torn's "key owner in
  federal jail", "key change cooldown" and "key temporary disabled" errors all clear by
  themselves, and MacTorn treated all three as permanent: it stopped polling and told you
  to fix a key that was fine. It now waits and resumes on its own.
- **Requests that can never succeed are no longer retried forever.** An error meaning "this
  request is wrong" (wrong API version, wrong category, an ID that no longer exists) used
  to be retried at poll cadence indefinitely. It now disables that one endpoint.
- **An IP block gets an hour of quiet** instead of the continued requests that earned it.
- **The client-side daily row budget became an actual limit.** MacTorn measured it and
  showed it in Diagnostics without ever consulting it, so nothing stopped a runaway row
  source except Torn answering with an error.
- **Forum category listings are counted honestly.** That endpoint accepts a row limit and
  defaults to 100. MacTorn declared it did not and booked 20 per call, five times under
  what a default request pulls against the daily cap.
- **The watchlist stopped asking for bazaar prices Torn no longer publishes.** On API v2
  the per-item `bazaar` selection returns a directory of bazaars stocking an item and no
  prices at all, so the code reading `cost` out of it could never match. Prices come from
  the item market, which is where they were already coming from.

### Quality
- Verified against Torn's OpenAPI document, spec version 6.13.1 (2026-08-26).
- README's API table is now compared against the endpoint registry by a test, character
  for character. It had been advertising a forum endpoint the app declared and never
  called.
- 74 new tests covering the request gate, key placement, selection narrowing, the error
  taxonomy, the item catalog and the forum category watch.

## [1.11.1] — 2026-07-31 — focused account views

### Changed
- **Account is split into focused modules.** Money, Properties, Stocks, and Faction
  now have separate destinations under the existing Account group, keeping the
  financial overview readable without merging every holding into one long screen.
- **Money is a glanceable summary.** Cash, total tracked value, and quick actions
  remain together, while detailed property and stock holdings live in their own views.

### Fixed
- Module scroll views now stay inside the compact popover instead of expanding to
  their full content height, so long lists remain scrollable and the footer stays
  reachable on smaller displays.

### Quality
- Added a compact-window UI regression covering four Account modules at 320×480,
  a 24-row Stocks fixture, footer visibility, and scrolling to the final action.

## [1.11.0] — 2026-07-30 — compact UX & resilience

### Changed
- **Status at a glance.** The oversized Next Action panel is now a compact single-row
  summary, and the Status popover uses a fixed, denser layout so the important timers
  remain visible without excessive scrolling.
- **Settings by category.** Settings now opens one of six focused sections at a time
  instead of presenting one long, deeply scrollable form.
- **Current travel planning.** Destination times follow Torn's current official values
  and can be calculated for either standard airport travel or a Private Island airstrip
  with a pilot.
- **Clearer navigation and commands.** Related destinations are grouped consistently,
  common actions have keyboard shortcuts, and destructive actions expose Undo where
  appropriate.
- **Privacy-safe diagnostics.** Sentry was updated to 9.23 and diagnostics, feedback,
  and account transitions were tightened to avoid leaking sensitive Torn data.

### Added
- **Freshness and recovery states** across live modules, including explicit loading,
  stale-data, empty, permission, and retry states.
- **Account-scoped sessions and snapshots** so switching API keys cannot retain data,
  notifications, or pending work from the previous Torn account.
- **Bounded service fan-out** for faction, market, forum, stocks, and user snapshots,
  with focused service tests and deterministic persistence coverage.
- **Accessibility and UX audit artifacts** with an implementation backlog and traceable
  recommendations for the completed quality pass.

### Fixed
- Long-lived polling and notification state now resets safely when the active account
  changes.
- Input validation, semantic snapshot comparison, and endpoint error handling now
  produce actionable recovery paths instead of ambiguous or duplicated UI states.
- The monolithic `AppState` implementation was split into focused services and
  extensions, reducing state coupling while preserving existing behavior.

### Quality
- Expanded unit, integration, UI-harness, and service coverage; reliability-critical
  modules remain protected by the 80% line-coverage gate.
- Release validation now checks a universal `arm64` + `x86_64` binary and strict
  ad-hoc signing, matching the project's ad-hoc distribution policy.

## [1.10.0] — 2026-07-15 — reliability & product audit

A large reliability + product pass (audit Etaps A–G, C, and follow-ups). Highlights: key
validation & onboarding ("Test Connection"), a deterministic UI-test harness that gates
merges, error-14 per-source pausing, poll-wide diagnostics health, a persistent OC-ready
dedup, plus the earlier spine (typed API registry, error taxonomy, notification de-dup, the
Next Action timeline, diagnostics, and the halt-on-dead-key fix). The full plan and deferred
backlog live in [`ISA.md`](ISA.md).

### Fixed
- **Chain-expiring notification fired on every poll.** While a chain's timeout was under
  60 s, "Chain Expiring! ⚠️" was re-sent on *every* refresh (a burst of identical
  banners). It now fires **exactly once** per crossing into the danger window and
  re-arms only after the chain leaves it (a member hits, the chain ends, or it drops),
  via a new persistent `NotificationCoordinator` whose de-dup survives an app restart.
- **Flaky unit test / non-deterministic suite.** `AppState` hardcoded
  `UserDefaults.standard`, so watchlist tests raced on the shared store under parallel
  execution (`testPriceThreshold_persistedWithWatchlist` failed intermittently on
  `main`). `AppState` now takes an injectable `UserDefaults`; each test isolates its own
  suite. The suite is green and deterministic across 8 parallel runners.

### Added
- **Typed Torn API registry** (`TornEndpoint` / `TornEndpointRegistry`): one catalog of
  all 10 endpoints (version, path, selections, access level, cadence, point-in-time vs
  row-based, record limit, cache policy, budget category, critical/optional). It drives
  request building, the README "API Data Usage" table and onboarding disclosure — a
  contract test pins every registry URL to its legacy `TornAPI` builder so they can't
  drift.
- **Typed error taxonomy** (`TornAPIError`): classifies Torn error codes (permanent key,
  insufficient permissions, rate limit, daily row limit, temporary backend) plus
  transport states (offline / transport / malformed / cancelled), with `haltsAllRequests`
  (codes 2/16/18) and `haltsCategoryOnly` (code 14) semantics and a `RetryPolicy`
  exponential backoff (2/5/15/30/60 s, capped at 5 min, jittered). Wiring into the live
  fetch path is deferred (ISA ISC-15).
- **`SECURITY.md`** — private vulnerability disclosure policy and supported-version note.
- **`ISA.md`** — system-of-record for the audit program with the full A–L backlog and
  deferral reasons.

### Added — Etap D (polling budget + reconnect)
- **API budget accounting** (`PollingCoordinator`): every request-issuing path records
  against a rolling requests/min + requests/day count and per-category rows/day (driven
  by the typed registry), with a conservative 60/min hard cap that no path bypasses. This
  makes the usage that caused error 14 (v1.9.2) measurable and bounded.
- **Immediate refresh on reconnect.** After a network outage, MacTorn refreshes once as
  soon as connectivity returns (on the genuine down→up edge) instead of waiting up to a
  full refresh interval.
- **Shared testable clock** (`TimeSource`) behind the budget windows — also the clock the
  upcoming "Next Action" timeline will use.
- The **15s** refresh option is now labelled **"15s aggressive"** with a note that Torn
  may serve cached data for ~30s, so 15s can spend API budget for no fresher data.

### Added — Etap F (diagnostics)
- **Diagnostics screen** (Settings → Diagnostics): app/macOS/architecture, network and
  notification-permission state, whether an API key is configured and the access level
  it needs, last successful refresh, live request/record budget counters, and
  per-endpoint outcome/latency/size.
- **"Copy sanitized report"** — a clipboard snapshot that is PII-safe by construction:
  it never contains the API key, full URLs, player name/ID, money, stats,
  faction/company names, or raw payloads.

### Added — Etap J (Next Action)
- **Next Action timeline.** A new card at the top of the Status tab shows the single
  soonest thing to happen — bars filling, cooldowns ending, travel landing, hospital/jail
  release, education finishing, OC becoming ready, chain timeout, or refills waiting —
  with a live countdown, plus the list of what follows. All times come from one shared,
  testable clock. Pick which categories appear in **Settings → Next Action**.

### Added — Etap G (deterministic UI tests + hardened CI)
- **Hermetic UI-test harness.** Launched with `--uitesting`, the app builds itself from
  fixtures and test doubles — a URL-routed fake network session, an isolated `UserDefaults`,
  an in-memory Keychain (so a UI test never touches your real Torn key), and controllable
  connectivity — and surfaces the menu-bar content in a real window the test runner can
  drive. Real UI tests now cover onboarding-without-a-key, tab navigation, and invalid-key
  error surfacing. This is developer-facing only: it is fully DEBUG-gated, so the Release
  app carries none of the fixture/harness code.
- **UI tests gate merges.** The CI UI-test job no longer swallows failures
  (`continue-on-error` removed).
- **Coverage gate.** CI fails if any reliability-critical module (API error taxonomy,
  endpoint registry, polling/notification coordinators, Next Action engine) drops below
  80% line coverage. SwiftUI views are excluded — they're validated by the UI-test suite.
  Also available locally via `make coverage-gate`.

### Fixed — duplicate OC-ready alert after relaunch (Etap E)
- **"OC Ready!" no longer re-alerts when you reopen the app.** The organized-crime ready
  notification is now deduplicated persistently (once per OC), so relaunching MacTorn while
  the same OC is still ready won't fire it again. A new OC still alerts.

### Changed — more reliability closures (Etap F)
- **Diagnostics now cover the stock-metadata call too** (last outcome/latency/size), alongside
  the poll fan-out added earlier.

### Changed — reliability closures (Etap B/F follow-ups)
- **A daily read-limit no longer stalls unrelated data.** If Torn returns "daily read limit
  reached" (error 14) for a row-based feed (activity, faction news), MacTorn now pauses just
  that feed for an hour and keeps everything else — bars, cooldowns, travel, the chain
  counter — updating live. Previously the whole faction/activity overlay could be affected.
- **Diagnostics now cover the whole poll.** Endpoint health (last outcome, latency, size) is
  recorded for every endpoint the app polls (faction, activity, v2 user, ranked wars, news),
  not only the fast user poll — so a "Copy sanitized report" is more useful when something's
  off. (Rarely-called market/forum/stocks calls are a small follow-up.)

### Added — Etap C (key validation & onboarding)
- **Test Connection.** Onboarding (Settings) gains a "Test Connection" button that checks
  your API key against Torn's official key-info endpoint and tells you exactly what it
  unlocks: your access type (e.g. Full Access), your player ID, and — if the key is Limited
  or Custom — precisely which features won't load. No more guessing why a tab is empty.
- **Clearer data & privacy disclosure.** The "API Data Usage & Privacy" section now states
  the required access level, that your key is stored in the macOS Keychain (never plaintext),
  that all Torn data stays on your Mac, that crash reporting is opt-in, and lists the exact
  selections requested — generated from the app's endpoint registry so it can't drift.

### Fixed — Etap B (stop retrying a dead key)
- **A bad or paused API key now halts polling** instead of retrying forever. When Torn
  returns a permanent key/permission error (codes 2 / 16 / 18), MacTorn stops the poll
  loop, shows the specific message, and stays stopped even when the menu re-opens —
  until you change the key. Previously it showed "API Error: …" and kept hammering the
  dead key every cycle. Transient errors (rate limit, backend) are unaffected.

### Notes
- 77 new unit tests since `main` (330 total, all green). The one existing test that
  encoded the old "keep retrying a dead key" behaviour was updated to the new halt
  contract; no other feature behaviour changed. CI's Release build was also un-broken
  (Xcode 16 for `Package.resolved` v3).

## [1.9.2] - 2026-07-15

### Fixed
- **"API Error: Daily read limit reached" (Torn error code 14).** MacTorn was tripping Torn's *per-category* cloud-data cap — 50,000 rows/day (rolling 24 h) for row-based categories like `events`, `attacks` and faction `news` — which is a completely separate limit from the 100-requests/minute rate limit (the app was never close to that one). The single `user/` poll bundled `events` **and** `attacks` (up to ~100 rows each, no `limit`) and ran every 30 s around the clock: ~288,000 rows/day/category, roughly 5–6× over the cap, so any one category alone would trip error 14. Faction `news` (every 60 s) piled on a second over-quota category.
  - The fast poll (refresh interval, default 30 s) now carries **only point-in-time selections** (`basic,bars,cooldowns,travel,profile,money,battlestats,properties,stocks`) — no row-based categories — so it can't touch the daily cap. All live bars, cooldown/travel countdowns and notifications are unchanged.
  - `events`, `messages` and `attacks` moved to a **separate slow call** (every 5 min) with a hard `limit=25`, and faction ranked-wars/news moved from a 60 s to a 5 min gate (also `limit=25`). Net: ~288k → ~7k rows/day/category, with comfortable headroom even at the 15 s refresh floor. Events/attacks/messages now refresh every few minutes instead of every 30 s — they're display-only, so no functional loss.

## [1.9.1] - 2026-07-03

### Performance
- **Throttle the heaviest faction API calls.** The ranked-war (~15 KB) and news (~23 KB) v2 calls added in 1.9.0 are the largest in a poll cycle and change slowly, but were fetched every poll — as often as every 15 s. A 60 s time-based gate now fetches them at most once per minute regardless of the refresh interval (still runs on the first poll so the Faction tab populates immediately), cutting ~150 KB/min of near-static traffic at the 15 s floor. No user-visible change.

## [1.9.0] - 2026-07-03

Audit of MacTorn's Torn API usage against the live v2 OpenAPI spec (6.0.0) and real API responses. API v1 is frozen (not sunset) — every selection MacTorn relies on still returns its v1 shape — but two selections had drifted out from under the client, and v2 opened up four new signals worth surfacing. Plan: `Plans/sprawd-czy-si-nie-ticklish-rivest.md`.

### Fixed
- **Faction Organized Crimes were silently empty.** After Torn made Organized Crimes 2.0 mandatory faction-wide (~Feb 2025), the v1 `faction/?selections=crimes` selection returns only frozen pre-migration OC-1.0 *history* (0 active crimes, newest from Feb 2025), and its `initiated` field flipped from Bool to Int — so the client's all-or-nothing decode dropped every crime. The test fixture used `"initiated": false` (a Bool), so the suite stayed falsely green. The dead OC-1.0 list is gone; the app now shows the player's **own current OC 2.0** via v2 `/user?selections=organizedcrime` — a "ready in Xh" timer, status, slots filled, and your own progress — verified against a live response.
- **Cooldown countdowns weren't anchored to server time.** The client anchored drug/medical/booster end-times on a top-level `timestamp` field, but the live v1 user root returns `server_time` (top-level `timestamp` only appears with the `timestamp` selection, which we don't request). So `serverTimestamp` was always nil and the countdowns silently fell back to the local Mac clock — defeating the clock-skew correction they were built for. Now decodes `server_time` with a legacy `timestamp` fallback.

### Added
- **Your Organized Crime 2.0 status** in the Faction tab: name, difficulty, live "ready in" countdown, slots filled, and your own progress bar — plus an OC-ready notification. The modern replacement for the removed faction OC-1.0 list.
- **Dailies card** in the Status tab: which daily refills (energy / nerve / token) you still have to claim, and a live completion timer for an in-progress education course.
- **Bounty-on-you alert.** A red badge in the Status tab and a notification when someone places a bounty on you (`/user?selections=bounties`).
- **Faction ranked war + news.** The Faction tab shows the active ranked war as a lead-vs-target progress bar (your faction vs the opponent) and a feed of recent faction news (`/v2/faction/rankedwars`, `/v2/faction/news?cat=main`).

All four user-side signals ride a single combined v2 `/user` call. Also hardened the test network mock against a data race on concurrent fetches. 253 unit tests, all green.

## [1.8.13] - 2026-06-04

### Fixed
- **Surface Torn API v2 errors on the market and forum endpoints instead of swallowing them.** The v2 endpoints (`/v2/market/{id}`, `/v2/forum/{id}/thread`, `/v2/forum/{id}/threads`) return errors as `{"code":Int,"error":String}` — `error` is a top-level string — per the official Torn OpenAPI spec. The client only recognised the legacy v1 envelope (`{"error":{"code","error"}}`), so every v2 API error (rate-limit code 5, incorrect key code 2, access-level-too-low, etc.) slipped through undetected: a rate-limited watchlist item showed up as "No listings", and a rate-limited forum check parsed into a bogus "Unknown" thread with post count 0, corrupting watch state. A new `tornAPIErrorMessage(in:)` helper recognises both envelopes and is now used at all six API error-parse sites. Added contract tests for both envelope shapes plus integration tests proving the market and forum paths surface v2 rate-limit / incorrect-key errors.

## [1.8.12] - 2026-05-25

### Fixed
- **Stop spamming Sentry with macOS "App Hanging" false positives.** Sentry-Cocoa enables `AppHangTracking` by default with a 2-second threshold. For a `MenuBarExtra` app that's whatever-it-wants-to-be most of the time, normal macOS scenes — display wake, fence creation in `+[CAFenceHandle newFenceFromDefaultServer]`, `CGSPostLocalNotification` in SkyLight — routinely block the main thread for >2 s and are captured as application errors. Both unresolved issues against 1.8.10/1.8.11 (MACTORN-2, MACTORN-3) had **zero in-app frames** — pure `mach_msg2_trap` → AppKit/QuartzCore/SkyLight system traces, nothing actionable in MacTorn code. Now `options.enableAppHangTracking = false`. Real crashes and explicit `SentrySDK.capture()` calls still report normally. Same noise-reduction rationale as v1.8.11's `enableCaptureFailedRequests = false`.

## [1.8.11] - 2026-05-12

### Fixed
- **Stop spamming Sentry with upstream Torn API 5xx errors.** Sentry-Cocoa 9.x defaults `enableCaptureFailedRequests` to `true`, which auto-captures any URLSession response with a 500–599 status as an application error. When Torn API returned 504 Gateway Timeout (upstream overload, not a MacTorn bug), Sentry reported it as a MacTorn error — 71 such events from 6 users landed against 1.8.10. Now `enableCaptureFailedRequests = false`. Crashes and explicit `SentrySDK.capture()` calls still report normally. The code change was present from commit `e54fc80`, but tag `v1.8.10` was cut before that commit, so the binary in users' hands didn't include it — `v1.8.11` is the actual rollout of the fix.

## [1.8.10] - 2026-04-30

### Fixed
- **Booster/drug/medical countdown no longer jumps on every poll.** v1.8.9 fixed the long-term clock-skew drift by storing absolute end-timestamps (`endsAt = serverTimestamp + duration`), but each ~30 s API poll still re-derived `endsAt` from a fresh integer-second `serverTimestamp` and integer-second `cooldowns.{kind}` pair. API rounding plus network-latency variance made the recomputed value wobble by ±1–3 s vs the previous one, which the menu bar rendered as a visible jump on every refresh. `CooldownEnds.merged(with:toleranceSeconds:)` now pins each `*EndsAt` across polls when the freshly computed value is within ±3 s; larger gaps are treated as a real cooldown reset (new booster/drug/medical) and adopt the new value. Transitions in/out of active (0 ↔ nonzero) are always immediate so the countdown starts/clears without delay. Travel/hospital/jail are unaffected — they already receive absolute Unix epochs from the API and don't have this jitter. Plan: `MacTorn/Plans/ca-y-czas-mam-taki-quiet-crescent.md`.

## [1.8.9] - 2026-04-30

### Fixed
- **Drift-free cooldown countdowns.** Booster/medical/drug countdowns previously drifted by ~30 s vs torn.com because we stored the API's *relative* duration and subtracted `Date().timeIntervalSince(fetchTime)` locally each tick — any Mac↔server clock skew compounded into a constant offset. Now we convert each cooldown into an absolute Unix end-timestamp at fetch time (`endsAt = serverTimestamp + duration`) and every view computes `max(0, endsAt − now)`. New `CooldownEnds` value type owns the conversion; `Cooldowns.soonestActive(from:)` was replaced with `CooldownEnds.soonestActive()`. Travel, hospital, jail, and chain countdowns already used absolute timestamps and are unchanged. Plan: `Plans/wszystkie-czasy-kt-re-s-dazzling-bumblebee.md`.
- Faction Chain timer: switched from a one-shot string render of `chain.timeout` to a per-second `TimelineView`, so the chain countdown now ticks live like every other countdown in the app.

### Added
- **Opt-in crash + error reporting via Sentry.** Off by default. After upgrading, users see a one-time prompt explaining the option; the toggle also lives in Settings (`Send crash reports`). When enabled, only crashes and unhandled errors are sent — no performance traces, no replays, no `sendDefaultPii`. URLs in events and breadcrumbs run through the existing `tornRedactedURL` so the Torn API key never leaves the device. Project: `mactorn` on `mactorn.sentry.io` (DE region).
- New `SentryManager` (`Utilities/SentryManager.swift`) that owns SDK lifecycle and PII scrubbing; new `SentryOptInPromptView` overlay shown once per upgrade.

## [1.8.8] - 2026-04-27

### Performance
- **Live timer no longer churns SwiftUI every second.** The 1 Hz countdown that drives the menu bar label and the travel countdown now skips `@Published`/Observation writes when the displayed value hasn't changed (e.g. cooldowns shown as `Hh Mm` only mutate every ~60 s). Removes per-second invalidation cascade across `MenuBarLabel`, header, and TravelView.
- **Polling no longer restarts on every menu open.** `MenuBarExtra` fires `onAppear` on each popover open; previously each open cancelled the timer and immediately re-fetched. `startPolling()` now no-ops when a timer is already running and the last fetch is < `refreshInterval / 2` old. `refreshNow()` keeps an explicit `force: true` bypass for the user-initiated refresh button. Same guard added to `startForumPolling()`.
- **Watchlist threshold notifications are now batched.** When the periodic watchlist refresh sees ≥ 2 items cross their price threshold in a single pass, a single summary notification (`"3 price alerts: Xanax, Plushie +1 more"`) is emitted instead of N separate banners. Single-item add-to-watchlist still fires individually.
- **Forum poll short-circuits unchanged threads.** `checkThreadForUpdates` returns early when the post count is unchanged since the last poll, skipping the notification path and the post-count write entirely.
- **Stocks metadata retry uses exponential backoff (60 s → 300 s → 1800 s cap).** Previously a persistent `torn/?selections=stocks` failure was retried on every 30 s main poll, burning API quota. Backoff resets on success.
- **Release build is now stripped end-to-end.** `SWIFT_OPTIMIZATION_LEVEL=-O`, `DEAD_CODE_STRIPPING=YES`, `DEPLOYMENT_POSTPROCESSING=YES`, `STRIP_INSTALLED_PRODUCT=YES`, `STRIP_STYLE=all` are now explicit on the project-level Release config (previously relying on Xcode defaults; `DEPLOYMENT_POSTPROCESSING` was off, so the binary that ended up in `build/Build/Products/Release/MacTorn.app` was not actually stripped on a plain `make release`).

### Changed
- **`AppState` migrated from `ObservableObject` + `@Published` to `@Observable` (Observation framework, macOS 14+).** SwiftUI now invalidates only the views that actually read a changed property — previously a single fetch cycle wrote 7 `@Published` properties and triggered 7 invalidation rounds across every view that observed `AppState`. All 11 views switched from `@EnvironmentObject` to `@Environment(AppState.self)`; `MacTornApp` switched from `@StateObject` to `@State`; `SettingsView` uses `@Bindable` to keep the existing `$appState.refreshInterval` Picker binding.
- `@AppStorage("refreshInterval")` and `@AppStorage("appearanceMode")` on `AppState` replaced with stored properties + `didSet` write-through to `UserDefaults` (required because `@AppStorage` is a SwiftUI property wrapper and doesn't compose with `@Observable`). Behavior unchanged: same UserDefaults keys, same defaults, persistence across launches preserved.

### Tests
- New `AppStatePerformanceTests` records `JSONDecoder` baselines via `XCTest.measure` for full-response and stocks-metadata parsing, plus a regression guard for the stocks backoff ladder.

## [1.8.7] - 2026-04-27

### Security
- **API key now stored in macOS Keychain** instead of plaintext UserDefaults (`~/Library/Preferences/com.mactorn.app.plist`). On first launch the app migrates any existing key automatically and clears the old plist entry. Service: `com.mactorn.app`, account: `apiKey`, accessible after first unlock.
- **Stop leaking the API key into `os_log`/Console.** All log statements that referenced a request URL now run through a redactor that emits `scheme://host/path?[sorted-query-keys]` with values dropped. The previous `url.absoluteString.prefix(80)` was exposing the 16-character key to anyone reading Console / sysdiagnose. Also removed raw API response and player-name diagnostic logs.
- **Hardened Runtime + App Sandbox + entitlements** enabled on Debug and Release. Network access is the only granted entitlement (`com.apple.security.network.client`).
- **TornAPI URL builders** now use `URLComponents` + `URLQueryItem` instead of string interpolation — keys with `&`, `=`, or whitespace are percent-encoded correctly.
- **Watchlist input clamped** at the trust boundary: `itemId` must be in `(0, 100000)`, `name` is trimmed and capped at 64 chars.
- **Notification text sanitized** centrally in `NotificationManager.send`/`scheduleNotification` — strips control characters, length-caps title (80) and body (200) so a MITM'd or compromised Torn API can't spoof multi-line notifications.
- **Decoder failures** at the outer envelope are now logged with key path + error class instead of being silently swallowed.
- **`.gitignore` hardened** against accidental commit of signing material (`*.p12`, `*.cer`, `*.mobileprovision`), `.env`, and release archives.
- **CI workflows:** added `concurrency:` groups to the Claude code-review workflows (least-privilege `permissions:` were already in place).

Full audit and per-finding breakdown: `SECURITY_AUDIT.md` in the repo root. Distribution model is unchanged (ad-hoc signed direct download — Gatekeeper warning on first launch is expected; right-click → Open).

## [1.8.6] - 2026-04-26

### Added
- **Dynamic menu bar status text** — the menu bar label now adapts to player state instead of always showing a static icon:
  - **Traveling** → ✈️ + country flag + remaining travel time *(unchanged)*
  - **Hospitalized abroad** → 🏥 + country flag + hospital countdown
  - **Hospitalized in Torn** → 🏥 + hospital countdown
  - **Jailed in Torn** → 🚓 + jail countdown
  - **Idle with active cooldowns** → soonest-expiring cooldown with type emoji: 💊 Drug, 🧪 Booster, 🩹 Medical
  - **Idle, no cooldowns** → falls back to the existing `bolt`/`bolt.fill`/`globe`/error icon
- Live 1-second countdown extended from travel-only to all of the above states; computed from server timestamps where available (`travel.timestamp`, `status.until`) and adjusted against the last fetch time for relative cooldown values.

### Changed
- `MenuBarLabel` is now a thin renderer over a centralized `MenuBarDisplay` enum on `AppState`, replacing the inline travel-only conditional. Priority order: traveling > hospital (abroad/home) > jail > soonest cooldown > fallback icon.

## [1.8.5] - 2026-04-18

### Fixed
- **Stocks metadata never loaded** — `startPolling()` fired before `apiKey` was hydrated from `@AppStorage`, the once-per-session flag flipped, and `fetchStocksMetadata` short-circuited forever. Replaced the flag with an idempotent check (`stocksMetadata.isEmpty && !apiKey.isEmpty`) that retries every poll tick until it succeeds.
- **Property "Upkeep" was misleading (round 2)** — verified against the real Torn API: `upkeep` is a per-day RATE that only applies when you currently reside in the property, not a debt. For properties owned but not lived in (`status: "Owned by them"`), the user pays $0 even though the field returns $100,000. Removed `upkeep` and `staff_cost` from the UI entirely; surface `status` instead.

### Changed
- Property cards now show `status` (e.g., "Owned by them") + `marketprice` + `cost` + happy bonus. "Rented" badge clarified as "Rented out" since it means rented to another player.


### Fixed
- **Stocks metadata parsing failed silently** — `torn/?selections=stocks` returns extra fields (`director`, `forecast`, `demand`, `benefit`, etc.) that broke the strict `Decodable` decoder. Replaced with `JSONSerialization`-based parser that tolerates unknown fields and reports the specific failure mode (network error vs API error vs missing key) to the log.
- **Property "Upkeep" was misleading** — Torn API's `upkeep` field is "money owed for upkeep" (accrued debt), not the upkeep rate. Relabeled to "Owed" in the Money tab and "Upkeep due" in the Properties tab, only shown when > 0.

## [1.8.3] - 2026-04-18

### Fixed
- **Stocks $0 cost basis** — `transactions` field comes back from Torn API as a dict keyed by transaction_id, not an array. The decoder silently swallowed the type mismatch via `try?` and returned $0 for every holding. Now decodes both shapes.
- **Properties section empty** — code mapped to a non-existent `money` field. Replaced with real Torn API fields: `cost`, `marketprice`, `upkeep`, and `rented` (with days remaining).

### Added
- **Stock names + market value** — fetches `torn/?selections=stocks` once per session and caches to UserDefaults. Each stock now shows its acronym + name and current market value (`shares × current_price`) instead of "Stock #N" with $0.
- **Property cost / upkeep / rent badge** — each property card now shows market price, weekly upkeep, purchase cost, and a "Rented Nd" badge when applicable.

### Internal
- `feedbackResponded*` now no-ops under XCTest so test runs don't open mail/forum.

## [1.8.2] - 2026-04-12

### Changed
- Removed faction forum auto-monitoring (Torn API does not expose private faction forum threads)
- Faction forum threads can still be watched by pasting their URL/ID manually
- Fixed "Faction Forum" quick link to correctly open the user's faction forum page

## [1.8.1] - 2026-04-12

### Fixed
- Fixed faction forum monitoring using wrong category ID (was using faction ID instead of discovering the actual forum category)
- Faction forum category is now discovered by matching faction name against forum categories API
- Toggling faction monitor off now resets cached data for clean rediscovery

## [1.8.0] - 2026-04-12

### Added
- Forum Watch tab — track Torn forum threads for new posts directly from the menu bar
- Add threads by pasting forum URL or thread ID
- Per-thread notification toggle (on = alerts, off = bookmark/shortcut only)
- Faction forum auto-monitoring — toggle to detect and notify about new faction forum threads
- Separate forum polling interval (2m / 3m / 5m), independent of main data refresh
- Click any watched thread to open it in your browser

## [1.7.1] - 2026-04-12

### Changed
- Return flight now shows 🏠 (home) instead of 🇺🇸 in menu bar when flying back to Torn

### Added
- Private Island setting — players with a private island can set 🏝️ as their return icon instead of 🏠

## [1.7.0] - 2026-04-11

### Added
- Bazaar price alerts — set price thresholds on watchlist items, get notified when price drops below
- Organized Crime timer — live countdown for active OCs in Faction tab with ready notification
- Net worth dashboard — enhanced Money tab showing cash, properties, and stock holdings breakdown
- TRI Hub quick link — one-click access to hub.tri.ovh from Quick Links

### Changed
- Money tab now shows comprehensive net worth with properties and stocks sections
- Faction API now fetches organized crime data
- User API now fetches stock holdings data
- Updated deployment target to macOS 14.0 (macOS 13 no longer receives security updates)

### Fixed
- Fixed deprecated onChange(of:) API usage for macOS 14+
- Fixed redundant await on @MainActor calls
- Fixed NetworkMonitor.shared nonisolated default parameter (Swift 6 preparation)

## [1.6.0] - 2026-03-14

### Added
- Cooldown quick action buttons: when a cooldown reaches Ready, the cell becomes a clickable button that opens the corresponding Torn Items page (drugs, medical, boosters/alcohol)
- New "Booster cooldown link" setting to choose between Boosters and Alcohol item page
- Accessibility support for cooldown action buttons (VoiceOver labels and hints)

## [1.5.1] - 2026-02-04

### Added
- Expanded browser support in browser picker with additional browser options

## [1.5.0] - 2026-02-04

### Added
- Preferred browser support for opening Torn links (system default browser selection)
- GitHub Actions integration with Claude Code for automated PR assistance and code review
- BrowserManager utility for managing browser preferences across the app

### Changed
- Improved link handling to respect user's default browser choice

## [1.4.7] - 2026-01-27

### Added
- In-app feedback prompt with smart timing (1 hour, 1 week, 1 month thresholds)
- Positive feedback links to Torn forums thread
- Negative feedback opens email for direct developer contact
- 5-minute cooldown between prompt dismissals
- Comprehensive test coverage for feedback logic

## [1.4.6] - 2025-01-25

### Fixed
- Fixed incorrect "Released" notification triggering when landing from travel
- "Released! 🎉 - You are now free" notification now only fires when released from Hospital or Jail, not when arriving from airplane travel

## [1.4.5] - 2025-01-25

### Fixed
- Improved travel timer accuracy by using API timestamp directly instead of calculating from fetch time offset
- Travel countdown now stays synchronized regardless of network delays or fetch timing

### Added
- Comprehensive test coverage for travel timer calculations

## [1.4.4] - Previous Release

### Fixed
- Resolve Swift concurrency errors by extracting MainActor functions
- Fix watchlist item mutation to update via copy

### Added
- Universal Binary support for Intel and Apple Silicon Macs
- Improved accessibility support
- Display cooldown labels as text instead of icons

## [1.4.3] - Earlier Release

### Added
- GitHub wiki documentation
- Migrated wiki to GitHub Wiki feature

## [1.4.2] - Earlier Release

### Changed
- Various bug fixes and improvements

## [1.4.1] - Earlier Release

### Changed
- Various bug fixes and improvements

## [1.4] - Initial Public Release

### Added
- Native macOS menu bar app for Torn game monitoring
- Status tab with live bars, cooldowns, and travel monitoring
- Travel tab with live countdown timer in menu bar
- Money tab with cash, vault, points display
- Attacks tab with battle stats and recent attacks
- Faction tab with chain status
- Watchlist tab for item price tracking
- Smart notifications for various game events
- Configurable refresh intervals
- Launch at login support
- Light and dark mode support
- Accessibility support with Reduce Transparency
