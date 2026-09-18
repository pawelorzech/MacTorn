# Torn API — audyt MacTorn, 18.09.2026

## Wynik i zakres

Bezpośrednio pobrany oficjalny OpenAPI ma wersję **6.13.6**. Indeks wyszukiwarki i komunikat administratora z 11.09 wskazują jeszcze 6.13.5; podstawą porównania jest pobrany JSON. Rejestr aplikacji wspomina poprzednie sprawdzenie 6.13.1 z 26.08.2026.

Nie znalazłem ogłoszonego wyłączenia używanych endpointów ani nowej zmiany wymagającej pilnej migracji całej aplikacji na v2. Zidentyfikowałem jednak trzy luki integracyjne wymagające poprawy. To ustalenia z porównania kontraktu i kodu, a nie dowód, że błędy powstały dopiero w ostatniej wersji API.

Sprawdzono rejestr 13 endpointów, używane modele odpowiedzi, parsowanie w serwisach, kontrolę uprawnień, odświeżanie klucza i prezentację czasu aktualizacji. Audyt nie używał prywatnego klucza, nie wykonywał żądań danych konta, nie uruchamiał aplikacji ani testów XCTest. Pierwotny audyt obejmował wyłącznie ten raport. Poniżej zachowano ustalenia sprzed wdrożenia; na późniejsze polecenie użytkownika rozpoczęto implementację wszystkich sześciu proponowanych grup funkcji i trzech poprawek w wersji 1.15.0.

## Zgodność obecnych wywołań

| Wywołanie MacTorn | Ocena |
| --- | --- |
| v1 user: basic, bars, cooldowns, travel, profile, money, battlestats, properties, stocks | Brak znalezionej zapowiedzi wyłączenia. Migracja wymaga osobnych modeli, nie zmiany samego URL. OpenAPI v2 nie dowodzi zgodności odpowiedzi v1. |
| v1 user: events, attacks | Brak znalezionego wymogu migracji. Parser ataków nie odczytuje pola chain. |
| v1 faction: basic, chain | Brak znalezionej zapowiedzi wyłączenia. |
| v1 torn: stocks | Można utrzymać; bonusy akcji warto wdrożyć przez v2. |
| v2 user: organizedcrime, refills, education, bounties, notifications | Używane pola zgodne ze schematem; nieobsługiwany wariant błędu organizedCrime opisany poniżej. |
| v2 user/virus | Zgodny model item + until, prawidłowa obsługa null. |
| v2 faction/rankedwars | Model zgodny z FactionRankedWarDetails; nie mylić z innym schematem FactionRankedWar. |
| v2 faction/news | Poprawny parametr cat=main i wymóg access.faction; luka dla uprawnień Custom. |
| v2 market/{id}/itemmarket | Odczyt listings zgodny; ignorowane informacje o wieku globalnego cache. |
| v2 torn/items | Aplikacja wykorzystuje tylko id/name; planowane usunięcie dawnych cen sklepowych jej nie dotyczy. |
| v2 forum/{threadId}/thread, forum/{categoryIds}/threads | Ścieżki i odczytywane pola zgodne; luka dla uprawnień Custom. Dokumentacja opisuje listę kategorii jako publiczną — wsparcia prywatnego forum frakcji nie należy gwarantować bez osobnej weryfikacji. |
| v2 key/info | Poprawna otoczka info, user.faction_id/company_id oraz access.faction. |

## Zalecane poprawki

### 1. P1 — uprawnienia dedykowanych endpointów dla kluczy Custom

`TornEndpointGate.swift:143` sprawdza dla endpointów bez parametru selections tylko poziom klucza. `TornKeyInfo.swift`, funkcja `KeyValidator.availability`, robi to samo. Brak parametru selections w URL nie oznacza braku uprawnienia do selekcji: key/info udostępnia listy m.in. market.itemmarket, forum.thread/threads i faction.news.

Skutek: klucz Custom o wystarczającym poziomie, ale bez odpowiedniej selekcji, może zostać uznany za uprawniony. Aplikacja wysyła niedozwolone żądanie, dostaje kod 16 i odświeża capabilities, ale lokalne sprawdzenie nadal nie rozpoznaje powodu odmowy. Istniejące zabezpieczenie retry ogranicza pętlę; nie usuwa błędnej oceny uprawnień.

Propozycja: oddzielić metadane wymaganych capabilities od selekcji wysyłanych w query. Zastosować tę samą regułę w gate i Test Connection, zachowując osobny wymóg członkostwa/access.faction. Dla selekcji słabo opisanych w key/info potwierdzić zachowanie kontrolowanym testem; nie zakładać, że każdy endpoint musi mieć identyczną reprezentację.

Testy do wdrożenia: Custom bez itemmarket/thread/news → brak requestu i konkretny komunikat; dodanie capability → moduł działa; brak faction API access nadal blokuje news. Aktualne godzinowe odświeżanie capabilities oraz jednorazowe odświeżenie po kodzie 16 już są zaimplementowane.

### 2. P2 — rozpoznać zagnieżdżony błąd OC jako stan funkcji

Schemat `UserOrganizedCrimeResponse` dopuszcza `organizedCrime` jako obiekt przestępstwa, null albo `UserOrganizedCrimeError` z kodem 27. Przykład legalnego wariantu:

```json
{"organizedCrime":{"code":27,"error":"Must be migrated to organized crimes 2.0."}}
```

`UserSnapshotService.swift:333–343` obsługuje wyłącznie null i `OrganizedCrime2`. Obiekt błędu trafia do malformedSelections, zachowując stary stan OC. Pozostałe sekcje v2 nadal się aktualizują, więc nie jest to awaria całego pollingu.

Propozycja: jawny stan „OC 2.0 niedostępne / wymagana migracja”, wstrzymanie alertów opartych na dawnym OC oraz zachowanie poprawnych refills/education/notifications. Nie traktować tego stanu jak uszkodzonego JSON-a.

Test: powyższy payload z poprawnymi sekcjami sąsiednimi; sprawdzić komunikat, brak nieaktualnego alertu OC i aktualizację pozostałych danych.

### 3. P2 — odróżnić pobranie odpowiedzi od wieku danych rynku

`ItemMarket` ma `cache_timestamp` i opcjonalne `cache_delay`; bounties udostępnia `bounties_timestamp` i opcjonalne `bounties_delay`. To globalnie cache'owane dane. Częstsze żądania ani wyłączenie lokalnego URLCache nie zapewniają świeższej ceny.

`MarketWatchService.apply` zapisuje `lastUpdated = Date()`, a WatchlistView wyświetla „Updated … ago”. Pomijamy datę danych nadaną przez Torn, więc świeżo pobrana odpowiedź może wyglądać jak świeża cena, choć zawiera starszy snapshot.

Propozycja: zachowywać osobno fetchedAt i dataTimestamp, pokazywać wiek ceny, uwzględnić cache_delay w harmonogramie i nie traktować ponownego odczytu tego samego snapshotu jako nowego zdarzenia. Analogiczne metadane przy bounty pomogą wyjaśnić opóźnienia alertów. Opcjonalne pola delay muszą pozostać opcjonalne.

Test: dwie odpowiedzi z tym samym cache_timestamp → wiek danych nie zeruje się; nowszy timestamp → aktualizacja; brak delay → bezpieczny fallback.

## Zapowiedziane zmiany na 01.01.2027

- Ataki v2: chain może być null zamiast 0. Obecny parser MacTorn korzysta z v1 i nie modeluje chain, więc nie wymaga z tego powodu poprawki. Przy migracji v2 użyć pola opcjonalnego.
- faction/warfare zostanie usunięte; zastępują je osobne selekcje wojenne. MacTorn używa faction/rankedwars, więc nie jest objęty tym usunięciem.
- torn/itemdetails będzie zwracać tablicę zamiast pojedynczego obiektu. MacTorn tego endpointu nie używa.
- W torn/items pola value.vendor, buy_price i sell_price są oznaczone do usunięcia; zastępuje je value.shops. MacTorn czyta tylko id/name. Nowe funkcje cen sklepów powinny od razu używać shops.

## Nowe lub niewykorzystane możliwości

Nie wszystkie pozycje są nowościami wrześniowymi. To funkcje dostępne w aktualnym API, których aplikacja jeszcze nie wykorzystuje.

| Priorytet | API | Propozycja dla MacTorn | Koszt i ograniczenia |
| --- | --- | --- | --- |
| Wysoki | user/organizedcrimes, Minimal; dodane 19.02.2026 | Gdy nie mamy własnego OC: lista wolnych miejsc, rola/CPR i link do dołączenia w Torn. Alert o nowym pasującym miejscu. | Zwraca tylko Recruiting i puste sloty. Odczyt co 2–5 min, tylko gdy funkcja aktywna; deduplikacja po OC/pozycji. |
| Wysoki | user/stocks + torn/stocks v2, stan użytkownika Limited; refaktor 23.02.2026 | Bonus gotowy do odebrania, postęp do następnego bonusu i alert. Pasuje do istniejącej zakładki Stocks i Next Action. | Nowe DTO: tablica stocks, id/shares/bonus/transactions; obecny model v1 nie pasuje. Poll 2–5 min, metadane osobno w cache; unikać podwójnego pobierania holdings przez v1 i v2. |
| Średni, sezonowo wysoki | user/competition + torn/elimination (+ eliminationteam), Public | Panel Elimination: drużyna, wynik, własne ataki, pozostali uczestnicy i podsumowanie ataków drużyn. | Wrześniowe dodatki obejmują participants_left i attacking_summary. Ten ostatni pokazuje ostatnią zakończoną minutę. Odpytywać tylko podczas wydarzenia, np. co 60 s, z obsługą niedostępności poza sezonem. |
| Średni | user/trades i user/trade, Limited; dodane 10–12.03.2026 | Lista aktywnych wymian, przypomnienie o zmianie stanu i przejście do wymiany w Torn. | cat=ongoing, odpytywanie tylko przy aktywnym module; alerty po zmianie, nie przy każdym odczycie. Odczyt danych nie umożliwia zatwierdzenia wymiany przez API. |
| Średni | torn/items → value.shops; dodane 18.08.2026 | W Travel pokazać, co kupić w danym kraju; w Watchlist porównanie ceny sklepowej z ceną rynku. | Rozszerzyć istniejący katalog; nie dokładać szybkiego pollingu. To ceny katalogowe, nie dowód bieżącego zapasu w zagranicznym sklepie ani gwarantowanego zysku. |
| Niski | faction/warfareranked, warfareraids, warfareterritory, warfarechains, dirtybombs; dodane 14.08.2026 | Historia konfliktów jako rozwinięcie zakładki Faction. | Nie zastępować działającego podglądu rankedwars bez potrzeby. Historia z paginacją pobierana na żądanie. |

`user/snapshot` (27.07.2026), faction/snapshot i company/snapshot to dzienne eksporty CSV. Nie są odpowiednikiem lokalnego `UserSnapshotService` i nie nadają się do zastąpienia szybkiego pollingu pasków, podróży i cooldownów. Na obecnym etapie nie rekomenduję ich integracji.

Kolejność prac: uprawnienia Custom → stan błędu OC → wiek cen → bonusy akcji i wolne miejsca OC. Elimination warto przesunąć wyżej, jeśli użytkownicy korzystają z obecnego wydarzenia. Migrację podstawowego v1 prowadzić selekcja po selekcji, z testami rzeczywistych kształtów odpowiedzi, a nie zbiorczą zamianą URL.

## Źródła

- [Oficjalny OpenAPI JSON, pobrany 18.09.2026 — 6.13.6](https://www.torn.com/swagger/openapi.json)
- [Swagger UI](https://www.torn.com/swagger/index.html)
- [Dokumentacja API, cache, limity, custom keys i patch notes](https://www.torn.com/api.html)
- [Komunikaty administratora API, w tym 11.09.2026 i ostrzeżenia deprecacyjne](https://www.torn.com/forums.php?p=threads&f=63&t=16401584&b=0&a=0)

Schemat zawiera również ślady nieaktualnych opisów, np. wzmiankę o usunięciu pola pozycji OC w czerwcu, mimo że nadal jest opisane. Z tego powodu rozróżniono zgodność kontraktu od potwierdzenia rzeczywistej odpowiedzi produkcyjnej.

## Zakończenie wdrożenia 1.15.0

Zaimplementowano trzy grupy poprawek i wszystkie sześć proponowanych modułów. Moduły i alerty są opcjonalne; historia konfliktów oraz szczegóły wymian pobierane na żądanie. Katalog sklepów współdzieli cache nazw przedmiotów.

Walidacja: 776 testów jednostkowych bez błędów oraz ponowny przebieg 19 testów CompanionStore, obejmujący dwie dodatkowe regresje zmiany konta i wyłączania modułu podczas pobierania. Analiza statyczna, uniwersalny build Release arm64/x86_64 oraz ścisła kontrola podpisu ad-hoc przeszły. Pokrycie linii aplikacji: 45,52%. Testów manualnych ani lokalnych testów UI nie wykonywano na wyraźną prośbę użytkownika. Nie wykonywano zapytań prywatnym kluczem do produkcyjnego Torn API.
