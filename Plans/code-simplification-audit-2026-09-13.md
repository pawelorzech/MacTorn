# MacTorn: analiza uproszczen i wydajnosci

Data: 2026-09-13. Analizowany HEAD: `4244102`. Dokument jest propozycja, nie wdrozeniem.
Kod aplikacji, testy i ich wymagania pozostaja bez zmian.

> Powyzsze opisuje moment audytu. Po akceptacji "ok dzialaj" wdrozono zmiany
> opisane w sekcji "Wdrozenie po akceptacji" na koncu dokumentu.

## Wniosek

Najwiekszy potencjal to mniej powielonych zasad transportu i zarzadzania zadaniami,
a nastepnie mniej parsowania JSON i publikacji widgetow. Nie zalecam przepisywania
aplikacji ani dodawania frameworka. Liczba linii sama nie jest miara wydajnosci.

`AppState` wraz z rozszerzeniami ma 3154 linie; `TornModels.swift` ma 2116.
To liczby fizycznych linii z komentarzami. Podzial tych plikow sam w sobie nie
zmniejszy ilosci logiki ani nie przyspieszy aplikacji.

Analiza obejmuje orkiestracje, serwisy, transport, modele, cache, budzety,
timery, wybrane sciezki widokow, widgety oraz testy i CI. To przeglad statyczny
wsparty uruchomieniem istniejacych testow, nie profil CPU calej aplikacji.

## 1. P1: jedna obsluga transportu i bledow

Dowody:
- `ViewModels/UserSnapshotService.swift:10`: `UserServiceResult` nie ma bledu HTTP;
  `loadActivity`, `loadUserV2` i `loadVirus` nie sprawdzaja zwroconego statusu.
- `ViewModels/FactionService.swift:4`: osobny wynik z bledem HTTP i osobny transport.
- `ViewModels/ForumWatchService.swift:9`: dwa kolejne prawie identyczne enumy wynikow.
- `ViewModels/MarketWatchService.swift:155`: kolejna implementacja; brak odpowiedzi
  HTTP nie jest odrzucany tak samo jak w serwisie forum/frakcji.
- `ViewModels/AppState+FactionFetch.swift:7`: powtarzane switche sukces/API/HTTP/decode
  i mapowanie wyjatkow dla basic, wars i news.

Propozycja: wspolna mala warstwa transportowa z odpowiedzia zawierajaca status,
bajty i czas odbioru oraz wspolnym typem bledow. Dekodowanie i znaczenie wyniku
pozostaja domenowe. Wspolny helper raportuje blad/diagnostyke po kontroli tozsamosci.
Nie nalezy chowac polityki uprawnien, rezerwacji budzetu i publikacji pod ogolnym
frameworkiem sieciowym. `noListings`, jawne null i brak pola nadal sa rozne.

Zysk: usuniecie powielonej obslugi i niespojnosci; przede wszystkim niezawodnosc.
Testy odbioru: HTTP 403/404/429/500, brak HTTP, error envelope w HTTP 200, anulowanie,
czesciowy JSON i zachowanie ostatnich poprawnych danych. Zachowac wszystkie
dotychczasowe scenariusze i asercje serwisow oraz AppState.

## 2. P1: wspolny cykl zycia pobierania metadanych

Dowody:
- `ViewModels/AppState+PollingUserFetch.swift:111`: stocks uruchamia nieprzechowywany
  Task bez ochrony przed kolejnym rownoleglym pobraniem.
- `ViewModels/AppState+PersistenceStocks.swift:23`: po await nie ma kontroli
  generacji konta przed `handleAPIError`.
- `ViewModels/AppState+ItemCatalog.swift:65`: `defer { itemCatalogTask = nil }`
  nie sprawdza, czy zadanie nadal jest wlascicielem uchwytu; po await rowniez brak
  kontroli generacji przed obsluga bledu.
- `ViewModels/AppState.swift:485`: reset anuluje i zeruje uchwyt katalogu
  (dokladne polozenie patrz `resetAccountScopedState`), ale nie zatrzymuje stocks.

Scenariusz wynikajacy z kodu: zadanie stocks dla klucza A czeka na siec, uzytkownik
przechodzi na B, odpowiedz A zawiera blad klucza. Stara odpowiedz wywoluje obsluge
bledu na aktualnym AppState i moze zatrzymac polling B. Anulowane zadanie katalogu
moze tez wyzerowac uchwyt nowszego zadania. Nie wykonano osobnej reprodukcji tych
scenariuszy w tym audycie; wymagaja nowych testow przed naprawa.

Propozycja: jeden niewielki mechanizm single-flight, backoff i wlascicielstwa zadania,
uzywany przez stocks i katalog. Przechowywac tozsamosc konta w momencie startu;
odrzucac stare efekty uboczne po await. Wspoldzielony cache nazw moze zostac globalny,
ale blad starego klucza nie moze zmieniac nowej sesji. Uzyc wstrzyknietego TimeSource.

Odbior: przy opoznionej odpowiedzi wiele tickow oznacza jedno pobranie metadanych;
blad A po przejsciu na B nie zmienia B; zakonczenie A nie usuwa uchwytu B;
anulowanie nie nalicza backoff jak awaria; istniejaca drabina 60/300/1800 s zachowana.

## 3. P1: mniej dekodowania, ciezka praca poza MainActor

Dowody:
- `ViewModels/AppState+PollingUserFetch.swift:572`: caly user JSON jest parsowany
  na MainActor, w tym dla pobrania listy kluczy do logu.
- `ViewModels/UserSnapshotService.swift:88`: ten sam JSON jest ponownie parsowany,
  a nastepnie dekodowany przez JSONDecoder. To trzy odczyty struktury odpowiedzi.
- `ViewModels/UserSnapshotService.swift:205`: sekcje v2 sa zamieniane JSON -> obiekt
  -> ponownie Data -> Decodable.
- `ViewModels/FactionService.swift:126`: podobna ponowna serializacja tablic;
  serwis jest izolowany MainActor.
- `ViewModels/AppState+ItemCatalog.swift:84`: synchroniczne `parseItemCatalog`
  wywolane z MainActor. Samo `nonisolated` na funkcji synchronicznej nie przenosi pracy.

Propozycja: parsowac odpowiedz user raz w serwisie, zachowujac wczesna walidacje
bledu przed uruchomieniem zapytan pobocznych. Stopniowo wprowadzic typowane
dekodowanie poszczegolnych sekcji bez ponownego tworzenia Data. Parsowanie katalogu
i wiekszych odpowiedzi odseparowac od publikacji stanu na MainActor.

Ryzyko: uproszczenie do jednego rygorystycznego DTO moze odrzucac cala odpowiedz
przy uszkodzonej sekcji. Zachowac `UserV2Section.unchanged`, jawne null, walidacje
liczb i kontrakt wymaganych pol. Zachowac czas odbioru do obliczania zegara serwera.

Odbior: benchmark calego `parseSnapshot` i v2, katalog 1500/5000 elementow,
Time Profiler dla glownego watku; identyczne wyniki testow hostile/partial/missing/null.
Obecny benchmark samego TornResponse nie mierzy calej powyzszej sciezki.

## 4. P2: usuniecie martwego kodu i wyniesienie kodu referencyjnego do testow

- `Models/TornModels.swift:1973`: `ForumThreadResponse`, `ForumAuthor`,
  `ForumThreadSummary` nie maja uzyc poza wzajemnymi deklaracjami. Kandydat do
  usuniecia: blok w obszarze 1973-2006 (liczba obejmuje klamry i odstepy).
  Potwierdzic kompilacja wszystkich targetow, zachowujac testy.
- `Models/TornModels.swift:1474`: `TornAPI` dubluje rejestr endpointow.
  Produkcja korzysta z `TornEndpointRegistry`; stare buildery sa uzywane przez testy.
  Przeniesc je jako niezalezny oracle do targetu testowego (okolo 135 linii bloku).
  Nie zastepowac testu porownaniem rejestru do niego samego. Zachowac wszystkie
  asercje URL, kodowania, limitow i auth. To zmniejszenie kodu produkcyjnego,
  nie calkowitej liczby linii repozytorium.
- `ViewModels/AppState.swift:508`: `APIError.invalidData` nie ma uzyc.
- `Utilities/ShortcutsManager.swift:135`: `updateShortcut` i `resetToDefaults`
  nie maja wywolan. To mniejszy kandydat; zachowac odczyt starych ustawien,
  modele kompatybilnosci i ich testy. Sam manager jest uzywany przez StatusView.
- `ViewModels/AppState.swift:497`: drugi NumberFormatter dla liczb calkowitych;
  mozna skierowac konsumentow przez istniejacy TornFormatter po sprawdzeniu formatu.

Zysk glownie w utrzymaniu. Nie obiecuje mniejszego pliku wykonywalnego:
Release juz ma dead-code stripping i optymalizacje kompilatora.

## 5. P2: polaczenie publikacji widgetow w jedna aktualizacje

`ViewModels/AppState+Widgets.swift:29` zapisuje snapshot i wywoluje
`reloadAllTimelines`. W pojedynczym cyklu publikacja moze zajsc po user.fast,
user.v2 i virus (`AppState+PollingUserFetch.swift:755,848,937`). Zapis jest
synchroniczny i atomowy (`WidgetShared/WidgetSnapshot.swift:64`).

Propozycja: laczyc bliskie aktualizacje w jedna publikacje finalnego snapshotu.
Oddzielic swiezosc danych od semantycznej zmiany zawartosci; nie pomijac odswiezenia
`updatedAt` na zawsze tylko dlatego, ze wartosci sie nie zmienily. Reset konta musi
natychmiast wyczyscic snapshot i anulowac oczekujacy zapis.

Odbior: licznik zapisow i zadan reload dla cyklu z trzema odpowiedziami,
test resetu podczas oczekiwania, zachowanie oznaczenia stale po 5 minutach.
Jesli endpoint jest wolny, publikacja podstawowych danych nie powinna na niego czekac.
Liczba zadan reload nie oznacza liczby faktycznych przerysowan WidgetKit.

## 6. P2: nie skanowac calej doby przy kazdym sprawdzaniu limitu

`Utilities/PollingCoordinator.swift:50,102`: `canMakeRequest` usuwa stare elementy
z tablic i skanuje dobowa historie; `count` tworzy dodatkowa tablice przez `filter`.
`record` ponownie usuwa przeterminowane wpisy. Koszt rosnie z liczba wpisow w dobie.

Pierwszy maly krok: zliczanie bez tymczasowej tablicy. Kolejka z indeksami i
inkrementalne sumy tylko jesli pomiar wykaze sens; nie dodawac skomplikowanego
bufora cyklicznego dla niezauwazalnego zysku.

Odbior: benchmark po 10 tys. i 50 tys. wpisow, identyczne decyzje na granicach
60 s/24 h oraz przy zmianach zegara. Istniejace PollingCoordinatorTests pozostaja.

## 7. P2: zatrzymywac timer, gdy odliczanie juz sie skonczylo

`ViewModels/AppState+LiveNextAction.swift:28`: timer wywoluje tylko `tick`.
`shouldRunLiveTimer` sprawdzany jest w `manageLiveTimer`, wywolywanym po snapshotach.
Po zakonczeniu ostatniego cooldownu timer moze dalej budzic aplikacje do kolejnego
udanej aktualizacji; przy braku sieci trwa to dluzej. Guard wartosci ogranicza
publikacje, ale nie zatrzymuje wybudzen.

Propozycja: przy ticku kontrolowac, czy pozostalo cos do odliczania i zatrzymywac
timer. Dla podrozy, szpitala i wiezienia zero oznacza oczekiwanie na potwierdzenie
z serwera, nie potwierdzony powrot/zwolnienie. Zachowac te semantyke.

Odbior: liczba tickow po ostatnim deadline wynosi zero, poprawny restart po nowej
odpowiedzi, wszystkie testy ServerClockOffset i cooldown pozostaja zielone.

## 8. P3: optymalizacje lokalne po pomiarze

- `ViewModels/AppState+ItemCatalog.swift:173`: wyszukiwanie za kazdym razem
  normalizuje nazwy i sortuje wszystkie trafienia przed prefix(limit).
  Posortowany indeks przygotowany raz po zaladowaniu katalogu moze ograniczyc prace.
  Zmierzyc opoznienie wyszukiwania dla 1500/5000 wpisow; zachowac prefix-first,
  case-insensitive i kolejnosc lokalizowana. Ten krok moze dodac kod.
- `ViewModels/MarketWatchService.swift:193`: sortowanie calej listy dla dwoch
  najtanszych ofert mozna zastapic jednym przejsciem. Zachowac znaczenie drugiej
  oferty (moze miec taka sama cene), ilosci i walidacje. Przy malych odpowiedziach
  nie oczekiwac zauwazalnej zmiany.

## Testy i zasady wdrozenia

Nie usuwac testow, nie oslabiac asercji, nie zwiekszac timeoutow lub progow tylko
po to, zeby zmiana przeszla. Refaktor interfejsu moze wymagac zmiany wywolan w testach,
ale wszystkie dotychczasowe scenariusze i niezalezne wartosci oczekiwane zostaja.

Obecne benchmarki `AppStatePerformanceTests` mierza 50 dekodowan malej fixture
oraz 50 parsowan metadanych stocks. W lokalnym przebiegu 2026-09-13 raportowaly
odpowiednio okolo 0.003 s i 0.001 s na partie; rozrzut 45.4% i 17.3%.
Oba wyniki maja puste `baselineName` i `baselineAverage`. To pomiar orientacyjny,
nie dowod przyspieszenia ani skonfigurowany gate regresji czasu wykonania.
Dodac benchmarki rzeczywistych sciezek i porownanie na tym samym toolchainie,
bez oslabiania istniejacych testow. Stabilne liczniki requestow/zapisow/tickow sa
lepszym pierwszym gate niz niestabilny prog milisekund na wspoldzielonym CI.

Kolejnosc wdrozenia:
1. Dodac regresje metadanych z pkt 2, naprawic wlascicielstwo zadan.
2. Usunac jednoznacznie martwe modele, przeniesc oracle TornAPI do testow.
3. Wspolny transport i obsluga bledow, po jednym serwisie.
4. Parsowanie JSON i publikacja widgetow, z pomiarem przed/po.
5. Timer, budzety i wyszukiwanie zgodnie z wynikami pomiarow.

Po kazdym etapie pelne unit tests i dotychczasowy coverage gate >=80%; po zmianach
UI/widgetow/timerow rowniez odpowiednie testy UI i manualne scenariusze. Na koniec
static analysis oraz lokalny build Release dla arm64/x86_64. Bez publikacji.
Gdy krytyczny kod trafi do nowego pliku, dodac go do coverage gate zamiast zgubic
ochrone przez zmiane sciezki. Obecny gate obejmuje tylko piec wymienionych plikow,
nie wszystkie serwisy ani caly AppState.

### Wynik lokalnej walidacji

- Xcode 26.6, build 17F113, macOS arm64. CI wskazuje Xcode 16.4, wiec lokalny
  wynik nie jest potwierdzeniem identycznego zachowania referencyjnego toolchaina CI.
- Pelny target MacTornTests: 738 testow, 0 failures; czas zestawu okolo 139 s.
- Coverage gate 80%: PASS. TornAPIError 90.91%, TornEndpoint 95.12%,
  PollingCoordinator 100%, NotificationCoordinator 98.36%, NextAction 98.88%.
- Wynik: `/private/tmp/MacTorn-analysis-tests-retry.xcresult`.
- Log: `/private/tmp/MacTorn-analysis-tests-retry.log`.
- Pierwsza proba skonczyla sie przed testami na pobieraniu zaleznosci Sentry
  z powodu niedostepnego DNS w sandboxie. Ponowienie z dostepem przeszlo.
- Nie uruchamiano UI tests, Instruments, static analysis ani osobnego Release.
  Nie ma pomiaru CPU, energii lub czasu otwarcia aplikacji. Wnioski o potencjale
  runtime wymagaja opisanych wyzej pomiarow przed/po implementacji.
- Nowe scenariusze ryzyka wykryte statycznie nie sa uznawane za sprawdzone
  tylko dlatego, ze istniejace 738 testow jest zielone.

## Czego nie robic

- Nie usuwac zabezpieczen anulowania, generacji konta, hostile numeric, migracji
  cache ani rozroznienia braku danych od pustego wyniku.
- Nie zmniejszac czestotliwosci wszystkich polli: to zmienia swiezosc alertow.
- Nie dodawac cache odpowiedzi live bez kontraktu swiezosci.
- Nie wdrazac starego planu performance bez ponownej weryfikacji: @Observable,
  guardy zmian wartosci, backoff stocks i batchowanie alertow juz istnieja.
- Nie pomijac dekodowania na podstawie Content-Length: rozne odpowiedzi moga miec
  identyczna dlugosc. Taka sugestia ze starego planu nie jest bezpieczna.
- Nie traktowac migracji Swift 6, podzialu plikow czy zmiany Combine na async
  jako automatycznego przyspieszenia lub redukcji liczby bledow.

## Wdrozenie po akceptacji

Wdrozone lokalnie, bez commita, push ani publikacji:

- Wspolny transport i wynik dla user, faction, forum oraz metadanych; wspolne
  raportowanie bledow z zachowaniem domenowej interpretacji pustych danych.
- Metadane maja jeden request w toku na zrodlo, token wlascicielstwa i kontrole
  konta po await. Reset anuluje ich zadania. Stare/anulowane wyniki nie modyfikuja
  nowej sesji, jej bledow ani backoff. Backoff i wiek katalogu uzywaja TimeSource.
- Usuniete powtorne parsowanie glownego user JSON na MainActor. Niepoprawny
  snapshot nadal pozwala pobrac niezalezne dane opcjonalne; blad API blokuje fan-out.
- User v2 dekoduje sekcje bez ich ponownej serializacji do Data. Zachowane missing,
  explicit null, malformed oraz aktualizacja poprawnych sekcji przy uszkodzonej innej.
- Parsowanie forum, faction i metadanych oraz kodowanie cache metadanych odbywa sie
  poza MainActor przez wspolna granice transportu. Potwierdza to test wykonania.
- Usuniete trzy martwe modele forum, nieuzywane metody edycji skrotow i invalidData.
  Niezalezny oracle TornAPI przeniesiony w calosci do testow, bez zmiany ich asercji.
- Publikacje widgetow sa laczone w oknie 100 ms. Reset konta natychmiast czysci
  snapshot i anuluje oczekujacy zapis. Nowy czas pobrania nadal odswieza widget.
- Timer zatrzymuje sie po ostatnim widocznym odliczaniu. Uplyw terminu podrozy
  nie staje sie potwierdzeniem ladowania; potrzebna jest odpowiedz serwera.
- Test malego okna ujawnil sztywne 640 px w ContentView. Wysokosc przeniesiona do
  panelu MenuBarExtra, a ContentView dostosowuje sie do okna, w tym testowych 480 px.

Bilans kodu produkcyjnego: 420 linii mniej netto (fizyczne linie razem z komentarzami).
Czesc to przeniesienie oracle do testow; nie jest to obietnica zmniejszenia binarium.
Zachowano wszystkie istniejace testy i asercje, dodano 11 nowych testow jednostkowych.
Coverage gate rozszerzono o NetworkSession.swift przy niezmienionym progu 80%.

Dowody regresji i redukcji pracy:

- Przed naprawa dwa nowe testy metadanych odtworzyly 10 nieudanych asercji dla
  starego konta i anulowania; po naprawie przechodza.
- Dwa rownolegle wywolania pobierania danego rodzaju metadanych: 1 request.
- Trzy bliskie publikacje widgetow: 1 zapis i 1 zadanie odswiezenia, z najnowszym
  snapshotem. Kolejny czas pobrania nadal powoduje nowa publikacje.
- Wygasly timer: brak aktywnego timera; nowy cooldown uruchamia go ponownie.
- Pelny zestaw jednostkowy: 749 testow, 0 failures. Dotychczasowy baseline: 738.
- Coverage gate: PASS. Nowy transport 100%; pozostale wartosci takie jak w audycie.
- Wynik jednostkowy: `/private/tmp/MacTorn-optimized-unit-final.xcresult`.
- Koncowe `xcodebuild analyze build` Release: PASS, aplikacja i widgety maja
  architektury arm64/x86_64. `codesign --verify --deep --strict`: PASS, podpis ad-hoc.
- Log analizy i buildu: `/private/tmp/MacTorn-optimized-release-final.log`.
- Lokalny build: `/private/tmp/MacTorn-optimized-release/Build/Products/Release/MacTorn.app`.
- UI: 13/14 scenariuszy przeszlo w pelnym przebiegu; test forum zaslonilo
  zewnetrzne okno 1Password wywolane przez Warp (potwierdzone nagraniem testu).
  Powtorka tego samego testu, bez zmian kodu ani asercji: PASS. Lacznie wszystkie
  14 scenariuszy zaliczone, ale nie w jednym czystym przebiegu.
- Wyniki UI: `/private/tmp/MacTorn-optimized-ui-final.xcresult` oraz
  `/private/tmp/MacTorn-forum-ui-retry.xcresult`. W pierwszym przebiegu rowniez
  27 testow metadanych i katalogu na koncowych zrodlach: PASS.
- Uzgodniony zakres przyszlego release: GitHub Releases z nowym plikiem `.dmg`
  oraz zastapienie lokalnie zainstalowanej aplikacji nowa wersja. Sam build Release
  nie oznacza wydania. W tym etapie nie publikowano ani nie zastepowano instalacji.

Pozostawiono bez zmian licznik dobowego budzetu, indeks wyszukiwania, sortowanie
ofert i formatowanie liczb. Pierwsze trzy wymagaja pomiaru przed dodawaniem bardziej
zlozonego kodu; formatery maja rozne ustawienia locale. Nie ma wiarygodnego pomiaru
procentowego przyspieszenia calej aplikacji ani energii, wiec takie wartosci nie sa
deklarowane. Testy liczby operacji nie sa pomiarem czasu CPU calego procesu.
