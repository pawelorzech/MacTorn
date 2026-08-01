# MacTorn — ocena UX i rekomendacje

Data: 2026-08-01
Wersja: 1.11.1
Zakres: przegląd heurystyczny warstwy widoków, przejście głównych ścieżek jako persony,
inspekcja kontraktów dostępności w kodzie.

Fakty i lokalizacje są w `AUDIT_REPORT.md`. Ten dokument zawiera oceny i rekomendacje —
czyli rzeczy, co do których można się ze mną nie zgodzić.

**Zastrzeżenie metodologiczne, które trzeba czytać przy każdej ocenie niżej:** aplikacja
nie została uruchomiona w tym przebiegu. Wszystko, co dotyczy wyglądu, kontrastu,
przycięcia treści i mowy VoiceOver, jest wywnioskowane z kodu, nie zaobserwowane. Oceny
liczbowe są w związku z tym oceną *kontraktu zapisanego w kodzie*, nie doświadczenia.

---

## Ocena ogólna

MacTorn dobrze realizuje swoją podstawową obietnicę: rzut oka na pasek menu mówi, czy coś
się dzieje, a dwa kliknięcia wystarczą do dowolnego modułu. Nawigacja `Now / Account /
Watch`, skróty `⌘1…⌘7`, Undo z sześciosekundowym oknem, walidacja progu ceny zachowująca
błędny input, wspólny komponent stanów modułu — to jest robota na poziomie, którego nie ma
większość aplikacji menu-bar.

Słabym punktem nie jest brak mechanizmów, tylko **niekonsekwencja w ich stosowaniu**. Ten
sam projekt zawiera wzorcowy pasek postępu z pełną semantyką dostępności
(`ProgressBarView.swift:66`) i pasek postępu lotu zrobiony z dwóch prostokątów bez żadnej
semantyki (`TravelView.swift:61`). Zawiera prawdziwy stan pusty w Stocks i „Loading…" bez
końca w Faction. Zawiera świetne, ludzkie komunikaty błędów w `TornAPIError.swift:111` i
gołe „HTTP Error: 502" na ścieżkach, które ich nie używają.

To jest dobra wiadomość: nie trzeba niczego wymyślać, trzeba dokończyć rozprowadzanie
wzorców, które już istnieją.

### Ocena heurystyczna

Skala 1–5. W nawiasie zmiana względem oceny z 2026-07-30 — obniżki wynikają z ustaleń,
których poprzedni przebieg nie wykrył, nie z regresji w kodzie.

| Kryterium | Ocena | Uzasadnienie |
|---|---:|---|
| Widoczność stanu systemu | 3,8 (−0,9) | Wspólny `ModuleStateView` i freshness per endpoint są dobre, ale trzy moduły pokazują „Loading…" w nieskończoność zamiast stanu, a dwa ekrany potrafią wyświetlić dwa sprzeczne komunikaty naraz. **Alert chainu przez cały czas nie działał** — to najgorszy możliwy przypadek niewidoczności stanu: system milczał, a użytkownik miał podstawy sądzić, że jest pilnowany. |
| Dopasowanie do modelu użytkownika | 4,6 | Terminologia zgodna z Tornem, Quick Travel rozróżnia Standard i Airstrip. |
| Kontrola i odwracalność | 4,3 (−0,3) | Undo watchlisty i forum jest wzorcowe. Minus za „Clear" progu alertu bez Undo i za zablokowany Quit podczas pierwszego ładowania (naprawione). |
| Spójność | 3,9 (−0,6) | Wzorce istnieją, ale są stosowane wybiórczo — patrz przykłady wyżej. |
| Zapobieganie błędom | 4,4 (−0,2) | Walidacja jest dobra. Minus za brak blokady podwójnego zapisu klucza i za nieunieważniany wynik „Test Connection" (oba naprawione). |
| Rozpoznawanie zamiast pamiętania | 4,0 (−0,6) | Grupy i skróty działają, ale ustawienia dostępności i wyglądu są pod etykietą „Startup", gdzie nikt ich nie poszuka. |
| Efektywność dla regularnego gracza | 4,5 (−0,2) | `⌘R`, `⌘,`, `⌘1…⌘7` pokrywają podstawy. Minus za watchlistę ograniczoną do sześciu zaszytych przedmiotów. |
| Minimalizm i hierarchia | 4,3 | Nawigacja grupowa realnie zmniejszyła gęstość w 320 pt. |
| Obsługa błędów | 3,6 (−1,0) | Ostatnie dobre dane przeżywają błąd przejściowy — z jednym wyjątkiem, który był najgorszy z możliwych: 403/404 kasował cały snapshot i obwiniał klucz (naprawione). Komunikaty na kilku ścieżkach są w języku programisty i mają mniejszą wagę wizualną niż zwykły tekst. |
| Dostępność | 2,9 (−1,3) | Tu jest największa różnica względem poprzedniej oceny. Pięć zakładek nie ma **ani jednego** modyfikatora dostępności, wynik ataku jest przekazywany wyłącznie kolorem i ikoną, a etykieta w pasku menu — jedyna zawsze widoczna powierzchnia — nie miała żadnej semantyki (naprawione). Poprzednia ocena 4,2 opierała się na tym, że mechanizmy AX *istnieją*; nie sprawdzono, ilu miejsc nie objęły. |

**Średnia: 4,03 / 5** (poprzednio 4,55).

Obniżka nie oznacza, że produkt się pogorszył. Oznacza, że poprzednia ocena mierzyła
obecność mechanizmów, a ta mierzy ich pokrycie.

---

## Przejście ścieżek jako persony

**Nowy użytkownik.** Dostaje od razu ekran Settings z sześcioma zakładkami i polem
`SecureField`. Nie ma zdania mówiącego, czym jest ta aplikacja ani jakiego klucza
potrzebuje. Informacja o wymaganym poziomie dostępu i zapewnienie „klucz trafia do
Keychaina, dane nie opuszczają Maca" — czyli dokładnie te argumenty, które zdejmują opór
przed wklejeniem klucza do nieznanego programu — siedzą w domyślnie zwiniętej sekcji
`DisclosureGroup("API Data Usage")` w zakładce Privacy. To jest największa strata na
ścieżce do pierwszej wartości.

**Gracz bez frakcji.** Do tego audytu widział „Loading faction data…" w nieskończoność.
Naprawione, ale to jest przykład ogólniejszego wzorca: aplikacja zakładała, że każdy jej
użytkownik ma pełen zestaw danych.

**Gracz polegający na alercie chainu.** Nie dostawał go nigdy. Aplikacja reklamuje „Chain
timer with timeout warning" i „Smart Notifications: … chain expiring". To nie jest kwestia
UX w sensie estetycznym — to obietnica, której produkt nie dotrzymywał.

**Użytkownik VoiceOver.** Ikona w pasku menu była czytana jako ciąg glifów. Po wejściu do
okna pięć z dziewięciu zakładek to niepowiązany strumień pojedynczych tekstów i nazw
symboli SF. Przycisk Retry — jedyna droga wyjścia z błędu — traci nazwę, bo
`ModuleStateView` scala dzieci i nadpisuje etykietę tekstem statusu. To nie jest
„aplikacja z brakami w dostępności", to aplikacja, której główne moduły są dla tej persony
nieczytelne.

**Użytkownik z deuteranopią.** Lista ataków jest dla niego bezużyteczna: wygrana i
przegrana różnią się wyłącznie kolorem ikony, a słowo `result` („Attacked", „Mugged",
„Hospitalized", „Lost") nigdy nie trafia na ekran, mimo że jest w modelu.

**Użytkownik na wolnym łączu.** Do tego audytu miał martwy popover bez wyjścia podczas
pierwszego ładowania — `.disabled` obejmowało też stopkę z Quit, a domyślny timeout
`URLSession` to 60 s. Naprawione.

**Użytkownik zmieniający klucz.** Mógł kliknąć „Test Connection" dla klucza A, wpisać
klucz B, zobaczyć nadal zielone „✓ Full Access · ID 123456" i zapisać B w przekonaniu, że
został zweryfikowany. Naprawione.

---

## A. Quick wins

Małe, tanie, niskiego ryzyka. Kolejność według `Priority score = Impact × Confidence / Effort`.

| # | Rekomendacja | Problem użytkownika | Impact | Effort | Confidence | Risk | Score |
|---|---|---:|---:|---:|---:|---:|
| A1 | Wynik ataku jako **tekst** obok nazwy przeciwnika + `accessibilityLabel` na wierszu | Lista ataków jest nieczytelna dla osób nierozróżniających kolorów; dane są w modelu, tylko nie trafiają na ekran | 5 | 1 | 5 | 1 | **25,0** |
| A2 | `.accessibilityLabel` na `ProgressView` w Faction (OC, wojna rankingowa) | VoiceOver ogłasza „62 procent" bez informacji, czego dotyczy | 4 | 1 | 5 | 1 | **20,0** |
| A3 | `ModuleStateView`: `.combine` → `.contain`, żeby przycisk Retry zachował nazwę | Jedyna droga wyjścia z błędu jest bezimienna, w 8 z 9 zakładek | 5 | 1 | 4 | 2 | **20,0** |
| A4 | `.padding(4).contentShape(Rectangle())` na przyciskach ikonowych w listach | Klikalny jest wyłącznie glif ~11 pt; trafienie wymaga precyzji | 4 | 1 | 4 | 1 | **16,0** |
| A5 | Treść błędu wątku forum pod tytułem, nie tylko w tooltipie `.help` | Bez myszy użytkownik widzi żółty trójkąt i nie ma jak poznać przyczyny | 4 | 1 | 4 | 1 | **16,0** |
| A6 | Zamienić `.foregroundColor(.secondary)` na `.primary` w `errorSection` i dodać CTA „Otwórz ustawienia" przy błędach klucza | Błąd ma mniejszą wagę wizualną niż zwykły tekst i nie prowadzi donikąd | 4 | 1 | 4 | 1 | **16,0** |
| A7 | Zmapować cztery surowe `errorMsg` na `TornAPIError.userMessage` | „HTTP Error: 502" i „Failed to decode user data" nic nie mówią; dobre komunikaty już istnieją obok | 4 | 1 | 4 | 2 | **16,0** |
| A8 | `.accessibilityAddTraits(.isModal)` na obu nakładkach | Kursor VoiceOver wchodzi „pod" pytanie wymagające odpowiedzi | 3 | 1 | 4 | 1 | **12,0** |
| A9 | Wydzielić sekcję „Appearance" (wygląd + przezroczystość + przeglądarka) z „Startup" | Nikt nie szuka ustawień dostępności pod etykietą „Startup" | 4 | 2 | 4 | 1 | **8,0** |
| A10 | Zamienić dosłowny `Color.gray` na `.secondary` / `Color(nsColor:)` w komponentach listowych | Szary nie adaptuje się między jasnym a ciemnym motywem | 3 | 1 | 3 | 1 | **9,0** |
| A11 | Inna ikona dla zakładki Watchlist (Stocks i Watchlist mają tę samą) | Nie da się ich odróżnić wzrokowo w pasku grup i w menu | 2 | 1 | 5 | 1 | **10,0** |
| A12 | Usunąć albo wyrenderować nieużywany parametr `icon` w komponentach cooldownu | Sugeruje funkcję, której nie ma; ikona byłaby dodatkowym, niekolorowym nośnikiem znaczenia | 2 | 1 | 5 | 1 | **10,0** |

---

## B. Średni zakres

| # | Rekomendacja | Problem użytkownika | Impact | Effort | Confidence | Risk | Score |
|---|---|---:|---:|---:|---:|---:|
| B1 | **Dokończyć dostępność pięciu zakładek** (Attacks, Faction, Money, Properties, Stocks + 5 komponentów): `accessibilityElement(children: .combine)` na wierszach-kartach, jawne etykiety, `accessibilityHidden(true)` na ikonach dekoracyjnych | Główne moduły są dla użytkownika VoiceOver niepowiązanym strumieniem tekstów | 5 | 3 | 5 | 2 | **8,3** |
| B2 | **Zakotwiczyć wszystkie odliczania w `server_time`** (C-04) — przechować offset zegara serwera przy parsowaniu snapshotu i odejmować go w pięciu miejscach w modelach | Przy rozjeździe zegara Maca użytkownik widzi w jednym UI dwa różne czasy: cooldowny poprawne, travel/hospital/jail spóźnione. „Arrived" pojawia się później niż lądowanie w grze | 5 | 3 | 5 | 3 | **8,3** |
| B3 | **Persystentne latche dla alertów progowych i cooldownowych** (C-05) — z zasianiem przy pierwszym snapshocie bez wysyłania | Restart aplikacji tuż przed końcem cooldownu gubi alert bezpowrotnie; to jest główna funkcja produktu | 5 | 3 | 4 | 3 | **6,7** |
| B4 | **Pole „Item ID" w watchliście** obok siatki popularnych, na wzór `ForumWatchView.addThread()` | Moduł nazywa się „Price Watch", a obsługuje 6 z ~1000 przedmiotów Torna | 4 | 2 | 5 | 1 | **10,0** |
| B5 | **Ekran powitalny przy pustym kluczu** — dwa zdania o aplikacji, jawnie „potrzebujesz klucza z dostępem Limited", jawnie „klucz trafia do Keychaina, nic nie opuszcza tego Maca"; picker sekcji ukryty do czasu zapisania klucza | Najdłuższy odcinek drogi do pierwszej wartości; argumenty zdejmujące opór są schowane w zwiniętej sekcji | 4 | 2 | 4 | 1 | **8,0** |
| B6 | **Jedno źródło komunikatu o stanie modułu** — usunąć lokalne „Loading…" i `errorSection` tam, gdzie działa już `ModuleStateView` | Dwa sprzeczne komunikaty naraz na jednym ekranie | 4 | 2 | 4 | 2 | **8,0** |
| B7 | **Debounce na `refreshNow()`** (C-06) — minimalny odstęp na ścieżce `force`, bez kasowania timera; z wyjątkiem dla pierwszego odświeżenia po zapisaniu klucza | Przytrzymane ⌘R generuje serię żądań, z których żadne nie zdąży opublikować danych | 3 | 2 | 5 | 2 | **7,5** |
| B8 | **Persystentny dedup bounty + agregacja** (C-08) | N otwartych bounty = N osobnych bannerów przy każdym starcie aplikacji | 3 | 2 | 5 | 2 | **7,5** |
| B9 | **Granulacja minutowa etykiet AX w `TimelineView`** (A-09) — osobny, wolniejszy strumień dla dostępności | Etykieta zmieniana co sekundę zwykle powoduje ciągłe re-anonsowanie i uniemożliwia odczytanie reszty ekranu | 4 | 2 | 3 | 2 | **6,0** |
| B10 | **Undo dla „Clear" progu alertu cenowego** | Niespójność: usunięcie pozycji ma pełne Undo, skasowanie progu nie ma nic | 2 | 2 | 5 | 1 | **5,0** |

---

## C. Eksperymenty — wartość niepewna, wymagają walidacji

| # | Hipoteza | Jak zwalidować |
|---|---|---|
| C1 | Ujednolicenie wysokości zakładek (dziś tylko Status ma `maxHeight: 480`) zmniejszy wrażenie „skaczącej" stopki | Zrzuty ekranu wszystkich dziewięciu zakładek przy `height: 640`, porównanie pozycji stopki. Może się okazać, że różnica jest niezauważalna |
| C2 | `DiagnosticsView` (sheet 380 pt) w oknie 320 pt jest przycięty lub wychodzi poza krawędź ekranu przy ikonie w prawym rogu | Otworzyć na Macu z ikoną w prawym rogu paska menu i na wąskim ekranie. Jeśli działa — zostawić, jeśli nie — zamienić na pełnoekranową nawigację wewnątrz okna |
| C3 | Przy powiększonym tekście systemowym sztywne `320×640` + 16× `lineLimit(1)` ucina treść zamiast ją przełamywać | Włączyć powiększenie tekstu w macOS, przejść wszystkie zakładki. Dopiero wynik decyduje, czy warto ruszać layout |
| C4 | Menu-bar variant „Next Action" (J-02 z poprzedniego programu) realnie skraca czas do decyzji | Prototyp za flagą, tydzień używania przez Pawła. Ryzyko: pasek menu ma już własną logikę priorytetów, dołożenie drugiej może dawać sprzeczne sygnały |
| C5 | Twarde gating modułów na podstawie `keyInfo` (ISC-16.1) pomaga bardziej, niż szkodzi | Odłożone świadomie i słusznie: gating musi być fail-open, bo użytkownik może nigdy nie kliknąć „Test Connection". Zanim to wrócić, zmierzyć, ilu użytkowników w ogóle uruchamia Test Connection |

---

## D. Odrzucone

| Pomysł | Dlaczego nie |
|---|---|
| Przepisanie warstwy widoków na inny wzorzec nawigacji | Obecna nawigacja `Now / Account / Watch` działa i jest przetestowana. Problemem jest pokrycie wzorców dostępności, nie architektura nawigacji. Przepisanie skasowałoby istniejące pokrycie testowe bez rozwiązania realnego problemu |
| Notaryzacja i Developer ID | Wymaga płatnego programu Apple. Paweł podjął decyzję odwrotną (T16-A / ISC-25). Zamiast tego tani krok pośredni: publikować SHA-256 artefaktów w release notes, żeby weryfikacja była w ogóle możliwa |
| Certificate pinning dla `api.torn.com` | Udokumentowane jako świadomie przyjęte ryzyko (F-05). ATS w trybie domyślnym już wymusza HTTPS; pinning w aplikacji desktopowej jednego użytkownika dokłada koszt utrzymania (rotacja certyfikatów potrafi zabić aplikację) bez realnego zysku w tym modelu zagrożeń |
| Zbieranie telemetrii użycia (które zakładki, jak często) | Nie ma pytania produktowego, na które ta dana odpowiada, a którego Paweł nie może sobie odpowiedzieć sam — jest jedynym poważnym użytkownikiem tej aplikacji obok społeczności Torna. Zbieranie „na przyszłość" jest sprzeczne z pozycjonowaniem produktu („dane nie opuszczają Maca") i podważyłoby najmocniejszy argument w onboardingu |
| Lokalizacja interfejsu na polski | Torn jest grą anglojęzyczną, terminologia w UI musi zgadzać się z terminologią w grze. Tłumaczenie „chain" albo „nerve" pogorszyłoby dopasowanie do modelu użytkownika |
| Wyodrębnienie `TornAPIClient` i dalszy rozkład `AppState` (ISC-22) | `AppState` ma dziś ~390 linii fasady i pięć wydzielonych serwisów. Cel został osiągnięty; dalszy podział byłby refaktorem dla refaktoru, przy realnym ryzyku regresji w ścieżce anulowania i tożsamości konta, która jest najdelikatniejszą częścią tego kodu |
| Podpięcie `RetryPolicy` pod wszystkie błędy retryable | Kuszące, bo typ już istnieje i jest przetestowany, ale przy cadence 15–120 s aplikacja i tak się podnosi przy następnym ticku. Dodanie drugiej warstwy ponawiania nad istniejącym timerem to ryzyko podwojenia ruchu w aplikacji, która pilnuje budżetu API. **Rekomendacja: usunąć martwy typ i akapit nagłówka, a nie podpinać** |

---

## Metryki

Produkt jest lokalny i nie zbiera telemetrii — i tak ma zostać. Poniższe metryki są
możliwe do odczytania **bez wysyłania czegokolwiek**, z ekranu Diagnostics i z lokalnych
liczników.

| Metryka | Skąd | Po co |
|---|---|---|
| Liczba żądań/min i /dzień per kategoria | `PollingCoordinator`, ekran Diagnostics | Pilnuje, czy zmiany (np. debounce z B7) faktycznie zmniejszają ruch |
| Rozkład `errorClass` per endpoint | `EndpointHealthTracker`, ekran Diagnostics | Odpowiada na pytanie z ograniczeń audytu: czy 403/404 w ogóle występuje i jak często |
| Odsetek pollingów kończących się `.ok` | `EndpointHealthTracker` | Prosty wskaźnik „czy aplikacja robi to, po co jest" |
| Latencja p50/p95 per endpoint | `EndpointHealthTracker` | Wykrywa degradację po stronie Torna, zanim użytkownik ją zgłosi |
| Czy alert chainu kiedykolwiek wystrzelił | `NotificationCoordinator` (latch `chain.expiring`) | **Najważniejsza metryka po tym audycie.** Do dziś odpowiedź brzmiała „nigdy" i nikt tego nie zauważył. Warto sprawdzić po pierwszym tygodniu |
| Liczba kluczy odrzuconych trwale (kody 2/16/18) | `endpointHealth` | Mierzy, czy onboarding klucza działa |

Nie proponuję: śledzenia, które zakładki są otwierane, czasu spędzonego w aplikacji ani
niczego, co wymagałoby wysłania danych z Maca.

---

## Roadmapa

**Najbliższy patch (1.11.2) — już zrobione, wymaga tylko przejścia bramki UI**

Naprawy z tego audytu: martwy alert chainu, utrata watchlisty przy uszkodzonym blobie,
403/404 kasujący snapshot, dostępność paska menu, „Loading…" bez końca, zablokowany Quit,
nieunieważniany Test Connection, cicha odmowa duplikatu, Reduce Motion, systemowe Reduce
Transparency, bramka schematów URL, bramka autora w workflow Claude.

**Kolejne wydanie (1.12) — dokończyć rozprowadzanie wzorców**

Wszystkie quick winy z sekcji A (A1–A12) plus B1 (dostępność pięciu zakładek), B4 (pole
Item ID), B5 (ekran powitalny), B6 (jedno źródło komunikatu o stanie). To jest wydanie „to,
co już umiemy, wszędzie tam, gdzie jeszcze tego nie ma".

**Większe wydanie (1.13) — czas i niezawodność alertów**

B2 (kotwiczenie wszystkich odliczań w `server_time`) i B3 (persystentne latche alertów) —
dwie zmiany o realnym ryzyku regresji, które zasługują na własny przebieg z testami na
`MutableTimeSource` i własną turę QA. Do tego B7 i B8. Sprzątanie: C-09 (usunąć martwy
`RetryPolicy`), C-10 (wstrzykiwana sesja w `UpdateManager`), B-02 (bumpować numer builda).

**Do walidacji przed decyzją**

C1–C5 z sekcji C. Żadnego z nich nie warto implementować przed zobaczeniem wyniku pomiaru.

---

## Manual QA — lista przed publikacją

Kolejność od najbardziej ryzykownego. Pierwsze trzy pozycje są **blokujące**, bo dotyczą
kodu zmienionego w tym audycie i nieprzetestowanego wizualnie.

- [ ] **Uruchomić zestaw testów UI** (`make test-ui`, 8 testów) — nie został uruchomiony
      w tym przebiegu, a zmieniono `ContentView`, `SettingsView`, `WatchlistView`,
      `ForumWatchView`, `StatusView`, `FactionView`, `MoneyView`, `AttacksView` i fixture
      harnessu (usunięty zmyślony klucz `chain`).
- [ ] **Alert chainu na żywo** — z prawdziwym kluczem, przy aktywnym chainie z timeoutem
      spadającym poniżej 60 s. To jest funkcja, która nie działała nigdy; jej pierwsze
      zadziałanie musi zostać zobaczone, nie założone.
- [ ] **Karta chainu w zakładce Status i wpis chain w Next Action** — obie czytają teraz
      `liveChain`; sprawdzić, że pokazują to samo co zakładka Faction.
- [ ] Pierwsze uruchomienie na wolnym łączu: Quit i Settings muszą być klikalne podczas
      nakładki „Loading Torn Data…".
- [ ] Gracz bez frakcji (albo klucz bez dostępu do frakcji): zakładka Faction pokazuje
      komunikat o stanie, nie „Loading…".
- [ ] Zmiana klucza: wpisać klucz A, „Test Connection", zielony wynik; wyczyścić pole,
      wpisać klucz B — zielony wynik musi zniknąć.
- [ ] Dodanie do watchlisty przedmiotu, który już na niej jest: panel zostaje otwarty i
      pokazuje powód.
- [ ] Systemowe **Reduce transparency** włączone przed startem aplikacji → solidne tła bez
      dotykania przełącznika w aplikacji. Następnie przełączyć w trakcie działania → UI
      musi zareagować bez restartu.
- [ ] Systemowe **Reduce motion** → baner Undo i panele dodawania pojawiają się bez
      wjeżdżania z góry.
- [ ] VoiceOver na ikonie w pasku menu w każdym stanie: podróż, szpital, więzienie,
      cooldown, brak licznika.
- [ ] Uszkodzenie blobu watchlisty (ręcznie w `UserDefaults`), restart, poczekać na cykl
      odświeżenia cen → oryginalny blob musi przetrwać pod kluczem `watchlist`, a kopia
      wylądować pod `watchlist.unreadable`.
- [ ] Powiadomienia: uprawnienie, treść, kliknięcie.
- [ ] Launch at Login po wylogowaniu i zalogowaniu.
- [ ] Dwa rzeczywiste konta A→B.
- [ ] Rzeczywisty Full Keyboard Access.
- [ ] Universal Release: `make release && make verify-release`.
