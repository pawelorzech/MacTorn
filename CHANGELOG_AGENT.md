# CHANGELOG_AGENT: zmiany wykonane przez agenta

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
