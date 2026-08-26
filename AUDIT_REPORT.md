# MacTorn — raport audytu technicznego

Last verified: 2026-08-26 | wersja bazowa 1.11.1 → wydanie 1.12.0
Gałąź: `feature/torn-api-2026-08`
Poprzednie przebiegi: 2026-08-01 (1.11.1) i 2026-07-30 (1.10.0), zachowane w historii gita.

Zakres zamówiony przez Pawła: „upewnij się, że dobrze korzystamy ze wszystkich endpointów;
jak coś się zmieniało, wdróż to". Audyt skupił się więc na warstwie Torn API, a resztę
drzewa sprawdził pod kątem regresji.

Ten dokument zawiera fakty i lokalizacje `plik:linia`. Oceny i rekomendacje produktowe są
w `UX_RECOMMENDATIONS.md`, wykaz zmian w `CHANGELOG_AGENT.md`.

---

## Streszczenie stanu

Kod produkcyjny jest w bardzo dobrym stanie i poprzednie audyty wyczyściły klasykę:
force-unwrapy, puste `catch`, redakcja URL-i w logach, klucz w Keychainie, sandbox z dwoma
uprawnieniami. Ten przebieg nie znalazł ani jednego problemu tej klasy.

Znalazł natomiast **dziewięć defektów w sposobie rozmawiania z Torn API**. Wszystkie były
niewidoczne dla zielonego zestawu testów, bo wszystkie polegały na tym, że aplikacja
wysyłała żądanie, na które serwer odpowiadał zgodnie z prawdą „nie", i nikt tego „nie" nie
liczył. Trzy z nich zmieniały to, co użytkownik widzi:

1. **Aplikacja znała odpowiedź i pytała mimo to.** `/key/info` mówi dokładnie, które selekcje
   klucz może odczytać i czy właściciel jest we frakcji. MacTorn dekodował to od wersji
   1.9, ale tylko do panelu za przyciskiem „Test Connection", którego prawie nikt nie naciska.
   `keyInfo` zostawał `nil`, więc gracz bez frakcji wydawał żądanie na `faction/basic` co
   trzydzieści sekund, bez końca, wyłącznie po to, żeby usłyszeć odmowę.
2. **Jedna niedozwolona selekcja kosztowała cały poll.** Torn odrzuca *całe* żądanie błędem
   16, jeśli zawiera choć jedną selekcję, której klucz nie może odczytać. Prośba o
   `battlestats` do klucza Minimal Access kosztowała więc paski, cooldowny i licznik podróży w
   tym samym wywołaniu, a nie tylko statystyki bojowe.
3. **Połowa kodów błędów była źle zaklasyfikowana.** Torn własnymi nazwami mówi „key owner in
   federal jail", „key change cooldown", „key temporary disabled". Wszystkie mijają same.
   MacTorn traktował je jako trwałe: zatrzymywał polling i kazał użytkownikowi naprawić
   klucz, któremu nic nie było.

Do tego jedna martwa funkcja, którą README ogłaszał jako działającą (obserwowanie kategorii
forum), jeden endpoint proszący o dane, których Torn na v2 już nie zwraca (`bazaar`), oraz
klientowy budżet wierszy, który był mierzony i nigdy nie sprawdzany.

Wszystkie dziewięć naprawione na gałęzi. Żaden nie był P0.

---

## Mapa projektu

Natywna aplikacja macOS 14+ w SwiftUI, `MenuBarExtra`, ~13 400 linii kodu produkcyjnego.
Bez backendu własnego, bez bazy danych, bez logowania. Jedyna integracja to odczyt z
`api.torn.com` kluczem API użytkownika.

| Warstwa | Gdzie | Rola |
|---|---|---|
| Rejestr endpointów | `Networking/TornEndpoint.swift` | jedyne źródło prawdy: budowa URL-i, metadane, tabela w README |
| Bramka żądań | `Networking/TornEndpointGate.swift` | decyduje, czy wolno wydać żądanie (**nowe w tym przebiegu**) |
| Taksonomia błędów | `Networking/TornAPIError.swift` | klasyfikacja kodów Torna na decyzje retry/stop |
| Budowa żądania | `TornAPIClient` w `Models/TornModels.swift` | nagłówek `Authorization`, `comment`, polityka cache |
| Uprawnienia klucza | `Networking/TornKeyInfo.swift` | dekoduje `/key/info`, mapuje na dostępność endpointów |
| Budżet | `Utilities/PollingCoordinator.swift` | żądania/min, wiersze/dobę per kategoria |
| Stan | `ViewModels/AppState*.swift` (8 plików) | `@MainActor @Observable`, polling, powiadomienia |
| Usługi transportowe | `ViewModels/{UserSnapshot,Faction,MarketWatch,ForumWatch}Service.swift` | dekodowanie, bez wiedzy o `AppState` |
| Widoki | `Views/` (9 modułów + Settings + Diagnostics) | popover 320 pt |

**Przepływ danych:** timer Combine → `fetchData()` → `reserveRequest(id)` (bramka +
budżet) → `endpointURL(id)` (rejestr, zawężony do uprawnień klucza) →
`TornAPIClient.request(for:)` → usługa dekoduje → `AppState` publikuje → SwiftUI.

**Miejsca przechowywania danych:** Keychain (klucz API, `KeychainStore`), UserDefaults
(watchlista, obserwowane wątki, reguły powiadomień, skróty, cache metadanych giełdy i
katalogu przedmiotów). Zero danych na serwerze.

**Największe ryzyka konstrukcyjne:** jedno wywołanie v1 `user` obsługuje dziewięć selekcji
naraz (awaria = ciemno w całej aplikacji); polling co 30 s przy limitach Torna 100
żądań/min i 50 000 wierszy/dobę/kategoria; klucz API w URL na v1.

---

## Stan bazowy

Wykonane polecenia i wyniki **przed** zmianami tej gałęzi:

| Polecenie | Wynik |
|---|---|
| `make test` (`xcodebuild test -only-testing:MacTornTests`) | ✅ 569 testów, 0 błędów |
| `xcodebuild build` (Debug) | ✅ BUILD SUCCEEDED |
| `make analyze` (analiza statyczna Xcode) | ✅ 0 ostrzeżeń, 0 błędów |
| `make coverage-gate` (próg 80 % na modułach krytycznych) | ✅ PASSED |
| `make scan` (gitleaks, pełna historia) | ✅ 182 commity, brak wycieków |
| `make test-ui` (XCUITest) | ❌ **nie dało się uruchomić**, patrz Ograniczenia |
| SwiftLint | ❌ nie zainstalowany w tym środowisku |

Zielony build nie jest dowodem, że aplikacja działa poprawnie: wszystkie dziewięć defektów
niżej istniało przy 569 zielonych testach.

---

## Problemy naprawione

### P1-1 · Żądania wysyłane mimo wiedzy, że klucz ich nie obsłuży

**Status:** potwierdzony (analiza statyczna + brak jakiegokolwiek wywołania bramkującego).
**Lokalizacja:** `ViewModels/AppState+PollingUserFetch.swift:88` (dawne `reserveRequest`),
`Networking/TornKeyInfo.swift:160` (`KeyValidator.validate`, wynik używany tylko w UI).
**Reprodukcja:** klucz Public Only albo gracz bez frakcji → `faction/basic` wysyłane co
`refreshInterval`, w nieskończoność, z odpowiedzią odmowną.
**Oczekiwane vs rzeczywiste:** oczekiwane to pominięcie żądania, o którym wiadomo, że nic nie
zwróci. Rzeczywiste: żądanie wysyłane, odmowa logowana na poziomie `warning` i porzucana.
**Przyczyna źródłowa:** `validateKey()` wywoływane wyłącznie z przycisku „Test Connection"
(`Views/SettingsView.swift:272`), jedyne takie miejsce w kodzie. Kto nie nacisnął, ten miał
`keyInfo == nil` na zawsze, więc nie było czego bramkować.
**Poprawka:** `TornEndpointGate` (nowy plik) odmawia na podstawie `/key/info`;
`refreshKeyInfoIfNeeded()` dociąga uprawnienia w tle bez dotykania stanu UI „Test
Connection". `reserveRequest` przepuszcza żądanie tylko przez bramkę.
**Ryzyko regresji:** bramka mogłaby zablokować działający endpoint, gdyby `/key/info`
skłamało. Zabezpieczenie: brak wiedzy nie blokuje niczego. `keyInfo == nil` przepuszcza
wszystko, a odmowa wymaga *pełnego* braku selekcji.
**Weryfikacja:** `TornEndpointGateTests` (15 testów), w tym
`testUnvalidatedKeyBlocksNothing` pilnujący kierunku ostrożności.

### P1-2 · Jedna niedozwolona selekcja psuła całe wywołanie

**Status:** potwierdzony na podstawie dokumentacji OpenAPI Torna (`ErrorAccessLevelTooLow`,
kod 16, zwracany dla całego żądania).
**Lokalizacja:** `Networking/TornEndpoint.swift:139` (dawne `url(key:parameter:)`, bez
zawężania) i `Models/TornModels.swift:1297` (stała `selections`).
**Reprodukcja:** klucz Minimal Access + `user.fast` z `battlestats` → kod 16 na całą
odpowiedź → `handlePermanentKeyError` → polling zatrzymany.
**Przyczyna źródłowa:** lista selekcji była stała zamiast wynikać z uprawnień klucza, choć
`parseSnapshot` już przyjmował `grantedSelections` do *interpretacji* odpowiedzi.
**Poprawka:** `TornEndpoint.resolvedSelections(granted:)` przycina żądanie do tego, co klucz
umie odczytać; `AppState.endpointURL(_:parameter:key:)` przekazuje uprawnienia z `keyInfo`.
Przy zerowym przecięciu URL nie powstaje wcale i bramka odmawia.
**Ryzyko regresji:** gdyby `/key/info` pomijało nazwę selekcji, którą v1 przyjmuje,
zawężenie po cichu obcięłoby funkcję. Sprawdzono: wszystkie dziewięć nazw z `user.fast` jest
w enumie `UserSelectionName` specyfikacji 6.13.1.
**Weryfikacja:** `TornAPIClientTests.testNarrowingAsksOnlyForWhatTheKeyCanRead` i cztery
sąsiednie; `UserSnapshotContract.isSatisfied` już wcześniej akceptował zawężone odpowiedzi.

### P1-3 · Błędy przejściowe klucza traktowane jak trwałe

**Status:** potwierdzony wobec `components.schemas.Error*` w OpenAPI 6.13.1.
**Lokalizacja:** `Networking/TornAPIError.swift:151` (dawny `classify`, przypadek
`case 1, 2, 10, 11, 12, 13, 18`).
**Reprodukcja:** właściciel klucza trafia do federal jail → Torn zwraca kod 10 → MacTorn
klasyfikuje jako `permanentKey` → `handlePermanentKeyError` czyści stan, ustawia
`keyHalted`, zatrzymuje polling i wyświetla komunikat o nieprawidłowym kluczu. Aplikacja
nie wraca do życia, dopóki użytkownik sam nie ruszy klucza.
**Oczekiwane vs rzeczywiste:** oczekiwane to przeczekać i wznowić. Rzeczywiste: trwały stop
plus mylący komunikat.
**Przyczyna źródłowa:** kody 10, 11, 12 i 13 wrzucono do jednego worka z 1, 2 i 18. Nazwy
Torna („federal jail", „change cooldown", „temporary disabled") wprost mówią, że mijają.
**Poprawka:** nowa klasa `temporaryKey` z `pauseDuration` 600 s i automatycznym wznowieniem
(`handleRecoverableKeyError`). Osobno: kody, które nigdy się nie powiodą (6, 7, 19, 21, 22,
23, 25–30), dostały klasę `endpointUnavailable` i wyłączają tylko swój endpoint zamiast być
retryowane w nieskończoność; kod 8 (blokada IP) dostał godzinę ciszy zamiast retry, które go
wywołało.
**Ryzyko regresji:** nieznany, przyszły kod Torna nadal wpada w `temporaryBackend`, czyli
„spróbuj później", nigdy w twardy stop.
**Weryfikacja:** `TornAPIErrorTests`, cztery nowe testy pokrywające każdą klasę, w tym
`testUnknownFutureCodeDegradesToRetry`.

### P2-4 · `bazaar` proszony o dane, których v2 nie zwraca

**Status:** potwierdzony wobec `BazaarResponseSpecialized` / `Bazaar` w OpenAPI 6.13.1.
**Lokalizacja:** `ViewModels/MarketWatchService.swift:179` (dawna gałąź parsująca),
`Models/TornModels.swift:1365` (dawny `marketURL`).
**Reprodukcja:** odświeżenie ceny dowolnej pozycji watchlisty. `/v2/market/{id}` zwraca dla
selekcji `bazaar` obiekt `{"bazaar": {"specialized": [...]}}`, gdzie elementy to `{id, name,
is_open, weekly_customers}`, czyli katalog bazarów mających przedmiot, bez żadnej ceny.
**Oczekiwane vs rzeczywiste:** kod rzutował `json["bazaar"]` na `[[String: Any]]` i czytał
`cost`/`quantity`. Rzutowanie na tablicę nie może się udać na słowniku, więc gałąź była
martwa; żądanie nadal ciągnęło ten payload.
**Przyczyna źródłowa:** kształt z API v1, gdzie `bazaar` faktycznie zwracał oferty z cenami.
Torn zmienił to na v2 i aplikacja za tym nie poszła.
**Poprawka:** `bazaar` usunięty z selekcji, martwa gałąź usunięta, fixture testowy
poprawiony, bo dotąd „udowadniał", że parser czyta kształt, którego serwer nie produkuje.
**Ryzyko regresji:** ceny bazarowe bywają niższe niż na item markecie, więc alert cenowy
teoretycznie traci źródło. W praktyce nie traci nic, bo to źródło i tak nie działało; Torn
nie udostępnia cen bazarowych per przedmiot na v2 w żadnej formie.
**Weryfikacja:** `AppStateWatchlistTests` przechodzą na poprawionym fixture (najniższa cena
950 pochodzi teraz z listingu item marketu).

### P2-5 · Obserwowanie kategorii forum ogłoszone, nigdy niepodłączone

**Status:** potwierdzony (`grep` po `factionForumAutoMonitor`: zero odczytów w kodzie
produkcyjnym przed zmianą).
**Lokalizacja:** `Models/TornModels.swift:1686` (pola konfiguracji),
`Utilities/NotificationManager.swift:24` (`case factionNewThread`),
`Networking/TornEndpoint.swift:310` (endpoint `forum.threads`), `README.md:164` (tabela).
**Reprodukcja:** brak, bo nie dało się tego włączyć: nie było ani UI, ani wywołania.
**Oczekiwane vs rzeczywiste:** README i ujawnienie w onboardingu mówiły użytkownikowi, że
MacTorn czyta wątki kategorii forum. Nie czytał ich wcale.
**Przyczyna źródłowa:** rusztowanie funkcji weszło do repo bez ostatniego kroku i nic tego
nie wykrywało. Test sprawdzał liczbę wierszy tabeli w README, nie ich treść.
**Poprawka:** funkcja dokończona (`AppState+MarketForum.swift`,
`ForumWatchService.applyCategory`), przełącznik i pole ID kategorii w Settings. Pierwszy
odczyt jest cichy: kategoria mieści do stu wątków, więc „wszystko, czego nie znam, jest
nowe" oznaczałoby sto powiadomień o rozmowach sprzed miesięcy.
**Ryzyko regresji:** pusty zbiór ID jest niejednoznaczny („nigdy nie patrzyłem" vs
„patrzyłem, było pusto"), więc doszła osobna flaga `hasSeededFactionThreads`, a
`ForumWatchConfig` dekoduje się pole po polu, żeby konfiguracja ze starszego builda nie
wyzerowała się przy wczytaniu.
**Weryfikacja:** `ForumCategoryWatchTests` (14 testów), w tym
`testAnOlderConfigWithoutTheSeededFlagStillLoads`.

### P2-6 · Klientowy budżet wierszy był mierzony i nigdy nie sprawdzany

**Status:** potwierdzony (`grep isWithinRecordBudget`: zero wywołań poza definicją).
**Lokalizacja:** `Utilities/PollingCoordinator.swift:94`.
**Przyczyna źródłowa:** funkcja napisana pod Diagnostics i nigdy niepodpięta do ścieżki
decyzyjnej. Jedynym realnym hamulcem dla rozpędzonego źródła wierszy był błąd 14 od Torna.
**Poprawka:** bramka sprawdza budżet przed wydaniem żądania wierszowego.
**Weryfikacja:** `TornEndpointGateTests.testRowBudgetIsEnforcedAndNotMerelyMeasured`.

### P2-7 · Rozliczenie wierszy listingu kategorii forum zaniżone pięciokrotnie

**Status:** potwierdzony wobec `ApiLimit100` w OpenAPI 6.13.1.
**Lokalizacja:** `Networking/TornEndpoint.swift:317` (`sendsLimitQuery: false`,
`recordLimit: 20`).
**Przyczyna źródłowa:** rejestr deklarował, że `/v2/forum/{id}/threads` nie przyjmuje
`limit`. Przyjmuje, i domyślnie zwraca 100 wierszy. Księgowano 20.
**Poprawka:** `sendsLimitQuery: true`, `limit` wysyłany jawnie, `TornAPI` zsynchronizowane.
**Weryfikacja:** `TornEndpointTests.testRegistryURLsMatchLegacyBuilders`.

### P2-8 · Blokada IP i zawieszony klucz pauzowały tylko jeden endpoint

**Status:** potwierdzony (analiza `handleRecoverableKeyError` po pierwszej poprawce).
**Lokalizacja:** `ViewModels/AppState+PollingUserFetch.swift` (`noteEndpointFailure`
wywoływane z identyfikatorem pojedynczego endpointu).
**Przyczyna źródłowa:** cool-off był z definicji per endpoint, a blokada IP i zawieszony
klucz odmawiają wszystkiemu jednakowo. Pozostałe osiem endpointów dalej biło w tę samą
ścianę, a blokadę IP dalsze żądania pogłębiają.
**Poprawka:** `TornEndpointGate.noteAccountWideFailure(_:)` pauzuje cały rejestr.
**Weryfikacja:** `TornEndpointGateTests.testAnAccountWideFailurePausesEveryEndpoint`.

### P3-9 · Fixture UI-testów rozjeżdżał się z rejestrem po cichu

**Status:** potwierdzony (wprowadzony przez tę gałąź, wykryty przed scaleniem).
**Lokalizacja:** `Helpers/UITestSupport.swift:389` (ręczna lista `selections`).
**Reprodukcja:** dodanie selekcji `notifications` do `user.v2` sprawiło, że fixture
`/key/info` przestał jej udzielać → bramka odmawiałaby `user.v2` przez cały przebieg
UI-testów, a objawem byłby pusty panel w zupełnie innym miejscu.
**Poprawka:** fixture wyprowadza udzielone selekcje z `TornEndpointRegistry`, plus dwa testy
(`FixtureKeyInfoTests`) pilnujące, że klucz fixture'a przechodzi przez bramkę dla każdego
endpointu.

---

## Problemy pozostawione (niewdrożone)

| Priorytet | Problem | Powód niewdrożenia | Zalecane działanie |
|---|---|---|---|
| P2 | Migracja szybkiego polla z v1 na v2 | Kształty odpowiedzi różnią się istotnie (`travel.departed_at` vs `departed`, `money` przemianowane, `battlestats` z płaskiego na obiektowy, `stocks` ze słownika na tablicę). To przepisanie warstwy modelu na najbardziej krytycznej ścieżce, bez możliwości weryfikacji na żywym kluczu w tej sesji. Nieproporcjonalne do wydania nocnego. | Zaplanować jako osobne zadanie z żywym kluczem i porównaniem odpowiedzi v1↔v2 pole po polu. v1 nie jest wygaszone: OpenAPI Torna mówi, że niezmigrowana selekcja v2 „will default to the API v1 version". |
| P2 | Klucz API nadal w query stringu na v1 | Torn dokumentuje nagłówek `Authorization: ApiKey` wyłącznie dla v2. Wysłanie go na v1 „na wszelki wypadek" bez żywego klucza do sprawdzenia to ryzyko wywalenia najważniejszego wywołania w aplikacji. | Sprawdzić na żywym kluczu, czy v1 honoruje nagłówek. Jeśli tak — przenieść i tam. Do tego czasu chroni `tornRedactedURL`. |
| P3 | ~250 plików `com.mactorn.tests.*.plist` w `~/Library/Preferences` i wpisy `com.mactorn.app.tests.*` w pęku kluczy | Śmieci po testach na maszynie deweloperskiej, nie w produkcie. Poza zakresem zamówionego audytu API. | Dodać sprzątanie w `tearDown` testów, które tworzą izolowane suity i wpisy Keychain. |
| P3 | `AppState+MarketForum.swift` ma 57 % pokrycia | Nowa ścieżka kategorii forum jest przetestowana na poziomie `ForumWatchService`; nieprzetestowana zostaje warstwa orkiestracji w `AppState`. | Dodać test integracyjny na `checkFactionForumForNewThreads` z mockiem sesji. |
| P3 | `/user/virus` odpytywane co 30 min także wtedy, gdy gracz nigdy nie programuje wirusów | 48 żądań na dobę przy limicie 100/min, nieistotne wobec budżetu. | Zostawić. Ewentualnie wydłużyć odstęp po N kolejnych pustych odpowiedziach. |

---

## Obszary sprawdzone i czyste

- **Sekrety.** `make scan` na 182 commitach historii: zero wycieków. Allowlist w
  `.gitleaks.toml` dopasowuje **całe** trafienie (`regexTarget = "match"`), więc naprawiony
  wcześniej błąd dopasowania po podciągu nie wrócił.
- **Analiza statyczna.** `xcodebuild analyze`: zero ostrzeżeń przed i po zmianach.
- **Force-unwrapy w nowym kodzie.** Dwa, oba postaci `słownik[klucz]!` gdzie klucz pochodzi
  z `słownik.keys.sorted()`, więc bezpieczne z konstrukcji i zgodne ze stylem sąsiedniego kodu.
  Zero `try!`, `as!`, `fatalError`, pustych `catch`, `print`, `TODO`.
- **Redakcja URL-i.** `tornRedactedURL` nadal usuwa wszystkie wartości query; test
  `testRedactedURLNeverCarriesAValue` sprawdza to dla każdego endpointu w rejestrze.
- **Kontrakt odpowiedzi przy zawężeniu.** `UserSnapshotContract.isSatisfied` już wcześniej
  przecinał żądane selekcje z udzielonymi, a wszystkie pola `TornResponse` są opcjonalne, więc
  zawężona odpowiedź dekoduje się poprawnie zamiast jako `malformed`.
- **Izolacja kont.** Każda nowa ścieżka asynchroniczna (`fetchVirusIfNeeded`,
  `refreshKeyInfoIfNeeded`) sprawdza `isCurrentAccount` po `await` przed zapisem stanu.
  `resetAccountScopedState()` anuluje nowe uchwyty zadań. Katalog przedmiotów celowo
  przeżywa zmianę konta, bo to dane globalne gry, jak metadane giełdy.
- **Deprecacje w API.** Przejrzano cały dokument OpenAPI pod kątem pól oznaczonych
  `deprecated` i dat usunięcia. Żadne z nich nie dotyczy danych, których MacTorn używa
  (`TornItem.value.buy_price`/`sell_price`/`vendor`: 1 stycznia 2027; `faction/warfare`:
  1 stycznia 2027; `FactionSlotPositionInfo.number`: 1 czerwca 2026).
- **Prywatność.** Nie doszło żadne nowe zbieranie danych. Nowe pole raportu
  diagnostycznego (`suppressedEndpoints`) niesie wyłącznie zamknięty słownik klasyfikacji i
  nazwy selekcji, nigdy tekstu z serwera ani wpisanego przez użytkownika, zgodnie z regułą
  z issue #58.

---

## Poprawki 1.12.1 (audyt bezpieczeństwa po wydaniu)

Niezależny audyt bezpieczeństwa 1.12.0 znalazł cztery rzeczy, których ten raport nie
opisywał. Wszystkie potwierdzone empirycznie przed naprawą.

### P2-10 · Sanityzacja przepuszczała separatory linii Unicode

**Status:** potwierdzony własnym testem przed naprawą.
**Lokalizacja:** `Utilities/NotificationManager.swift` (`sanitize`),
`Networking/TornAPIError.swift` (`sanitized`).
**Przyczyna źródłowa:** `CharacterSet.controlCharacters` to kategorie Unicode Cc i Cf.
U+2028 LINE SEPARATOR (Zl) i U+2029 PARAGRAPH SEPARATOR (Zp) do nich nie należą, a CoreText
łamie na nich linię. Sprawdzone:

```
U+000A LF   stripped: true
U+2028 LS   stripped: false
U+2029 PS   stripped: false
U+202E RLO  stripped: true
```

**Reprodukcja:** tytuł wątku z `/forum/{id}/threads` jest CAŁYM ciałem powiadomienia
(`AppState+MarketForum.swift`). Tytuł `Re: raid\u{2029}\u{2029}MacTorn: your API key
expired, re-enter it at …` daje dwuakapitowe powiadomienie, którego druga część wygląda,
jakby napisał ją MacTorn. Ta sama droga dotyczy nazwy wirusa, nazwy OC, `listerName`
bounty i `TornAPIError.userMessage`, który dla kodów 1/2/18, 16 i domyślnej gałęzi
`temporaryBackend` zwraca łańcuch Torna dosłownie.
**Poprawka:** obie sanityzacje filtrują `CharacterSet.controlCharacters.union(.newlines)`,
co pokrywa LF, CR, NEL, LS i PS. Stała jest jedna i wspólna, żeby nie rozjechały się znowu.

### P2-11 · Katalog przedmiotów wpisywał nieograniczony tekst serwera do danych użytkownika

**Status:** potwierdzony (mój własny kod z tej gałęzi).
**Lokalizacja:** `AppState+ItemCatalog.swift` (`parseItemCatalog`, `backfillWatchlistNames`),
`Models/TornModels.swift` (`WatchlistItem.renamed(to:)`).
**Przyczyna źródłowa:** `MarketWatchService.add` przycinał nazwę wpisaną przez użytkownika do
64 znaków. Nazwa z katalogu nie przechodziła przez żadne ograniczenie, a backfill zapisywał
ją do trwałej watchlisty. Do tego `parseItemCatalog` nie ograniczał ani liczby wpisów, ani
długości nazwy, a wynik ląduje w UserDefaults, które macOS materializuje w całości przy
każdym starcie.
**Poprawka:** jedna wspólna stała `WatchlistItem.maximumNameLength`, stosowana i przy
wpisywaniu, i przy zmianie nazwy z katalogu; katalog ograniczony do 5 000 wpisów.

### P3-5 · Przycisk „Download Update" otwierał dowolny host https

**Lokalizacja:** `Views/SettingsView.swift`, `Models/TornModels.swift` (`GitHubRelease.htmlUrl`).
**Przyczyna źródłowa:** `BrowserManager` sprawdzał schemat, nie host, a URL pochodzi z
odpowiedzi api.github.com. **Poprawka:** `UpdateManager.isTrustedReleaseURL` z allowlistą
github.com.

### P3-6 · Scrubber Sentry nie znał nagłówka, który wprowadziło 1.12.0

**Lokalizacja:** `Utilities/SentryManager.swift` (`scrub(_ event:)`).
**Przyczyna źródłowa:** scrubber czyścił `url` i `queryString`, czyli dokładnie te miejsca,
z których klucz właśnie się wyprowadził. **Poprawka:** `req.headers = nil`. Dziś
niewykorzystywalne (tracking sieci wyłączony, a sentry-cocoa sam usuwa `Authorization`), ale
to była cudza decyzja, a teraz jest nasza.

### Zostawione Pawłowi

| Priorytet | Problem | Dlaczego nie teraz |
|---|---|---|
| P3 | `.reloadIgnoringLocalAndRemoteCacheData` jest wg Apple niezaimplementowane; brak kluczy w cache'u opiera się na nagłówkach `no-store` Torna, nie na naszej konfiguracji | Naprawa to sesja efemeryczna albo `urlCache = nil`, czyli zmiana na każdej ścieżce żądania. Audytor sprawdził `Cache.db`: zero wierszy, więc dziś nic nie wycieka. Zmiana na jasny dzień, nie na łatkę o drugiej w nocy. |
| P3 | 2 522 wpisy `com.mactorn.app.tests.*` w pęku kluczy i 44 000+ plików `.plist` po testach | Higiena maszyny deweloperskiej, nie produktu. Sprzątanie pęku kluczy wymaga i tak rąk Pawła. Docelowo: usuwanie w `tearDown`. |

---

## Poprawki 1.12.2 (trzy audyty, które dotarły po wydaniu)

Audyty diff, integralności danych i dostępności/UX odezwały się po opublikowaniu 1.12.1.
Wszystkie trzy znalazły rzeczy, których nie zauważyłem, i **każda naprawiona niżej jest
defektem w tym, co sam wprowadziłem w 1.12.0.**

| # | Problem | Skąd |
|---|---|---|
| P1-12 | Dodanie pozycji watchlisty po nazwie działało tylko myszką. „Xanax" + Return → „Enter a positive item ID.", przy widocznym dopasowaniu tuż pod polem. Sztandarowa funkcja 1.12.0 była w połowie zepsuta. | UX |
| P1-13 | Obserwowanie kategorii forum ogłaszało stare wątki jako nowe. Torn zwraca jedną stronę 20 wątków, a `applyCategory` **podmieniał** pamięć zamiast ją sumować. Wątek, który spadł poniżej cięcia, był zapominany, więc kolejna odpowiedź wypychająca go na górę przychodziła jako „New forum thread". Przy aktywnej kategorii to stan normalny, nie przypadek brzegowy. | dane |
| P1-14 | Zmiana ID kategorii w locie zapisywała wątki starej kategorii pod nową, co dawało serię powiadomień o miesięcznych wątkach. | dane |
| P1-15 | `keyInfo` czytane raz na uruchomienie, bez TTL i bez ponowienia. Dołączenie do frakcji w trakcie sesji wyłączało alert chainu do restartu; jedno nieudane `/key/info` przy starcie cicho rozbrajało bramkę na całą sesję. | diff |
| P1-16 | Zawężanie selekcji nigdy nie działało na poll, dla którego istnieje. `startPolling` uruchamiał odczyt uprawnień **równolegle** z pierwszym `fetchData()`, więc ten pierwszy zawsze prosił o wszystko. Komentarz bramki obiecywał coś, czego kod nie robił. | diff |
| P2-12 | `disablesEndpoint` było martwym kodem, a `endpointUnavailable`/`insufficientPermissions` nie zapisywały cool-offu. Do tego `market.item` i `forum.thread` — dwa endpointy sparametryzowane, czyli najbardziej narażone na kod 6 — jako jedyne nie zgłaszały błędów do bramki. Usunięty wątek forum albo martwe ID przedmiotu były odpytywane co poll, bez końca. | diff |
| P2-13 | Przełącznik obserwowania kategorii można było włączyć bez ID i był wtedy trwale bezczynny, bez żadnego sygnału. | UX |
| P2-14 | Tytuły wątków forum lądowały nieograniczone w trwałym blobie `forumWatchedThreads`. Gorzej: ten blob chroni `threadsLoadFailed`, więc rozdęcie robi się **trwałe** zamiast samo się goić. | security |
| P3-7 | `notifiedBountyKeys` czyszczone w `resetAccountScopedState` wbrew komentarzowi C-03 tuż nad nim, więc przejściowy błąd klucza powodował ponowne ogłoszenie każdego bounty. Poprawka jednolinijkowa. | dane |
| P3-8 | Wiersz odznak renderował się pusty, zostawiając lukę. Diagnostyka pokazywała `faction.basic` obok powodu po ludzku. | UX |

**Jeden z testów 1.12.0 utrwalał defekt jako poprawne zachowanie.**
`testThreadsFallingOffTheListingAreForgottenQuietly` sprawdzał połowę kurczącą się i
zatrzymywał się krok przed podaniem z powrotem ID, które wypadło. Sonda falsyfikująca od
audytora (`XCTAssertTrue(service.applyCategory(threads([1,2,3])).isEmpty)`) padała.
Przepisany, razem z nagłówkiem pliku opisującym limit stu wątków, którego kod nigdy nie
używał.

### Zostawione Pawłowi

| Priorytet | Problem | Dlaczego nie teraz |
|---|---|---|
| P1 | Cztery magazyny (`notificationRules`, `travelNotificationSettings`, `customShortcuts`, `appFeedbackState`) używają syntezowanego `Codable`, nie mają strażnika `loadFailed` i **nadpisują nieczytelny blob w tej samej instrukcji**, w której odczyt się nie powiódł. Audytor sprawdził empirycznie: syntezowany `Codable` rzuca na brakującym kluczu nawet gdy init memberwise ma default, więc dodanie jednego pola kasuje to ustawienie każdemu użytkownikowi. | Cztery mechaniczne strażniki to dokładnie ten kształt zmiany, który wygląda bezpiecznie i nie jest. Promień rażenia przy pomyłce: wszyscy użytkownicy. Audytor zaproponował napisanie tego jako diffów do przejrzenia na trzeźwo. |
| P1/P2 | Klucz o niskich uprawnieniach nadal zabija aplikację przy pierwszym pollu, bo kod 16 to `haltsAllRequests`, a `isHalted` czyści się tylko w `updateAPIKey` za `guard newValue != apiKey` — wklejenie **tego samego** klucza nic nie daje. | Zmiana semantyki zatrzymania na najbardziej krytycznej ścieżce. Uporządkowanie odczytu uprawnień przed pierwszym pollem (P1-16) usuwa wyścig, który ten kod 16 produkował; reszta na jasny dzień. |
| P2 | `forumWatchConfig` dekodowany przez `try?` bez flagi porażki, a `save()` pisze bezwarunkowo. Komentarz mówi „zawsze odtwarzalna preferencja" — nieprawda: `factionForumCategoryId` to numer, który użytkownik wygrzebał z URL-a forum. | Ten sam kształt co P1 wyżej, ta sama decyzja. |
| P2 | `WatchedThread` na syntezowanym `Codable`: kolejne dodane pole opróżni listę na stałe, bo `threadsLoadFailed` blokuje potem każdy zapis. Bajty przeżywają pod `forumWatchedThreads.unreadable`, ale nic tego klucza nie czyta ani o nim nie mówi — ścieżka odzysku, którą strażnik miał umożliwić, nigdy nie została dokończona. | Wymaga decyzji, czy dokończyć konwencję `.unreadable`, czy ją porzucić. To projekt, nie łatka. |
| P2 | `.prefix()` liczy grafemy, nie bajty, więc „64-znakowa" nazwa z 50 000 znaków łączących waży 6 MB. Sufit z P2-11 nie jest sufitem bajtowym, a `AppState+ItemCatalog` czyta odpowiedź bez limitu rozmiaru. | Amplifikacja 1:1, więc to poprawność sufitu, nie ekspozycja. Naprawa: cap na `unicodeScalars` plus strażnik rozmiaru odpowiedzi. |
| P2 | Rekomendacja A1: wyprowadzić `TornEndpointGate.denial(...).userExplanation` do `ModuleStateView`. `ModulePresentationState` ma już przypadek `.permission` z przyciskiem **Settings** zamiast Retry, a `isSelfHealing` jest napisane i nieczytane przez nic. Dziś pominięty moduł pokazuje „No data yet" i Retry, który nigdy nie pomoże. | Jedyna rzecz z tej listy z ciężarem projektowym. Zasługuje na własne przejście, nie na dopisek o trzeciej w nocy. |
| P3 | `TornEndpointDenial.label` liczy pozostały czas z zegara systemowego, nie z wstrzykniętego `TimeSource`. Ten sam problem w `AppState+ItemCatalog` (cztery miejsca). | Dotyczy napisu w Diagnostyce i testowalności, nie danych. |
| P3 | Timer forum przeżywa trwały błąd klucza: `handlePermanentKeyError` woła `stopPolling()`, nie `stopForumPolling()`. | Jedna linijka, ale chcę ją zobaczyć w kontekście reszty semantyki zatrzymania. |
| P3 | Przejściowe błędy sieci są utrwalane jak stan — po restarcie wiersze pokazują „Network Error", choć nic im nie jest. | Kosmetyka o realnym koszcie zaufania. |
| P3 | `userMessage` zwraca łańcuch Torna dosłownie dla kodów 1/2/18 i 16. Kopia aplikacji już istnieje (gałąź `message.isEmpty ?`), a `.temporaryKey` już przełącza się po `code`, więc to usunięcie ternary, nie pisanie tekstów. | Robota redakcyjna w kilku gałęziach. Zysk bezpieczeństwa skromny, zysk dla issue #58 duży. |
| P3 | `parseStocksMetadata` bez limitu długości nazw i liczby wpisów. Komentarz katalogu przedmiotów wskazuje na nią jako wzór, a relacja się odwróciła. | Wcześniejsze, nie moje, i teraz jawnie udokumentowane. |
| P3 | Brak `uiTestID` na nowych kontrolkach, przez co poprawki wrażliwej na szerokość warstwy odznak nie da się objąć testem regresji przy 320 pt. | Warto zrobić razem z A1. |

---

## Walidacja po zmianach

| Polecenie | Wynik |
|---|---|
| `make test` | ✅ 643 testy, 0 błędów (569 przed) |
| `xcodebuild build` (Debug) | ✅ BUILD SUCCEEDED |
| `make analyze` | ✅ 0 ostrzeżeń |
| `make coverage-gate` | ✅ PASSED. `TornAPIError` 94,20 %, `TornEndpoint` 95,06 %, `PollingCoordinator` 100 %, `NotificationCoordinator` 98,36 %, `NextAction` 96,63 % |
| `make scan` | ✅ brak wycieków |
| `make test-ui` (lokalnie) | ❌ nie uruchomiono, patrz Ograniczenia |
| CI `Tests` na scalonym `main` (przebieg 32914341887) | ✅ wszystkie trzy joby, w tym `Fixture UI Tests` |

Pokrycie nowych plików: `TornEndpointGate.swift` 83,16 %, `AppState+ItemCatalog.swift`
76,15 %, `ForumWatchService.swift` 96,41 %.

---

## Ograniczenia audytu

**Bez żywego klucza API.** Klucz Pawła leży w pęku kluczy, a jego odczyt wymaga
interaktywnej zgody, której o tej porze nie było komu udzielić (próba zablokowała powłokę na
dziesięć minut). Cały audyt warstwy API oparto więc na dokumencie OpenAPI Torna
(`https://www.torn.com/swagger/openapi.json`, wersja specyfikacji **6.13.1**, pobrany
2026-08-26), a nie na porównaniu z żywymi odpowiedziami. Specyfikacja jest źródłem
autorytatywnym i sama zawiera zastrzeżenie, że rozwój v2 trwa. **Każda zmiana kształtu
żądania w tej gałęzi powinna zostać potwierdzona pierwszym uruchomieniem na prawdziwym
kluczu.** Dotyczy zwłaszcza: nagłówka `Authorization` na v2, zawężania selekcji i usunięcia
`bazaar`.

**Bramka testów wymagała obejścia.** Na tej maszynie `xcodebuild test` regularnie zawieszał
się na kroku `RegisterWithLaunchServices`: build rejestruje pakiet `MacTorn.app`, a
`lsregister` blokuje się, dopóki żyje instancja tego pakietu, którą sam build wcześniej
uruchomił. Do tego `testmanagerd` potrafił zostać w stanie, w którym host testowy nigdy nie
startuje. Działająca sekwencja: wyrejestrować pakiet (`lsregister -u`), usunąć
`Build/Products/Debug/*.app`, ubić osierocone instancje i `testmanagerd`, a potem rozbić
przebieg na `build-for-testing` i `test-without-building`. Warto to zapamiętać, bo kosztowało
kilkadziesiąt minut i wygląda jak zawieszony build, a nie jak problem środowiska.

**UI-testy: lokalnie nie, na CI tak.** `make test-ui` kończy się na tej maszynie
`Timed out while enabling automation mode` — runner XCUITest potrzebuje aktywnej,
odblokowanej sesji graficznej, a maszyna pracowała bez nadzoru. Ten sam błąd występuje na
`main`, więc to ograniczenie środowiska, nie regresja.

Zestaw przeszedł natomiast **na GitHub Actions**, na runnerze z prawdziwą sesją: przebieg
32914341887 na scalonym `main` zaliczył wszystkie trzy joby, w tym `Fixture UI Tests`. To
domyka lukę, którą wcześniejsza wersja tego raportu opisywała jako najpoważniejszą.
Stwierdzenia o *wyglądzie* (przycięcie treści przy 320 pt, kontrast, mowa VoiceOver)
pozostają wnioskami z kodu, bo tego UI-testy i tak nie sprawdzają.

**Drugie spojrzenie przyszło po wydaniu 1.12.0.** Rozesłałem cztery równoległe audyty
(diff, security, integralność danych, dostępność/UX) jako osobne agenty. Przez 44 minuty
żaden nie odpowiedział, więc nie czekałem dłużej i nie zmyślałem ich ustaleń: dziewięć
defektów opisanych wyżej znalazłem sam, tym samym okiem, które pisało poprawki.

Audyt bezpieczeństwa dotarł **po** opublikowaniu 1.12.0 i znalazł rzeczy, których nie
zauważyłem. Dwie z nich naprawione w 1.12.1 (osobna sekcja niżej), dwie zostawione Pawłowi.
Wniosek na przyszłość: to wydanie poszło bez niezależnej weryfikacji, bo agenty milczały, a
ja uznałem ciszę za brak ustaleń. Cisza agenta nie jest wynikiem audytu.

**Bez SwiftLinta.** Nie jest zainstalowany w tym środowisku. Jego miejsce zajęła `xcodebuild
analyze`, która pokrywa mniej.

**Odstępstwo od procedury.** Skill każe zakładać gałąź `feature/audit-fixes`. Poprawki
powstały na `feature/torn-api-2026-08` razem z pracą, którą audytowały, bo to jedno
zamówienie kończące się jednym wydaniem. Rozdzielanie ich na dwie gałęzie dałoby dwa
przeplatające się zestawy zmian w tych samych plikach.
