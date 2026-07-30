# MacTorn — stan realizacji i pozostały backlog

Data: 2026-07-30
Status: lokalne bramki automatyczne T01 i wdrożenia T02–T13/T17 zakończone; T14/T15 wymagają manualnego QA; T16-A pozostaje decyzją końcową

Skala dawnych decyzji: Impact, Confidence, Effort i Risk 1–5.
`Priority score = Impact × Confidence / Effort`.

## Stan tematów

| ID | Temat | Wybrany wariant | Stan | Aktualny dowód / następny krok |
|---|---|---|---|---|
| T01 | Zielone testy i CI | B — macOS CI + lokalny recovery | Lokalne bramki zakończone | 428/428 unit i 8/8 UI; coverage, Debug, build-for-testing, analyze, scan i Release PASS. Pierwszy zdalny workflow pozostaje niezweryfikowany do czasu publikacji. |
| T02 | Walidacja alertu cenowego | A — inline validation | Zakończone | Dodatnia liczba całkowita, inline error, disabled Set, błędny Enter nie zamyka formularza. |
| T03 | Odwracalne usuwanie | B — Undo 6 s | Zakończone | Watchlist i forum przywracają pełny element, ustawienia i pozycję. |
| T04 | Nawigacja siedmiu modułów | B — Now / Account / Watch | Zakończone | Maks. 2 akcje do modułu, selected AX, zachowane test IDs. |
| T05 | Semantic fonts | B — migracja + layout checks | Zakończone automatycznie | Brak 8 pt, minimum `.caption2`; 320 pt smoke PASS. Real system contrast/większy tekst pozostaje w T14. |
| T06 | Loading/empty/error/recovery | A — wspólny komponent | Zakończone | `ModuleStateView` i kontekstowe Retry/Settings. |
| T07 | Freshness per moduł | B — status per endpoint | Zakończone | Fresh/stale/error bez usuwania ostatnich dobrych danych. |
| T08 | Współbieżność watchlist/forum | B — bounded concurrency = 4 | Zakończone | `BoundedTaskQueue`, limit 4, anulowanie i testy. |
| T09 | Semantyczna walidacja odpowiedzi | B — kontrakt capabilities | Zakończone | Full/custom/underprivileged/empty payload i brak fałszywego `lastUpdated`. |
| T10 | Podział `AppState` | A — serwisy + facade | Zakończone | `AppState.swift` 377 linii, 5 serwisów/store, 6 extension files, izolowane testy. |
| T11 | Aktualizacja Sentry | A — 9.23.x | Zakończone | Resolved 9.23.0; opt-in/off, crash-only i PII scrubber w zielonym unit suite. |
| T12 | Keyboard-first | B — skróty + focus + testy | Zakończone w kodzie | Commands, `⌘R`, `⌘,`, `⌘1…⌘7`, Escape i focus. Real Full Keyboard Access pozostaje w T14. |
| T13 | Porządek w Settings | A — stały przełącznik sekcji | Zakończone | 6 stale widocznych kategorii; jedna aktywna sekcja naraz, z lokalnym scrollem tylko dla nadmiarowej treści. |
| T14 | Pełny audyt accessibility | B — VoiceOver + keyboard + kontrast | Częściowo | Automatyczny AX/320 pt smoke PASS; manualna macierz systemowa otwarta. |
| T15 | Scenariusze systemowe i konta | B — fixture + dwa konta | Częściowo | Synthetic A→B PASS; realne konta, notifications i Launch at Login otwarte. |
| T16 | Dystrybucja | A — pozostajemy przy ad-hoc | Zakończona decyzja | Universal `x86_64 arm64`, strict/deep ad-hoc PASS. Bez Developer ID/notary/publikacji. |
| T17 | Aktualne czasy lotów | A — API live + Patch #438 + Airstrip | Zakończone | 24 TravelTests; 11×Standard, 11×Airstrip; aktywny lot API-driven. |

## Aktualny punkt odniesienia

- Produkcja Swift: 51 plików / 11 920 linii.
- Testy Swift: 37 plików / 7 265 linii.
- Unit methods w źródłach: 428.
- UI methods w źródłach: 8.
- Sentry Cocoa resolved: 9.23.0.
- `AppState.swift`: 377 linii.
- Sześć plików extension `AppState+*.swift`: łącznie 1 640 linii.
- Serwisy/store:
  - `AccountSessionStore`;
  - `UserSnapshotService`;
  - `FactionService`;
  - `MarketWatchService`;
  - `ForumWatchService`.

## Zamknięte fale wykonawcze

### Fala 1 — niezawodność i quick wins

- [x] T02 walidacja alertu.
- [x] T03 Undo.
- [x] T06 wspólne stany/recovery.
- [x] T07 freshness.
- [x] T08 bounded concurrency.
- [x] T09 kontrakty odpowiedzi.

### Fala 2 — nawigacja, dostępność i maintenance

- [x] T04 grouped navigation.
- [x] T05 semantic fonts i 320 pt checks.
- [x] T11 Sentry 9.23.0.
- [x] T12 Commands i keyboard-first.
- [x] T13 Settings IA.
- [x] T17 Quick Travel Standard/Airstrip + pilot.

### Fala 3 — architektura

- [x] `AccountSessionStore` i `UserSnapshotService`.
- [x] `FactionService`, `MarketWatchService` i `ForumWatchService`.
- [x] 377-liniowy `AppState.swift` facade.
- [x] 31 izolowanych testów pięciu serwisów/store.

## Pozostała kolejka

### T01 — końcowe bramki automatyczne

Potwierdzone:

- [x] final Debug;
- [x] final build-for-testing;
- [x] `make coverage-gate`;
- [x] 428/428 unit, 0 failed, 0 skipped;
- [x] finalny post-merge `make analyze`;
- [x] finalny `make scan`, brak wycieków;
- [x] universal strict ad-hoc Release;
- [x] 320 pt accessibility-display smoke;
- [x] synthetic A→B UI regression.
- [x] finalny pełny zestaw 8 UI tests, 0 failed/skipped/expected.

Oczekujące:

- [ ] pierwszy zdalny run nowego workflow CI i zachowanie artefaktów.

Unit result bundle: `/Users/pawelorzech/Programowanie/MacTorn/TestResults.xcresult`.
UI result bundle: `/tmp/mactorn-final-ui-suite-20260730-1058-clean.xcresult`.

Coverage:

- `TornAPIError`: 99,07%;
- `TornEndpoint`: 83,56%;
- `PollingCoordinator`: 100%;
- `NotificationCoordinator`: 100%;
- `NextAction`: 96,51%.

### T14 — manualny audit systemowej dostępności

Automatyczne kontrakty AX i 320 pt smoke są zielone, ale nie zastępują:

- [ ] VoiceOver audio i kolejności czytania dla 7 modułów + Settings;
- [ ] rzeczywistego Full Keyboard Access, focus ring i kolejności Tab/Shift-Tab;
- [ ] systemowego Reduce Motion;
- [ ] systemowego Increase Contrast;
- [ ] systemowego Reduce Transparency;
- [ ] większego tekstu/zoom w powierzchni 320 pt.

Definition of done: manualna macierz bez otwartego P1/P2; automatyzowalne regresje dostają test.

### T15 — manualne konta i integracje systemowe

Automatyczny fixture A→B przechodzi i dowodzi, że opóźniona, niekooperatywna odpowiedź A nie wraca po publikacji B.

Nadal wymagają jawnej zgody i przygotowania użytkownika:

- [ ] dwa dedykowane testowe klucze podane wyłącznie przez UI;
- [ ] brak flasha i danych A w każdym module po przejściu na B;
- [ ] permission, treść, timing, kliknięcie i odmowa notifications;
- [ ] Launch at Login po wylogowaniu/zalogowaniu oraz po wyłączeniu.

Agent nie odczytuje Keychain, nie zapisuje kluczy w logach i nie zmienia zgód/systemowego login item bez autoryzacji.

### T16 — utrzymana decyzja ad-hoc

Decyzja użytkownika: **T16-A**.

- [x] `make release`: PASS.
- [x] `make verify-release`: PASS.
- [x] Artefakt: `DerivedData/Release/Build/Products/Release/MacTorn.app`.
- [x] `x86_64 arm64`.
- [x] `Signature=adhoc`, brak `TeamIdentifier`.
- [x] Strict/deep codesign i designated requirement: PASS.
- [ ] Developer ID: poza zakresem.
- [ ] Notarization/stapling: poza zakresem.
- [ ] Gatekeeper distribution smoke/publikacja: poza zakresem.

Początkowy błąd Sentry PCM po zmianie zależności był wyłącznie starym cache w `DerivedData/Release`. Po usunięciu tego scoped cache niezmienione polecenie Release przeszło.

## Globalne Definition of Done

Każda przyszła zmiana musi zachować:

- test regresyjny dla zmienionej logiki;
- brak sekretów i PII w logach/diagnostyce;
- `git diff --check`;
- build-for-testing, unit i coverage gate;
- analyze;
- dla lokalnego Release: universal binary i strict ad-hoc codesign;
- manualny smoke zmienionej ścieżki;
- aktualizację dokumentacji;
- brak commit/push/publikacji bez osobnej zgody.
