# CHANGELOG_AGENT: zmiany wykonane przez agenta

Last verified: 2026-09-26 | gałąź `feature/audit-fixes` (z `main` @ `07b1f82`) → wydanie 1.15.1
Zamówienie: `/audit` całego repo bez testów manualnych i bez uruchamiania aplikacji, potem
commit, push, release i podmiana lokalnej instalacji.
Poprzedni przebieg (2026-08-26) jest niżej.

---

## Commity (16, od najstarszego)

| Commit | Zmiana | ID z `AUDIT_REPORT.md` |
|---|---|---|
| `dc4fec4` | Akcje wracają do „Total Tracked” przy włączonych Stock bonuses | R-01 |
| `f82f5c0` | Watchlista: `cache_timestamp` przeliczany na zegar Maca, `cache_delay` ograniczony do 0…300 s | R-02 |
| `e4f2db6` | „Arriving in” pokazuje „Ready” przy zerze | R-04 |
| `7c78ea6` | Akcje CI przypięte do SHA, bramka autora w PR review | S-01, S-04 |
| `3db1143` | Zawężone uprawnienia `/new-version` | S-02 |
| `0a345bc` | Dokumentacja bezpieczeństwa opisuje `mactorn://` | S-03 |
| `9d483b7` | Dostępność: Return i fokus w polu klucza, modalne prompty, wypowiadany stan ikony w pasku menu, linki przez BrowserManager, puste stany, „Travel status unavailable”, obszary kliknięcia i etykiety | A-01…A-08 |
| `52b2f04` | Reset konta kasuje zaplanowane alerty lądowania | F-01 |
| `886705a` | „Test Connection” na niezapisanym kluczu nie nadpisuje `keyInfo` | F-02 |
| `02799f3` | Zmiana interwału (główny i forum) przeinstalowuje działający timer | F-03 |
| `20277ff` | Przerwane odświeżenie Watchlisty dostarcza alerty, które już zapisało | F-04 |
| `33ae701` | Timer alertów cenowych co 5 minut w tle | F-05 |
| `88080a0` | Forum Watch zatrzymuje się po trwałym błędzie klucza | F-06 |
| `807c3cb` | Okno limitu requestów zachowuje sekundę graniczną | R-03 |
| `20caaab` | Karta łańcucha „Unavailable” przy braku timeoutu | R-05 |
| `6a2ff1f` | Tolerancja timerów (0,1 s dla odliczania, 10% dla pollingu i forum) | P-08 |

## Zmienione pliki

- **Kod produkcyjny (`MacTorn/MacTorn/`):**
  - `MacTornApp.swift`
  - `ViewModels/`: `AppState.swift`, `AppState+PollingUserFetch.swift`, `AppState+MarketForum.swift`, `AppState+LiveNextAction.swift`, `AccountSessionStore.swift`, `MarketWatchService.swift`
  - `Utilities/PollingCoordinator.swift`
  - `Views/`: `StatusView.swift`, `ContentView.swift`, `SettingsView.swift`, `TravelView.swift`, `WatchlistView.swift`, `ForumWatchView.swift`, `Components/ChainView.swift`, `Components/SentryOptInPromptView.swift`
- **Testy (`MacTorn/MacTornTests/`):**
  - `ViewModels/`: `CompanionStoreTests.swift`, `MarketWatchServiceTests.swift`, `AppStateTests.swift`, `AppStateWatchlistTests.swift`, `AppStateForumWatchTests.swift`, `PollingCoordinatorTests.swift`
  - `Models/`: `KeyValidationTests.swift`, `ChainTests.swift`
- **CI, doktryna i dokumentacja:**
  - `.github/workflows/`: `claude.yml`, `claude-code-review.yml`, `gitleaks.yml`
  - `.claude/commands/new-version.md`, `SECURITY.md`, `SECURITY_AUDIT.md`
  - raporty `AUDIT_REPORT.md`, `UX_RECOMMENDATIONS.md` i ten plik

## Dodane i zmienione testy

- **Liczba testów:** z 781 do 808 (+27).
- **Nowe klasy i testy:**
  - `TravelNotificationAccountScopeTests` (3)
  - `PollingCadenceChangeTests` (3)
  - `WatchlistPriceAlertTimerTests` (8)
  - `ForumWatchKeyHaltTests` (3)
  - `testValidatingAnUnsavedKeyDoesNotReplaceTheActiveKeyInfo`
  - `testSupersededRefreshStillDeliversAlertsItAlreadyLatched`
  - `testSubSecondRequestIsNotDroppedBeforeItsMinuteElapses`
  - 3 testy `ChainView.mode(for:)` w `ChainTests`
  - 3 testy `MarketPriceSnapshot.localized(using:)`
  - 2 testy stocks w `CompanionStoreTests`
- **Dwa testy zmieniły intencję.** Oba kodowały błąd, a nie wymaganie. Zmiana jest jawna, nie jest osłabieniem:
  - `testDisabledV2StocksDoNotChangeLegacyRequestAndEnabledAvoidsDuplicateHoldings` wymagał wycinania `stocks`. Zastąpiły go `testEnablingV2StocksKeepsLegacyStocksSelection` i `testEnablingV2StocksStillPopulatesStocksDataFromFastPoll`. Zakładka Stocks i tak chowa panel v1 przy włączonym companion, więc na ekranie nic się nie dubluje.
  - `testSecondResolutionBoundaryIsStable` oczekiwał 0 dokładnie po 60 s, czyli wcześniejszego zapominania żądania. Teraz oczekuje 1 po 60 s i 0 po 61 s, tak jak liczył kod sprzed `c71ee24`.
- **Test do obserwacji:** `testSupersededRefreshStillDeliversAlertsItAlreadyLatched` opiera się na `Task.sleep` z marginesem ok. 150 ms i może być niestabilny na obciążonej maszynie.

## Zmiany zachowania widoczne dla użytkownika

- **Money:** „Total Tracked” zawsze liczy akcje.
- **Watchlist:**
  - Alerty cenowe przychodzą w tle co 5 minut, dla przedmiotów z ustawionym progiem. Nie ma żadnych żądań, gdy żaden próg nie jest ustawiony.
  - Etykieta „Price data from … ago” liczy od czasu na zegarze Maca.
  - Pusta lista nie pokazuje już paska „No data yet · Retry”.
  - Ręczne odświeżenie przy wstrzymanym kluczu nic nie robi.
- **Status i Faction:**
  - „Arriving in: Ready” przy zerze.
  - Czerwona karta „Unavailable”, gdy łańcuch ma trafienia, ale nie ma timeoutu ani cooldownu. `ChainView` jest współdzielony, więc karta pojawia się też w Statusie.
- **Travel:** bez danych o podróży widać „Travel status unavailable” zamiast „In Torn City”.
- **Settings:**
  - Return w polu klucza zapisuje i łączy.
  - Przy pierwszym uruchomieniu pole klucza ma fokus.
  - Linki otwierają się w wybranej przeglądarce i VoiceOver czyta je jako przyciski.
  - Zmiana interwału działa od razu.
- **Konta:**
  - Zmiana lub usunięcie klucza kasuje zaplanowane alerty lądowania.
  - „Test Connection” na niezapisanym kluczu nie wpływa na aktywne konto.
- **Forum Watch:** zatrzymuje się po trwałym błędzie klucza i wraca przy następnym otwarciu menu z poprawnym kluczem.
- **Dostępność:** prompty Feedback i Sentry blokują treść pod spodem, a ikona w pasku menu mówi „error”, „abroad” albo „energy full”.

## Potencjalne regresje

- **Budżet requestów:** timer alertów cenowych dodaje żądania `market.item` w tle. Przy N przedmiotach z progiem to N żądań co 5 minut (ograniczonych przez `cache_delay`, limit 4 równoległych i bramkę `reserveRequest`).
- **Watchlista po aktualizacji:** pozycje zapisane przed fixem R-02 mają znacznik w czasie serwera. Przy zegarze Maca spóźnionym o X sekund pierwsza nowa cena może być pominięta najwyżej przez X sekund.
- **Karta łańcucha:** nowa karta „Unavailable” pojawi się w miejscach, gdzie wcześniej nie było nic (Status).
- **Picker 15 s:** etykieta VO na segmencie może zostać zignorowana przez AppKit. Jest nieszkodliwa, ale może nic nie dawać.

## Manual QA — do sprawdzenia przed publikacją lub po niej

1. Włącz „Stock bonuses” i uruchom aplikację ponownie. „Total Tracked” w Money powinno zawierać akcje.
2. Ustaw próg ceny na przedmiocie, zamknij popover i poczekaj ponad 5 minut. Powinno przyjść powiadomienie, gdy cena jest poniżej progu.
3. Przy pierwszym uruchomieniu bez klucza: fokus w polu klucza, a Return zapisuje.
4. VoiceOver na ikonie w pasku menu, w stanie błędu i za granicą.
5. Prompt Sentry lub Feedback: Tab i VoiceOver nie powinny wychodzić poza prompt.
6. W trakcie lotu: po dojściu do zera „Arriving in” pokazuje „Ready”.
7. Zmień interwał odświeżania z 30 s na 2 min. Kolejne odświeżenie nastąpi po 2 minutach, nie po 30 s.
8. Przełącz konto w trakcie lotu. Alert lądowania starego konta nie powinien przyjść.
9. Pierwszy run CI po przypięciu SHA: workflowy `claude`, `claude-code-review` i `gitleaks` startują poprawnie.
10. `make test-ui`, gdy ekran będzie wolny. Nie był uruchamiany w tym przebiegu.

---

# Poprzedni przebieg (2026-08-26)


Last verified: 2026-08-26 | gałąź `feature/torn-api-2026-08` → wydanie 1.12.0
Zamówienie: audyt i naprawa warstwy Torn API, wdrożenie tego, co się w API zmieniło,
`/audit`, `/stop-slop`, wydanie produkcyjne.

Poprzedni przebieg (2026-08-01, wersja 1.11.1) jest w historii gita.

---

## Podsumowanie

37 plików, +2518 / −150 linii. Dziewięć defektów w warstwie API naprawionych, cztery
funkcje dodane, 74 nowe testy. Zestaw testów jednostkowych urósł z 569 do 643. Wszystkie
bramki jakości poza UI-testami zaliczone. UI-testy nie dały się uruchomić w tym środowisku
(patrz *Do ręcznego QA*).

---

## Nowe pliki

| Plik | Rola |
|---|---|
| `MacTorn/Networking/TornEndpointGate.swift` | Decyduje, czy wolno wydać żądanie: uprawnienia klucza, przynależność do frakcji, cool-offy po błędach, budżet wierszy. |
| `MacTorn/ViewModels/AppState+ItemCatalog.swift` | Katalog przedmiotów Torna: pobranie, cache, wyszukiwanie po nazwie, uzupełnianie nazw w watchliście. |
| `MacTornTests/Models/TornEndpointGateTests.swift` | 18 testów bramki. |
| `MacTornTests/Models/TornAPIClientTests.swift` | 12 testów budowy żądania: nagłówek, `comment`, zawężanie selekcji, redakcja. |
| `MacTornTests/Models/UserV2AdditionsTests.swift` | 13 testów liczników powiadomień i wirusa. |
| `MacTornTests/ViewModels/ItemCatalogTests.swift` | 17 testów katalogu przedmiotów. |
| `MacTornTests/ViewModels/ForumCategoryWatchTests.swift` | 15 testów obserwowania kategorii forum. |
| `scripts/add-source-file.py` | Dopisuje plik Swift do `project.pbxproj` (projekt nie używa synchronizacji katalogów Xcode 16). **Odstępstwo od reguły „TypeScript zawsze, Python nigdy bez zgody":** to narzędzie deweloperskie, nie kod produktu, a repo nie ma toolchainu Node. Przepisanie na basha znaczyłoby wielolinijkowe wstawki w `sed`/`awk` do formatu OpenStep plist, czyli więcej ryzyka niż korzyści. Do decyzji Pawła. |

---

## Wykonane poprawki

Numeracja odpowiada `AUDIT_REPORT.md`.

**P1-1 · Bramkowanie żądań uprawnieniami klucza.** `TornEndpointGate` odmawia żądań, o
których `/key/info` mówi, że nie mogą się powieść. `AppState.refreshKeyInfoIfNeeded()`
dociąga uprawnienia w tle przy starcie pollingu, bez dotykania stanu przycisku „Test
Connection". `reserveRequest(_:)` przepuszcza żądanie wyłącznie przez bramkę.
Pliki: `TornEndpointGate.swift` (nowy), `AppState+PollingUserFetch.swift`, `AppState.swift`.

**P1-2 · Zawężanie selekcji do uprawnień.** `TornEndpoint.resolvedSelections(granted:)` i
`url(key:parameter:granted:)`. Nowy pojedynczy budowniczy `AppState.endpointURL(_:parameter:key:)`
zastąpił bezpośrednie wywołania `TornAPI.*URL` we wszystkich dwunastu miejscach, co domyka
zaległość A-02 z ISA. Stare buildery zostają jako niezależna druga implementacja, z którą
`TornEndpointTests` porównuje każdy URL z rejestru.
Pliki: `TornEndpoint.swift`, `AppState+PollingUserFetch.swift`, `AppState+FactionFetch.swift`,
`AppState+MarketForum.swift`, `AppState+PersistenceStocks.swift`.

**P1-3 · Przepisana taksonomia błędów.** Nowe klasy `temporaryKey` (kody 10–13, wznowienie
automatyczne po 10 min), `endpointUnavailable` (kody 6, 7, 19, 21, 22, 23, 25–30, wyłączają
tylko swój endpoint), `ipBlocked` (kod 8, godzina ciszy). `pauseDuration` zamiast jednej
stałej pauzy dla wszystkiego. `handleRecoverableKeyError` zatrzymuje polling i planuje
wznowienie zamiast wymagać interwencji użytkownika.
Pliki: `TornAPIError.swift`, `AppState+PollingUserFetch.swift`.

**P2-4 · Usunięcie selekcji `bazaar`.** Na v2 zwraca katalog bazarów bez cen, więc gałąź
parsująca `cost`/`quantity` nie mogła zadziałać. Selekcja, gałąź i błędny fixture usunięte.
Pliki: `TornEndpoint.swift`, `TornModels.swift`, `MarketWatchService.swift`,
`TornAPIFixtures.swift`, `AppStateWatchlistTests.swift`, `TornResponseTests.swift`.

**P2-5 · Dokończenie obserwowania kategorii forum.** `ForumWatchService.fetchCategoryThreads`
i `applyCategory`, wywołanie w pętli pollingu forum, przełącznik i pole ID w Ustawieniach.
Pierwszy odczyt jest cichy, sterowany nową flagą `hasSeededFactionThreads`, bo pusty zbiór
ID nie odróżnia „nigdy nie patrzyłem" od „patrzyłem, było pusto".
Pliki: `ForumWatchService.swift`, `AppState+MarketForum.swift`, `SettingsView.swift`,
`TornModels.swift`.

**P2-6 · Egzekwowanie budżetu wierszy.** `isWithinRecordBudget` wpięte w bramkę.
Plik: `TornEndpointGate.swift`.

**P2-7 · Poprawne rozliczanie wierszy listingu kategorii forum.** `sendsLimitQuery: true`,
`limit` wysyłany jawnie.
Pliki: `TornEndpoint.swift`, `TornModels.swift`.

**P2-8 · Pauza całego rejestru przy błędach kontowych.** `noteAccountWideFailure(_:)`:
blokada IP i zawieszony klucz pauzują wszystkie endpointy, nie tylko ten, który zauważył.
Pliki: `TornEndpointGate.swift`, `AppState+PollingUserFetch.swift`.

**P3-9 · Fixture UI-testów wyprowadzony z rejestru.** Ręczna lista udzielonych selekcji
zastąpiona wyliczeniem z `TornEndpointRegistry`, plus dwa testy pilnujące zgodności.
Pliki: `UITestSupport.swift`, `UITestHarnessTests.swift`.

---

## Dodane funkcje

**Liczniki powiadomień.** Selekcja `notifications` dołączona do istniejącego wywołania v2,
więc zero dodatkowych żądań. Odznaka nieprzeczytanych wiadomości w Statusie zastąpiona wierszem
czterech liczników (wiadomości, zdarzenia, nagrody, konkursy). Selekcja `messages` usunięta
z wywołania wierszowego, bo ten sam licznik przychodzi teraz za darmo. O ⅓ mniej wierszy w
kategorii `activity`.
Pliki: `TornEndpoint.swift`, `TornModels.swift`, `UserSnapshotService.swift`,
`AppState.swift`, `AppState+PollingUserFetch.swift`, `StatusView.swift`.

**Odliczanie programowania wirusa.** Nowy endpoint `user.virus` (`/v2/user/virus`; `virus`
nie jest selekcją łączoną, brakuje jej w enumie `UserSelectionName`). Wirus dołącza do osi
Next Action i wywołuje powiadomienie po zakończeniu. Odczyt tylko wtedy, gdy odpowiedź mogła
się zmienić: po minięciu znanego terminu albo po pół godziny niewiedzy.
Pliki: `TornEndpoint.swift`, `TornModels.swift`, `UserSnapshotService.swift`,
`AppState+PollingUserFetch.swift`, `NextAction.swift`, `AppState+LiveNextAction.swift`,
`NotificationManager.swift`.

**Katalog przedmiotów i wyszukiwanie po nazwie.** Nowy endpoint `torn.items`, cache w
`UserDefaults` na tydzień, wyszukiwanie z rankingiem prefiks-przed-podciągiem, uzupełnianie
nazw pozycji zapisanych jako `Item #<id>`. Nazwy wpisane przez użytkownika nietykane.
Pliki: `AppState+ItemCatalog.swift` (nowy), `TornEndpoint.swift`, `TornModels.swift`,
`AppState.swift`, `WatchlistView.swift`, `AppState+MarketForum.swift`.

**Sekcja „Not being requested" w Diagnostyce.** Lista pominiętych endpointów z powodem, w
panelu zdaniami po ludzku (`userExplanation`), w kopiowanym raporcie etykietami maszynowymi
(`label`).
Pliki: `Diagnostics.swift`, `DiagnosticsView.swift`, `AppState+LiveNextAction.swift`,
`TornEndpointGate.swift`.

---

## Zmiany zachowania

Rzeczy, które użytkownik może zauważyć, także te niezamierzone:

1. **Mniej żądań.** Gracz bez frakcji nie wysyła już trzech żądań frakcyjnych na cykl.
   Klucz o niskich uprawnieniach nie wysyła żądań, których nie obsłuży.
2. **Zawężone żądania zwracają mniej danych.** Klucz, który wcześniej dostawał błąd 16 na
   całe wywołanie, dostaje teraz częściową odpowiedź. Moduły odpowiadające niedozwolonym
   selekcjom pozostają puste, celowo, ale bez wyjaśnienia w samym module (patrz
   rekomendacja A1 w `UX_RECOMMENDATIONS.md`).
3. **Inny komunikat błędu przy problemach przejściowych klucza.** Zamiast „Your API key is
   invalid or paused" pojawia się zdanie o federal jail / cooldownie i automatyczne
   wznowienie.
4. **Licznik nieprzeczytanych odświeża się z każdym pollem**, nie co pięć minut.
5. **Cena na watchliście pochodzi wyłącznie z item marketu.** Wcześniej kod *próbował*
   uwzględnić bazar, ale nie mógł, więc widoczna cena się nie zmienia. Fixture testowy się
   zmienił, żeby przestać udawać, że mógł.
6. **Nazwy pozycji watchlisty zapisane jako `Item #<id>` zmienią się na prawdziwe** przy
   pierwszym pobraniu katalogu.
7. **Pierwsze uruchomienie po aktualizacji wykona jedno dodatkowe żądanie** (`/key/info`) i
   jedno duże (`/torn/items`, kilkaset kB, raz na tydzień).
8. **Klucz API v2 wędruje w nagłówku, nie w URL-u.** Niewidoczne, chyba że ktoś ogląda
   ruch; wtedy widoczne bardzo.
9. **Każde żądanie podpisane `comment=MacTorn`** w logu klucza na torn.com.

---

## Potencjalne regresje

Rzeczy, które mogą pójść źle i na które trzeba patrzeć po wydaniu:

| Ryzyko | Dlaczego mogłoby wystąpić | Jak rozpoznać |
|---|---|---|
| **Torn nie akceptuje nagłówka `Authorization` na v2** | Zmiana oparta na dokumentacji, nie na żywym teście. | Diagnostyka: `user.v2`, `market.item`, `key.info` z wynikiem `error` zamiast `ok`. |
| **`/key/info` pomija nazwę selekcji, którą v1 przyjmuje** | Zawężenie po cichu obcięłoby funkcję. Sprawdzono, że wszystkie dziewięć nazw z `user.fast` jest w enumie specyfikacji, ale to sprawdzenie na papierze. | Moduł pusty mimo klucza Full Access; Diagnostyka wymieni go w „Not being requested". |
| **Bramka blokuje działający endpoint** | Błąd w mapowaniu kategorii albo w `/key/info`. | Jak wyżej. Obejście: bramka nie blokuje nic, dopóki `keyInfo == nil`, więc usunięcie i ponowne wpisanie klucza bez klikania Test Connection przywraca stary tryb do czasu pierwszego udanego `/key/info`. |
| **Katalog przedmiotów nadpisuje ręcznie wpisaną nazwę** | Warunek uzupełniania sprawdza dokładne dopasowanie do `Item #<id>`. | Nazwa własna zmieniona po aktualizacji. Pokryte testem `testBackfillLeavesUserChosenNamesAlone`. |
| **Obserwowanie kategorii forum zalewa powiadomieniami** | Gdyby flaga zasiewu nie zapisała się przed pierwszym powiadomieniem. | Seria powiadomień o starych wątkach zaraz po włączeniu. Pokryte pięcioma testami. |
| **Konfiguracja forum ze starszego builda resetuje się** | Nowe pole w `Codable`. | Znikają obserwowane wątki albo interwał wraca do 3 min. Pokryte testem `testAnOlderConfigWithoutTheSeededFlagStillLoads`. |

---

## Bramki jakości

| Bramka | Przed | Po |
|---|---|---|
| `make test` | 569 ✅ | 643 ✅ |
| `xcodebuild build` | ✅ | ✅ |
| `make analyze` | 0 ostrzeżeń | 0 ostrzeżeń |
| `make coverage-gate` (80 % na modułach krytycznych) | PASSED | PASSED |
| `make scan` (gitleaks, 182 commity) | brak wycieków | brak wycieków |
| `make test-ui` (lokalnie) | ❌ nie uruchamia się | ❌ nie uruchamia się |
| CI `Tests` (z `Fixture UI Tests`) | — | ✅ przebieg 32914341887, wszystkie joby |

---

## Do ręcznego QA

Pełna lista jest na końcu `UX_RECOMMENDATIONS.md`. Trzy punkty, które trzeba sprawdzić
**zanim** wydanie trafi do kogokolwiek poza Pawłem:

1. **Diagnostyka → Endpoints: wszystkie v2 z wynikiem `ok`.** To jedyny test tego, czy Torn
   akceptuje przeniesienie klucza do nagłówka. Jeśli któryś jest `error`, cofnąć
   `TornAPIClient.usesHeaderAuth` do `false` i wydać patch.
2. **Szybki poll aktualizuje paski i cooldowny.** Weryfikuje zawężanie selekcji na
   najbardziej krytycznej ścieżce.
3. **`make test-ui` na odblokowanej sesji.** Lokalnie się nie uruchamia; na CI przeszła
   (przebieg 32914341887), więc pokrycie jest, ale warto raz puścić u siebie.

## Dodatek: 1.12.1

Niezależny audyt bezpieczeństwa dotarł po opublikowaniu 1.12.0. Cztery naprawy, wszystkie w
`AUDIT_REPORT.md` jako P2-10, P2-11, P3-5 i P3-6:

- sanityzacja przepuszczała U+2028/U+2029, więc spreparowany tytuł wątku forum mógł dopisać
  drugi akapit do powiadomienia (`NotificationManager`, `TornAPIError`),
- katalog przedmiotów wpisywał nieograniczony tekst serwera do trwałej watchlisty
  (`parseItemCatalog`, `WatchlistItem.renamed(to:)`),
- „Download Update" otwierał dowolny host https (`UpdateManager.isTrustedReleaseURL`),
- scrubber Sentry nie czyścił nagłówków (`SentryManager.scrub`).

15 testów regresyjnych w `MacTornTests/Models/HostileResponseTests.swift`. 663 testy
jednostkowe przechodzą.


## Dodatek: 1.12.2

Trzy audyty (diff, integralność danych, dostępność/UX) odezwały się po opublikowaniu
1.12.1. Znalazły dwanaście defektów, **wszystkie w tym, co sam wprowadziłem w 1.12.0.**
Pełny opis w `AUDIT_REPORT.md` jako P1-12…P1-16, P2-12…P2-14, P3-7, P3-8.

Naprawione:

- dodawanie pozycji watchlisty po nazwie działało tylko myszką (Return i Add szły prosto
  do parsera ID); brak dopasowania nie renderował niczego,
- obserwowanie kategorii forum ogłaszało stare wątki jako nowe, bo pamięć była podmieniana
  jedną stroną 20 wątków zamiast sumowana; zmiana kategorii w locie mogła dać serię
  powiadomień,
- `keyInfo` bez TTL i bez ponowienia; zawężanie selekcji nigdy nie działało na pierwszym
  pollu, bo odczyt uprawnień szedł równolegle z nim, nie przed nim,
- `disablesEndpoint` było martwe, a `market.item` i `forum.thread` nie zgłaszały błędów do
  bramki, więc martwe ID było odpytywane co poll bez końca,
- przełącznik forum mógł być włączony bez ID i był wtedy bezczynny bez sygnału,
- tytuły wątków forum trafiały nieograniczone do trwałego blobu,
- `notifiedBountyKeys` czyszczone wbrew własnemu komentarzowi,
- Diagnostyka pokazywała slug endpointu, wiersz odznak renderował się pusty.

**Jeden test z 1.12.0 utrwalał defekt jako poprawne zachowanie** i został przepisany.

671 testów jednostkowych przechodzi. Dwanaście dalszych ustaleń zostawionych Pawłowi z
uzasadnieniem — największe to cztery magazyny preferencji, które kasują własne dane przy
nieudanym dekodowaniu.
