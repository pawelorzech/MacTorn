# MacTorn — stan UX i dalsze rekomendacje

Data: 2026-07-30
Zakres: stan po wdrożeniach T01–T17, przegląd heurystyczny, testy modeli i fixture'ów oraz automatyczna inspekcja kontraktów UI/Accessibility.

## Podsumowanie

MacTorn realizuje podstawową obietnicę aplikacji menu-bar: pozwala szybko sprawdzić stan Torn, przejść do właściwego modułu i odzyskać się po błędzie bez otwierania pełnej aplikacji.

Najważniejsze wcześniejsze problemy zostały rozwiązane:

- siedem równorzędnych zakładek zastąpiła nawigacja `Now / Account / Watch`;
- każdy z siedmiu modułów jest dostępny w maksymalnie dwóch akcjach lub bezpośrednim skrótem klawiaturowym;
- ręczne fonty 8 pt zastąpiły style semantyczne, nie mniejsze niż `.caption2`;
- alert ceny waliduje dodatnią liczbę całkowitą, pokazuje inline error i nie zamyka formularza po błędzie;
- usuwanie pozycji watchlisty i obserwowanych wątków ma sześciosekundowe Undo;
- moduły korzystają ze wspólnego modelu loading / empty / stale / error i pokazują właściwą akcję recovery;
- freshness jest liczona per endpoint, a ostatnie poprawne dane pozostają widoczne podczas przejściowego błędu;
- polling i odświeżanie mają ograniczoną współbieżność zamiast niekontrolowanego burstu zapytań;
- nawigacja kliknięciem i Commands współdzieli jeden stan;
- Settings ma sześć stale widocznych kategorii i pokazuje tylko jedną sekcję naraz.
- Status jest ograniczony do zwartej powierzchni, a Next Action pokazuje wyłącznie najbliższe zdarzenie.

Pozostałe ryzyka dotyczą przede wszystkim walidacji na prawdziwym macOS i prawdziwych kontach, a nie brakujących mechanizmów w kodzie. Nadal potrzebne są ręczne przejścia VoiceOver, rzeczywisty Full Keyboard Access, systemowe Increase Contrast / Reduce Motion / Reduce Transparency, zmiana między dwoma kontami, dostarczenie powiadomień oraz Launch at Login.

Techniczny punkt odniesienia: lokalny automated release candidate jest zielony — 428/428 unit, 8/8 UI, coverage gate, Debug/build-for-testing, post-merge analyze, scan oraz universal strict ad-hoc Release przechodzą. Pierwszy zdalny run nowego workflow CI nie został jeszcze wykonany.

## Ocena heurystyczna

Skala: 1 — słabo, 5 — bardzo dobrze. Ocena uwzględnia wdrożenia T01–T17, ale nie zastępuje otwartych testów manualnych.

| Kryterium | Ocena | Uzasadnienie |
|---|---:|---|
| Widoczność stanu systemu | 4,7 | Loading, freshness, stale data, błędy endpointów i diagnostyka mają wspólny język i recovery CTA. |
| Dopasowanie do modelu użytkownika | 4,6 | Terminologia odpowiada Torn, a Quick Travel rozróżnia Standard oraz Airstrip + pilot. |
| Kontrola i odwracalność | 4,6 | Watchlist i forum mają Undo; formularze zachowują błędny input; Escape zamyka aktywne warstwy tam, gdzie jest to bezpieczne. |
| Spójność | 4,5 | Moduły współdzielą komponent stanów, semantyczną typografię i konsekwentne wzorce retry/error. |
| Zapobieganie błędom | 4,6 | Klucz, forum ID i próg ceny mają walidację; zapis alertu nie przyjmuje wartości pustej, tekstowej, zerowej ani ujemnej. |
| Rozpoznawanie zamiast pamiętania | 4,6 | Trzy grupy i aktywny picker ograniczają liczbę równoczesnych opcji; Commands pokazuje skróty. |
| Efektywność dla regularnego gracza | 4,7 | Refresh `⌘R`, Settings `⌘,` i moduły `⌘1…⌘7` obsługują podstawowe zadania bez myszy. |
| Minimalizm i hierarchia | 4,4 | Nawigacja grupowa oraz sekcje Settings zmniejszyły gęstość w powierzchni 320 pt. |
| Obsługa błędów | 4,6 | Ostatnie dobre dane nie znikają przy błędzie chwilowym, a użytkownik dostaje adekwatne Retry lub Open Settings. |
| Dostępność | 4,2 | AX labels, selected traits, semantyczne fonty i widoczny focus są wdrożone; pełny manualny audyt audio i systemowego FKA pozostaje otwarty. |

Średnia heurystyczna: **4,55 / 5**.

## Najważniejsze ścieżki użytkownika

### 1. Szybki check stanu

Cel: w kilka sekund sprawdzić bars, cooldowny, travel/status i kolejną akcję.

Stan: wdrożony. Status jest domyślnym modułem grupy Now. Progress bary są pojedynczymi elementami AX z nazwą, wartością i procentem. Stan modułu odróżnia dane świeże, stare, ładowanie i błąd, zachowując ostatni poprawny snapshot.

### 2. Zmiana lub test klucza

Cel: wkleić klucz, sprawdzić uprawnienia i rozpocząć polling bez wyświetlenia danych poprzedniego konta.

Stan: wdrożony i objęty deterministycznym fixture'em. Whitespace-only nie aktywuje zapisu, spóźniona odpowiedź starej sesji nie nadpisuje nowej, a trwałe odrzucenie usuwa stary snapshot.

Otwarte: ręczny test szybkiej zmiany pomiędzy dwoma rzeczywistymi kontami testowymi.

### 3. Obserwowanie wątku

Cel: wkleić URL lub ID, włączyć monitoring i bezpiecznie zarządzać listą.

Stan: wdrożony. Błędny input pozostaje w polu, format i duplikat mają osobne inline errors, a usunięty wątek można przywrócić przez Undo wraz z pełnym stanem i pozycją.

### 4. Alert ceny

Cel: ustawić dodatnią cenę progową dla itemu.

Stan: wdrożony. Formularz przyjmuje wyłącznie dodatnią liczbę całkowitą, pokazuje konkretny inline error, wyłącza Set dla niepoprawnej wartości i nie zamyka się po błędnym Enter. Usuniętą pozycję można przywrócić przez Undo.

### 5. Quick Travel

Cel: otrzymać uczciwy szacunek lotu i odróżnić estymatę od aktywnego lotu.

Stan: wdrożony.

- Dla planowanego lotu użytkownik jawnie wybiera `Standard` albo `Airstrip + pilot`.
- Interfejs informuje, że Airstrip + pilot wymaga odpowiedniego upgrade'u i aktywnego pilota.
- Szacunki uwzględniają oficjalne czasy oraz wariancję ±3%.
- Aktywny lot jest API-driven: UI pokazuje czas pozostały zwrócony dla bieżącej podróży zamiast zastępować go lokalną estymatą.
- Ustawienie Private Island steruje wyłącznie skrótem/ikoną powrotu i nie przełącza metody estymacji.

### 6. Nawigacja i Settings bez myszy

Cel: odświeżyć dane, przejść do modułu i zmienić ustawienie klawiaturą.

Stan: wdrożony.

- Refresh: `⌘R`
- Settings: `⌘,`
- Status, Travel, Attacks, Money, Faction, Watchlist, Forums: `⌘1…⌘7`
- Escape zamyka Settings, aktywne pole lub modal tam, gdzie nie narusza onboardingu.
- Widoczne menu Commands i fokus na elementach nawigacji ułatwiają odkrycie obsługi klawiaturą.

Otwarte: pełne ręczne przejście z włączonym systemowym Full Keyboard Access.

### 7. Diagnoza i recovery

Cel: rozpoznać offline, zły klucz, brak uprawnień, rate limit lub awarię pojedynczego endpointu.

Stan: wdrożony. Wspólny komponent stanu kieruje do Retry lub Settings, per-endpoint freshness rozróżnia brak danych od danych nieświeżych, a Diagnostics pokazuje connectivity, budżet zapytań i zdrowie endpointów bez PII.

## Wdrożenia T02–T17 istotne dla UX

| Obszar | Stan | Kryterium potwierdzające |
|---|---|---|
| Walidacja progu cenowego | Wdrożone | Inline error, disabled Set, błędny Enter nie zamyka formularza. |
| Undo watchlisty i forum | Wdrożone | Przywrócenie pełnego elementu i pierwotnej pozycji w ciągu 6 s. |
| Nawigacja grupowa | Wdrożone | `Now / Account / Watch`, aktywny podrzędny picker, maks. 2 akcje do modułu. |
| Typografia semantyczna | Wdrożone | Brak ręcznych 8 pt; produkcyjne widoki używają stylów co najmniej `.caption2`. |
| Wspólne stany i recovery | Wdrożone | Jednolity loading / empty / stale / error oraz właściwe CTA. |
| Freshness | Wdrożone | Stan per endpoint i zachowanie ostatnich dobrych danych. |
| Ograniczona współbieżność | Wdrożone | Kolejka z limitem i obsługą anulowania zamiast burstu requestów. |
| Keyboard-first | Wdrożone | Commands, `⌘R`, `⌘,`, `⌘1…⌘7`, Escape i widoczny fokus. |
| Settings IA | Wdrożone | Stały przełącznik sześciu kategorii; jedna sekcja naraz, lokalny scroll tylko po rozwinięciu długiej treści. |
| Quick Travel | Wdrożone | Jawny Standard/Airstrip + pilot; aktywny lot oparty na API. |

## Status walidacji

### Potwierdzone automatycznie

- 428/428 unit tests, 0 failed, 0 skipped.
- Coverage gate: PASS.
- `TornAPIError` 99,07%, `TornEndpoint` 83,56%, `PollingCoordinator` 100%, `NotificationCoordinator` 100%, `NextAction` 96,51%.
- Debug i build-for-testing: PASS.
- Post-merge analyze: PASS.
- Scan: PASS, brak wycieków.
- 320 pt accessibility-display navigation smoke: PASS.
- Synthetic account A→B: PASS.
- Finalny MacTornUITests: 8/8 PASS, 0 failed/skipped/expected.
- All-modules + Settings AX: PASS, 48.535 s.
- Stale account switch: PASS, 15.534 s.
- UI bundle: `/tmp/mactorn-final-ui-suite-20260730-1058-clean.xcresult`.
- Quick Travel: 24/24 `TravelTests`, w tym komplet Standard/Airstrip oraz API-driven active flight.
- Universal Release `x86_64 arm64` i strict ad-hoc codesign: PASS.

### Oczekujące

- pierwszy zdalny run workflow CI i jego artefakty;
- VoiceOver audio i real Full Keyboard Access;
- systemowe motion/contrast/transparency;
- dwa rzeczywiste konta, notifications i Launch at Login.

## Aktualna architektura informacji

```text
Now
  Status
  Travel
  Attacks

Account
  Money
  Faction

Watch
  Watchlist
  Forums
```

W powierzchni 320 pt stale widoczne są trzy grupy, a drugi rząd pokazuje wyłącznie moduły aktywnej grupy. Commands zapewnia bezpośredni skok bez przechodzenia przez oba poziomy.

Settings zachowuje liniową kolejność wizualną i Accessibility:

```text
Account
Refresh
Notifications
Privacy
Startup
Diagnostics & About
```

Stały przełącznik kategorii zastępuje dawną długą stronę i jump menu. Zmiana sekcji podmienia treść w tym samym miejscu, więc użytkownik nie traci orientacji ani nie musi wracać na początek listy.

## Dalsze rekomendacje

| Priorytet | Rekomendacja | Rodzaj | Kryterium zakończenia |
|---|---|---|---|
| P1 | Przejść wszystkie moduły i Settings z VoiceOver audio. | Manualny test systemowy | Logiczna kolejność, poprawne nazwy i wartości, brak podwójnie czytanych kontrolek. |
| P1 | Przejść pełny scenariusz z rzeczywistym Full Keyboard Access. | Manualny test systemowy | Każdy interaktywny element osiągalny, focus zawsze widoczny, brak pułapki. |
| P1 | Sprawdzić Increase Contrast, Reduce Motion i Reduce Transparency w ustawieniach systemowych. | Manualny test systemowy | Brak utraty stanu selected/focus, czytelne warstwy i brak zbędnego ruchu. |
| P1 | Zmienić szybko dwa rzeczywiste konta testowe. | Manualny test integracyjny | Brak flasha poprzedniej tożsamości i brak danych starego konta po zmianie. |
| P2 | Zweryfikować powiadomienia na prawdziwym urządzeniu i koncie. | Manualny test integracyjny | Jedno poprawne powiadomienie, właściwy deep link i brak duplikatów. |
| P2 | Zweryfikować Launch at Login po restarcie i po odmowie systemowej. | Manualny test systemowy | Poprawny start, czytelny błąd i możliwość odzyskania. |
| P2 | Sprawdzić większy tekst/zoom we wszystkich sześciu sekcjach Settings i siedmiu modułach. | Manualny test wizualny | Brak obcięć, overlapów i niedostępnych akcji w szerokości 320 pt. |
| P3 | Przeprowadzić krótkie testy zadaniowe z graczami Torn. | Badanie użyteczności | Quick check, alert ceny, forum watch i recovery wykonane bez podpowiedzi. |

## Checklist UX / Accessibility

### Wdrożone i objęte testami automatycznymi

- [x] Każdy moduł ma nazwę i selected trait w AX.
- [x] Ikonowe refresh/add/remove/open mają zrozumiałe etykiety.
- [x] Energy/Nerve/Happy/Life czytają nazwę, wartość i procent.
- [x] Błędny wątek i próg ceny zachowują wpis oraz pokazują inline error.
- [x] Set alertu jest wyłączony dla pustej, tekstowej, zerowej i ujemnej wartości.
- [x] Watchlist i forum mają Undo.
- [x] Invalid key, offline, stale data i brak danych są rozróżnialne.
- [x] Recovery prowadzi do Retry lub Settings zależnie od stanu.
- [x] Freshness i zdrowie są liczone per endpoint.
- [x] Ograniczona współbieżność respektuje anulowanie.
- [x] Nawigacja grupowa mieści siedem modułów w trzech grupach.
- [x] Fonty produkcyjne używają stylów semantycznych co najmniej `.caption2`.
- [x] Commands mapuje jednoznacznie `⌘R`, `⌘,` oraz `⌘1…⌘7`.
- [x] Settings ma sześć stale widocznych kategorii i jedną aktywną sekcję.
- [x] Quick Travel rozdziela Standard, Airstrip + pilot i API-driven active flight.
- [x] Diagnostics nie ujawnia klucza ani danych gracza.

### Nadal wymagane ręcznie

- [ ] VoiceOver audio: kolejność i brzmienie wszystkich siedmiu modułów oraz Settings.
- [ ] Rzeczywisty Full Keyboard Access: kolejność tabulacji, focus ring i brak pułapki.
- [ ] Systemowe Increase Contrast, Reduce Motion i Reduce Transparency.
- [ ] Większy tekst / zoom bez obcięć w szerokości 320 pt.
- [ ] Szybka zmiana pomiędzy dwoma rzeczywistymi kontami testowymi.
- [ ] Dostarczenie, treść, deep link i deduplikacja powiadomień.
- [ ] Launch at Login po restarcie oraz obsługa odmowy/błędu systemowego.
