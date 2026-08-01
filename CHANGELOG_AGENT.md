# CHANGELOG_AGENT

## 2026-08-01 — audyt kompleksowy (wersja bazowa 1.11.1)

Gałąź: `main` (naprawy bezpośrednio na `main` — decyzja Pawła).
Szczegóły i lokalizacje: `AUDIT_REPORT.md`. Rekomendacje: `UX_RECOMMENDATIONS.md`.

Podsumowanie: 22 naprawione problemy, 28 nowych testów jednostkowych, 2 testy przepisane
na poprawny kontrakt, 32 zmienione pliki, 4 pliki odtrackowane.

### Zmiany zachowania widoczne dla użytkownika

1. **Alert „Chain Expiring!" zaczyna działać.** Do tej pory nie wystrzelił ani razu — kod
   czytał pole, którego API Torna nie zwraca. Karta chainu w zakładce Status i wpis chain
   w osi Next Action również były z tego powodu puste; teraz obie pokazują dane.
2. **Przejściowy błąd HTTP 403/404 nie kasuje już danych na ekranie** i nie twierdzi
   nieprawdziwie „Invalid API Key". Prawdziwe odrzucenie klucza (koperta `error` przy HTTP
   200) nadal zatrzymuje polling — bez zmian.
3. **Uszkodzona watchlista i lista wątków nie znikają bezpowrotnie.** Nieczytelny wpis jest
   zachowywany zamiast nadpisywany; kopia trafia pod klucz `*.unreadable`.
4. **Pasek menu mówi VoiceOverowi, co się dzieje** — „Traveling to Japan, arriving in
   2 minutes 35 seconds" zamiast odczytywania emoji.
5. **Systemowe „Reduce transparency" działa automatycznie.** Przełącznik w aplikacji
   nazywa się teraz „Always reduce transparency" i wymusza solidne tła niezależnie od
   ustawienia systemowego.
6. **Animacje respektują systemowe „Reduce motion"** (watchlista, obserwowane wątki).
7. **Faction, Money i Attacks nie pokazują już „Loading…" bez końca** — po zakończonym
   odświeżeniu nazywają stan („nie należysz do frakcji lub klucz nie ma dostępu").
8. **Settings i Quit działają podczas pierwszego ładowania.**
9. **Wynik „Test Connection" znika po edycji pola klucza.**
10. **„Save & Connect" nie da się kliknąć kilka razy pod rząd.**
11. **Dodanie przedmiotu już obecnego na watchliście mówi o tym wprost** zamiast zamykać
    panel jak przy sukcesie.
12. **Nieoczekiwany schemat URL nie jest już otwierany** — wyłącznie `http`/`https`.

Zmiany 5–8 i 11 nie zostały zweryfikowane wizualnie (aplikacja nie była uruchamiana).

### Zmienione pliki — model i logika

| Plik | Zmiana |
|---|---|
| `Models/TornModels.swift` | `MenuBarDisplay` niesie znaczenie zamiast glifów: `.traveling(destination:seconds:)`, `.hospitalAbroad(destination:seconds:)`, `.cooldown(kind:seconds:)`. Dodane `accessibilityDescription` i czysta `spokenDuration(_:)`. `CooldownKind.displayName` |
| `ViewModels/AppState.swift` | Nowe `liveChain` (mapuje `factionService.basic?.chain` na `Chain`). Setter `apiKey` woła `notificationCoordinator.reset()` i czyści `notifiedBountyKeys` |
| `ViewModels/AppState+FactionFetch.swift` | `checkChainNotification()` wołane zaraz po `publishBasic` — tam, gdzie dane chainu wchodzą do systemu |
| `ViewModels/AppState+NotificationsFeedback.swift` | Sprawdzenie chainu usunięte ze ścieżki snapshotu użytkownika; nowe `checkChainNotification()` |
| `ViewModels/AppState+LiveNextAction.swift` | Snapshot Next Action czyta `liveChain` |
| `ViewModels/AppState+PollingUserFetch.swift` | Usunięta gałąź `case 403, 404` kasująca `data` i ustawiająca „Invalid API Key" |
| `ViewModels/AppState+MarketForum.swift` | `addToWatchlist` zwraca `Bool` (`@discardableResult`) |
| `ViewModels/MarketWatchService.swift` | Flaga `loadFailed`; `save()` odmawia nadpisania nieczytelnego blobu; kopia pod `watchlist.unreadable`; `allowPersistenceAfterUserEdit()` w add/remove/restore |
| `ViewModels/ForumWatchService.swift` | To samo dla wątków. Dodatkowo: brak użytecznego `posts` → `.malformed` (z tolerancją dla liczby jako stringu); pusty tytuł nie nadpisuje dobrego |
| `Utilities/BrowserManager.swift` | `open` otwiera wyłącznie `http`/`https` z niepustym hostem; polityka wydzielona do czystej `isWebURL(_:)` |
| `Helpers/TransparencyEnvironment.swift` | `SystemAccessibilitySettings` (czyta `NSWorkspace.accessibilityDisplayShouldReduceTransparency`, nasłuchuje zmian) + `TransparencyPolicy.effective(system:userOverride:)` |
| `Helpers/UITestSupport.swift` | Usunięty zmyślony klucz `chain` z fixture'u odpowiedzi użytkownika |

### Zmienione pliki — widoki

| Plik | Zmiana |
|---|---|
| `MacTornApp.swift` | `.accessibilityLabel` na etykiecie paska menu; glify wyprowadzane z modelu; `reduceTransparency` w środowisku liczone przez `TransparencyPolicy` |
| `Views/ContentView.swift` | `.disabled` przeniesione z całego `VStack` na sam obszar treści (stopka zawsze aktywna); nakładka ładowania `.allowsHitTesting(false)`; nowe `isBlockingInitialLoad` |
| `Views/SettingsView.swift` | `.onChange(of: inputKey)` resetuje `keyValidation`; „Save & Connect" wyłączone podczas `isLoading`; przełącznik przezroczystości przemianowany, z podpowiedzią i `accessibilityHint` |
| `Views/StatusView.swift` | Karta chainu czyta `appState.liveChain` |
| `Views/FactionView.swift`, `Views/MoneyView.swift`, `Views/AttacksView.swift` | Rozróżnienie „ładowanie" od „brak danych" |
| `Views/WatchlistView.swift` | Komunikat przy odrzuconym duplikacie (`addItemError`), panel zostaje otwarty; `reduceMotion` na animacjach i przejściu |
| `Views/ForumWatchView.swift` | `reduceMotion` na animacjach i przejściu |

### Zmienione pliki — konfiguracja, CI i doktryna

| Plik | Zmiana |
|---|---|
| `.github/workflows/claude.yml` | Bramka `author_association` (`OWNER`/`MEMBER`/`COLLABORATOR`) we wszystkich czterech gałęziach `if:` — publiczne repo, więc komentarz obcej osoby uruchamiał workflow z sekretami |
| `.gitleaks.toml` | `regexTarget = "match"` + placeholdery zakotwiczone na całej wartości zamiast dopasowania w linii |
| `.githooks/pre-commit` | Fail-closed przy braku gitleaks (było `exit 0`) |
| `scripts/coverage-gate.sh` | `awk -v` zamiast interpolacji parametru do programu awk |
| `.claude/commands/new-version.md` | Przepisane pod projekt Xcode (było: „update version in gradle files"); uzupełnione `allowed-tools`; dodany krok podmiany lokalnej instalacji i zakaz uruchamiania testów UI bez pytania |
| `CLAUDE.md` | Sekcja „Torn API" zgodna z rejestrem; jawnie zapisane, że chain żyje na endpointcie faction i że 403/404 nie oznacza złego klucza |
| `README.md` | Deklaracje dostępności zgodne z implementacją + akapit o tym, czego brakuje |

### Odtrackowane (pliki zostają na dysku)

`MacTorn-1.5.1.zip`, `MacTorn/Archive/MacTorn-v1.0.zip`, `MacTorn/Archive/MacTorn-v1.2.zip`,
`MacTorn/Archive/MacTorn-v1.2.1.zip` — ~8,3 MB archiwów śledzonych wbrew `.gitignore`.
Historia gita nadal je zawiera; historii nie przepisywałem.

### Dodane testy (28)

| Klasa | Liczba | Co pilnuje |
|---|---:|---|
| `ChainSourceTests` | 7 | Że `user.fast` **nie** prosi o selekcję `chain`, a `faction.basic` prosi; że `liveChain` mapuje dane frakcji; że alert wystrzeliwuje w oknie zagrożenia i milczy poza nim; że latch krawędziowy tłumi powtórki; że oś Next Action widzi chain z frakcji |
| `MenuBarAccessibilityTests` | 5 | Formatowanie mówionego czasu (w tym wartość ujemna); że **żaden** glif nie wycieka do mowy; że nazwa celu podróży i rodzaj cooldownu trafiają do etykiety; że brak celu nie produkuje „Unknown"/„nil" |
| `BrowserManagerPolicyTests` | 3 | Że przechodzą tylko `http`/`https`; że `file://`, `javascript:`, `ssh://`, `mailto:` i schematy własne są odrzucane; że URL bez hosta jest odrzucany |
| `MarketWatchCorruptStoreTests` | 4 | Że zapis w tle nie nadpisuje nieczytelnego blobu; że oryginał trafia pod klucz odzyskiwania; że czyste pierwsze uruchomienie nadal zapisuje; że edycja użytkownika wznawia zapisy |
| `ForumWatchResilienceTests` | 5 | Jw. dla wątków; że konfiguracja zapisuje się mimo zablokowanej listy; że alert o nowych postach przeżywa częściową odpowiedź |
| `ForumThreadParseTests` | 3 | Że odpowiedź bez `posts` to `.malformed`, nie sukces; że liczba jako string jest tolerowana; że pusty tytuł nie gubi licznika |
| w `AppStateTests` | 1 | `testTornErrorEnvelopeStillHaltsOnBadKey` — że złagodzenie 403/404 nie połknęło prawdziwej awarii klucza |

### Testy przepisane (2)

`testFetchData_invalidAPIKey_HTTP403` i `…HTTP404` utrwalały zachowanie, które audyt uznał
za błędne (403/404 = zły klucz + skasowanie danych). Zastąpione przez
`testHTTP403IsTreatedAsTransientAndKeepsTheLastGoodSnapshot` i wariant 404, sprawdzające
odwrotny, poprawny kontrakt. **To jest zmiana specyfikacji, nie obejście czerwonego
testu** — dlatego równocześnie dołożony został test pilnujący, że prawdziwa awaria klucza
nadal zatrzymuje polling.

### Potencjalne regresje do obserwacji

1. **Chain.** Alert, karta w Status i wpis w Next Action zależą teraz od danych frakcji.
   Gracz bez frakcji nie zobaczy ich w ogóle — poprawnie, ale to zmiana. Częstotliwość
   alertu zależy od cadence pollingu frakcji; jeśli okaże się zbyt rzadka względem
   60-sekundowego progu, trzeba przyspieszyć `faction.basic` albo obniżyć próg.
2. **403/404.** Aplikacja nie zatrzyma się już na tych kodach. Gdyby Torn zaczął ich
   używać do sygnalizowania odrzuconego klucza (dziś nie używa), objawiłoby się to cichym
   pollingiem w pętli. Warto zerknąć w `endpointHealth` po kilku dniach.
3. **Blokada zapisu przy nieczytelnym blobie.** Gdyby flaga nie została zdjęta, zapisy
   zamilkłyby na stałe. Zdejmują ją add/remove/restore/toggle.
4. **`ContentView`.** Struktura `VStack` przebudowana (nowy `Group` wokół treści).
   Kompiluje się, `.disabled` jest węższe, ale **układ nie został obejrzany**.
5. **Nakładka ładowania** ma `.allowsHitTesting(false)`, więc stopka pod przyciemnieniem
   jest klikalna, ale nadal przyciemniona — do oceny, czy nie jest to mylące.
6. **Fixture UI.** Usunięcie zmyślonego klucza `chain` może wpłynąć na testy UI, które nie
   zostały uruchomione w tym przebiegu.
7. **`gitleaks`.** Węższy allowlist może dawać nowe trafienia na linijkach z placeholderami.
   Pełna historia przeszła czysto.
8. **Hook pre-commit.** Na maszynie bez gitleaks commit będzie blokowany — zamierzone;
   wyjście awaryjne to `git commit --no-verify`.

### Bramki po zmianach

| Kontrola | Wynik |
|---|---|
| `xcodebuild test -only-testing:MacTornTests` | **PASS — 460/460**, 0 failed, 0 skipped (baseline 432) |
| `bash scripts/coverage-gate.sh TestResults.xcresult 80` | **PASSED** — TornAPIError 99,07%, TornEndpoint 83,56%, PollingCoordinator 100%, NotificationCoordinator 100%, NextAction 96,51% |
| `xcodebuild analyze` | **ANALYZE SUCCEEDED**, zero ostrzeżeń |
| `xcodebuild build -configuration Debug` | **BUILD SUCCEEDED**, zero ostrzeżeń |
| `make release` + `make verify-release` | **PASS** — `x86_64 arm64`, `Signature=adhoc`, strict/deep codesign, DR valid |
| `gitleaks git` (pełna historia) | **PASS** — 132 commity, `no leaks found` |
| `make test-ui` (8 testów) | **NIEWYKONANE** — przerwane na prośbę Pawła |

### Do wykonania ręcznie

Pełna lista w `UX_RECOMMENDATIONS.md` → „Manual QA". Trzy pozycje blokujące przed wydaniem:

1. `make test-ui` — 8 testów, nieuruchomionych, przy ośmiu zmienionych plikach widoków i
   zmienionym fixture harnessu.
2. Alert chainu na żywo z prawdziwym kluczem — funkcja, która nie działała nigdy.
3. Układ `ContentView` po przebudowie `VStack` — wizualnie nieobejrzany.

**Nic nie zostało zacommitowane.** Zmiany czekają w drzewie roboczym `main`.

---

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
