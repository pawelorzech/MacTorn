# MacTorn — Accessibility and System QA Report

Date: 2026-07-30
Scope: T14-B execution and T15-B preparation without secrets

## Automated coverage

- [x] All seven modules are reachable through stable AX identifiers and expose the
  expected selected state.
- [x] Navigation group and module controls expose non-empty, stable labels.
- [x] Status progress elements expose combined labels and exact values.
- [x] Settings exposes stable AX identifiers and labels for the key field, Save and
  Test Connection.
- [x] The 320 pt fixture window is checked for navigation clipping and overlap with
  process-local Reduce Transparency, Reduce Motion and Increase Contrast preference
  arguments. SwiftUI exposes the latter two environment values as read-only, so this is
  a best-effort smoke and not a substitute for the real system-setting matrix below.
- [x] Synthetic account A to B is covered without Keychain or network access. The
  fixture delivers a delayed, cancellation-ignoring A response and verifies that A
  never flashes after B becomes active.
- [x] UI tests skip notification permission prompts and update network calls.

Automated checks are hermetic. The strings `fixture-account-a` and
`fixture-account-b` are test tokens, not Torn credentials.

### Validation status

- Fixture/unit contract: passed, 13 tests, 0 failures.
- 320 pt accessibility-display navigation smoke: passed.
- Synthetic account A→B UI regression: passed; B remained visible after the delayed,
  cancellation-ignoring A response completed.
- The seven-module AX traversal reaches the progress-value assertions successfully.
  Its latest rerun exposed only a test viewport issue (the preserved Status scroll
  offset hid the first progress element); the test now resets the scroll position and
  needs one final rerun after the current parallel `AppState` extraction is stable.

## Manual T14-B matrix

Use the Debug UI-test fixture or a dedicated local QA build. Do not use production
credentials.

| Surface | VoiceOver order/audio | Full Keyboard Access | Reduce Motion | Increase Contrast |
|---|---|---|---|---|
| Status | [ ] | [ ] | [ ] | [ ] |
| Travel | [ ] | [ ] | [ ] | [ ] |
| Attacks | [ ] | [ ] | [ ] | [ ] |
| Money | [ ] | [ ] | [ ] | [ ] |
| Faction | [ ] | [ ] | [ ] | [ ] |
| Watchlist | [ ] | [ ] | [ ] | [ ] |
| Forums | [ ] | [ ] | [ ] | [ ] |
| Settings | [ ] | [ ] | [ ] | [ ] |

For every row:

1. VoiceOver: confirm spoken order matches visual/task order, selected navigation is
   announced, values are not split into noisy fragments, and icon actions have meaningful
   names. Record audio findings manually; XCTest cannot assess pronunciation or listening
   effort.
2. Full Keyboard Access: traverse forward and backward, confirm a visible focus ring,
   no focus trap, logical group/module order and activation with Space/Return.
3. Reduce Motion: enable the real macOS setting and confirm no essential state depends
   on animation and no unexpected motion remains.
4. Increase Contrast: enable the real macOS setting and confirm selected state, focus,
   progress tracks, banners and text remain distinguishable.

Acceptance: no open P1/P2 accessibility issue. Any reproducible semantic regression gets
an AX/XCUITest before closure.

## Manual T15-B system scenarios

These steps require explicit user preparation and are intentionally not automated:

### Two dedicated test accounts

- [ ] User supplies two dedicated non-production Torn test keys through the UI.
- [ ] Confirm account A identity and a recognizable A-only datum.
- [ ] Start Refresh, immediately save account B, then return to Status.
- [ ] Confirm A disappears immediately and never flashes while B loads or after B appears.
- [ ] Confirm watchlist, forum, faction, money and diagnostics contain no A data.
- [ ] Remove both test keys from the QA profile after the run.

Never paste keys into this report, terminal output, source, fixtures or screenshots.
The agent did not read the real Keychain or local configuration.

### Notification permission and alert

- [ ] In a dedicated macOS QA profile, user explicitly approves notification permission.
- [ ] Trigger a fixture-safe notification path and confirm title/body, timing and click
  behavior.
- [ ] Test denied permission and confirm the app remains usable with clear recovery.
- [ ] Record the macOS version and permission state, without player data.

The UI-test harness intentionally bypasses the system prompt. No notification permission
was changed during automated work.

### Launch at Login

- [ ] In the dedicated QA profile, enable Launch at Login.
- [ ] Log out and back in, then confirm MacTorn starts once and remains a menu-bar app.
- [ ] Disable Launch at Login, repeat logout/login and confirm it does not start.

This changes persistent system state and requires the user's explicit approval. It was not
performed during automated work.

## Known limits

- VoiceOver audio quality and reading order require an interactive listening session.
- Full Keyboard Access and real Reduce Motion/Increase Contrast behavior depend on global
  macOS settings; process-level fixture injection is only a regression smoke test.
- Notification authorization and Launch at Login require system consent and a dedicated
  macOS QA profile.
- Real account switching requires two dedicated test accounts supplied by the user.
- XCUITest drove only the hermetic app fixture. The `computer-use` safety boundary was
  applied: no direct interaction with system settings, consent dialogs, VoiceOver audio
  or real-account credentials was attempted.
