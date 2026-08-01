# MacTorn — raport audytu technicznego

Data audytu: 2026-08-01
Audytowana wersja: 1.11.1 (`MARKETING_VERSION = 1.11.1`, `CURRENT_PROJECT_VERSION = 1`)
Gałąź: `main` (naprawy wykonane bezpośrednio na `main` — decyzja Pawła z 2026-08-01)
Poprzedni audyt: 2026-07-30, wersja bazowa 1.10.0

Ten dokument zawiera fakty i lokalizacje. Oceny, rekomendacje i priorytetyzacja produktowa
znajdują się w `UX_RECOMMENDATIONS.md`. Wykaz zmian w `CHANGELOG_AGENT.md`.

---

## Streszczenie stanu

Kod produkcyjny MacTorna jest w bardzo dobrym stanie inżynierskim: brak force-unwrapów,
brak `fatalError`, brak pustych `catch`, wszystkie pliki wpięte w `project.pbxproj`,
`xcodebuild analyze` bez ostrzeżeń, konsekwentna redakcja URL-i w 60 wywołaniach loggera,
sandbox z dokładnie dwoma uprawnieniami i klucz API w Keychainie. Audyt bezpieczeństwa nie
znalazł ani jednego P0 ani P1.

Audyt znalazł natomiast trzy problemy klasy P1, których poprzednie przebiegi nie wykryły,
bo wszystkie trzy są niewidoczne dla zielonego zestawu testów:

1. **Alert „Chain Expiring!" nie działał w produkcji od momentu powstania.** Kod czytał
   pole `chain` ze snapshotu użytkownika; endpoint `user` API Torna nie ma takiej selekcji
   i `user.fast` nigdy o nią nie prosił. Testy przechodziły, ponieważ fixture DEBUG
   dopisywał to pole do odpowiedzi użytkownika — czyli test weryfikował świat, który nie
   istnieje. Ta sama martwa ścieżka dotyczyła karty chainu w zakładce Status i wpisu chain
   w osi Next Action.
2. **Uszkodzony blob w `UserDefaults` trwale kasował watchlistę i obserwowane wątki.**
   Nieudane dekodowanie było nieodróżnialne od „brak danych, pierwsze uruchomienie", a
   pierwszy zapis w tle nadpisywał odzyskiwalny blob pustą listą.
3. **Etykieta w pasku menu — jedyna zawsze widoczna powierzchnia aplikacji — nie miała
   żadnej semantyki dostępności.** VoiceOver czytał surowe glify.

Wszystkie trzy zostały naprawione wraz z testami regresyjnymi. Łącznie naprawiono 22
problemy; 28 nowych testów jednostkowych.

**Ograniczenie tego przebiegu:** zestaw testów UI (8 testów XCUITest) **nie został
uruchomiony** — Paweł przerwał go w trakcie, ponieważ XCUITest przejmuje ekran i fokus
podczas pracy na komputerze. Aplikacja nie była też uruchamiana wizualnie. Wszystkie
ustalenia dotyczące wyglądu są w związku z tym oznaczone jako wymagające weryfikacji
manualnej. Zestaw UI należy uruchomić przed publikacją wydania.

---

## Mapa projektu

Aplikacja menu-bar dla macOS 14+, SwiftUI + `MenuBarExtra`, Swift 5 language mode,
Universal Binary (arm64 + x86_64), sandbox + hardened runtime, podpis ad-hoc.

- 51 plików produkcyjnych Swift (~12 000 linii), 37 plików testowych.
- Jedna zależność zewnętrzna: Sentry Cocoa 9.23.0 (przypięta rewizja `afa7510e`).
- Model: fasada `AppState` (~390 linii) + 6 plików rozszerzeń + 5 serwisów/store.
- Persystencja: klucz API w Keychainie (`com.mactorn.app`), reszta w `UserDefaults`
  (wstrzykiwanym, żeby testy nie współdzieliły `.standard`).
- Sieć: `NetworkSession` (protokół, wstrzykiwany), wszystkie żądania Torna przechodzą
  przez bramkę budżetu `PollingCoordinator.reserveRequest`.

Przepływ danych: `MenuBarExtra` → `ContentView` → moduły → `AppState` → serwisy →
`api.torn.com` (v1/v2). Jedyny wyjątek: `UpdateManager` uderza w `api.github.com` przez
`URLSession.shared`, z pominięciem wstrzykiwanej sesji (patrz C-10).

Obszary największego ryzyka, potwierdzone w tym audycie: (a) rozjazd między modelem, do
którego pisany jest kod, a modelem, który zwraca prawdziwe API; (b) persystencja
`UserDefaults` bez rozróżnienia „brak danych" od „dane nie do odczytania"; (c) kotwiczenie
czasu — część odliczań używa `server_time`, część lokalnego `Date()`.

---

## Stan bazowy (przed zmianami)

Wykonane polecenia i ich dosłowne wyniki:

| Polecenie | Wynik |
|---|---|
| `xcodebuild test -only-testing:MacTornTests` | **PASS — 432/432**, 0 failed, 0 skipped (macOS 26.5.1, arm64, Xcode 26.6) |
| `bash scripts/coverage-gate.sh … 80` | **PASS** — TornAPIError 99,07%, TornEndpoint 83,56%, PollingCoordinator 100%, NotificationCoordinator 100%, NextAction 96,51% |
| `xcodebuild analyze` | **ANALYZE SUCCEEDED**, zero ostrzeżeń |
| `xcodebuild build -configuration Debug` | **BUILD SUCCEEDED** |
| `gitleaks git` (pełna historia) | **PASS** — 132 commity, 1,40 MB, `no leaks found` |
| `xcodebuild test -only-testing:MacTornUITests` | **NIE UKOŃCZONO** — przerwane na prośbę Pawła (XCUITest przejmuje ekran) |

Zielony build nie był dowodem poprawności: trzy z naprawionych niżej problemów (C-01,
D-01, D-02) przechodziły przez wszystkie powyższe bramki.

Pokrycie kodu produkcyjnego przez testy jednostkowe: 23,94% (4040/16874 linii). Warstwa
widoków ma 0–2,5% — z założenia, bo pokrywa ją zestaw UI. Poza widokami zerowe pokrycie
mają `BrowserManager.swift` i `SoundManager.swift`.

---

## Problemy naprawione

Kolejność: utrata/integralność danych → security → poprawność → dostępność → UX → dokumentacja.

### Utrata danych

| ID | Prio | Problem | Lokalizacja | Status | Przyczyna źródłowa | Poprawka | Weryfikacja |
|---|---|---|---|---|---|---|---|
| D-01 | P1 | Uszkodzony blob w `UserDefaults` trwale kasował watchlistę i obserwowane wątki | `MarketWatchService.swift:52`, `ForumWatchService.swift:56` | potwierdzony | `try?` zrównywał „klucza nie ma" (legalne pierwsze uruchomienie) z „klucz jest, ale nie parsuje" (awaria); warstwa zapisu nie wiedziała, że odczyt zawiódł, i pierwszy zapis w tle nadpisywał odzyskiwalny blob pustą listą | Flaga `loadFailed` ustawiana, gdy blob istnieje, ale nie daje się zdekodować; `save()` odmawia zapisu; oryginał kopiowany pod klucz `*.unreadable`; świadoma edycja użytkownika (add/remove/restore/toggle) zdejmuje flagę | 7 nowych testów: `MarketWatchCorruptStoreTests` (4), `ForumWatchResilienceTests` (3) |
| D-02 | P2 | Częściowa odpowiedź forum trwale gubiła alert o nowych postach | `ForumWatchService.swift:204` | potwierdzony | Odpowiedź z `title`, ale bez `posts`, przechodziła jako sukces z `postCount: 0`; zero trafiało do `lastKnownPostCount`, a strażnik `previousCount > 0` w `apply` połykał kolejny prawdziwy przyrost | Brak użytecznego `posts` → `.malformed` (z tolerancją dla liczby jako stringu); pusty tytuł nie nadpisuje dobrego | 3 nowe testy w `ForumThreadParseTests` + 2 w `ForumWatchResilienceTests` |

### Bezpieczeństwo

| ID | Prio | Problem | Lokalizacja | Status | Przyczyna źródłowa | Poprawka | Weryfikacja |
|---|---|---|---|---|---|---|---|
| S-01 | P2 | `BrowserManager.open` otwierał dowolny schemat URL przez `NSWorkspace` | `BrowserManager.swift:96` | potwierdzony | Whitelist schematów napisana jako router wyboru przeglądarki, nie jako bramka; gałąź „nie http/https" spadała do `NSWorkspace.shared.open(url)`. Osiągalne łańcuchem zdalnym: `GitHubRelease.htmlUrl` → „Download Update" (`SettingsView.swift:392`) | Tylko `http`/`https` z niepustym hostem jest otwierane; reszta odrzucana. Polityka wydzielona do czystej funkcji `BrowserManager.isWebURL` | 3 nowe testy `BrowserManagerPolicyTests` (m.in. `file://`, `javascript:`, `ssh://`, brak hosta) |
| S-02 | P2 | Workflow `claude.yml` uruchamiany komentarzem dowolnej osoby na publicznym repo | `.github/workflows/claude.yml:19` | wysoce prawdopodobny | Brak warunku na `author_association`; treść komentarza staje się promptem wykonywanym z sekretami repo. Obrona istniała wyłącznie wewnątrz akcji zewnętrznej | Bramka `OWNER/MEMBER/COLLABORATOR` we wszystkich czterech gałęziach `if:` | Inspekcja pliku; brak uruchomienia zdalnego w tym przebiegu |
| S-05 | P3 | Allowlist gitleaks wyciszał całą linię zawierającą słowo `example`/`sample`/`dummy` | `.gitleaks.toml:34` | potwierdzony | Allowlist działał na dopasowaniu w linii, nie na wartości sekretu | `regexTarget = "match"` + wzorce zakotwiczone na całej wartości | `gitleaks git` na pełnej historii: 132 commity, `no leaks found` |
| S-06 | P3 | Hook pre-commit cicho przepuszczał commit przy braku gitleaks | `.githooks/pre-commit:9` | potwierdzony | Fail-open na brakującym narzędziu; `make hooks` zostawiał hook, który wygląda na zainstalowany, a nic nie sprawdza | Fail-closed: `exit 1` z instrukcją instalacji i jawnym `--no-verify` | Inspekcja; gitleaks obecny lokalnie, hook aktywny (`core.hooksPath=.githooks`) |
| S-07 | P3 | Cztery archiwa ZIP (~8,3 MB) śledzone w gicie wbrew własnemu `.gitignore` | `MacTorn-1.5.1.zip`, `MacTorn/Archive/*.zip` | potwierdzony | Reguła ignorowania dodana po fakcie, bez `git rm --cached` | `git rm --cached` na czterech plikach; pliki zostają na dysku, `.gitignore` je łapie | `git check-ignore -v` potwierdza dopasowanie |
| S-08 | P3 | `coverage-gate.sh` interpolował parametr wprost do programu awk | `scripts/coverage-gate.sh:62` | potwierdzony (wzorzec) | `$THRESHOLD` (nieprzefiltrowany `$2`) stawał się kodem awk | Przekazanie przez `-v pct=… -v threshold=…` | `make coverage-gate` PASS |

### Poprawność

| ID | Prio | Problem | Lokalizacja | Status | Przyczyna źródłowa | Poprawka | Weryfikacja |
|---|---|---|---|---|---|---|---|
| C-01 | P1 | Alert „Chain Expiring!", karta chainu w Status i wpis chain w Next Action były martwe w produkcji | `AppState+NotificationsFeedback.swift:41`, `AppState+LiveNextAction.swift:136`, `StatusView.swift:39` | potwierdzony (dwie niezależne weryfikacje + moja własna) | Logika pisana przeciwko `TornResponse.chain`; API Torna nie zwraca chainu na endpointcie `user`, a `user.fast` nie prosi o taką selekcję (`TornEndpoint.swift:161`). Prawdziwy chain żyje w `FactionChain` na endpointcie faction. Fixture DEBUG (`UITestSupport.swift:254`) zmyślał klucz `chain` w odpowiedzi użytkownika, więc regresja nigdy nie została złapana | Nowa właściwość `AppState.liveChain` mapująca `factionService.basic?.chain` (oba modele używają absolutnego uniksowego `timeout`, więc mapowanie jest kopiowaniem pól). Sprawdzenie alertu przeniesione do `checkChainNotification()` wołanego **w miejscu, w którym dane chainu wchodzą do systemu** — zaraz po `publishBasic` w `AppState+FactionFetch.swift`. Zmyślony klucz usunięty z fixture'u | 7 nowych testów `ChainSourceTests`, w tym `testUserFastEndpointDoesNotRequestChain` pilnujący, że alert nie może znów zawisnąć na nieistniejącej selekcji |
| C-02 | P2 | HTTP 403/404 kasował cały snapshot i raportował „Invalid API Key" | `AppState+PollingUserFetch.swift:290` | potwierdzony | Torn sygnalizuje zły klucz przez HTTP 200 + koperta `error` (obsłużone osobno); 403/404 pochodzi z warstwy edge/CDN i jest przejściowe. Była to jedyna ścieżka błędu niszcząca dane | Gałąź 403/404 usunięta — obsługiwana jak każdy inny błąd HTTP: `errorMsg = "HTTP Error: <kod>"`, `data` nietknięte | 2 testy przepisane na poprawny kontrakt + nowy `testTornErrorEnvelopeStillHaltsOnBadKey` pilnujący, że prawdziwa awaria klucza nadal zatrzymuje polling |
| C-03 | P3 | `notificationCoordinator.reset()` nie był wołany przy zmianie konta mimo komentarza mówiącego inaczej | `NotificationCoordinator.swift:74`, `AppState.swift` | potwierdzony | Metoda istniała i była udokumentowana, ale nie miała ani jednego wywołania produkcyjnego | `reset()` + wyczyszczenie `notifiedBountyKeys` w setterze `apiKey` (świadomie nie w `resetAccountScopedState()`, które jest wołane też przy przejściowym błędzie klucza — tam czyszczenie latchy powtórzyłoby alerty) | Pełny zestaw jednostkowy zielony |

### Dostępność

| ID | Prio | Problem | Lokalizacja | Status | Przyczyna źródłowa | Poprawka | Weryfikacja |
|---|---|---|---|---|---|---|---|
| A-01 | P2 | „Reduce Transparency" nigdy nie czytało ustawienia systemowego macOS, mimo że README to obiecywał | `MacTornApp.swift:8`, `TransparencyEnvironment.swift:5` | potwierdzony (`rg` na `accessibilityDisplayShouldReduceTransparency` → 0 trafień w całej historii repo) | Wartość pochodziła wyłącznie z `@AppStorage` domyślnie `false`; przełącznik schowany w sekcji „Startup" | `SystemAccessibilitySettings` czyta `NSWorkspace.accessibilityDisplayShouldReduceTransparency` i nasłuchuje `accessibilityDisplayOptionsDidChangeNotification`; `TransparencyPolicy.effective(system:userOverride:)` łączy je (system jako podłoga, przełącznik tylko dodaje). Etykieta zmieniona na „Always reduce transparency" z podpowiedzią | `make coverage-gate` PASS; działanie z realnym przełącznikiem systemowym **wymaga weryfikacji manualnej** |
| A-02 | P1 | Etykieta w pasku menu nie miała żadnej semantyki dostępności | `MacTornApp.swift:140` | potwierdzony | `MenuBarDisplay` niósł wyłącznie prezentację (emoji flagi, emoji cooldownu). W modelu nie zostawała żadna nazwa, którą VoiceOver mógłby wypowiedzieć | Model niesie teraz znaczenie: `.traveling(destination:seconds:)`, `.cooldown(kind:seconds:)`; glify wyprowadzane w widoku. Dodane `accessibilityDescription` (czysta funkcja) i `.accessibilityLabel` na etykiecie | 8 nowych testów `MenuBarAccessibilityTests`, w tym test pilnujący, że żaden glif nie wycieka do mowy |
| A-03 | P2 | Zero wsparcia dla Reduce Motion w całym projekcie | `WatchlistView.swift`, `ForumWatchView.swift` (10 miejsc) | potwierdzony (`rg reduceMotion` → 0 trafień) | Bezwarunkowe `withAnimation` i `.transition(.move(...))` | `@Environment(\.accessibilityReduceMotion)` w obu widokach; animacje i przejścia warunkowe | Kompilacja PASS; efekt **wymaga weryfikacji manualnej** przy systemowym Reduce Motion |

### UX

| ID | Prio | Problem | Lokalizacja | Status | Przyczyna źródłowa | Poprawka | Weryfikacja |
|---|---|---|---|---|---|---|---|
| U-01 | P1 | „Loading…" bez końca dla gracza bez frakcji lub z kluczem o ograniczonym dostępie | `FactionView.swift:74`, `MoneyView.swift:84`, `AttacksView.swift:46` | potwierdzony | Warunkiem był wyłącznie `data == nil`, bez rozróżnienia „jeszcze nie przyszło" od „przyszło i tego nie ma" | Rozróżnienie po `lastUpdated == nil`; po zakończonym odświeżeniu komunikat nazywa stan („Nie należysz do frakcji lub klucz nie ma dostępu") | Kompilacja PASS; **wymaga weryfikacji manualnej** |
| U-02 | P2 | Podczas pierwszego ładowania cały interfejs, łącznie z Quit i Settings, był zablokowany | `ContentView.swift:109` | potwierdzony | `.disabled()` obejmował `VStack` razem ze stopką; nakładka bez anulowania. Domyślny timeout `URLSession` to 60 s | `.disabled` przeniesione wyłącznie na obszar treści; stopka zawsze aktywna; nakładka `.allowsHitTesting(false)` | Kompilacja PASS; **wymaga weryfikacji manualnej** |
| U-03 | P2 | Wynik „Test Connection" nie unieważniał się po edycji pola klucza | `SettingsView.swift:242` | potwierdzony | Brak `.onChange(of: inputKey)`; zielone „✓ Full Access · ID …" dla klucza A zostawało pod świeżo wpisanym kluczem B | `.onChange` resetuje `keyValidation` do `.idle` | Kompilacja PASS |
| U-04 | P2 | „Save & Connect" bez zabezpieczenia przed wielokrotnym kliknięciem | `SettingsView.swift:249` | potwierdzony | `.disabled` tylko na pustym polu; trzy szybkie kliknięcia = trzy odświeżenia w aplikacji pilnującej budżetu API | Dodane `|| appState.isLoading` | Kompilacja PASS |
| U-05 | P2 | Ciche odrzucenie przy dodawaniu duplikatu do watchlisty | `WatchlistView.swift:58`, `AppState+MarketForum.swift:15` | potwierdzony | `addToWatchlist` zwracało `Void`; panel zamykał się bezwarunkowo, więc odrzucenie wyglądało identycznie jak sukces | `addToWatchlist` zwraca `Bool`; przy odrzuceniu panel zostaje otwarty i pokazuje powód | Kompilacja PASS |

### Dokumentacja i doktryna (audytowane jak kod wykonywalny)

| ID | Prio | Problem | Lokalizacja | Status | Poprawka |
|---|---|---|---|---|---|
| DOC-01 | P3 | Komenda `/new-version` kazała agentowi „update version in gradle files" w projekcie Xcode; `allowed-tools` nie obejmowały pushu ani release'u, których sama instrukcja żądała | `.claude/commands/new-version.md:2,15` | potwierdzony | Przepisana pod rzeczywisty projekt: `MARKETING_VERSION` i `CURRENT_PROJECT_VERSION` w `project.pbxproj`, uzupełnione `allowed-tools`, dodany krok podmiany lokalnej instalacji, jawny zakaz uruchamiania testów UI bez pytania |
| DOC-02 | P3 | Sekcja „Torn API" w `CLAUDE.md` opisywała zestaw selekcji porzucony dawno temu (jeden endpoint user z `events,messages,attacks`) | `CLAUDE.md` | potwierdzony | Opis wskazuje typowany rejestr jako źródło prawdy, rozdziela `user.fast` od `user.activity`, jawnie zapisuje, że chain żyje na endpointcie faction, i że 403/404 nie oznacza złego klucza |
| DOC-03 | P2 | README deklarował automatyczną reakcję na systemowe „Reduce Transparency", której implementacja nie miała | `README.md:86` | potwierdzony | Deklaracja jest teraz prawdziwa (A-01); dopisano Reduce Motion i VoiceOver oraz uczciwy akapit o tym, czego jeszcze brakuje |

---

## Problemy pozostawione (niewdrożone)

Zgłaszam wszystkie znalezione. Poniższe nie zostały naprawione w tym przebiegu — powód
podany przy każdym.

### Poprawność

| ID | Prio | Problem | Lokalizacja | Status | Powód niewdrożenia |
|---|---|---|---|---|---|
| C-04 | P2 | Wszystkie odliczania **poza cooldownami** ignorują `server_time` i liczą od lokalnego `Date()` | `TornModels.swift:224`, `:230`, `:398`, `:421`, `:748` | potwierdzony | Wymaga przeprowadzenia offsetu zegara serwera przez pięć miejsc w modelach albo wstrzyknięcia `TimeSource` do modeli. Przy rozjeździe zegara Maca użytkownik widzi w jednym UI dwa różne czasy (cooldowny poprawne, travel/hospital/jail spóźnione). Zmiana o realnym ryzyku regresji na wszystkich licznikach — zasługuje na osobny, dedykowany przebieg z testami na `MutableTimeSource` |
| C-05 | P2 | Alerty progowe (bary) i cooldownowe gubią się przy restarcie aplikacji | `AppState+NotificationsFeedback.swift:14`, `:74` | potwierdzony | `previous*` startują jako `nil`, więc pierwszy poll po restarcie nie wykryje żadnego przejścia, a drugi ma już „przed" równe „po". Poprawne rozwiązanie (persystentne latche przez `NotificationCoordinator`) wymaga zasiania latchy przy pierwszym snapshocie bez wysyłania, inaczej pierwsze uruchomienie wyśle banner na każdy aktywny cooldown |
| C-06 | P2 | `refreshNow()` omija throttle; przytrzymane ⌘R generuje serię żądań | `AppState+PollingUserFetch.swift:10`, `MacTornApp.swift:104` | potwierdzony | Jedynym hamulcem jest twardy limit 60 req/min. Dodatkowo każde nowe żądanie anuluje poprzednie, więc w serii żadne nie zdąży opublikować danych. Poprawka (debounce ~3 s na ścieżce `force`) nie może blokować natychmiastowego odświeżenia po zapisaniu klucza — wymaga rozróżnienia obu ścieżek |
| C-07 | P2 | Odpowiedź anulowanego pollu może zgasić spinner następnego | `AppState+PollingUserFetch.swift:215` | potwierdzony (statycznie) | Skutek wyłącznie kosmetyczny, żadne dane nie giną. Wymaga monotonicznego licznika pollu; nie zdążyłem tego przetestować runtime'owo, a bez testu nie chcę ruszać ścieżki anulowania |
| C-08 | P3 | Dedup bounty nie przeżywa restartu — N otwartych bounty = N bannerów przy każdym starcie | `AppState.swift:214`, `AppState+PollingUserFetch.swift:531` | potwierdzony | Wymaga migracji na `NotificationCoordinator` + agregacji wielu bounty w jeden banner + przycinania rosnącego słownika epok |
| C-09 | P3 | `RetryPolicy` i `isRetryable` to martwy kod; nagłówek pliku opisuje backoff, którego nikt nie wywołuje | `TornAPIError.swift:15`, `:181` | potwierdzony | Wymaga decyzji: podpiąć retry czy usunąć typ razem z testami. Funkcjonalnie luka jest mała (cadence 15–120 s i tak podnosi aplikację), ale komentarz wprowadza w błąd |
| C-10 | P3 | `UpdateManager` używa `URLSession.shared` z pominięciem wstrzykiwanej sesji; `Task` bez przechowanego handle'a | `TornModels.swift:1160`, `AppState+NotificationsFeedback.swift:102` | potwierdzony | Cel to GitHub, nie Torn, więc ominięcie budżetu jest uzasadnione. Problemem jest testowalność (0% pokrycia) i brak anulowania przy teardownie |

### Dostępność (wszystkie potwierdzone w kodzie, skutek dla VoiceOver wymaga weryfikacji manualnej)

| ID | Prio | Problem | Lokalizacja |
|---|---|---|---|
| A-04 | P1 | Pięć zakładek nie ma **ani jednego** modyfikatora dostępności — VoiceOver czyta każdy `Text` i `Image` osobno, jako niepowiązany strumień | `AttacksView`, `FactionView`, `MoneyView`, `PropertiesView`, `StocksView`, plus komponenty `ChainView`, `EventsView`, `StatusBadgesView`, `FeedbackPromptView`, `SentryOptInPromptView` |
| A-05 | P1 | Wynik ataku (wygrana/przegrana) przekazywany wyłącznie ikoną i kolorem; słowo `result` nigdy nie trafia na ekran | `AttacksView.swift:73`, `TornModels.swift:621` |
| A-06 | P1 | `ModuleStateView` łączy dzieci przez `.combine` i nadpisuje etykietę — przycisk Retry/Settings traci nazwę. Komponent współdzielony przez 8 zakładek | `DiagnosticsView.swift:182` |
| A-07 | P2 | Pasek postępu lotu to dwa prostokąty bez semantyki; wzorzec zrobiony poprawnie leży obok w `ProgressBarView.swift:66` | `TravelView.swift:61` |
| A-08 | P2 | `ProgressView(value:)` bez etykiet — VoiceOver ogłasza samo „62 procent" | `FactionView.swift:247`, `:307` |
| A-09 | P2 | Etykieta dostępności przeliczana co sekundę w `TimelineView` — ryzyko zapętlonego ogłaszania | `NextActionView.swift:46`, `StatusView.swift:499`, `FactionView.swift:40` |
| A-10 | P2 | Bardzo małe obszary klikalne (glif `.caption`, ~11 pt, bez `contentShape`) | `WatchlistView.swift:275`, `:330`, `ForumWatchView.swift:280` |
| A-11 | P2 | Treść błędu wątku forum dostępna wyłącznie przez tooltip `.help` — niedostępna bez myszy | `ForumWatchView.swift:264` |
| A-12 | P2 | Nakładki modalne nie mają `.accessibilityAddTraits(.isModal)` — kursor VoiceOver wchodzi „pod spód" | `ContentView.swift:126` |
| A-13 | P3 | Dosłowny `Color.gray` (nie adaptujący się do motywu) jako kolor ikon i teł w komponentach listowych | `WatchlistView.swift:281`, `ForumWatchView.swift:306`, `ProgressBarView.swift:44`, `TravelView.swift:64`, `ChainView.swift:36` |
| A-14 | P3 | Sztywne wymiary `320×640` i 16 wystąpień `lineLimit(1)` — przy powiększonym tekście systemowym treść zostanie ucięta zamiast przełamana. **Hipoteza wymagająca testu manualnego** | `ContentView.swift:142`, `SettingsView.swift:103` |

Uwaga pozytywna, potwierdzona: w całym drzewie nie ma **ani jednego** `.font(.system(size:))`
— wszystkie fonty są semantyczne.

### UX

| ID | Prio | Problem | Lokalizacja |
|---|---|---|---|
| U-06 | P1 | Dwa sprzeczne komunikaty o stanie jednocześnie na jednym ekranie (`ModuleStateView` + lokalny „Loading…"/`errorSection`) | `FactionView.swift:10` vs `:74`; `StatusView.swift:14` vs `:144` |
| U-07 | P1 | Komunikaty błędów w języku programisty, bez instrukcji i z **niższą** wagą wizualną niż zwykły tekst (`.secondary`); dobre, ludzkie komunikaty istnieją obok, w `TornAPIError.swift:111`, ale te ścieżki je omijają | `AppState+PollingUserFetch.swift:199`, `:307`, `:359`; `StatusView.swift:144` |
| U-08 | P2 | Ustawienia dostępności, wyglądu i przeglądarki schowane pod sekcją „Startup"; „Booster cooldown link" siedzi w „Notifications" | `SettingsView.swift:345`, `:314` |
| U-09 | P2 | Pierwsze uruchomienie: formularz bez kontekstu; wymagany poziom dostępu i zapewnienie o Keychainie schowane w domyślnie zwiniętej sekcji | `ContentView.swift:83`, `SettingsView.swift:569` |
| U-10 | P2 | Nie da się obserwować przedmiotu spoza sześciu zaszytych na stałe — moduł „Price Watch" obsługuje 6 z ~1000 przedmiotów Torna | `WatchlistView.swift:142` |
| U-11 | P2 | `DiagnosticsView` jako sheet 380 pt w oknie 320 pt. **Hipoteza wymagająca weryfikacji manualnej** | `SettingsView.swift:108`, `DiagnosticsView.swift:96` |
| U-12 | P3 | „Clear" kasuje próg alertu cenowego bez potwierdzenia i bez Undo, mimo że usuwanie pozycji ma pełne Undo | `WatchlistView.swift:311` |
| U-13 | P3 | Wewnętrzne fallbacki wyciekają do UI („Unknown", „Stock #123") | `StatusView.swift:163`, `TravelView.swift:135`, `StocksView.swift:56` |
| U-14 | P3 | Tylko Status ma `maxHeight: 480`; pozostałe osiem zakładek nie ma ograniczenia — stopka „skacze" przy przełączaniu | `StatusView.swift:81` |
| U-15 | P3 | Dwie nakładki (feedback + Sentry opt-in) mogą pojawić się jednocześnie | `ContentView.swift:126` |
| U-16 | P3 | Nieużywany parametr `icon` w komponentach cooldownu — zdefiniowany, przekazywany, nigdy nie renderowany | `StatusView.swift:414`, `:493` |
| U-17 | P3 | Zakładki Stocks i Watchlist dzielą tę samą ikonę | `ContentView.swift:46`, `:49` |

### Bezpieczeństwo, build i utrzymanie

| ID | Prio | Problem | Lokalizacja | Powód niewdrożenia |
|---|---|---|---|---|
| S-03 | P2 | Dystrybucja binarki podpisanej ad-hoc, bez notaryzacji; README uczy odruchu „prawy przycisk → Otwórz" na niepodpisanej aplikacji z internetu | `Makefile:112`, `README.md` | Developer ID wymaga płatnego programu Apple — świadoma decyzja Pawła (T16-A / ISC-25, „WON'T DO"). Tani krok pośredni: publikować SHA-256 artefaktów w release notes |
| S-04 | P3 | `DiagnosticsReport.lastErrorSummary` niesie surowy komunikat serwera wbrew komentarzowi, który deklaruje „never a raw server string" | `Diagnostics.swift:177`, `AppState+LiveNextAction.swift:169` | Wpływ praktyczny niski (komunikaty Torna to stałe stringi), ale inwariant zapisany w kodzie jest fałszywy. Raport jest kopiowany do schowka i z założenia wklejany do publicznych zgłoszeń |
| S-09 | P3 | Prywatny adres e-mail zaszyty w kodzie publicznej aplikacji | `AppState+NotificationsFeedback.swift:176` | Świadoma decyzja produktowa (kanał feedbacku), nie błąd. Zgłoszone jako świadomy koszt prywatności |
| S-10 | P3 | `kSecAttrAccessibleAfterFirstUnlock` zamiast wariantu `WhenUnlocked` | `AccountSessionStore.swift:154` | Poprawny wybór dla aplikacji odpytującej API przy zablokowanym ekranie. Zalecane wyłącznie dopisanie komentarza uzasadniającego, żeby nikt tego nie „poprawił" i nie zepsuł pollingu w tle |
| B-01 | P2 | CI przypina Xcode 16.4 twardą asercją (`test "$(xcodebuild -version …)" = "Xcode 16.4"`), lokalnie stoi Xcode 26.6 | `.github/workflows/tests.yml:17`, `:31` | Determinizm kosztem kruchości: gdy obraz runnera `macos-15` przestanie mieć tę wersję, wszystkie trzy joby padną twardo. Dodatkowo lokalny i zdalny kompilator to inne wersje Swifta. Zmiana strategii pinowania to decyzja Pawła, nie audytora |
| B-02 | P3 | `CURRENT_PROJECT_VERSION = 1` we wszystkich konfiguracjach mimo `MARKETING_VERSION = 1.11.1` | `project.pbxproj:854` i 5 dalszych | Numer builda nigdy nie rósł; `Diagnostics` raportuje `build: 1` dla każdego wydania, więc dwa buildy tej samej wersji są nierozróżnialne. Naprawione w instrukcji `/new-version`, ale samej wartości nie bumpowałem — to należy do procesu wydania |
| B-03 | P3 | Status CVE dla Sentry Cocoa 9.23.0 niezweryfikowany | `Package.resolved` | Wymaga zapytania sieciowego do GitHub Advisory Database; odpowiedź z pamięci byłaby zgadywaniem. Jedyna luka w pokryciu audytu bezpieczeństwa |

---

## Obszary sprawdzone i czyste

Wymienione, żeby zakres audytu był jawny i żeby te własności nie uległy regresji.

**Klucz API i sekrety.** Klucz wyłącznie w Keychainie (generic password, service
`com.mactorn.app`), migracja z `UserDefaults` kasuje stary wpis, brak
`kSecAttrSynchronizable` (nie idzie do iCloud). Testy używają service z sufiksem PID,
harness UI ma Keychain w pamięci — realny klucz Pawła nigdy nie jest czytany przez testy.
Przejrzane wszystkie 60 wywołań loggera w kodzie produkcyjnym: żadne nie interpoluje URL-a,
klucza ani `error.localizedDescription`. Historia gita czysta (132 commity).

**Cache HTTP.** Zweryfikowane empirycznie, nie z lektury kodu: wszystkie 6 ścieżek żądań
ustawia `.reloadIgnoringLocalAndRemoteCacheData`, a w `Cache.db` i 428 KB WAL-a w
kontenerze aplikacji nie ma ani jednego wystąpienia `torn.com` ani `key=<wartość>`.

**Sentry.** Opt-in, domyślnie wyłączony, SDK nie startuje bez zgody. `sendDefaultPii=false`,
`enableNetworkTracking=false`, `enableNetworkBreadcrumbs=false`,
`enableCaptureFailedRequests=false`, `tracesSampleRate=0.0`, `beforeSend`/`beforeBreadcrumb`
przepuszczają URL-e przez redakcję. Zero `SentrySDK.capture(...)` — wysyłane są tylko crashe.
Katalogi envelopes i raportów crashy puste.

**PII w warstwie trwałej.** Przejrzane wszystkie 18 zapisów do `UserDefaults`: brak nazwy
gracza, ID, kasy, statystyk i nazwy frakcji. Dane sesyjne żyją tylko w pamięci.
`Diagnostics.sanitizedText()` nie zawiera klucza ani identyfikatorów gracza.

**Transport i uprawnienia.** Wszystkie URL-e to literały `https://`. Brak
`NSAppTransportSecurity` w `Info.plist`, czyli ATS w trybie domyślnym (restrykcyjnym).
Entitlements: dokładnie `app-sandbox` + `network.client`, nic więcej. Hardened runtime
włączony w obu konfiguracjach.

**Współbieżność i integralność.** Token generacji sprawdzany bezpośrednio przed każdą
publikacją, bez `await` pomiędzy sprawdzeniem a zapisem — nadpisanie danych nowszego konta
starszą odpowiedzią jest niemożliwe. Zmiana klucza inkrementuje generację i anuluje
zadania w locie synchronicznie na MainActor. Timery nie mogą się zduplikować (każdy start
robi `cancel()` przed przypisaniem). Bramka budżetu szczelna: wszystkie żądania Torna mają
`reserveRequest`, jedyne `URLSession.shared` to GitHub. Brak dzielenia przez zero w
obliczeniach procentów i postępu. `BoundedTaskQueue` poprawnie propaguje anulowanie.

**Jakość kodu.** Zero `try!`, `as!`, `fatalError`, zero pustych `catch`, zero force-unwrapów
bez ochrony w logice. Wszystkie pliki źródłowe i testowe wpięte w `project.pbxproj`.

**Pozostałe workflow.** `tests.yml` ma `permissions: contents: read` i akcje przypięte do
SHA. `claude-code-review.yml` używa `pull_request`, nie `pull_request_target` — PR z forka
nie dostaje sekretów. `scripts/diagnose-xctest.sh` jest read-only i świadomie używa `ps
comm` zamiast pełnej linii poleceń, żeby nie wyciekły argumenty obcego procesu.

---

## Walidacja po zmianach

| Kontrola | Wynik | Rodzaj |
|---|---|---|
| `xcodebuild test -only-testing:MacTornTests` | **PASS — 460/460**, 0 failed, 0 skipped (baseline 432; +28 nowych testów) | automatyczna |
| `bash scripts/coverage-gate.sh … 80` | patrz niżej | automatyczna |
| `xcodebuild analyze` | patrz niżej | automatyczna |
| `xcodebuild build -configuration Debug` | **BUILD SUCCEEDED**, zero ostrzeżeń | automatyczna |
| `gitleaks git` (pełna historia, nowa konfiguracja) | **PASS** — 132 commity, `no leaks found` | automatyczna |
| `git check-ignore` na odtrackowanych archiwach | **PASS** — cztery pliki dopasowane przez `.gitignore` | automatyczna |
| `xcodebuild test -only-testing:MacTornUITests` | **NIEWYKONANE** — przerwane na prośbę Pawła | — |
| Wygląd, VoiceOver, Reduce Motion, Reduce Transparency na żywo | **NIEWERYFIKOWANE** — aplikacja nie była uruchamiana | — |

Rozgraniczenie jest twarde: wszystko, co dotyczy renderowania, mowy VoiceOver i realnych
ustawień systemowych, pozostaje **niezweryfikowane w tym środowisku**. Poprawki A-01, A-03,
U-01 i U-02 mają potwierdzoną kompilację i logikę, ale nie potwierdzony wygląd.

---

## Ograniczenia audytu

1. Zestaw testów UI nie został uruchomiony (decyzja Pawła, XCUITest przejmuje ekran).
   **To jest bramka, którą trzeba przejść przed wydaniem** — zwłaszcza że zmieniono
   `ContentView`, `SettingsView`, `WatchlistView`, `ForumWatchView`, `StatusView`,
   `FactionView`, `MoneyView`, `AttacksView` oraz fixture harnessu.
2. Aplikacja nie była uruchamiana wizualnie — żadna obserwacja o wyglądzie, kontraście,
   przycięciu treści czy zachowaniu sheetów nie jest w tym raporcie potwierdzona.
3. Status CVE dla Sentry Cocoa 9.23.0 niesprawdzony (brak zapytania sieciowego).
4. C-04 (kotwiczenie czasu) potwierdzone statycznie; realnej skali rozjazdu nie zmierzono.
5. C-07 (wyścig `isLoading`) wywnioskowane ze ścieżek anulowania, nie potwierdzone
   runtime'owo.
6. Nie sprawdzono, czy 403/404 faktycznie występuje w produkcji ani jak często —
   warto zajrzeć w `endpointHealth` po kilku dniach działania.
