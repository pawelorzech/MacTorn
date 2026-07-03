# MacTorn — Torn API audit + fixes + new v2 features

## Context

Paweł poprosił o dokładny audyt: czy Torn API, z którego korzysta MacTorn, zmieniło się pod nogami, oraz czy są nowe endpointy pod nowe ficzery. Torn aktywnie migruje v1 → v2, więc to realne ryzyko.

**Metoda audytu (zrobione):** ściągnięty żywy OpenAPI spec (`https://www.torn.com/swagger/openapi.json`, wersja **6.0.0**, 205 endpointów), pełny inwentarz pól które MacTorn faktycznie parsuje (2 agenty Explore po `TornModels.swift` / `AppState.swift` / fixtures), oraz **żywe uwierzytelnione calle** kluczem Pawła (z `~/.config/torn/config.json`) żeby zweryfikować spec względem rzeczywistości, nie tylko dokumentacji.

**Werdykt:** API v1 jest **zamrożone (frozen), nie wygaszone (sunset)** — wszystkie selekcje MacTorn nadal działają. Są **2 realne busy** i **4 grupy nowych ficzerów** do dodania (wybór Pawła: pełny zakres).

---

## Findings (audyt — co się zmieniło)

### ✅ Zdrowe (potwierdzone żywym callem)
`user/?selections=basic,bars,cooldowns,travel,profile,events,messages,money,battlestats,attacks,properties,stocks` — **każde** pole które MacTorn czyta jest obecne w żywej odpowiedzi w kształcie v1:
- bars (energy/nerve/happy/life) z `increment/interval/ticktime/fulltime`, `chain` pod userem (`current/maximum/timeout/cooldown`)
- travel (`destination/timestamp/departed/time_left`), cooldowns (`drug/medical/booster`)
- money top-level (`money_onhand/vault_amount/points/cayman_bank/donator`), battlestats, flat `attacks` (`attacker_id/defender_id/result/respect`), properties, stocks (dict), events/messages (dicty)
- faction `basic` (`ID/name/respect`) + `chain` (`current/max/timeout/cooldown`) — OK

**Ważne dlaczego v1 zostaje:** v2 mocno **poprzemianowywał** te pola (`money_onhand`→`wallet`, `marketprice`→`market_price`, travel `timestamp`→`arrival_at`, faction `ID`→`id`, bars v2 zgubił `increment/ticktime/fulltime`). MacTorn **słusznie** trzyma się v1 dla tych danych. Spec ma tylko **2 deprecacje**, obie dot. slotów OC (usunięte 1 czerwca 2026 — już za nami).

### ❌ BUG 1 — Ficzer "Organized Crimes" frakcji jest martwy
`faction/?selections=crimes` po migracji na OC 2.0 zwraca **wyłącznie zamrożoną historię OC 1.0**: 100 ukończonych zbrodni, najnowsza `time_started` = **11 lutego 2025**, **0 aktywnych** (`time_left=0` we wszystkich). Do tego **decode i tak się wywala**: żywe `initiated` to teraz **Int (`1`)**, a MacTorn typuje je jako `Bool` (`OrganizedCrime.initiated: Bool`, non-opt, all-or-nothing `JSONDecoder`) → każda zbrodnia odrzucona → ficzer pokazuje pustkę. Fixture używa `"initiated": false` (Bool), więc **testy są fałszywie zielone**.
- Kod: `TornModels.swift:643-693` (model `OrganizedCrime`/`OCParticipant`), `AppState.swift:1281-1284` (parse), selekcja `TornModels.swift:1022`.

### ⚠️ BUG 2 — Kotwica cooldownów po cichu nie działa
MacTorn kotwiczy odliczanie drug/medical/booster na top-level `timestamp` (`decoded.serverTimestamp`), ale **żywa odpowiedź nie zawiera `timestamp`** — zawiera `server_time`. Więc `serverTimestamp == nil` i kod spada na fallback do **lokalnego zegara Maca** (`AppState.swift:1209`), co przeczy jawnej intencji z komentarza ("match torn.com even if the Mac clock is skewed"). W praktyce łagodne (Mac zwykle NTP-synced), ale zamierzone zachowanie nie zachodzi nigdy.
- Kod: `TornModels.swift:31/39` (`serverTimestamp` ← klucz `"timestamp"`), użycie `AppState.swift:1209`.

### Test blind spots
- Fixture OC 1.0 (`TornAPIFixtures.swift:287-298`): `initiated: false`, `planner_id`/`planner_name` — nie pasuje do żywego kształtu (`initiated:1`, `planned_by`/`initiated_by`, brak `planner_*`).
- Brak fixtures dla `battlestats`/`properties` mimo że są parsowane; brak testu na Int-`initiated`.

---

## Zmiany do wykonania

### Część A — Fixy (obowiązkowe)

**A1. Kotwica cooldownów → `server_time`** (one-liner, największy stosunek wartości do ryzyka)
W `TornResponse` zmapować `serverTimestamp` na obecny w odpowiedzi klucz `server_time` (z fallbackiem na `timestamp` dla kompatybilności): `AppState.swift:1209` zacznie dostawać realny czas serwera. Reużyć istniejącej ścieżki `CooldownEnds.from(cooldowns:anchor:)` (`TornModels.swift:123`) — bez zmian w logice, tylko źródło anchora.

**A2. Martwe OC frakcji → usunąć parse OC 1.0 + zdjąć `crimes` z selekcji**
- Usunąć `crimes` z `faction/?selections=basic,chain,crimes` → `basic,chain` (`TornModels.swift:1022`), skasować parse OC 1.0 (`AppState.swift:1281-1284`) i model `OrganizedCrime`/`OCParticipant` (`TornModels.swift:643-693`) — zastąpione przez B1 (własne OC 2.0).
- Zaktualizować/zastąpić `OrganizedCrimeTests.swift` testami OC 2.0; naprawić fixture; dodać regresję dekodującą `initiated` jako Int.

### Część B — Nowe ficzery (wszystkie 4 wybrane przez Pawła)

**Architektura:** żywy call potwierdził, że **v2 przyjmuje łączone selekcje w jednym callu** — jeden dodatkowy request `GET /v2/user?selections=organizedcrime,refills,education,bounties` obsługuje B1–B3 naraz. Nowy builder w enumie `TornAPI` (`TornModels.swift:1000-1041`), parse przez `JSONSerialization` (spójne z istniejącym stylem v2 dla market/forum), detekcja błędów przez istniejące `tornAPIErrorMessage` (`TornModels.swift:1073`). Refille/edukacja zmieniają się wolno → można pollować rzadziej niż główny tick.

**B1. Własne OC 2.0 (readiness)** — `GET /v2/user?selections=organizedcrime` (`organizedCrime`, oneOf `FactionCrime`|błąd|null)
Żywy kształt: `id, name, difficulty, status, created_at, planning_at, ready_at, executed_at, expired_at, previous_crime_id, slots[], rewards`. Menu bar / zakładka: **„OC ready in Xh"** z `ready_at` (jak istniejący timer travel), `status`, `name`. To realny następca zabitego ficzera OC. Model `OrganizedCrime2` + widok w `FactionView.swift` (lub nowy `OrganizedCrimeView`).

**B2. Dzienne refille + edukacja** — te same selekcje `refills`,`education`
- `refills`: `{energy:Bool, nerve:Bool, token:Bool, special_count:Int}` → nudge „Energy refill: dostępny/zrobiony".
- `education`: `{complete:[Int], current: {id, until}|null}` → gdy `current != null`, timer „Edukacja: kończy się za …" (jak cooldown). Gdy null — kurs nie trwa.
- Model `Refills`, `EducationStatus`; widok w `StatusView.swift` lub nowy „Dailies".

**B3. Bounties na Ciebie** — selekcja `bounties`
Żywy kształt (pusty teraz): `Bounty { target_id, target_name, target_level, lister_id, lister_name (null gdy anon), reward:Int, reason, quantity:Int, is_anonymous:Bool, valid_until:Int }`. Alert bezpieczeństwa „⚠️ Bounty na Tobie: $X" gdy tablica niepusta (filtruj `target_id == player_id`). Podpiąć pod istniejący `NotificationManager` + regułę powiadomień (`NotificationRule`, `TornModels.swift:1100`).

**B4. Wojny rankingowe + news frakcji** — **wymaga dedykowanych ścieżek** (łączony `GET /v2/faction?selections=rankedwars,news` zwrócił `code 21 "Incorrect category"` — do rozwiązania na etapie implementacji: prawdopodobnie `news` potrzebuje param `cat`, a wojny idą przez `GET /v2/faction/rankedwars`).
- Kształty ze spec: `FactionRankedWarDetails { id, start, end, target, winner, factions[] }`; `News { id, text, timestamp }`.
- **Krok 0 tego ficzera:** żywy call na `/v2/faction/rankedwars` i `/v2/faction/news` żeby domknąć dokładny kształt i wymagane parametry (kluczem Pawła). Widok: zakładka Faction — pasek postępu wojny (`target` vs bieżący wynik) + feed newsów.

---

## Krytyczne pliki

| Plik | Zmiana |
|------|--------|
| `MacTorn/MacTorn/Models/TornModels.swift` | `server_time` mapping (A1); zdjąć `crimes` z selekcji + skasować model OC 1.0 (A2); nowe modele `OrganizedCrime2`/`Refills`/`EducationStatus`/`Bounty`/`RankedWar`/`FactionNews`; nowe buildery URL v2 user/faction w enumie `TornAPI` |
| `MacTorn/MacTorn/ViewModels/AppState.swift` | anchor `server_time` (A1); usunąć parse OC 1.0 (A2); fetch+parse łączonego `/v2/user` (B1-B3) i `/v2/faction/*` (B4); stan + notyfikacje (bounties) |
| `MacTorn/MacTorn/Views/FactionView.swift` | zamienić listę OC 1.0 na własne OC 2.0 (B1) + wojny/news (B4) |
| `MacTorn/MacTorn/Views/StatusView.swift` (lub nowy widok) | refille + edukacja (B2), bounty alert (B3) |
| `MacTorn/MacTornTests/Fixtures/TornAPIFixtures.swift` | naprawić fixture OC; dodać fixtures v2 (organizedcrime/refills/education/bounties/rankedwars/news); dodać `server_time` |
| `MacTorn/MacTornTests/...` | przepisać `OrganizedCrimeTests` na OC 2.0; testy anchor (`server_time`), refills/education/bounties; regresja Int-`initiated` |

Reużyć: `CooldownEnds.from` (`TornModels.swift:123`) dla timerów; `tornAPIErrorMessage`/`tornRedactedURL` (`TornModels.swift:1047-1083`) dla nowych v2 calli; `NotificationManager` + `NotificationRule` dla alertów bounty/refill/OC-ready.

---

## Status: ZREALIZOWANE (2026-07-03)

Wszystkie fixy + 4 ficzery zaimplementowane i przetestowane. **252 unit testy zielone, `make build` OK.**

**Zweryfikowane:** kształty żywego API (każdy endpoint trafiony realnym kluczem; fixtures = te same kształty), OC 2.0 (Paweł ma aktywne "Clinical Precision"), semantyka `lead/target` wojny (na żywej wojnie The Masters), dual-key anchor (`server_time` + legacy fallback), naprawiony data-race w mocku. **Niezweryfikowane:** wizualny rendering na urządzeniu (natywny menu-bar app — Interceptor go nie napędza, fresh-build + keychain/signing niepewne). To granica akceptowalna: warstwa danych + build + testy pokryte.

**Rate-limit:** poll główny = 5 calli (user-v1 + faction-v1 + user-v2 + rankedwars + news), floor 15s → **20/min << 100/min limitu Torn**. Watchlist na własnym cadence. Bez regresji. **Follow-up (efektywność, nie korektność):** rankedwars (15KB) + news (23KB) zmieniają się wolno — throttle do co N-tego pollu oszczędziłby ~150KB/min.

## Weryfikacja (end-to-end)

1. **Żywe calle (krok 0 implementacji):** dograć dokładny kształt `/v2/faction/rankedwars` i `/v2/faction/news` kluczem Pawła (jedyna nie-dodomknięta rzecz — reszta zweryfikowana na żywo w audycie). Zapisane próbki żywych odpowiedzi: `…/scratchpad/{usr,fac,v2user,v2fac}.json`.
2. `make test` — wszystkie unity zielone; **nowy** test regresyjny: dekodowanie OC z `initiated` jako Int nie może wywalać; anchor bierze `server_time`.
3. `make build` + uruchomienie appki w menu barze na koncie Pawła: potwierdzić że (a) cooldowny zgadzają się z torn.com, (b) OC readiness pokazuje realny timer, (c) refille/edukacja/bounty renderują się poprawnie, (d) zakładka Faction pokazuje wojnę/news. Zero „pustego OC".
4. Sanity: `make test-all` (unit + UI).
