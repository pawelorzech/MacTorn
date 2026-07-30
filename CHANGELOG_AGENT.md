# CHANGELOG_AGENT

## 2026-07-30 — audyt i wdrożenia T01–T17

### Zakres

Przeprowadzono audyt kodu, bezpieczeństwa, sieci, pollingów, buildów, zależności, architektury i interfejsu macOS. Wdrożono testowane poprawki T01–T13 i T17, przygotowano automatyczną część T14/T15 oraz zachowano decyzję T16-A o lokalnym universal Release podpisywanym ad hoc.

### Zmiany produkcyjne

#### Izolacja konta i stan

- Dodano generation barrier oraz `AccountSessionStore`.
- Zmiana klucza anuluje stare zadania i czyści dane poprzedniego konta.
- Odpowiedzi user/faction/activity/v2 oraz key validation publikują stan wyłącznie dla bieżącej sesji.
- Wydzielono `UserSnapshotService`, `FactionService`, `MarketWatchService` i `ForumWatchService`.
- `AppState.swift` zmniejszono z 2 256 do 377 linii; logika pomocnicza znajduje się w sześciu extension files.

#### Sieć, freshness i współbieżność

- Wszystkie ścieżki rezerwują request przez wspólną bramkę przed wykonaniem.
- Watchlist i forum korzystają z bounded concurrency = 4 z obsługą anulowania.
- Semantyczny kontrakt odpowiedzi nie traktuje brakującego krytycznego payloadu jako sukcesu.
- Freshness i zdrowie są śledzone per endpoint.
- Ostatnie poprawne dane pozostają widoczne podczas błędu chwilowego.
- `lastUpdated` zmienia się wyłącznie po poprawnym głównym snapshotcie.

#### UX, Accessibility i Settings

- Dodano wspólny `ModuleStateView` dla loading / empty / stale / offline / permission / rate limit i recovery.
- Dodano walidację dodatniego progu ceny, inline error, disabled Set i bezpieczny Enter.
- Watchlist i forum mają sześciosekundowe Undo pełnego elementu i pozycji.
- Nawigację siedmiu tabów zastąpiły grupy `Now / Account / Watch`.
- Produkcyjne widoki używają fontów semantycznych co najmniej `.caption2`.
- Commands zapewnia Refresh `⌘R`, Settings `⌘,` i moduły `⌘1…⌘7`.
- Kliknięcia, Commands i UI-test window współdzielą `AppNavigationState`.
- Settings ma stały przełącznik sześciu kategorii i pokazuje jedną sekcję naraz; przewija się tylko treść aktywnej sekcji, gdy naprawdę nie mieści się w panelu.
- Status ma ograniczoną wysokość, a rozbudowana lista Next Action została zastąpiona pojedynczym paskiem najbliższej akcji.
- Rozszerzono AX labels, values, selected traits i widoczny focus.
- Prefilled Settings SecureField dostał jawną etykietę AX `Torn API Key`; na macOS 26 placeholder znikał po wypełnieniu i pozostawiał pustą nazwę.

#### Quick Travel

- Zaktualizowano 11 kierunków do oficjalnych czasów po Torn Patch #438.
- Dodano jawny wybór Standard / Airstrip + pilot i informację o wymaganym upgrade/pilocie.
- UI informuje o wariancji ±3%.
- Aktywny lot nadal używa API `timestamp`, `departed` i `time_left`, nie lokalnej estymaty.
- Preferencja Private Island steruje wyłącznie skrótem/ikoną powrotu.

#### Prywatność i zależności

- Sentry Cocoa zaktualizowano z 9.12.0 do **9.23.0**.
- Sentry pozostaje off-by-default, nie startuje w UI tests, ma wyłączone PII/network tracking i scrubbery URL.
- Usunięto wrażliwe wartości domenowe oraz surowe transportowe opisy z logów.
- Diagnostics pozostaje bez PII.

#### CI i lokalne bramki

- Workflow macOS ma osobne joby unit/coverage, fixture UI oraz analyze/universal ad-hoc Release.
- Akcje GitHub są przypięte do pełnych SHA.
- Dodano read-only diagnostykę lokalnego runnera XCTest.
- Makefile rozróżnia lokalny ad-hoc Release i opcjonalny, nieużywany `release-signed`.

### Testy dodane lub rozszerzone

- izolacja A→B, reset konta i spóźnione odpowiedzi/walidacje;
- wszystkie request paths i wspólny hard cap;
- semantyczne kontrakty full/custom/underprivileged/empty payload;
- bounded concurrency i anulowanie watchlist/forum;
- freshness, recovery i endpoint health;
- walidacja progu ceny i Undo;
- grouped navigation, Commands i sekcje Settings;
- Sentry opt-in/off, crash-only i PII scrubber;
- pięć wydzielonych serwisów/store: 31 izolowanych metod testowych;
- Quick Travel: 24 testy, w tym komplet Standard/Airstrip i API-driven active flight;
- hermetyczny syntetyczny scenariusz UI account A→B.

Aktualna liczba metod w źródłach:

- unit: **428**;
- UI: **8**;
- razem: **436**.

### Walidacja

- `make coverage-gate`: PASS.
- MacTornTests: **428 passed, 0 failed, 0 skipped**.
- Result bundle: `/Users/pawelorzech/Programowanie/MacTorn/TestResults.xcresult`.
- Coverage: `TornAPIError` 99,07%, `TornEndpoint` 83,56%, `PollingCoordinator` 100%, `NotificationCoordinator` 100%, `NextAction` 96,51%.
- Final Debug build: PASS.
- Final `build-for-testing`: PASS.
- Final post-merge `make analyze`: PASS, ponowiony po poprawce AX SecureField.
- Final `make scan`: PASS, brak wycieków.
- 320 pt accessibility-display navigation smoke: PASS.
- Synthetic account A→B UI regression: PASS.
- Final MacTornUITests: **8/8 passed, 0 failed, 0 skipped, 0 expected failures**.
- UI result bundle: `/tmp/mactorn-final-ui-suite-20260730-1058-clean.xcresult`.
- All-modules + Settings AX: PASS, 48.535 s.
- Stale account switch: PASS, 15.534 s.
- `make release`: PASS po wyczyszczeniu wyłącznie przestarzałego cache Sentry PCM w `DerivedData/Release`; początkowy błąd cache nie był błędem kodu.
- `make verify-release`: PASS.
- Artefakt: `DerivedData/Release/Build/Products/Release/MacTorn.app`.
- Architektury: `x86_64 arm64`.
- Podpis: `Signature=adhoc`, brak `TeamIdentifier`; strict/deep codesign i designated requirement są poprawne.

### Nadal oczekujące manualnie

- manualny VoiceOver audio;
- rzeczywisty Full Keyboard Access;
- systemowe Reduce Motion / Increase Contrast / Reduce Transparency;
- dwa rzeczywiste konta testowe;
- systemowe notifications i Launch at Login.

Pierwszy rzeczywisty run nowego workflow CI pozostaje niezweryfikowany do czasu publikacji zmian.

### Decyzja dystrybucyjna T16

Pozostajemy przy **T16-A: universal strict ad-hoc Release do użytku lokalnego**. Developer ID, notarization, stapling, Gatekeeper distribution smoke i publikacja nie zostały wykonane i nie są blockerem lokalnego zakresu. Każde rozszerzenie dystrybucji wymaga nowej decyzji oraz jawnej zgody.
