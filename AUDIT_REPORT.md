# MacTorn — raport audytu technicznego

Last verified: 2026-09-26 | baza `07b1f82` (v1.15.0) → gałąź `feature/audit-fixes`
Poprzednie przebiegi (2026-08-26, 2026-08-01, 2026-07-30) są niżej i w historii gita.

Zakres: cały projekt. Ograniczenie od Pawła: bez testów manualnych i bez uruchamiania
aplikacji, a XCUITest (`make test-ui`) jest wyłączony. Paweł zgodził się na `make test`,
mimo że test host uruchamia MacTorn.app (w pasku menu pojawia się wtedy ikona).

Ten dokument zawiera fakty z lokalizacją `plik:linia` i statusem potwierdzenia. Oceny i
rekomendacje są w `UX_RECOMMENDATIONS.md`, a wykaz zmian w `CHANGELOG_AGENT.md`. Ścieżki
podane bez prefiksu są względne wobec `MacTorn/MacTorn/`.

---

## Streszczenie stanu

- **Baseline na `07b1f82`:**
  - `make test`: 781 testów zaliczonych, 0 niezaliczonych.
  - `make analyze`: sukces, 0 ostrzeżeń w kodzie produkcyjnym.
  - CI na `main` (run `36067836868`) zielone.
- **Znalezione problemy:**
  - **P0:** żadnego.
  - **P1:** 9. Pięć to regresje z commitów `141a3cd` i `c71ee24` (reguła audytu każe traktować regresję jako co najmniej P1). Trzy dotyczą danych konta lub alertów. Jeden to funkcja obiecana w README, której nie było (timer alertów cenowych).
  - **P2 i P3:** pełna lista niżej.
- **Stan napraw:** wszystkie P1 naprawione na gałęzi. Naprawiono też 18 problemów P2/P3. Pozostałe są opisane jako otwarte, z powodem.
- **Po zmianach:** wyniki są w sekcji „Walidacja po zmianach”.

## Mapa projektu (bez zmian od 2026-08-26, uzupełnienia)

- **Aplikacja:** natywna macOS 14+, SwiftUI, `MenuBarExtra`, plus rozszerzenie widgetów (App Group w wariancie `.widgets`).
- **Sieć:** jedyna integracja sieciowa to `api.torn.com`, kluczem użytkownika z Keychaina.
- **Sentry:** opt-in, domyślnie wyłączony.
- **Zależności:** jedna, `sentry-cocoa` w wersji 9.23.0 (`Package.resolved`).
- **Nowe od ostatniego audytu:**
  - funkcje „companion” oparte na API v2 (`CompanionStore.swift`, `Networking/CompanionEndpoints.swift`);
  - bramka uprawnień dla kluczy Custom (`Networking/TornEndpointGate.swift`);
  - schemat URL `mactorn://` (`Info.plist`, `MacTornApp.swift` `onOpenURL`).
- **Test host:** unit testy hostują się w MacTorn.app (`TEST_HOST` w `project.pbxproj:1170`). `MacTornApp.init()` nie rozpoznaje XCTestu (`MacTornApp.swift:19-33`), więc przy `make test` rejestruje się `MenuBarExtra`, a Sentry startuje, jeśli jest włączony w UserDefaults.

## Stan bazowy — wykonane polecenia

| Polecenie | Wynik |
|---|---|
| `make test` (na `07b1f82`) | `** TEST SUCCEEDED **`, 781 passed, 0 failed |
| `make analyze` | `** ANALYZE SUCCEEDED **`, 0 ostrzeżeń w kodzie produkcyjnym |
| ostrzeżenia kompilatora w testach | 10: `MockNetworkSession.swift:24-25` (`NSLock` w kontekście async, błąd w Swift 6) oraz 8× nieużyty wynik (`CompanionStoreTests.swift:89`, `ForumCategoryWatchTests.swift:152`, `MarketWatchServiceTests.swift:140,143`, `NotificationCoordinatorTests.swift:369,431,454,515`) |
| `gitleaks git --log-opts=--all` (agent security) | 212 commitów, brak wycieków |
| `make test-ui`, `make test-all` | **nie uruchamiane** (zakaz Pawła) |
| lint / formatowanie | projekt nie ma SwiftLint ani swift-format; brak bramki do uruchomienia |

## Problemy — P1

| ID | Problem | Status | Lokalizacja | Przyczyna | Poprawka |
|---|---|---|---|---|---|
| R-01 | Po włączeniu „Stock bonuses” wartość akcji znika z „Total Tracked” (Money) albo zamarza. Stan zakładki Stocks też bazuje na zamrożonych danych | potwierdzony (test czerwony bez fixu) | `ViewModels/AppState+PollingUserFetch.swift:212-219,745` (przed fixem), `Views/MoneyView.swift:121-124`, `Views/StocksView.swift:13` | `141a3cd` wycinał selekcję `stocks` z `user.fast` i przestawał przypisywać `stocksData`, gdy companion stocks był włączony | naprawione `dc4fec4` |
| R-02 | Watchlista porównywała znacznik czasu serwera Torna z zegarem Maca. Przy przesuniętym zegarze odświeżanie i alerty stały przez czas równy przesunięciu, a etykieta pokazywała „in 2 hours ago”. `cache_delay` z API był zapisywany bez limitu | potwierdzony odczytem kodu | `ViewModels/AppState+MarketForum.swift:89-94`, `ViewModels/MarketWatchService.swift:161-162` | regresja z `141a3cd` | naprawione `f82f5c0` |
| R-04 | „Arriving in” w Statusie pokazuje „0:00” zamiast „Ready” | potwierdzony odczytem kodu | `Views/StatusView.swift:245` | `c71ee24` zamienił lokalny formatter na `TornFormatter.clock` | naprawione `e4f2db6` |
| R-05 | Karta łańcucha znika przy `current > 0` i `timeout <= 0` (wcześniej czerwone „Unavailable”) | zmiana kodu potwierdzona; to, czy Torn wysyła taki stan, jest hipotezą | `Views/Components/ChainView.swift` | `c71ee24` przeniósł warunek na `Chain.isActive` | naprawione `20caaab` |
| R-03 | Okno limitu requestów zapominało żądanie do 1 s za wcześnie; komentarz i test opisywały to odwrotnie | potwierdzony odczytem kodu | `Utilities/PollingCoordinator.swift` (`SlidingWindowCounter.prune`) | `c71ee24`, kubełki sekundowe z `<=` | naprawione `807c3cb`; test `testSecondResolutionBoundaryIsStable` kodował błąd i został skorygowany (opis w commicie) |
| F-01 | Zaplanowane alerty lądowania poprzedniego konta odpalają się po zmianie lub usunięciu klucza | potwierdzony (test czerwony) | `ViewModels/AppState.swift` `resetAccountScopedState()` | brak `cancelTravelNotifications()` przy resecie konta | naprawione `52b2f04` |
| F-02 | „Test Connection” z wpisanym, niezapisanym kluczem B nadpisuje `keyInfo` aktywnego konta A; bramka blokuje wtedy A na `faction.basic` do 1 h | potwierdzony (test czerwony) | `ViewModels/AppState+PollingUserFetch.swift` ~475 (`validateKey`) | bezwarunkowe przypisanie `keyInfo` | naprawione `886705a` |
| F-05 | Alerty cenowe Watchlisty działały tylko przy otwartej zakładce Watchlist, choć README obiecuje timer | potwierdzony (wszystkie 3 wywołania `refreshWatchlistPrices()` były w `Views/WatchlistView.swift`) | `ViewModels/AppState+MarketForum.swift:78` | timer nigdy nie istniał | dodany 5-minutowy timer w tle (decyzja Pawła), `33ae701` |
| F-04 | Alert cenowy ginie, gdy nowsze odświeżenie przerwie trwające | potwierdzony (test czerwony) | `ViewModels/AppState+MarketForum.swift:95` | współdzielona lista `pendingPriceAlerts` czyszczona przez następne odświeżenie po zapisaniu `lastAlertedPrice` | naprawione `20277ff` |

## Problemy — P2

| ID | Problem | Status | Lokalizacja | Stan |
|---|---|---|---|---|
| F-03 | Zmiana interwału odświeżania (główny i forum) nie działa do restartu | potwierdzony (test czerwony) | `ViewModels/AppState+PollingUserFetch.swift:16-19`, `ViewModels/AppState+MarketForum.swift` ~257 | naprawione `02799f3` |
| S-01 | Workflowy z `CLAUDE_CODE_OAUTH_TOKEN` używały ruchomych tagów (`@v1`, `@v2`, `@v4`) | potwierdzony (konfiguracja) | `.github/workflows/claude.yml`, `claude-code-review.yml`, `gitleaks.yml` | naprawione `7c78ea6` (SHA). Marketplace pluginu w `claude-code-review.yml:43` nadal wskazuje domyślną gałąź obcego repo — **otwarte** |
| P-01 | Timeline'y widgetów przeładowywane ok. 2× na poll (`publishWidgets()` z `parseDataInBackground` i z `applyUserV2Payload`) | wysoce prawdopodobny (odczyt kodu, niezmierzony) | `ViewModels/AppState+Widgets.swift:29-46`, `ViewModels/AppState+PollingUserFetch.swift:752,888` | **otwarte** |
| P-02 | Cały `StatusView.body` przelicza się co sekundę podczas lotu, gdy otwarta jest zakładka Status | potwierdzony odczytem kodu, wpływ niezmierzony | `Views/StatusView.swift:245` | **otwarte** |
| P-03 | Przy włączonych Shops i odmowie `torn.items` blob katalogu jest dekodowany dwa razy na poll na głównym wątku | potwierdzony odczytem kodu | `ViewModels/AppState+ItemCatalog.swift:111-145`, `ViewModels/CompanionStore.swift:168-195` | **otwarte** |
| F-06a | Lot powrotny zaraz po lądowaniu nie daje „Landed” ani „Landing Soon” (liczy się tylko zmiana `isTraveling`) | potwierdzony odczytem kodu | `ViewModels/AppState+NotificationsFeedback.swift:48-61` | **otwarte** |
| F-07a | Alert „Chain expiring” jest sprawdzany tylko przy fetchu frakcji; przy interwale 120 s okno <60 s bywa przeskakiwane | wysoce prawdopodobny (argument próbkowania) | `ViewModels/AppState+FactionFetch.swift:45` | **otwarte** |
| A-01 | Klucz API nie dało się zatwierdzić Returnem; pole nie dostawało fokusu przy pierwszym uruchomieniu | potwierdzony odczytem kodu | `Views/SettingsView.swift:245-291` | naprawione `9d483b7` |
| A-08 | Prompty Feedback/Sentry nie są modalne dla VoiceOvera i klawiatury | potwierdzony odczytem kodu | `Views/ContentView.swift:156-170` | naprawione `9d483b7` |
| A-03 | Stany ikony w pasku menu (błąd, za granicą, pełna energia) nie są wypowiadane | potwierdzony odczytem kodu | `MacTornApp.swift:189` | naprawione `9d483b7` |
| A-05 | Pusta lista w Watchlist/Forum pokazywała naraz „No data yet · Retry” i „No items watched” | potwierdzony odczytem kodu | `Views/WatchlistView.swift:16`, `Views/ForumWatchView.swift:16` | naprawione `9d483b7` |
| A-09 | Nic nie jest ogłaszane VoiceOverowi (0 wywołań `AccessibilityNotification`) | potwierdzony (grep) | wynik walidacji klucza, błędy dodawania, Undo | **otwarte** |
| A-10 | Undo znika po 6 s, przy zmianie zakładki i przy zamknięciu popovera | potwierdzony odczytem kodu | `Views/WatchlistView.swift:179`, `Views/ForumWatchView.swift:149` | **otwarte** |
| A-11 | Brak możliwości usunięcia klucza API z aplikacji (przycisk zablokowany dla pustego pola) | potwierdzony odczytem kodu | `Views/SettingsView.swift:269` | **otwarte** |
| A-12 | Prośba o zgodę na powiadomienia pojawia się przy pierwszym otwarciu, przed wpisaniem klucza; odmowa jest widoczna tylko w Diagnostyce | potwierdzony odczytem kodu | `Views/ContentView.swift:187` | **otwarte** |
| A-13 | Kolorowy tekst (zielony, żółty, pomarańczowy) w trybie jasnym ma kontrast ok. 1,6–2:1 | wysoce prawdopodobny (wartości przybliżone, niezmierzone) | `Views/MoneyView.swift:38,134`, `Views/WatchlistView.swift:439,549`, `Views/StatusView.swift:578`, `Views/SettingsView.swift:347,439,621,634` | **otwarte** |
| A-14 | Przełączniki companion stoją nad główną treścią pięciu zakładek | potwierdzony odczytem kodu | `Views/StatusView.swift:28`, `MoneyView.swift:19`, `WatchlistView.swift:20`, `TravelView.swift:115`, `FactionView.swift:110` | **otwarte** (decyzja produktowa) |
| A-15 | Forum Watch nie pokazuje w aplikacji, że są nowe posty | potwierdzony odczytem kodu | `Views/ForumWatchView.swift:222-313` | **otwarte** |

## Problemy — P3

| ID | Problem | Status | Lokalizacja | Stan |
|---|---|---|---|---|
| F-06 | Timer forum działał dalej po trwałym błędzie klucza (zgłoszone już 2026-08-26) | potwierdzony (test czerwony) | `handlePermanentKeyError`, `fetchForumUpdates` | naprawione `88080a0` |
| P-08 | Timery bez tolerancji (1 s, poll, forum) | potwierdzony | `AppState+LiveNextAction.swift:33`, `AppState+PollingUserFetch.swift:89`, `AppState+MarketForum.swift:268` | naprawione `6a2ff1f` |
| S-02 | `/new-version` pozwalał bez pytania na force-push, kasowanie tagów i `gh release delete` | potwierdzony (konfiguracja) | `.claude/commands/new-version.md:2` | naprawione `3db1143` |
| S-03 | `SECURITY.md` i `SECURITY_AUDIT.md` twierdziły, że nie ma schematów URL | potwierdzony | `SECURITY.md:68`, `SECURITY_AUDIT.md:57` | naprawione `0a345bc` |
| S-04 | `claude-code-review.yml` bez bramki autora (dziś nie do wykorzystania: forki nie dostają sekretów) | potwierdzony (konfiguracja) | `.github/workflows/claude-code-review.yml` | naprawione `7c78ea6` |
| A-02 | Przycisk „Enable” w prompcie Sentry jest bledszy przy Reduce Transparency | potwierdzony | `Views/Components/SentryOptInPromptView.swift:54` | naprawione `9d483b7` |
| A-04 | Trzy linki w Ustawieniach omijały ustawienie Preferred Browser | potwierdzony | `Views/SettingsView.swift:296,467,680` | naprawione `9d483b7` |
| A-06 | Brak danych o podróży pokazywał „In Torn City · Ready to travel” | potwierdzony | `Views/TravelView.swift:142-146` | naprawione `9d483b7` |
| A-07 | Ikony-przyciski ok. 16 pt i pola bez etykiet | potwierdzony | `Views/WatchlistView.swift:35`, `Views/ForumWatchView.swift:32,232`, `Views/SettingsView.swift:307,336` | naprawione `9d483b7` |
| R-06 | Liczby w trzech miejscach zmieniły się z lokalizacji systemu na en_US („$1,000,000”) | potwierdzony | odznaka bounty w `StatusView`, `RankedWarView` we `FactionView`, powiadomienie bounty w `AppState+PollingUserFetch.swift` | **otwarte** (możliwe, że zamierzone) |
| R-07 | Bramka kluczy Custom blokuje `market.item`, `torn.items`, `forum.*`, `faction.news`, jeśli `/key/info` nie poda nazw selekcji w oczekiwanej formie | hipoteza (sam plan `Plans/torn-api-audit-2026-09-18.md` każe to sprawdzić) | `Networking/TornEndpointGate.swift` | **otwarte**, wymaga testu na żywym kluczu Custom |
| P-04 | Przerwany poll zapisuje w stanie endpointów wynik `transport` i zużywa budżet `faction.news` | potwierdzony odczytem kodu | `ViewModels/AppState+FactionFetch.swift:95-143` | **otwarte** |
| P-05 | Wybudzenie, powrót sieci i otwarcie popovera mogą wysłać nakładające się żądania | wysoce prawdopodobny | `startPolling`, `refreshNow`, `NetworkMonitor` | **otwarte** |
| P-07 | Dwa zapisy do UserDefaults na poll (sprawdzenie łańcucha poza `batched`) | potwierdzony | `ViewModels/AppState+NotificationsFeedback.swift:148` | **otwarte**; próba naprawy pominięta, bo zmieniała moment alertu |
| P-09 | Dekodowanie poza głównym wątkiem zależy od trybu Swift 5 | latentny | `TornAPIClient.loadJSON` | **otwarte** |
| F-09 | Każdy aktywny bounty jest ogłaszany ponownie po każdym uruchomieniu (`notifiedBountyKeys` tylko w pamięci) | potwierdzony odczytem kodu | `ViewModels/AppState.swift:271`, `AppState+PollingUserFetch.swift:931-949` | **otwarte** |
| F-10 | Brak tytułu wątku może nadpisać znany tytuł wartością „Unknown” | potwierdzony odczytem kodu | `ViewModels/ForumWatchService.swift:169,294` | **otwarte** |
| I-01 | `kSecAttrAccessible` jest najpewniej ignorowany (legacy login keychain, brak `kSecUseDataProtectionKeychain`); dokumentacja przypisuje mu ochronę | wysoce prawdopodobny | `ViewModels/AccountSessionStore.swift:149-170`, `SECURITY_AUDIT.md:107,111` | **otwarte** (dryf dokumentacji) |
| I-02 | URLs v1 mają `key=` w query; to, czy klucz trafia do `Cache.db`, zależy od nagłówków Torna | bez zmian od poprzedniego audytu (zaakceptowane P3) | `Networking/TornEndpoint.swift:154` | **otwarte**, zaakceptowane |
| D-01 | `sentry-cocoa` 9.23.0; Dependabot proponuje 9.28.0; brak opublikowanych advisories | potwierdzony | `Package.resolved` | **otwarte** |
| T-01 | Test host uruchamia pełną aplikację (MenuBarExtra, Keychain, Sentry, jeśli włączony) | potwierdzony odczytem kodu | `MacTornApp.swift:19-33` | **otwarte** |
| A-16 | Nieprzetłumaczony żargon (Xanax, Refill, SED, FHC, CPR, OC 2.0); sekcja Armory widoczna bez frakcji | potwierdzony | `Views/FactionView.swift:123-131`, `Views/WatchlistView.swift:269` | **otwarte** |
| A-17 | Brak powiększania tekstu: 123 teksty `caption2` i 18 punktów `lineLimit(1)` w stałym oknie 320×640 | potwierdzony (grep) | `Views/ContentView.swift:172`, `MacTornApp.swift:59` | **otwarte** |
| — | Wcześniej zgłoszone i nadal otwarte: moduł nie mówi, dlaczego jest pusty (A1); ponowne zapisanie tego samego klucza po zatrzymaniu nic nie robi; surowy komunikat Torna przy trwałym błędzie klucza; odznaki bez rzeczownika; `[NotificationRule]` dekodowane wszystko albo nic | potwierdzone odczytem kodu | `Utilities/Diagnostics.swift:79-150`, `ViewModels/AccountSessionStore.swift:64`, `Networking/TornAPIError.swift:185`, `Views/StatusView.swift:196` | **otwarte** |

## Obszary sprawdzone bez znalezisk

- **Klucz API:** tylko w Keychainie. Nie trafia do App Group, widgetu, Diagnostyki, schowka, Sentry ani logów. Wszystkie logi zawierają tylko kody błędów, a `tornRedactedURL` usuwa wartości query.
- **Sentry:** opt-in. `beforeSend` i `beforeBreadcrumb` redagują URL-e. Tracing i breadcrumbs sieciowe są wyłączone.
- **Otwieranie URL-i:** tylko http i https z hostem, przez `BrowserManager.swift:97-126`. Link aktualizacji jest ograniczony do github.com.
- **HTML:** brak `NSAttributedString(html:)` i brak WebView.
- **Uprawnienia:** sandbox z samym `network.client`, Hardened Runtime włączony.
- **Artefakty w repo:** żaden `.zip`, `build/`, `dist/` ani `.xcresult` nie jest śledzony przez gita. Historyczne zipy z przeszłych commitów zawierają tylko ścieżkę budowania.
- **Poprzednie poprawki C-01, C-02, D-01, D-02, S-02, S-05 i P1-16…18** nadal obowiązują.
- **Bufory w pamięci:** wszystkie kolekcje są ograniczone. Brak cykli referencji.

## Walidacja po zmianach

| Polecenie (na HEAD gałęzi, `6a2ff1f`) | Wynik | Rodzaj weryfikacji |
|---|---|---|
| `make coverage-gate` (cały `MacTornTests` z pokryciem) | `** TEST SUCCEEDED **`, 808 passed, 0 failed; `coverage-gate: PASSED` (NetworkSession 100%, TornAPIError 90,91%, TornEndpoint 96,34%, PollingCoordinator 88,89%, NotificationCoordinator 98,62%, NextAction 98,98%) | automatyczna |
| `make analyze` | `** ANALYZE SUCCEEDED **`, 0 ostrzeżeń | automatyczna |
| Testy czerwone przed fixem | potwierdzone dla R-01 (2 testy padły z cofniętym fixem), F-01, F-02, F-03, F-04, F-05 (6 z 8), F-06, R-03, R-05 | automatyczna |
| Testy czerwone przed fixem **nie pokazane** | R-02 i R-04: test R-02 dotyczy nowej funkcji `localized(using:)`; R-04 nie ma testu (zmiana w widoku) | — |
| Ostrzeżenia kompilatora | build był przyrostowy i nie wyemitował ponownie ostrzeżeń testów, więc brak porównania | — |
| Zmiany UI (dostępność, karta łańcucha, podróż) | tylko kompilacja i odczyt kodu | **manualnie do sprawdzenia** |
| `make test-ui` | nie uruchamiane | nieweryfikowalne w tym środowisku (zakaz) |
| Workflowy CI po przypięciu SHA | poprawność zweryfikowana dopiero przy następnym runie na GitHubie | nieweryfikowalne lokalnie |

## Ograniczenia audytu

- **Aplikacji nikt nie uruchomił:** Paweł na to nie pozwolił. Wszystkie zmiany UI (dostępność, karta łańcucha, pusty stan podróży) są zweryfikowane kompilacją i odczytem kodu, a nie wzrokiem ani VoiceOverem.
- **XCUITest nie był uruchamiany.** Nowy identyfikator `uitest.chain.unavailable` nie ma testu UI.
- **Wydajność:** wszystkie wnioski pochodzą z odczytu kodu. Nic nie zostało zmierzone w Instruments.
- **Niesprawdzone:** ustawienia projektu Sentry po stronie serwera, żywy `Cache.db`, ACL Keychaina w runtime, ustawienia Actions na GitHubie oraz prawdziwa odpowiedź `/key/info` dla klucza Custom.
- **Jednorazowe przejście przy fixie R-02:** pozycje Watchlisty zapisane przed tym fixem mają znacznik w czasie serwera. Przy zegarze Maca spóźnionym o X sekund pierwsza nowa cena może zostać pominięta przez deduplikację najwyżej przez X sekund, po czym dane się wyrównują.

---

# Poprzedni przebieg (2026-08-26)


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
| ~~P1~~ **NAPRAWIONE** | Dominujący wyzwalacz zamknięty: `WatchedThread`, `NotificationRule`, `TravelNotificationSetting` i `KeyboardShortcut` mają ręczne `init(from:)` z `decodeIfPresent`, w rozszerzeniach (żeby przeżył syntezowany init memberwise, od którego zależą ich własne tablice `defaults`). Weryfikacja: 690 testów, 0 błędów; pięć nowych testów pada bez zmiany produkcyjnej; mechanizm sprawdzony osobno — syntezowany `Codable` rzuca na brakującym kluczu nawet z defaultem w init memberwise, forma z rozszerzeniem dekoduje i zachowuje memberwise. **Zostaje:** genuinelna korupcja (nie ewolucja schematu) i to, że jeden zepsuty element nadal wywala całą tablicę — patrz wiersz niżej. Poniższy opis zachowany, bo tłumaczy, czego dotyczyła diagnoza. | — |
| P2 | **Jeden zepsuty element nadal kosztuje całą tablicę.** Dekodowanie `[NotificationRule]` jest wszystko-albo-nic: wiersz, którego `id` jest liczbą zamiast tekstu, wywala cały dekode, a ścieżka ładowania instaluje wtedy domyślne i zapisuje je. `decodeIfPresent` tu nie sięga — `id` jest naprawdę wymagane i **powinno takie zostać** (reguła bez tożsamości nie da się z niczym powiązać i nie wolno jej wymyślać). | Poprawka to opakowanie „stratnej tablicy": dekodować przez `UnkeyedDecodingContainer` i pomijać elementy, które rzucą. Ok. 15 linijek, ale to **nowy generyczny prymityw**, nie konwersja per typ — świadomie poza łatką, którą się recenzuje. |
| ~~P1~~ (opis historyczny) | Cztery magazyny (`notificationRules`, `travelNotificationSettings`, `customShortcuts`, `appFeedbackState`) używają syntezowanego `Codable` i **nadpisują nieczytelny blob w gałęzi `else` tego samego wywołania**, w którym odczyt się nie powiódł. Dodanie jednego **nie-opcjonalnego** pola kasuje to ustawienie każdemu istniejącemu użytkownikowi (sprawdzone `swiftc`; pole opcjonalne jest bezpieczne, bo synteza emituje dla niego `decodeIfPresent`). **Nie kopiuj tu strażnika `loadFailed`** — patrz kolumna obok. | Dwa audyty niezależnie doszły do przeciwnych recept, i drugie ma rację. Oś to nie „strażnik czy brak", tylko **czy użytkownik umie odtworzyć dane**. Watchlista i wątki są nieodtwarzalne, więc zamrożenie jest tam słuszne. Te cztery wracają do sensownych domyślnych, które użytkownik ustawia z powrotem w minutę — a strażnik dałby tu gorszy tryb: aplikacja działa na domyślnych w pamięci i **po cichu odmawia zapisu**, więc każda kolejna edycja wygląda na udaną i znika po restarcie. Do tego strażnik nie przenosi się mechanicznie: w `MarketWatchService` bezpieczne jest go dopiero `allowPersistenceAfterUserEdit()` przy add/remove/restore, a te cztery nie mają takiego punktu — `updateRule`, `updateShortcut`, `updateTravelNotificationSetting` mutują i zapisują wprost. **Właściwa poprawka: dać tym czterem typom ręczny `init(from:)` w stylu `ForumWatchConfig`** (`TornModels.swift`), czyli pole po polu z `decodeIfPresent`. Usuwa dominującą przyczynę (ewolucję schematu) zamiast łagodzić skutki, nie potrzebuje żadnej furtki i degraduje się lepiej: jedna zepsuta reguła w tablicy nie zabiera całej tablicy. |
| P1 | **`NotificationRule.BarType` ma jako `rawValue` teksty wyświetlane** (`case energy = "Energy"`, `TornModels.swift`), a ten sam `rawValue` jest treścią powiadomienia (`AppState+NotificationsFeedback.swift`). Niewinna zmiana copy („Energy" → „Energy bar") unieważnia **wszystkie zapisane reguły wszystkich użytkowników**. | Wszyscy myślą o dodaniu pola; tego nikt nie oznaczy na review, bo to zmiana tekstu. Odsprzęgnąć `rawValue` od napisu przy okazji ręcznego `init(from:)` wyżej. |
| P1/P2 | Klucz o niskich uprawnieniach nadal zabija aplikację przy pierwszym pollu, bo kod 16 to `haltsAllRequests`, a `isHalted` czyści się tylko w `updateAPIKey` za `guard newValue != apiKey` — wklejenie **tego samego** klucza nic nie daje. | Zmiana semantyki zatrzymania na najbardziej krytycznej ścieżce. Uporządkowanie odczytu uprawnień przed pierwszym pollem (P1-16) usuwa wyścig, który ten kod 16 produkował; reszta na jasny dzień. |
| P2 | `forumWatchConfig` dekodowany przez `try?` bez flagi porażki, a `save()` pisze bezwarunkowo. Komentarz mówi „zawsze odtwarzalna preferencja" — nieprawda: `factionForumCategoryId` to numer, który użytkownik wygrzebał z URL-a forum. | Ten sam kształt co P1 wyżej, ta sama decyzja. |
| P2 | `WatchedThread` na syntezowanym `Codable`: kolejne dodane pole opróżni listę na stałe, bo `threadsLoadFailed` blokuje potem każdy zapis. Ta sama poprawka co wyżej: ręczny `init(from:)`. | Tu strażnik **jest** słuszny (dane nieodtwarzalne), więc chodzi tylko o to, żeby przestał się uruchamiać bez powodu. |
| P3 | **`.unreadable` zachowuje dowody, ale nie umożliwia odzysku.** Poza dwoma zapisami klucze `watchlist.unreadable` i `forumWatchedThreads.unreadable` występują wyłącznie w dwóch testach sprawdzających, że zapis nastąpił. Nie ma czytelnika, migracji, UI ani wzmianki w README. Komentarz „Keep it: a later app version may still be able to read it" opisuje zamiar, którego nikt nie zrealizował — a cykl życia gwarantuje, że nikt nie zauważy: po pierwszej świadomej edycji flaga gaśnie, główny klucz jest nadpisany, a `.unreadable` zostaje sierotą w pliście. | Odzysk możliwy tylko ręcznie (`defaults read com.mactorn.app watchlist.unreadable`), a użytkownik musi wiedzieć, że ten klucz istnieje. Trzy opcje rosnąco: poprawić komentarz na „zachowane do ręcznego odzysku, brak automatycznego czytelnika"; pokazać **obecność** klucza w raporcie diagnostycznym (bool, bez treści — mieści się w regule „bezpieczne z konstrukcji"); albo dopisać czytelnika, którego komentarz obiecuje. |
| P2 | `.prefix()` liczy grafemy, nie bajty, więc „64-znakowa" nazwa z 50 000 znaków łączących waży 6 MB. Sufit z P2-11 nie jest sufitem bajtowym, a `AppState+ItemCatalog` czyta odpowiedź bez limitu rozmiaru. | Amplifikacja 1:1, więc to poprawność sufitu, nie ekspozycja. Naprawa: cap na `unicodeScalars` plus strażnik rozmiaru odpowiedzi. |
| P2 | Rekomendacja A1: wyprowadzić `TornEndpointGate.denial(...).userExplanation` do `ModuleStateView`. `ModulePresentationState` ma już przypadek `.permission` z przyciskiem **Settings** zamiast Retry, a `isSelfHealing` jest napisane i nieczytane przez nic. Dziś pominięty moduł pokazuje „No data yet" i Retry, który nigdy nie pomoże. | Jedyna rzecz z tej listy z ciężarem projektowym. Zasługuje na własne przejście, nie na dopisek o trzeciej w nocy. |
| P3 | `TornEndpointDenial.label` liczy pozostały czas z zegara systemowego, nie z wstrzykniętego `TimeSource`. Ten sam problem w `AppState+ItemCatalog` (cztery miejsca). | Dotyczy napisu w Diagnostyce i testowalności, nie danych. |
| P3 | Timer forum przeżywa trwały błąd klucza: `handlePermanentKeyError` woła `stopPolling()`, nie `stopForumPolling()`. | Jedna linijka, ale chcę ją zobaczyć w kontekście reszty semantyki zatrzymania. |
| P3 | Przejściowe błędy sieci są utrwalane jak stan — po restarcie wiersze pokazują „Network Error", choć nic im nie jest. | Kosmetyka o realnym koszcie zaufania. |
| P3 | `userMessage` zwraca łańcuch Torna dosłownie dla kodów 1/2/18 i 16. Kopia aplikacji już istnieje (gałąź `message.isEmpty ?`), a `.temporaryKey` już przełącza się po `code`, więc to usunięcie ternary, nie pisanie tekstów. | Robota redakcyjna w kilku gałęziach. Zysk bezpieczeństwa skromny, zysk dla issue #58 duży. |
| P3 | `parseStocksMetadata` bez limitu długości nazw i liczby wpisów. Komentarz katalogu przedmiotów wskazuje na nią jako wzór, a relacja się odwróciła. | Wcześniejsze, nie moje, i teraz jawnie udokumentowane. |
| P3 | Brak `uiTestID` na nowych kontrolkach, przez co poprawki wrażliwej na szerokość warstwy odznak nie da się objąć testem regresji przy 320 pt. | Warto zrobić razem z A1. |

---

## Poprawki 1.12.3 (audyt poprawek z 1.12.2)

Ponowny audyt gałęzi 1.12.2 pokazał, że **naprawa P1-16 działała tylko warunkowo**, a
komunikat wydania mówił inaczej.

### P1-17 · Timer wyprzedzał odczyt uprawnień

**Status:** potwierdzony przez odczyt kodu przed poprawką.
**Przyczyna źródłowa:** w 1.12.2 przeniosłem `installPollingTimer()` **przed** zadanie
czekające na `/key/info`, a sink timera woła `fetchData()` bezwarunkowo. Jeśli `/key/info`
trwa dłużej niż jeden `refreshInterval`, tik timera wysyła dokładnie to niezawężone żądanie,
któremu cała poprawka miała zapobiec. Przy ustawieniu agresywnym (15 s) to zwykły zimny
handshake DNS+TLS, nie rzadki przypadek.

**Pierwsza próba naprawy była gorsza od problemu.** Wstrzymałem instalację timera do
zakończenia pierwszego pobrania — co zamknęło tę dziurę i otworzyło dwie inne, bo
`refreshNow()` instaluje timer, ilekroć żadnego nie zastanie: ręczne odświeżenie w trakcie
czekania tworzyło **drugi** timer i osierocało pierwszy, a anulowane pierwsze pobranie
zostawiało aplikację bez timera w ogóle. Wykrył to istniejący test
`testRefreshNowDoesNotReplaceTheAutomaticPollingTimer`, czyli akurat ten, który miał to
łapać.

**Poprawka docelowa:** timer instalowany natychmiast, jak zawsze, a kolejność wymuszona
flagą `awaitingFirstKeyInfo`, którą sprawdzają sink timera i `refreshNow`. Flaga jest
czyszczona **przed** sprawdzeniem anulowania, żeby anulowane pierwsze pobranie i tak
odblokowało polling.

### P2-15 · Drugi wywołujący nie czekał na trwający odczyt

`loadKeyInfoIfNeeded` miało `guard keyInfoTask == nil else { return }`, czyli strażnik przed
podwójnym startem **jednocześnie znosił** kolejność await-przed-fetch dla każdego
wywołującego poza pierwszym: drugie `startPolling` czekało na nic i pobierało z `keyInfo`
nadal `nil`. Teraz dołącza do trwającego zadania (`await existing.value`).

### P3-9 · Zewnętrzne zadanie nietrzymane i bez ponownej weryfikacji

Zadanie pierwszego pobrania nie było nigdzie przechowywane, nie łapało tożsamości konta i po
`await` wołało `fetchData()` bezwarunkowo — a `fetchData` nie ma strażnika `keyHalted`.
Teraz jest w `firstFetchTask`, sprawdza `isCurrent` i `!keyHalted` po przebudzeniu, i jest
anulowane w `resetAccountScopedState`.

### Zamknięte, nie naprawione

**Zawężanie selekcji nie może dziś wyzerować żadnego endpointu.** To była otwarta obawa z
1.12.2; audyt rozstrzygnął ją z dokumentu OpenAPI: `KeyInfoResponse.info.selections.user` ma
typ `array of UserSelectionName`, a `UserSelectionName` to jedna płaska przestrzeń nazw
obejmująca obie wersje API i zawierająca wszystkie pięć nazw, o które prosi `user.v2`
(`notifications`, `organizedcrime`, `refills`, `education`, `bounties`). Rozstrzygające, nie
wywnioskowane: enum niesie własny opis wymieniający członków spadających do v1 (`bazaar`,
`criminalrecord`, `display`, `networth`) i żadnej z naszych pięciu tam nie ma. Sprawdzone
też pozostałe przestrzenie — `FactionSelectionName` ma `basic` i `chain`,
`MarketSelectionName` ma `itemmarket`, `TornSelectionName` ma `stocks` i `items`.

**Zastrzeżenie na przyszłość:** `UserSelectionName` to `oneOf: [<enum>, {"type": "string"}]`,
więc Torn nie gwarantuje wyczerpalności enuma. „Nie ma na liście udzielonych" jest przez to
odrobinę mocniejszym wnioskiem, niż specyfikacja licencjonuje. Nie wdrożyłem proponowanego
zaworu (przy zerowym przecięciu wysyłać pełną listę), bo to znaczyłoby świadome wysłanie
żądania, o którym sądzimy, że padnie, a bramka i tak odmawia wcześniej przez
`keyLacksSelections`. Właściwy zawór to raczej traktowanie **nieznanej** nazwy jako
przepustki, nie pustego wyniku — do przemyślenia na trzeźwo.

---

## Rozwiązane w 1.13.0 — kolejność pierwszego żądania

### P1-18 · Gwarancja kolejności obejmuje wszystkie wejścia

**Status: naprawiony i objęty testami regresji.** Wspólny automat pierwszego pobrania
rozstrzyga `/key/info` przed `/user` także dla Save & Connect, `refreshNow()` i powrotu
łączności. Zachowany został synchroniczny kontrakt debounce i księgowania budżetu.
`FirstPollOrderingTests` sprawdzają kolejność sieciową i wszystkie wejścia, a test UI
sprawdza właściwe przejście do Settings po trwałym błędzie klucza.

Poniższy opis zachowujemy jako historię diagnozy przed poprawką. Wtedy
`Views/SettingsView.swift:259` było **jedynym** miejscem, w którym aplikacja
ustawiała `apiKey`, i zaraz po nim wołało `refreshNow()`, nie `startPolling()`. Cała
kolejność wprowadzona w 1.12.3 żyje w `startFirstFetch()`, wołanym wyłącznie z
`startPolling()`. Ta sama luka dotyczy `onConnectivityRestored` (`AppState.swift:426`).

**Dlaczego strażnik nie może zadziałać:** setter `apiKey` woła `resetAccountScopedState()`,
które czyści `awaitingFirstKeyInfo` — i **słusznie**, bo zawieszona flaga zablokowałaby
timer na zawsze. Skutek: flaga jest strukturalnie niezdolna zapalić się na jedynej
tranzycji, która zeruje `keyInfo`. Strażnik, który nie może zareagować na zdarzenie, przed
którym strzeże, nie jest strażnikiem.

**Skutek:** pierwszy poll po wpisaniu klucza idzie niezawężony. To dokładnie scenariusz
„pierwszy klucz w życiu użytkownika", czyli ten, dla którego cała rzecz powstała.

**To nie jest regresja.** Na tych ścieżkach aplikacja robi to, co robiła zawsze przed 1.12.0
— nikt nie stracił niczego, co miał. Zawężanie po prostu nie stosuje się tam, gdzie jest
najbardziej potrzebne.

**Próbowałem i wycofałem. To jest najważniejsza część tego wpisu.** Odroczenie w
`refreshNow` zmienia jego kontrakt z „synchronicznie spróbuj pobrać" na „czasem odłóż", co
unieważnia debounce ręcznego odświeżania, obsługę powrotu z offline i księgowanie budżetu —
wszystkie czytają wartość zwracaną przez `fetchData()`. **Siedem istniejących testów to
złapało** (`testRefreshNow_debouncesBurstAndAcceptsBoundaryAtThreeSeconds`,
`testOfflineTransportFailureReopensDebounceForReconnect` i pięć innych). Kod wycofany,
komentarz z diagnozą zostaje w miejscu.

Druga rozważana droga — przeniesienie kolejności do `fetchData()` — potrzebuje **trzeciego**
elementu stanu, żeby przerwać rekurencję, gdy `/key/info` padnie, i to na funkcji, przez
którą przechodzi każdy poll. Tryb awarii przy pomyłce: nieskończona rekurencja w ścieżce
pobierania. Nie o trzeciej w nocy.

**Kształt poprawki (do rozstrzygnięcia na trzeźwo) — i lepsze postawienie pytania.**

Audytor diff nazwał wzorzec, który przebiega przez wszystkie dzisiejsze defekty w tym
podsystemie: **za każdym razem było to drugie wejście do niezmiennika, który ustanawiało
tylko pierwsze wejście.**

| Defekt | Drugie wejście |
|---|---|
| P1-16 (1.12.2) | `fetchData` ścigające się z ładowaniem uprawnień |
| P1-17 (1.12.3) | timer wyprzedzający `await` |
| P1-18 (1.13.0) | `refreshNow` omijające wspólną kolejność pierwszego pobrania |

To reformułuje zadanie. Pytanie brzmi nie „jak sprawić, żeby `refreshNow` też czekało" — to
byłaby **czwarta łatka na tę samą klasę**, i moja próba dokładnie nią była. Pytanie brzmi:
**przez jaki jeden punkt musi przejść każde pierwsze żądanie?**

Uczciwa odpowiedź to prawdopodobnie `fetchData()` — jedyne miejsce, przez które przechodzą
wszystkie cztery ścieżki.

### Dlaczego cztery łatki przeciekły: brakujący stan, nie brakujący strażnik

Ta diagnoza jest ostrzejsza niż moja („potrzeba trzeciego elementu stanu") i nazywa, **który**
stan i **dlaczego** to generuje cały wzorzec.

Podsystem modeluje dziś pytanie o uprawnienia dwoma bitami: `keyInfo == nil` oraz
`awaitingFirstKeyInfo`. Razem wyrażają „nie pytano" i „pytam". **Nie potrafią wyrazić
„zapytano i odpowiedź brzmi: nie wiadomo".** Sprawdzone: `keyInfoLoadedAt` jest zapisywane w
dokładnie jednym miejscu — gałęzi sukcesu `loadKeyInfoIfNeeded` (`AppState+PollingUserFetch.swift:317`)
— i czyszczone przy zmianie konta (`AppState.swift:473`). Obie ścieżki porażki (malformed
`:312`, `catch` `:320`) tylko odnotowują zdrowie endpointu i wracają. Nic nigdzie nie
zapisuje, że próba była i się nie udała.

To jest ta rekurencja. Choke point w `fetchData` musi odmawiać, dopóki odpowiedź jest w toku,
i przepuszczać, gdy jest **rozstrzygnięta** — a nieudane ładowanie rozstrzyga ją jako
„nieznane", czyli jako *przepuść*, nie *czekaj*. Mając tylko te dwa bity, „padło" jest
nieodróżnialne od „jeszcze nie pytano", więc dowolny strażnik napisany przeciw nim albo czeka
w nieskończoność po nieudanym ładowaniu, albo nie czeka wcale.

I to jest generator wzorca z tabelki wyżej. **Każda łatka kodowała brakujący stan gdzie
indziej i doraźnie** — uchwyt zadania (P1-16), obecność timera (P1-17), flaga (P1-18) — a
każde nowe wejście czytało inny z tych zastępników. Cztery błędy „drugiego wejścia", jeden
niedomodelowany automat stanów.

**Pytanie do rozstrzygnięcia jest więc węższe niż „gdzie postawić choke point":** czy
ładowanie uprawnień dostaje prawdziwy stan rozstrzygnięcia — `unasked` / `inFlight` /
`settled(known)` / `settled(unknown, z terminem ponowienia)`. Przy takim modelu strażnik w
`fetchData` to dwie linijki, a nie czwarte balansowanie. `keyInfoLoadedAt` jest już prawie
tym polem; brakuje mu stemplowania **także przy porażce**, z własnym backoffem, żeby
„nieznane" było ponawiane, a nie zatrzaśnięte.

Zastrzeżenie od autora tej diagnozy, które powtarzam, bo jest istotne: nie zostało to
napisane ani przetestowane, i nie ma gwarancji, że przechodzi tych siedem testów — a to
właśnie ten sprawdzian zabił poprzednią próbę.

Warianty do rozważenia, w kolejności, w jakiej bym je oceniał:
1. **Kolejność w `fetchData()`** — jeden choke point, zamyka klasę zamiast łatać instancję.
   Koszt: znacznik „już próbowałem odczytać uprawnienia" osobny od `keyInfoLoadedAt` (który
   ustawia się tylko przy sukcesie), inaczej nieudane `/key/info` daje nieskończoną
   rekurencję w ścieżce pobierania.
2. **Przepiąć „Save & Connect" i `onConnectivityRestored` na `startPolling()`** — trzeba
   wtedy sprawdzić, czy strażnik wczesnego wyjścia w `startPolling` (`:16`) nie połknie
   wywołania; P2-17 usunęło jedną z dwóch przyczyn takiego połknięcia, ale nie obie.
3. **Osobna synchroniczna ścieżka w `refreshNow`**, która nadal zwraca to, czego oczekuje
   siedem testów. Najmniejsza zmiana, ale zostawia wzorzec nietknięty i będzie czwartym
   wejściem czekającym na piąte.

**Ponowny audyt:** interakcja `startPolling` i `refreshNow`, w tym zachowanie przy
nakładających się wywołaniach, została sprawdzona po wdrożeniu poprawki. Pełny zestaw
testów jednostkowych i UI przechodzi na ustabilizowanym drzewie.

### Naprawione w tym samym przebiegu (kandydat 1.13.0)

| # | Problem | Skąd |
|---|---|---|
| P2-16 | Przestarzałe zadanie pierwszego pobrania czyściło `awaitingFirstKeyInfo` bez sprawdzenia, czy nadal jest aktualne — ten sam błąd co wcześniejszy clobber uchwytu, przeniesiony na flagę. Teraz token `firstFetchGeneration`. | diff |
| P2-17 | `resetAccountScopedState` nie ruszało `timerCancellable` ani `lastFetchTime`, więc strażnik wczesnego wyjścia w `startPolling` czytał stan poprzedniego konta i przy zmianie klucza w ciągu połowy interwału w ogóle nie ustanawiał kolejności — „rzut monetą przy każdej zmianie klucza". Timer starego konta jest teraz kasowany. | diff |
| P2-18 | Migracja `seededCategoryId` wnioskowana z pustości listy zamiast z flagi: instalacja 1.12.1, która zasiała **pustą** kategorię, po aktualizacji zasiewała ją ponownie w ciszy i **połykała pierwszy wątek** — dokładnie to ogłoszenie, dla którego flaga powstała. | dane |
| P2-19 | Nic nie ograniczało liczby wierszy odpowiedzi. Listing dłuższy niż limit listy widzianych zamieniał stronę i eksmisję w pętlę: każdy poll wypycha stronę na przód, eksmituje ogon i ogłasza go ponownie następnym razem — **trwale**. `limit=20` to parametr żądania, a nie gwarancja serwera. Teraz `maximumThreadsPerListing = 100`, mocno poniżej limitu 500. | dane |
| P3-10 | 1.12.0 odcięło siatkę popularnych przedmiotów za `itemCatalog.isEmpty`. W 1.11.1 te sześć pozycji było **całym** mechanizmem dodawania (pola tekstowego nie było wcale), więc otwarcie panelu na zimno dawało puste pole tam, gdzie były klikalne pozycje. Potwierdzona regresja z tagów. Siatka jest znów fallbackiem dla każdego pozostałego stanu. | UX |

---

## Walidacja po zmianach

| Polecenie | Wynik |
|---|---|
| `xcodebuild test` (unit + coverage, finalne drzewo 1.13.0) | ✅ 709 testów, 0 błędów, 0 pominiętych |
| `xcodebuild analyze` | ✅ zakończone bez błędów analizatora |
| `coverage-gate.sh` | ✅ PASSED. `TornAPIError` 90,91 %, `TornEndpoint` 95,12 %, `PollingCoordinator` 100 %, `NotificationCoordinator` 98,36 %, `NextAction` 96,63 % |
| `xcodebuild test` (`MacTornUITests`) | ✅ 13/13, w tym błędny klucz, offline, 320 pt i kontrakt VoiceOver |
| `make release && make verify-release` | ✅ 1.13.0 (45), arm64 + x86_64, ścisły podpis ad-hoc |
| `make icon-check` | ✅ 10 przezroczystych plików PNG o prawidłowych wymiarach |
| `make scan` / `git diff --check` | ✅ brak wycieków i błędów whitespace |

---

## Ograniczenia audytu

**Bez żywego klucza API.** Audyt nie odczytywał prywatnego klucza z pęku kluczy ani nie
wysyłał próbnych żądań na koncie użytkownika. Cały audyt warstwy API oparto na dokumencie OpenAPI Torna
(`https://www.torn.com/swagger/openapi.json`, wersja specyfikacji **6.13.1**, pobrany
2026-08-26), a nie na porównaniu z żywymi odpowiedziami. Specyfikacja jest źródłem
autorytatywnym i sama zawiera zastrzeżenie, że rozwój v2 trwa. **Każda zmiana kształtu
żądania w tej gałęzi powinna zostać potwierdzona pierwszym uruchomieniem na prawdziwym
kluczu.** Dotyczy zwłaszcza: nagłówka `Authorization` na v2, zawężania selekcji i usunięcia
`bazaar`.

**UI-testy wymagają nieprzerwanej autoryzacji Accessibility.** Jeden przebieg stracił ją,
gdy komputer był równolegle używany; po przywróceniu dostępu świeża sesja zaliczyła
13/13. To ograniczenie runnera, nie wynik produktu. Testy sprawdzają drzewo dostępności,
etykiety i geometrię, ale ręczne odsłuchanie VoiceOver oraz kontrola ikony w Finderze i
Docku nadal pozostają manualną częścią QA.

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
