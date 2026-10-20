# MacTorn — analiza optymalizacyjna

Data: 2026-09-20
Zakres: `MacTorn/` (produkcja), bez `Archive/`. Testy nietknięte.
Baza: 16 538 linii kodu produkcyjnego, 13 475 linii testów, 793 funkcje testowe.

Cel: mniej kodu, mniej błędów, szybsze działanie, prostsze utrzymanie.
Zasada: **żaden test nie jest usuwany ani osłabiany**. Każda zmiana musi przejść `make test`.

---

## 0. STATUS WDROŻENIA (2026-09-20)

Wdrożone i zweryfikowane (`make test` ✅, `make coverage-gate` ✅ 88.89% PollingCoordinator):

**Faza 1 — quick wins**
- `TornFormatter`: dodane `clock`, `minutesSeconds`, `coarseDuration`, `compactETA`,
  `relativeDate`, `formatMoney(Int?)`. Usunięto **11 kopii** `formatTime`/`formattedTime`/
  `formatShortTime` z `MacTornApp`, `StatusView`, `TravelView`, `FactionView`,
  `StatusBadgesView`, `ChainView`, `NextActionView`.
- `openTorn(_:)` — jeden helper zamiast **7 kopii** `openURL` (Watchlist, Money, Properties,
  Stocks, Attacks, ForumWatch, Faction).
- `formatMoney(Int?)` — jeden formater zamiast 4 kopii (Money, Properties ×2, Stocks).
- `ChainUrgency` w modelu — jedna definicja progów 60/180 s zamiast 3 kopii; `FactionView`
  używa teraz `ChainView` zamiast własnej karty łańcucha.
- `CooldownItem`/`LiveCooldownItem` współdzielą `CooldownCell` (były byte-for-byte identyczne).
- Usunięty martwy kod: `MenuBarLabel.flagForDestination`, `SoundManager.playForEvent`,
  `NotificationManager.cancelNotification`, `pauseRowSource`, `isSelfHealing`,
  `TornEndpointRegistry.optional`, `OrganizedCrime2.readyDate`, `AppState.decimalFormatter`,
  `AppState.appearanceMode` (duplikat `@AppStorage`), `AppearanceMode.colorScheme`,
  `TornEndpoint.cachePolicy` + `TornCachePolicy` (pole nigdy nie czytane),
  `MacTornWidgets` `previewFamily` + martwy `#if WIDGET_GALLERY`.
- Usunięte nieużywane importy: `SoundManager` (SwiftUI), `TravelView` (AppKit),
  `NotificationManager` (AppKit), `AppState+Widgets` (WidgetKit).

**Faza 2 — hot-pathy**
- W-1: katalog itemów — `itemCatalogFetchedAt` w pamięci; koniec dekodowania bloba z
  UserDefaults 2×/poll (~11 500/dzień na main actorze).
- W-2: `PollingCoordinator` — `SlidingWindowCounter` (kubełki sekundowe, O(1) amortyzowane)
  zamiast tablic do 86 400 wpisów skanowanych 2–3× na request.
- W-6: `NotificationCoordinator.batched` — ~9 zapisów UserDefaults/poll → 1. Kontrakt
  per-call (i testy) zachowany.
- W-8: `TornEndpointRegistry.endpointsByID` — O(1) lookup w hot-path (był liniowy skan).
- F2: `refreshKeyInfoIfNeeded` sprawdza wiek przed `Task` (koniec ~2 880 alokacji Tasków/dzień).
- F12: forum — brak zapisu UserDefaults co 180 s, gdy nie ma nic do obserwowania.
- F15: `itemCatalog` — lowercased index przebudowywany tylko przy zmianie, nie na każdy keystroke.
- `NextActionCategory.order` — O(1) słownik zamiast `allCases.firstIndex` w komparatorze.
- `AppGroup.group(of:)` — jedno źródło prawdy dla przynależności do grupy.

**Rezultat:** 33 pliki zmienione, −581 / +477 linii (netto ~−100 linii produkcyjnych przy
dodaniu nowych współdzielonych helperów), a przede wszystkim usunięte duplikaty i hot-pathy.

**Świadomie pominięte** (bo testy pinują dokładne zachowanie — zasada „nie osłabiać testów"):
- W-3 (pojedynczy parse snapshotu) — `MoneyData`/`BattleStats`/`PropertyInfo.init(from:)` są
  testowane pod hostile input; przepisanie wymagałoby przepisania tych testów.
- W-4 (cache Next Action) — testy pinują znikający event po `fireAt` przy różnych `now`.
- W-7 (throttle widgetów) — test pinuje republikację świeżego timestampu przy każdym publishu.
- F5 (parallelizacja wars/news) — zmienia kolejność efektów; niższa wartość, wyższe ryzyko.
- Pola modeli tylko test-referenced (Bar.increment, Travel.arrivalDate, itd.).

---

## 1. Podsumowanie

Kod jest dobrej jakości — gęste, wyjaśniające komentarze, solidne testy, świadome decyzje
architektoniczne. Nie ma tu „bałaganu”. Są natomiast trzy konkretne klasy problemów:

| Klasa | Skala | Główny efekt |
|---|---|---|
| **Martwy / nieużywany kod** | ~64 znaleziska, ~1 200–1 800 linii | więcej powierzchni na błędy, mylące API |
| **Zduplikowana logika** | 5 klastrów, ~23 duplikaty (w tym 11× `formatTime`) | poprawka w jednym miejscu nie działa w pozostałych |
| **Praca w pętli odpytywania** | 8 realnych hot-pathów | ~5–11 tys. zbędnych dekodowań JSON/dzień, 9 zapisów UserDefaults/poll, O(n) skany |

Największe zwycięstwa to nie „refaktor dla refaktoru”, tylko:
**jedna prawda dla jednej rzeczy** (formatowanie, kolor łańcucha, wzorzec backoff) oraz
**przestanie robić drogą pracę w każdej pętli** (dekodowanie cache, sortowanie timeline'u, zapisy preferencji).

---

## 2. Wydajność — realne koszty (zweryfikowane)

### W-1. Cache katalogu itemów dekodowany z UserDefaults w każdej pętli — **krytyczne**
`ViewModels/AppState+ItemCatalog.swift:66-72` (`itemCatalogIsStale`) i `:135-138` (`cachedCatalogItems`).

`triggerItemCatalogFetchIfNeeded()` jest wołane co tick (`AppState+PollingUserFetch.swift:122`)
i po każdym udanym `fetchData` (`:605`). Predykat „stale” **dekoduje cały blob JSON** (z listą
sklepów dla ~1500 itemów) z UserDefaults na głównym aktorze, ~2× na poll. Przy 15 s: ~11 500
dekodowań/dzień i widoczne przycięcia klatki.

**Fix:** trzymać `itemCatalogFetchedAt` w pamięci (jedna `Date?`), `UserDefaults` dotykać tylko
przy ładowaniu i po udanym fetchu. ~10 linii mniej, zero dekodowań w pętli.

### W-2. `PollingCoordinator` — O(n) skany tablic na każdy request
`Utilities/PollingCoordinator.swift:34-35, 52-55, 73-83, 102-112`.

`requestTimestamps` rośnie do ~86 400 wpisów (dzień przy 1 req/s), a `prune()` i `count()`
skanują całą tablicę. `denial()` + `canMakeRequest()` = 2–3 pełne skany na każdy request,
3–6 requestów na poll, wszystko na main actor.

**Fix:** pierścień / liczniki kubełkowe per minuta — O(1) amortyzowane. Usuwa też `softTargetPerMinute`
(używanego tylko w testach) i `recordEvents` na rzecz `[kategoria: licznik]`.

### W-3. `UserSnapshotService.parseSnapshot` parsuje ten sam payload dwa razy
`ViewModels/UserSnapshotService.swift:93-145` i `:271-279`.

- parse #1: `JSONSerialization.jsonObject`
- parse #2: `JSONDecoder().decode(TornResponse.self)`
- każdy `StockHolding`: `JSONSerialization.data` → `JSONDecoder().decode` (round-trip per akcja)

To dominujący koszt CPU każdego polla. Działa w `Task.detached`, więc nie blokuje UI, ale zjada baterię.

**Fix:** jedno `JSONDecoder` na payload; pola pomocnicze (`money`, `battlestats`) wyciągnąć z
zdekodowanego `TornResponse`, a akcje dekodować jednym przebiegiem. Usuwa też ręczne
`init(from:)` dla `MoneyData`/`BattleStats`/`PropertyInfo` (`TornModels.swift:551, 577, 1141`)
używane wyłącznie przez testy — ~60 linii.

### W-4. Next Action przebudowywany **co sekundę**
`Views/Components/NextActionView.swift:10-14` + `AppState+LiveNextAction.swift:172-174`.

`nextEvents()` buduje snapshot i **sortuje do ~14 zdarzeń** w każdym ticku 1 Hz, mimo że dane
zmieniają się tylko przy pollu. `NextActionCategory.order` (`NextAction.swift:59`) robi
`allCases.firstIndex(of:)` (skan 16 przypadków) w komparatorze sortowania.

**Fix:** liczyć `[NextEvent]` raz na poll, zapisać w AppState; `TimelineView` tylko formatuje ETA.
`order` → statyczny `[Self: Int]`. Z 86 400 sortowań/dzień do ~2 880.

### W-5. 6 niezależnych `TimelineView` 1 Hz + 1 `Timer` 1 Hz
`StatusView.swift:439, 576`, `FactionView.swift:43, 220`, `ChainView.swift:13`, `NextActionView.swift:10`
oraz `AppState+LiveNextAction.swift:33`.

Gdy Status jest otwarty z aktywnymi cooldownami: ~7 zegarów 1 Hz, każdy unieważnia własny widok.
Brak obsługi `scenePhase` — timer działa też gdy popover zamknięty (menu bar tego wymaga,
ale widoki już nie).

**Fix:** jedno współdzielone źródło „teraz” (np. jeden `TimelineView` opakowujący sekcję albo
`now` publikowane z AppState). Min. dodać `.tolerance` do `Timer`.

### W-6. `NotificationCoordinator` zapisuje cały store do UserDefaults ~9× na poll
`Utilities/NotificationCoordinator.swift:114-140, 165-171` + `AppState+NotificationsFeedback.swift:20-62`.

`shouldFireOnEdge`/`shouldFireOnce` wołają `persistLatches()`/`persistEpochs()`, które kodują i
zapisują cały (do 256 wpisów) store. ~9 wywołań na poll → ~26 000 zapisów/dzień. Dodatkowo
`BoundedRecencyStore.record` robi `order.firstIndex(of:)` (O(256)) przy każdej obserwacji.

**Fix:** jeden `commit()` na koniec `checkNotifications`. `order` → `[String: Int]` indeks.

### W-7. Widget timelines przeładowywane co poll
`AppState+Widgets.swift:28-46`. `publishWidgets()` wołane z 3 miejsc, 100 ms debounce scala burst,
ale i tak raz na poll → ~2 880–5 760 `reloadAllTimelines()`/dzień.

**Fix:** próg czasowy (np. 60 s) i/lub reload tylko gdy `WidgetSnapshot` faktycznie się zmienił.

### W-8. `TornEndpointRegistry.endpoint(id:)` — liniowy skan w hot-path
`Networking/TornEndpoint.swift:418-420`. `all.first { $0.id == id }` wołane 2× per `reserveRequest`
(URL + gate), ~6×/poll. **Fix:** statyczny `[String: TornEndpoint]`.

### Pozostałe (mniejszy zysk, tanie)
- `refreshKeyInfoIfNeeded()` (`AppState+PollingUserFetch.swift:326`) tworzy `Task` co poll, żeby
  sprawdzić wiek — sprawdzić wiek **przed** `Task`.
- `AppState+FactionFetch.swift:75-141` — `wars` i `news` serializowane; mogą iść `async let`.
- `ContentView.swift:175` — `onAppear` w dwóch scenach (`WindowGroup` + `MenuBarExtra`) może
  wystartować podwójny poll; guard na „in-flight”, nie na czas.
- `AppState+MarketForum.swift:306` — `saveForumWatch()` zapisuje 2 bloby co 180 s nawet bez zmian.
- `searchItems` (`AppState+ItemCatalog.swift:227`) — lowercasing całego katalogu na każdy keystroke,
  bez debounce.
- `CompanionViews.swift:172-201` — filtrowanie/sortowanie w `body` + `first(where:)` per wiersz.

---

## 3. Martwy kod do usunięcia

Podział wg tego, czy testy sięgają do symbolu (testy zostają — jeśli symbol istnieje **tylko**
po to, by test go sprawdzał, usunięcie wymaga przeniesienia asercji na zachowanie, nie skasowania testu).

### 3a. Pewne do usunięcia (0 odwołań w testach i produkcji)
| Lokalizacja | Symbol |
|---|---|
| `MacTornApp.swift:224` | `MenuBarLabel.flagForDestination(_:)` |
| `SoundManager.swift:26` | `SoundManager.playForEvent(_:rules:)` |
| `NotificationManager.swift:178` | `cancelNotification(identifier:)` |
| `AppState+PollingUserFetch.swift:199` | `pauseRowSource(_:error:)` |
| `TornEndpointGate.swift:79` | `TornEndpointDenial.isSelfHealing` |
| `TornEndpoint.swift:423` | `TornEndpointRegistry.optional` |
| `TornModels.swift:849` | `OrganizedCrime2.readyDate` |
| `TornModels.swift:999` | `VirusProgramming.secondsRemaining(at:)` |
| `TornModels.swift:457` | `Status.timeRemaining` (wariant bez `at:`) |
| `TornModels.swift:714` | `AttackResult.timeAgo` (wariant bez `at:`) |
| `AppState.swift:512` | `AppState.decimalFormatter` (jest `TornFormatter`) |
| `AppState.swift:121` | `appearanceMode` — duplikat `@AppStorage` w `MacTornApp.swift:7` |
| `AppState.swift:52` | `AppearanceMode.colorScheme` |
| `TornEndpoint.swift:114` | `TornEndpoint.cachePolicy` + `TornCachePolicy` — **pole nigdy nie czytane**, a udaje działające throttling |
| `TornModels.swift:247, 272` | `Travel.arrivalDate`, `Travel.flightProgress` (widok/widget liczą własne) |
| `TornModels.swift:357, 372` | `TornDestination.flightTimeMinutes` / `.flightTimeFormatted` (warianty bez `method:`) |
| `MacTornWidgets.swift:41, 116-121, 157` | `previewFamily` + martwy `#if WIDGET_GALLERY` (flaga nigdzie niezdefiniowana) |

### 3b. Tylko dla testów — usunąć razem z przepisaniem asercji na zachowanie
`TornAPIError.haltsAllRequests/haltsCategoryOnly/disablesEndpoint`, `TornEndpointGate.activePauses()`,
`TornKeyInfo.KeyValidationResult.allCriticalAvailable/unavailableCount`,
`PollingCoordinator.softTargetPerMinute`, `TornEndpointRegistry.critical/markdownTable`,
`Travel.arrivalDate` (test `TravelTests`), `Chain.timeoutRemaining` (test `ChainTests`),
`OrganizedCrime2.isReady` (test), `TornEvent.date` (test), `cachePolicy` (test), `bountiesFetchedAt/CacheDelay`.

> Uwaga: `markdownTable()` generuje tabelę API w README — jeśli kontrakt README ma zostać,
> zostawić; inaczej usunąć razem z `version`/`purpose`/`cadence` w `TornEndpoint`.

### 3c. Nieużywane pola modeli (schema completeness — niższe ryzyko)
`TornResponse.error`/`TornError`, `TornResponse.chain` (jawnie martwe po C-01 — usunięcie
czyni to jawnym), `Bar.increment/interval/ticktime`, `TornMessage.name/type/title/timestamp`,
`OCSlot.position/checkpointPassRate`, `OCSlotUser.joinedAt`, `Refills.specialCount`,
`EducationStatus.complete`, `CurrentEducation.id`, `Bounty.targetName/targetLevel/reason/quantity`,
`RankedWar.start/winner`, `RankedWarFaction.chain`, `FactionNews.timestamp`,
`StockTransaction.timeBought`, `GitHubRelease.body`.

### 3d. Nieużywane importy
`SoundManager.swift:1` (SwiftUI), `TravelView.swift:2` (AppKit), `NotificationManager.swift:3` (AppKit),
`AppState+Widgets.swift:2` (WidgetKit).

**Razem:** ~64 znaleziska, szacunkowo **1 200–1 800 linii** mniej.

---

## 4. Duplikacja do konsolidacji

### D-1. `formatTime` — **11 kopii** (największy dług)
`MacTornApp.swift:234`, `TravelView.swift:24, 401`, `FactionView.swift:178, 288`,
`StatusView.swift:462, 474, 630`, `Components/StatusBadgesView.swift:58`,
`Components/ChainView.swift:78`, `Components/NextActionView.swift:52`.

**Fix:** `TornFormatter.duration(_:)` (+ wariant „spoken”). Usuwa ~10 prywatnych funkcji.

### D-2. `formatMoney(Int?)` — 4 identyczne kopie
`MoneyView.swift:165`, `PropertiesView.swift:76, 196`, `StocksView.swift:114`.
**Fix:** `TornFormatter.formatMoney(_: Int?)` zwracające `"Unavailable"`.

### D-3. `openURL(_:)` — 7 kopii
`WatchlistView:294`, `MoneyView:170`, `PropertiesView:70`, `StocksView:119`,
`AttacksView:172`, `ForumWatchView:193`, `FactionView:188`.
**Fix:** jeden helper w `BrowserManager` / rozszerzeniu `View`.

### D-4. Kolor/opis pilności łańcucha — 3 implementacje tych samych progów 60/180 s
`ChainView.swift:57-64, 69-76` i `FactionView.swift:169-176`.
**Fix:** jeden `ChainUrgency` (kolor + etykieta VoiceOver).

### D-5. Karta łańcucha zaimplementowana dwa razy
`Components/ChainView.swift:11-41` vs `FactionView.swift:42-61`.
**Fix:** `FactionView` ma użyć `ChainView`.

### D-6. `CooldownItem` vs `LiveCooldownItem` — niemal kopie
`StatusView.swift:485-553` vs `:563-640`. `cellContent` identyczne, różni je tylko źródło i `TimelineView`.
**Fix:** jedna view z `endsAt` + `live: Bool`.

### D-7. Wzorzec „karta/plakietka” — ~20 powtórzeń
Ternary `reduceTransparency ? a : b` + `.padding + .background + .cornerRadius` w
`WatchlistView`, `StatusBadgesView`, `CreditsView`, `MoneyView`, `AttacksView`, `ChainView`,
`FactionView`. `CompanionViews.swift:239` ma już lokalny `companionCard()` — wystarczy go uogólnić.
**Fix:** `View.tornCard(tint:)` / `View.tornBadge(tint:)`.

### D-8. Pozostałe wzorce
- 4 warianty „kafelka” (`ActionButton`, `ArmoryButton`, `StatItem`, `destinationButton`) → `TileButton`.
- 4× empty-state → `EmptyStateView`.
- 3× „loading vs brak dostępu” → rozszerzyć istniejące `ModuleStateView`.
- Panel dodawania + undo w Watchlist i Forum → wspólny helper.
- Przynależność do grup zakładek zakodowana 3×: `ContentView.swift:16-22, 54-60` + `ShortcutsManager.swift:55-68`.
- Matematyka procentów paska w 4 miejscach; postęp lotu w 3; clamp OC/war ręcznie zamiast `NumericSafety`.
- `AppState.decimalFormatter` vs `TornFormatter.decimalFormatter` — dwa `NumberFormatter`.
- `RelativeDateTimeFormatter` tworzony per wywołanie (`DiagnosticsView.swift:145, 268`).

### D-9. Powtarzalny `Codable` boilerplate
`(try? container.decode(...)) ?? default` w ~10 modelach; wzorzec `decodeIfPresent ?? shipped`
skopiowany 4× (`TravelNotificationSetting`, `NotificationRule`, `WatchedThread`, `KeyboardShortcut`).
**Fix:** jeden `TolerantDecoding` helper / property wrapper.

---

## 5. Architektura / utrzymanie

- `AppState+PollingUserFetch.swift` (**948 linii**) to „god file” — miesza lifecycle pollingu,
  key-info, politykę błędów, core fetch i 3 niezależne fetchery. Podzielić po istniejących `MARK`:
  `+Polling`, `+KeyInfo`, `+FetchUser`, `+FetchActivity`, `+FetchUserV2`.
- `AppState+MarketForum.swift` (473) — podzielić na `+Watchlist` i `+ForumWatch`.
- `AppState+PersistenceStocks.swift` (208) trzyma też reguły notyfikacji i ustawienia travel —
  nazwa nie zgadza się z zawartością.
- `Chain` vs `FactionChain`: `Chain` to cienki wrapper tworzony tylko przez `liveChain`.
  Można usunąć `Chain` i dać `ChainView` `FactionChain` — jedna warstwa mniej.
- **Reszta podziału na rozszerzenia jest sensowna** — nie konsolidować.

---

## 6. Proponowany plan (fazami, każda faza = zielone testy)

| Faza | Zakres | Zysk | Ryzyko |
|---|---|---|---|
| **1. Quick wins** | D-1, D-2, D-3, 3d (importy), 3a (bezpieczne usunięcia) | ~600–900 linii mniej, spójność | bardzo niskie |
| **2. Hot-path** | W-1, W-2, W-4, W-6, W-7, W-8 | główne zużycie CPU/baterii, brak przycięć | średnie (trzeba testy na backoff/dedup) |
| **3. Duplikacja widoków** | D-4…D-8 | ~400–600 linii mniej, poprawki raz | niskie (wizualne — UI testy) |
| **4. Modele** | 3c + D-9, usunięcie `Chain` | ~300–500 linii mniej | średnie (kontrakty dekodowania) |
| **5. Architektura** | podział god-files | prostsze utrzymanie, mniejsze konflikty | niskie (bez zmian zachowania) |

**Rekomendacja kolejności:** Faza 1 → Faza 2 → Faza 3/4/5 równolegle.
Faza 2 daje największy efekt „działa szybciej”; Faza 1 największy efekt „mniej kodu” przy zerowym ryzyku.

### Bramki
- Po każdej fazie: `make test` (793 testy) zielone. UI: `make test-ui`.
- Faza 2 dodatkowo: pomiar `requestsInLastDay` i czasu polla przed/po.
- Nie ruszać: `coverage-gate` (80% na modułach krytycznych) — usuwanie kodu może wymagać
  przeniesienia asercji, ale próg musi pozostać spełniony.

---

## 7. Czego NIE robić

- Nie usuwać `TornEndpoint` registry ani jego testów — to kontrakt API i README.
- Nie łączyć rozszerzeń `AppState` w jeden plik — obecny podział jest funkcjonalnie spójny.
- Nie usuwać timerów 1 Hz z menu bara — są wymagane; optymalizować widoki, nie źródło czasu.
- Nie usuwać testów „nieużywanych” symboli — przenieść asercje na zachowanie.
