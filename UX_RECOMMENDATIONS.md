# MacTorn: ocena UX i rekomendacje

Last verified: 2026-08-26 | wersja 1.12.0
Zakres tego przebiegu: powierzchnie zmienione przez gałąź `feature/torn-api-2026-08`.
Odznaki powiadomień w Statusie, wyszukiwarka przedmiotów w Watchliście, obserwowanie
kategorii forum w Ustawieniach, sekcja pominiętych endpointów w Diagnostyce. Do tego jedno
pytanie przekrojowe: czy użytkownik rozumie, dlaczego moduł jest pusty.

Fakty i lokalizacje są w `AUDIT_REPORT.md`. Tutaj są oceny, czyli rzeczy, co do których
można się ze mną nie zgodzić.

**Zastrzeżenie metodologiczne, obowiązujące dla każdej oceny niżej:** aplikacja nie została
uruchomiona w tym przebiegu. XCUITest wymaga aktywnej, odblokowanej sesji graficznej,
której nie było. Wszystko o wyglądzie, przycięciu treści i mowie VoiceOver jest wywnioskowane
z kodu, nie zaobserwowane. Oceniam *kontrakt zapisany w kodzie*, nie doświadczenie.
Poprzedni przebieg (2026-08-01) miał to samo ograniczenie.

---

## Ocena ogólna

Ta gałąź zmieniła głównie rzeczy, których użytkownik nie widzi. To jednocześnie jej
największa zaleta i jej największe ryzyko UX.

Zaleta: aplikacja przestała wysyłać żądania, o których wiedziała, że nic nie zwrócą. Gracz
bez frakcji nie płaci już budżetem API za pustą zakładkę, a klucz o niskich uprawnieniach
dostaje częściową odpowiedź zamiast żadnej. Pobyt w federal jail nie wygląda już jak
zepsuty klucz.

Ryzyko: pominięte żądanie wygląda z zewnątrz tak samo jak zepsute. Przed zmianą gracz bez
frakcji widział pustą zakładkę Faction i mógł założyć, że coś się ładuje. Po zmianie widzi
tę samą pustą zakładkę, tylko że teraz aplikacja celowo o nią nie pyta i nigdzie w głównym
interfejsie tego nie mówi. Diagnostyka to mówi, ale leży za Ustawieniami i nikt tam nie
zagląda bez powodu.

To jedyna rzecz z tego przebiegu, którą uważam za wartą uwagi produktowej; reszta to
drobiazgi.

### Ocena heurystyczna nowych powierzchni

| Powierzchnia | Ocena | Uzasadnienie |
|---|---|---|
| Odznaki powiadomień (Status) | 4/5 | Cztery liczniki tam, gdzie był jeden. Ikona niesie znaczenie, kolor tylko je wzmacnia, więc czyta się bez koloru. Minus za to, że sama liczba bez rzeczownika wymaga nauczenia się ikon; rzeczownik jest w tooltipie i w VoiceOverze, ale nie na ekranie. |
| Wyszukiwarka przedmiotów (Watchlista) | 5/5 | Największa poprawa w tym wydaniu. Zniknął wymóg znajomości numerycznego ID i ręcznego wpisania nazwy, czyli jedyna rzecz w tej aplikacji, która wymagała od użytkownika wiedzy spoza niej. |
| Obserwowanie kategorii forum (Ustawienia) | 3/5 | Funkcja działa i jest opisana, ale ID kategorii to nadal liczba, którą trzeba wyłuskać z URL-a. Tekst pomocniczy tłumaczy jak; to minimum, nie rozwiązanie. |
| Sekcja pominiętych endpointów (Diagnostyka) | 4/5 | Odpowiada na „dlaczego to jest puste", zdaniami po ludzku. Minus za lokalizację: zajrzy tam ktoś, kto już wie, że coś jest nie tak. |
| Odczucie zmian pod spodem | 5/5 | Zero widocznej regresji, mniej żądań, świeższy licznik nieprzeczytanych, automatyczne wznowienie zamiast komunikatu o zepsutym kluczu. |

---

## Przejście ścieżek jako persony

**Nowy użytkownik z kluczem Public Only.** Wkleja klucz, klika Test Connection, widzi, że
większość modułów jest niedostępna. Ten ekran działał i nadal działa. Ale jeśli *nie*
kliknie Test Connection, dostanie aplikację, która po cichu pomija połowę żądań i nigdzie
na głównym ekranie nie tłumaczy dlaczego. To ta sama pusta zakładka co przed zmianą, więc
nie regresja, tylko niewykorzystana okazja.
→ rekomendacja **A1**.

**Gracz bez frakcji.** Otwiera zakładkę Faction, widzi pustkę. Aplikacja wie dokładnie
dlaczego (`/key/info` podaje `faction_id: null`) i mówi to tylko w Diagnostyce.
→ rekomendacja **A1**.

**Regularny gracz dodający przedmiot do watchlisty.** Wpisuje „xanax", wybiera z listy,
gotowe. Wcześniej musiał znać 206 i wpisać nazwę ręcznie. Tę zmianę ktoś poczuje.

**Gracz wracający po przerwie z zestarzałym katalogiem.** Katalog jest cache'owany tydzień,
więc pierwsze otwarcie po dłuższej przerwie pokaże listę sprzed tygodnia, dopóki tło jej nie
odświeży. Przedmioty w Tornie przybywają rzadko, więc ryzyko jest realne, ale niskie.

**Gracz w federal jail.** Przed zmianą aplikacja stawała i mówiła, że klucz jest
nieprawidłowy. Po zmianie mówi, że Torn wstrzymał dostęp na czas pobytu, i wraca sama.
Komunikat jest w `TornAPIError.userMessage` i pojawia się w pasku błędu Statusu.

**Użytkownik z VoiceOverem.** Każda nowa odznaka ma `accessibilityLabel` z pełnym
rzeczownikiem i liczbą („3 events waiting. Opens Torn."), a nie samą cyfrą, którą widać na
ekranie. Wiersze sugestii przedmiotów mają etykietę „Add <nazwa> to the watchlist".
Zweryfikowane w kodzie, nie odsłuchane.

**Użytkownik na wolnym łączu.** Katalog przedmiotów to jedyny duży payload, jaki doszedł.
Pobiera się raz na tydzień, w tle, i nic na niego nie czeka: pole wyszukiwania działa jako
pole ID, dopóki katalogu nie ma.

---

## A. Quick wins

### A1 · Powiedz w module, dlaczego jest pusty

**Problem użytkownika:** zakładka jest pusta i nie wiadomo, czy to ładowanie, awaria, czy
świadome pominięcie. Aplikacja zna odpowiedź i trzyma ją w Diagnostyce.
**Rozwiązanie:** `ModuleStateView` już istnieje i obsługuje stany modułu. Dołożyć do niego
stan „pominięte" zasilany z `TornEndpointGate.denial(...).userExplanation`, czyli z tekstu,
który jest już napisany i przetestowany. Zakładka Faction dla gracza bez frakcji
pokazywałaby „You are not in a faction" zamiast pustki.
**Wpływ:** usuwa jedyną nową dwuznaczność wprowadzoną przez to wydanie.
**Zakres:** jeden nowy przypadek w `ModulePresentationState`, wywołanie w
`AppState.presentationState(endpointIDs:...)`, które już przyjmuje listę endpointów.
**Ryzyko:** niskie. **Wpływ na prostotę:** neutralny, bo zastępuje pustkę zdaniem.
**Walidacja:** UI-test z kluczem bez frakcji sprawdzający tekst w zakładce Faction.
**Metryka:** liczba zgłoszeń „faction tab is empty" na GitHubie.
**Impact 4 · Effort 2 · Confidence 5 · Risk 1 → score 10,0 · P1**

### A2 · Wyszukiwarka kategorii forum zamiast numeru

**Problem:** ID kategorii trzeba wyłuskać z URL-a forum. Tekst pomocniczy tłumaczy jak, co
jest przyznaniem się, że pole jest niewygodne.
**Rozwiązanie:** `/v2/forum/categories` zwraca listę kategorii z nazwami. Pobrać ją tak jak
katalog przedmiotów i podmienić pole tekstowe na `Picker`.
**Zakres:** jeden endpoint w rejestrze, jeden cache, jedna zmiana pola.
**Ryzyko:** niskie. **Wpływ na prostotę:** dodatni, bo usuwa tekst pomocniczy.
**Walidacja:** czy ktokolwiek włącza tę funkcję. Dziś nie da się tego zmierzyć, patrz
Metryki.
**Impact 3 · Effort 2 · Confidence 4 · Risk 1 → score 6,0 · P2**

### A3 · Rzeczownik przy odznace, gdy jest miejsce

**Problem:** odznaka pokazuje samą liczbę; rzeczownik jest tylko w tooltipie i VoiceOverze.
Przy jednej czy dwóch odznakach miejsce w popoverze jest.
**Rozwiązanie:** `ViewThatFits` z pełną formą („3 events") tam, gdzie się mieści, i skróconą
tam, gdzie nie.
**Ryzyko:** niskie, ale `ViewThatFits` bywa kapryśny przy dużym tekście systemowym.
**Impact 2 · Effort 2 · Confidence 3 · Risk 2 → score 3,0 · P3**

---

## B. Średni zakres

### B1 · Skrócić dystans od objawu do Diagnostyki

**Problem:** Diagnostyka odpowiada teraz na „dlaczego to jest puste", ale trafia tam tylko
ktoś, kto już podejrzewa problem techniczny.
**Rozwiązanie:** gdy bramka pomija cokolwiek trwale (`isSelfHealing == false`), pokazać w
stopce popovera dyskretny wskaźnik prowadzący prosto do sekcji „Not being requested".
**Zakres:** stopka, routing do Diagnostyki, warunek widoczności.
**Ryzyko:** średnie, bo łatwo zrobić z tego stałą, ignorowaną ikonkę.
**Walidacja:** prototyp na sobie przez tydzień przed wydaniem.
**Impact 3 · Effort 3 · Confidence 3 · Risk 3 → score 3,0 · P3**

### B2 · Ostrzeżenie o kluczu przy pierwszym uruchomieniu, bez klikania Test Connection

**Problem:** `refreshKeyInfoIfNeeded()` dociąga teraz uprawnienia klucza samo, więc
aplikacja *wie*, czego klucz nie umie, zanim użytkownik cokolwiek kliknie. Ta wiedza nie
trafia nigdzie poza bramkę.
**Rozwiązanie:** jeśli po pierwszym udanym `/key/info` któryś moduł jest trwale niedostępny,
pokazać jednorazową informację przy pierwszym wejściu w ten moduł.
**Ryzyko:** średnie, łatwo o natrętność. Musi być jednorazowe i odrzucalne.
**Impact 3 · Effort 3 · Confidence 4 · Risk 3 → score 4,0 · P2**

---

## C. Eksperymenty (wartość niepewna)

### C1 · Odznaka „awards" jako sygnał do działania

Liczniki awards i competition są nowe i nie wiadomo, czy ktokolwiek na nie zareaguje.
Torn pokazuje awards jako coś, co „czeka", ale w praktyce często czeka miesiącami.
**Walidacja:** używać samemu przez dwa tygodnie i sprawdzić, czy odznaka kiedykolwiek
skłoniła do kliknięcia, czy stała się stałym tłem.
**Decyzja do podjęcia:** jeśli tłem, dać przełącznik i domyślnie wyłączyć.

### C2 · Cena bazarowa w alertach cenowych

Torn nie udostępnia już cen bazarowych per przedmiot na v2 (patrz `AUDIT_REPORT.md`, P2-4).
Gdyby to wróciło, warto sprawdzić, czy alert oparty na najniższej cenie łącznie jest
lepszy od alertu tylko z item marketu. Bazar bywa tańszy, ale bywa też pułapką.
**Walidacja:** dopiero gdy API to udostępni.

---

## D. Odrzucone

| Pomysł | Dlaczego nie |
|---|---|
| Migracja szybkiego polla na API v2 „bo v2 jest nowsze" | v1 nie jest wygaszone i OpenAPI Torna wprost mówi, że niezmigrowana selekcja v2 spada do kształtu v1. Przepisanie warstwy modelu na najbardziej krytycznej ścieżce, bez różnicy dla użytkownika, to ryzyko bez nagrody. Temat wraca, gdy Torn ogłosi datę wyłączenia v1. |
| Panel „API health" jako stała zakładka | Diagnostyka to już jest, tylko schowana. Wyciąganie jej na stały widok zamienia narzędzie serwisowe w element interfejsu, który 95 % użytkowników ma oglądać codziennie bez powodu. |
| Powiadomienie, gdy bramka coś pominie | Pominięcie jest normalnym stanem dla klucza o niskich uprawnieniach. Powiadamianie o nim zamieniłoby poprawkę w źródło hałasu. |
| Automatyczne podnoszenie uprawnień klucza / instruowanie krok po kroku w Tornie | MacTorn nie kontroluje tamtego interfejsu i każda instrukcja zestarzeje się bez ostrzeżenia. Link do strony kluczy wystarczy. |
| Pobieranie pełnych szczegółów przedmiotów (`/torn/{ids}/itemdetails`) do watchlisty | Kilkaset kilobajtów i cały aparat cache'owania po to, żeby pokazać opis przedmiotu, którego użytkownik i tak nie czyta przy śledzeniu ceny. |
| Globalna tablica bounties (`/torn/bounties`) | To funkcja do polowania, nie do monitorowania własnego stanu, czyli materiał na inny produkt. |

---

## Metryki

MacTorn nie zbiera telemetrii poza opt-inowym Sentry i **nie ma być inaczej**. To cecha
produktu, nie brak. Dlatego poniższe „metryki" są w większości jakościowe albo pochodzą z
GitHuba, nie z aplikacji.

| Co mierzyć | Skąd | Po co |
|---|---|---|
| Zgłoszenia „X tab is empty" / „invalid API key" | issues na GitHubie | bezpośredni test A1 i poprawki błędów przejściowych klucza |
| Crash-free sessions | Sentry (opt-in) | regresja stabilności |
| Liczba żądań/dobę u siebie | `Diagnostics` → Requests/day | czy bramka faktycznie ścięła ruch; wartość przed zmianą warto zanotować przy pierwszym uruchomieniu |
| Wiersze/dobę per kategoria | `Diagnostics` | czy usunięcie `messages` ze ścieżki wierszowej zeszło o ~⅓ |
| Czy odznaki awards/competition prowadzą do kliknięcia | obserwacja własna | wejście do C1 |
| Czy ktokolwiek włącza obserwowanie kategorii forum | nie da się zmierzyć bez telemetrii | świadomie akceptujemy niewiedzę |

Celowo **nie** proponuję zliczania otwarć modułów, śledzenia ścieżek nawigacji ani
wysyłania konfiguracji klucza. Nic z tego nie jest warte złamania obietnicy „local-first".

---

## Roadmapa

**Najbliższy patch (1.12.1):** A1 (powód pustego modułu w module), plus cokolwiek wyjdzie
z pierwszego uruchomienia 1.12.0 na żywym kluczu.

**Kolejne wydanie (1.13.0):** A2 (wybór kategorii forum z listy) i B2 (jednorazowa
informacja o ograniczeniach klucza).

**Większe wydanie:** przygotowanie migracji na v2, czyli równoległe porównanie odpowiedzi
v1 i v2 pole po polu na żywym kluczu, spisane zanim Torn ogłosi wyłączenie v1. To praca
badawcza, nie wdrożeniowa, i powinna się odbyć, zanim będzie pilna.

**Do walidacji przed decyzją:** C1 (czy awards to sygnał, czy tło).

---

## Manual QA: lista przed publikacją

Wszystko poniżej wymaga żywego klucza API i odblokowanej sesji, więc żadnego z tych punktów
nie dało się wykonać w tym przebiegu. To lista dla Pawła przy pierwszym uruchomieniu
1.12.0, uporządkowana od największego ryzyka.

1. **Szybki poll nadal działa.** Otworzyć popover, sprawdzić, że paski, cooldowny i zegar
   podróży się aktualizują. To weryfikuje zawężanie selekcji i to, że rejestr buduje ten sam
   URL co dawne `TornAPI`.
2. **Żądania v2 przechodzą z nagłówkiem.** Diagnostyka → sekcja Endpoints: `user.v2`,
   `market.item` i `key.info` muszą mieć wynik `ok`, nie `error`. To jedyny test tego, czy
   Torn akceptuje `Authorization: ApiKey` tam, gdzie przeniosłem klucz.
3. **`comment=MacTorn` widoczny w logu klucza.** torn.com → Preferences → API → key log.
   Wpisy z ostatniej godziny powinny być podpisane `MacTorn`.
4. **Watchlista po nazwie.** Dodać „xanax" wpisując nazwę. Sprawdzić, że stare pozycje
   `Item #206` zmieniły nazwę na prawdziwą, a ceny i progi alertów przy nich zostały.
5. **Cena z item marketu jest sensowna.** Po usunięciu `bazaar` porównać pokazaną najniższą
   cenę z torn.com dla tego samego przedmiotu.
6. **Odznaki nie wychodzą poza popover.** Doprowadzić do stanu z co najmniej trzema
   niezerowymi licznikami i sprawdzić, że wiersz się mieści przy 320 pt.
7. **Wirus.** Jeśli akurat jest programowany, sprawdzić, że odliczanie pojawia się na osi
   Next Action i zgadza się z torn.com.
8. **Obserwowanie kategorii forum.** Włączyć z ID kategorii frakcji. Pierwsze sprawdzenie
   musi być ciche. Dopiero nowy wątek ma dać powiadomienie.
9. **Diagnostyka mówi prawdę.** Sekcja „Not being requested" powinna być pusta dla klucza
   Full Access i wymieniać endpointy frakcyjne dla gracza bez frakcji.
10. **Zmiana klucza czyści stan.** Wpisać inny klucz, sprawdzić, że dane poprzedniego konta
    znikają, a watchlista i obserwowane wątki zostają.
11. **UI-testy na odblokowanej sesji.** `make test-ui` nie dało się uruchomić w tym
    przebiegu. To jedyna bramka jakości, która nie została zaliczona przed wydaniem.
