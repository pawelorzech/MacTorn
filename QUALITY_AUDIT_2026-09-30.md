# MacTorn — audyt jakości, 30 września 2026

## Zakres i ograniczenia

Audyt dotyczy natywnej aplikacji macOS 14+ w SwiftUI: MenuBarExtra, dodatkowego
okna otwieranego z widgetów, dziewięciu modułów, Settings, Credits, Diagnostics,
dwóch nakładek oraz trzech widgetów. Nie ma frontendowego serwera, routingu WWW,
HTML dla crawlerów, sitemap, canonicali, OG ani początkowego JavaScriptu.
Wymagania SEO i mobilne breakpointy nie dotyczą tego produktu.

Na prośbę użytkownika **nie uruchamiano testów klikających ani automatyzacji UI**.
Nie przeprowadzono więc wizualnego QA, testu klawiatury/VoiceOver, powiększenia
200%, rzeczywistych ustawień dostępności ani pomiarów uruchomionej aplikacji.
Odczyt kodu i kompilacja widoku nie stanowią dowodu działania jego interfejsu.
Nie używano produkcyjnych kluczy Torn, nie wykonywano działań w grze, nie
zmieniano Launch at Login i nie publikowano ani nie pushowano zmian.
Zastany, nieśledzony `OPTIMIZATION_ANALYSIS.md` pozostawiono bez zmian.

## Potwierdzone problemy i poprawki

| Problem i wpływ | Poprawka u źródła | Dowód / stan |
| --- | --- | --- |
| Błąd zapisu Keychain przełączał konto w pamięci mimo niezapisania klucza; restart wracał do poprzedniego konta. Nieudana migracja usuwała ostatnią kopię starego klucza. | `APIKeyStoring` zwraca wynik zapisu/usunięcia. `AccountSessionStore` publikuje nową tożsamość dopiero po sukcesie, zachowuje migrację po błędzie. Settings pokazuje błąd i nie uruchamia połączenia ze starym kontem jako wyniku nowego zapisu. | Testy regresyjne zapisu i migracji zawiodły przed poprawką; dodatkowe testy zachowania danych, usunięcia i dokończenia migracji. |
| Ponowne zapisanie tego samego klucza po zatrzymaniu połączenia niczego nie wznawiało. | Jawny zapis zatrzymanego klucza rozpoczyna nową generację sesji. Automatyczne odświeżenie nadal nie omija zatrzymania. | Test regresyjny zawiódł przed poprawką. |
| Edycja pola w trakcie Test Connection zerowała tylko etykietę; stara odpowiedź ponownie pokazywała sukces. Dwa testy mogły nadpisywać wyniki w odwrotnej kolejności. | Generacja walidacji unieważniana przy edycji, nowym teście i resecie sesji; kontrola anulowania również dla niekooperatywnego transportu. | Dwa testy z kontrolowanymi odpowiedziami zawiodły przed poprawką; dodatkowy test anulowania. |
| Czas nieudanego żądania był prezentowany jako czas aktualizacji danych. Stan zdrowia endpointów pozostawał po zmianie konta; opóźniony błąd starego konta mógł skazić nowe. | Obserwowalny tracker oddziela czas ostatniego sukcesu od próby i resetuje stan konta. Ścieżki błędów sprawdzają tożsamość oraz anulowanie przed publikacją. | Testy czasu danych i resetu zdrowia zawiodły przed poprawką; dodatkowy test opóźnionego błędu frakcji. |
| Pusta, poprawnie pobrana lista sugerowała Retry. Dane niedostępne dla Custom key wyglądały jak brak rekordów. Lista cen/wątków mogła pokazywać „Data available” przed pierwszym sukcesem lub po błędach wierszy. | Wspólna prezentacja rozróżnia pierwszy odczyt, poprawną pustą odpowiedź, brak uprawnień, offline i stare dane. Listy korzystają z rzeczywistych dat/błędów swoich wierszy. Zegar jest wstrzykiwany również do ustalania świeżości. | Test pustej odpowiedzi zawiódł przed poprawką; dodatkowe testy uprawnień, zegara, offline i stanów obu list. |
| Odświeżenie forum ignorowało HTTP i niepoprawny JSON. Nowy wpis mógł na stałe pozostać zatytułowany „Loading...”. | Błąd widoczny przy wierszu, zachowanie znanego tytułu/licznika, identyfikator w miejsce niezakończonego ładowania i możliwość odzyskania przez Refresh. | Testy HTTP 503 → zachowanie danych oraz malformed → skuteczne odzyskanie. |
| Akcje pobrania historii/modułu opcjonalnego mogły nie dawać żadnego rezultatu przy offline lub braku uprawnień. | `CompanionStore` wyjaśnia odmowę przed budowaniem zawężonego URL; współdzielone kontrolki pokazują stan sieci/klucza i nie oferują nieskutecznego odświeżania. Recruiting nie wyświetla zamkniętych przestępstw jako otwartych slotów. | Testy odmowy bez wydania budżetu; wygląd kontrolek pozostaje nieweryfikowany w UI. |
| Pierwsze ładowanie wyłączało również Settings, mimo że pole pozwalało zapisać inny klucz. Nakładka przesłaniała ustawienia otwierane podczas oczekiwania. | Wyłączenie dotyczy treści modułu; Settings pozostaje dostępne. Nakładka ładowania nie zasłania Settings. | Zmiana widoku; wymaga interaktywnego QA. |
| Nieprawidłowa wartość czasu w odpowiedzi mogła przepełnić odejmowanie Int i zamknąć aplikację przy wyświetlaniu lotu. Model i widok powielały obliczenia. | Wspólne, ograniczone obliczenie postępu w `Travel`; bezpieczna konwersja czasu i obsługa przyszłego czasu odczytu. | Testy wartości skrajnych oraz zgodności modelu i widoku. |
| Test deklarujący okno 480 pt faktycznie wymuszał minimum 640 pt. Credits miało własną stałą wysokość mimo dostępnej przestrzeni. | Poprawiony limit fixture, asercja rzeczywistej wysokości i przewijanie do akcji; Credits korzysta z wysokości kontenera. | Zmienione testy UI nie były uruchamiane zgodnie z poleceniem użytkownika. |
| Testowy host jednostkowy uruchamiał konfigurację normalnej aplikacji. Wspólny NotificationManager mógł wysyłać/planować i anulować systemowe powiadomienia także z fixture. | Jednostkowy host ma własne preferencje, pusty magazyn kluczy i transport offline. Sentry oraz efekty NotificationManager są wyłączone w testach jednostkowych i UI, włączone normalnie w produkcji. | Test izolacji hosta; brak zmiany produkcyjnych uprawnień. |
| Pola dodania przedmiotu, wątku i progu cenowego opierały nazwę dostępną na placeholderze. Akcja anonimowego przeciwnika mogła być klikalna bez adresata. Zbrojownia była aktywna bez danych frakcji. | Jawne nazwy pól i wyłączenie akcji bez znanego celu/kontekstu. | Kontrola kodu i kompilacja; wymaga VoiceOver/klawiatury w UI. |

## Checklista pokrycia

„Kod” oznacza audyt implementacji. „Unit” oznacza wykonane testy logiki z
syntetycznymi danymi, a nie odwiedziny widoku ani interakcję z produkcyjnym Torn.
Żaden viewport nie został faktycznie uruchomiony w tym audycie.

| Powierzchnia / przepływ | Sprawdzone stany w kodzie i testach logiki | Layout w kodzie | Pokrycie |
| --- | --- | --- | --- |
| Status | pełna odpowiedź, brak danych, błędny klucz, HTTP 403/404/503, malformed, offline/reconnect, cooldown/landing, v2 częściowe | 320 pt, ScrollView, stały footer | Kod + unit; UI niewykonane |
| Travel | dom/lot/zagranica, nieznany cel, wygasły termin bez potwierdzenia lądowania, zegar serwera, skrajne liczby, alerty przed lądowaniem | 320 pt, przewijana siatka 11 celów | Kod + unit; UI niewykonane |
| Attacks | statystyki/ich brak, brak ataków, anonimowy przeciwnik, długie nazwy, bezpieczne sumy | 320 pt, ScrollView i siatka | Kod + unit modeli; UI niewykonane |
| Money | wartości zerowe, brak dostępu, skrajne sumy, opcjonalne trades i ich błędy | 320 pt, ScrollView | Kod + unit; UI niewykonane |
| Properties | brak odpowiedzi vs pusta tablica, wynajem i terminy, skrajne sumy | 320 pt, ScrollView | Kod + unit; UI niewykonane |
| Stocks | brak pozycji, duża fixture, brak metadanych, v2 bonuses, wartość/koszt, błędy i cache referencji | 320 pt, ScrollView | Kod + unit; UI niewykonane |
| Faction | brak frakcji/uprawnień, chain i jego wygaśnięcie, OC, wojna/news, historia i stronicowanie, opóźniona stara odpowiedź | 320 pt, ScrollView | Kod + unit; UI niewykonane |
| Watchlist | zero/jeden/wiele wpisów, dodawanie ID/nazwy, duplikat i złe ID, cache cen, progi, Undo, błędy pobrania | 320 pt, przewijanie, popover progu | Kod + unit; UI niewykonane |
| Forums | URL/ID i błędne wejście, duplikat, metadata/malformed/HTTP, recovery, alerty, kategorie, Undo | 320 pt, ScrollView | Kod + unit; UI niewykonane |
| Settings: 6 kategorii | zapis/migracja/odmowa Keychain, test wpisanego klucza, edycja podczas walidacji, A→B, cadence, wybór przeglądarki, uprawnienia | 320 pt, siatka i ScrollView; dostępne podczas ładowania | Kod + unit logiki; UI niewykonane |
| Diagnostics / Credits | raport bez klucza i PII, stany endpointów, powrót, linki autorów | sheet 380×500; Credits wypełnia kontener | Kod + unit raportu; schowek/linki/UI niewykonane |
| Feedback / Sentry prompt | akcje, Escape, odcięcie tła od AX/pointer, opt-in | nakładki 260/280 pt | Kod + testy polityki; fokus/kontrast nieweryfikowane |
| Widgety: Status / Next / Travel | snapshot bez klucza, stale, terminy, brak grupy/podpisu, reset konta i deeplink | macOS small/medium/large | Kod + unit; systemowe widgety niewykonane |
| Nawigacja / Commands / footer | 9 celów, grupy, Cmd+1…9, Refresh, Settings, Escape, Quit, deeplink | 320×640 produkcyjny popover; fixture 320×480 po poprawce | Kod + istniejące testy logiki; skróty/UI niewykonane |

## Weryfikacja

| Kontrola | Wynik |
| --- | --- |
| Pełne testy bazowe przed zmianami | **808/808**, 0 błędów, 0 pominiętych; `/tmp/mactorn-quality-baseline-full.xcresult` |
| Testy regresyjne przed poprawkami | **8 testów zawiodło**: zapis, migracja, wznowienie klucza, stara walidacja po edycji, kolejność walidacji, czas danych, reset zdrowia konta, pusta odpowiedź |
| Pierwszy pełny przebieg po poprawkach | **826/826**, 0 błędów |
| Końcowy zestaw jednostkowy na najnowszym kodzie | **833/833**, 0 błędów, 0 pominięć, 0 ostrzeżeń runtime; `/tmp/mactorn-quality-final-verified.xcresult`; 164 s samych testów |
| Coverage gate ≥80% | **Niezaliczony — brak danych profilu**. Xcode przy `-enableCodeCoverage YES` nie zapisał `.profraw`; wyeksportowany raport potwierdza `No profile data files were written`. Zielone testy nie są wynikiem coverage. |
| Analiza statyczna Xcode | **Odłożona — podwyższona presja pamięci**, niewykonana |
| Lokalna kompilacja Release / podpis / architektury / skan pakietu | **Odłożone — podwyższona presja pamięci**, niewykonane; nie deklarowano produkcyjnego buildu PASS |
| Testy klikające / interaktywne UI | **Niewykonane na wyraźne polecenie użytkownika** |
| Ikony | **PASS**, 10 przezroczystych PNG o oczekiwanych wymiarach |
| Skan bieżących źródeł gitleaks | **PASS**, brak wykrytych sekretów; bez wypisywania wartości |
| `git diff --check` | **PASS** |

Do weryfikacji używany jest istniejący Xcode 27.0 i przypięta zależność Sentry
9.23.0; nie dodano ani nie zaktualizowano zależności. Pierwsza próba pod sandboxem
zatrzymała się na rozwiązywaniu DNS dla zależności; przebieg z dostępem do sieci
zakończył się sukcesem.

Przy podwyższonej presji pamięci wstrzymano nowe kompilacje. Kontrole wykonywane
są pojedynczo, z `nice -n 15`, `-jobs 1` w ostatnim przebiegu (wcześniej 2)
oraz `-parallel-testing-enabled NO`. Sam dodatkowy Swift flag `-j2` nie gwarantuje
limitu, ponieważ Xcode dopisuje własne `-j12`; ograniczenie zadań nakładano
na zintegrowany system budowania Xcode. Zmniejszenie obciążenia ma pierwszeństwo
przed szybkością zakończenia audytu.

Osiem regresji uruchomiono przed poprawkami i potwierdzono czerwony wynik.
Łącznie dodano 25 testów jednostkowych. Log końcowego przebiegu:
`/tmp/mactorn-quality-final-verified.log`. Raport coverage wyeksportowano do
`/tmp/mactorn-quality-final-coverage/final.xccovreport`; zawiera błąd generowania,
nie pomiar pokrycia. Nie obniżono progu ani nie wyłączono tej kontroli w repozytorium.
Do wyjaśnienia pozostaje zapisywanie profili przez sandboxowany host testowy;
przyczyna nie została jeszcze potwierdzona. Nie ponawiano testów z wyłączonym
sandboxem i nie zmieniano produkcyjnych entitlements.

Zastane ostrzeżenia kompilatora dotyczą testów (nieużyte wyniki i stary sposób
używania NSLock w mocku). Nie są błędami runtime; nie zadeklarowano kompilacji
bez ostrzeżeń. Kontrola typów najnowszej wersji jest częścią udanego buildu testowego.

Po końcowym przebiegu testów system wielokrotnie zgłaszał presję pamięci 2
(ostrzeżenie), przy 24 GB fizycznego RAM i około 18–19 GB użytego swapu.
Dlatego odłożono pozostałe kompilacje zamiast uruchamiać je równolegle z pracą
innych agentów. Na koniec nie pozostawiono działającego procesu testów ani buildu.

## Pozostałe sprawdzenia wymagające człowieka / środowiska

- Wizualny i interakcyjny smoke wszystkich dziewięciu modułów, Settings, Credits,
  nakładek i widgetowego okna; jasny/ciemny motyw, długie dane i wysokości 360/480/640 pt.
- VoiceOver, Full Keyboard Access, widoczność fokusu, powrót fokusu po modalu,
  200% zoom oraz rzeczywiste Reduce Motion/Transparency/Increase Contrast.
- Docelowe linki w Torn, preferowana przeglądarka, systemowe notification consent
  i Launch at Login. Kod poprawnej akcji nie potwierdza dostępności zewnętrznej strony.
- Live API na dedykowanym koncie testowym oraz widgety z prawidłowym podpisem
  Apple i App Group. Brak tych sprawdzeń nie oznacza testu integracyjnego PASS.
- Pomiary CPU/RAM aplikacji w normalnym użyciu i porównanie czasu uruchomienia.
  Nie wykonywano takich pomiarów i nie zadeklarowano przyspieszenia. Odczyty RAM/swap
  hosta służyły wyłącznie ograniczeniu obciążenia, nie benchmarkowi MacTorn.

Sam audyt kodu i zielone testy nie zastępują powyższych sprawdzeń UI/systemowych.
