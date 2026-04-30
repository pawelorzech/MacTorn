# Plan: Cooldown countdown nie skacze przy każdym pollu

## Context

Po release v1.8.9 (commit `fcbb06d`, "drift-free countdowns" — plan w `MacTorn/Plans/wszystkie-czasy-kt-re-s-dazzling-bumblebee.md`) Paweł nadal widzi drift w licznikach na menubarze, w szczególności dla boostera. Symptom (potwierdzony): **wartość skacze przy każdym pollu, kierunek niekonsekwentny** (raz Mac przyśpiesza, raz zwalnia względem torn.com). To nie jest stały offset clock-skew — to *jitter z każdego odświeżenia z API*.

Cel: po każdym pollu menubarowy `🧪 m:ss` nie wykonuje widocznego skoku. Booster ma kończyć się na Macu w tym samym momencie co na torn.com.

## Mapa wszystkich liczników menubaru i jak są dziś liczone

`MenuBarLabel` (`MacTorn/MacTorn/MacTornApp.swift:51-69`) renderuje pięć stanów wyliczanych przez `AppState.computeMenuBarDisplay()` (`MacTorn/MacTorn/ViewModels/AppState.swift:474-501`) w 1 Hz tickerze (`Timer.publish(every: 1.0)`, linia 436). Każdy stan jest liczony jako `endsAt − Date().timeIntervalSince1970`:

| Stan | Pole źródłowe | Skąd `endsAt` | Skok per poll? |
|---|---|---|---|
| `traveling` | `Travel.timestamp` | absolutny Unix epoch z API | Nie — Torn zwraca jednoznaczny moment lądowania, stały między pollami |
| `hospitalAbroad` / `hospitalAtHome` | `Status.until` | absolutny Unix epoch z API | Nie — `until` ustawione raz w momencie hospitalizacji, niezmienne |
| `jail` | `Status.until` | absolutny Unix epoch z API | Nie — j.w. |
| `cooldown` (drug/booster/medical) | `CooldownEnds.{drug,booster,medical}EndsAt` | **liczone**: `serverTimestamp + cooldowns.{kind}` | **Tak — to ten case** |

Cooldowny są jedyną kategorią, w której API zwraca *duration* (`cooldowns.booster: Int`, sekundy do końca), a `endsAt` powstaje przez dodanie tego do `serverTimestamp` (top-level `timestamp` z odpowiedzi). Konwersja wykonuje się **na każdym pollu** w `parseDataInBackground` (`AppState.swift:1209-1214`):

```swift
if let cooldowns = decoded.cooldowns {
    let anchor = decoded.serverTimestamp ?? Int(Date().timeIntervalSince1970)
    self.cooldownEnds = CooldownEnds.from(cooldowns: cooldowns, anchor: anchor)
}
```

`CooldownEnds.from` (`TornModels.swift:123-129`) tworzy `boosterEndsAt = anchor + cooldowns.booster`. Każdy poll **nadpisuje** `cooldownEnds`.

## Root cause

Jeśli Torn API byłby idealnie spójny (`serverTimestamp` i `cooldowns.booster` reprezentują ten sam moment z dokładnością do milisekund), wtedy między pollami:

- Poll 1: `anchor = T₁`, `booster = D₁` → `endsAt = T₁ + D₁`
- Poll 2 ~30 s później: `anchor = T₂ ≈ T₁+30`, `booster = D₂ ≈ D₁−30` → `endsAt₂ = T₁ + D₁` (identyczne)

W rzeczywistości jest **co najmniej trzy źródła ±1–kilku sekund jittera**, które każde z osobna każą `endsAt` skakać per poll:

1. **Integer truncation po stronie API.** `cooldowns.booster` to `Int` sekund; `timestamp` to `Int` sekund. Jeżeli serwer zaokrągla w różnych miejscach kodu z innym precision (sekundy vs ms vs floor vs nearest), to `(timestamp, booster)` może w jednym pollu zwracać parę "spójną" a w następnym przesuniętą o ±1 s. Każdy ±1 s w którymkolwiek polu = ±1 s w `endsAt`.
2. **Variance latencji sieci.** Między momentem gdy serwer ostempluje `timestamp` a momentem gdy Mac odbierze odpowiedź mija RTT/2. Jeżeli RTT pulsuje (np. 200 ms vs 2 s na nieidealnym Wi-Fi/VPN), `endsAt` "kotwiczy" się na nieco innej rzeczywistości w każdym pollu. Niewidoczne dla absolutnych pól (`travel.timestamp`, `status.until`), ale dla cooldowns zachowuje się jak `±RTT_variance` na `endsAt`.
3. **Cache obecny po stronie ścieżki TCP/CDN.** `URLRequest.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData` (`AppState.swift:1026`) blokuje cache na poziomie URLSession, ale nie pośredników po drodze. Jeżeli poll 2 dostanie odpowiedź z cache 5 s wstecz, `cooldowns.booster` jest stary o 5 s a `timestamp` może być świeży lub równie stary — ich rozjazd da skok w `endsAt`.

Każda z tych przyczyn powoduje że `endsAt` **nie jest tym samym Int** w kolejnych pollach, mimo że *fizyczna chwila końca cooldownu jest jedna*. A skoro pre-tick math to `endsAt − Date()`, każdy nowy poll natychmiast przesuwa wyświetlaną wartość o (`endsAt_new − endsAt_old`) sekund — **widoczny skok**.

Dlaczego to nie dotyczy travel/hospital/jail: Torn zwraca tam jednoznaczny absolutny epoch (`travel.timestamp`, `status.until`), serwer ma go zapisany w bazie i każdy poll zwraca tę samą liczbę. Jitter nie ma się skąd wziąć. Cooldowny mają w bazie *duration* (lub równoważnie expiry obliczane z innej referencji), więc każda odpowiedź zaokrągla na nowo.

## Recommended fix: pinning `endsAt` z tolerancją

Zamiast nadpisywać `cooldownEnds` na każdym pollu, **zachowaj poprzedni `endsAt` jeśli nowy mieści się w tolerancji (≈3 s)**. Większy rozjazd traktuj jako sygnał że cooldown się zaczął/zresetował (nowy booster, medical po szpitalu itp.) — wtedy podmień.

To minimalna chirurgiczna zmiana: nie rusza `Date().timeIntervalSince1970`-based ticka, nie wymyśla globalnego ticker service, nie dotyka travel/hospital/jail (które nie mają problemu).

### Zmiana w modelu

W `CooldownEnds` (`MacTorn/MacTorn/Models/TornModels.swift:118-151`) dodać metodę:

```swift
/// Returns a copy where each `*EndsAt` is kept from `self` when the freshly computed
/// equivalent in `other` is within `toleranceSeconds`. Beyond that we assume the
/// cooldown was reset/started anew on the server and adopt the new value. A value of
/// 0 in either side (cooldown inactive) is always taken from `other` — when a cooldown
/// transitions in/out of active we want the immediate change.
func merged(with other: CooldownEnds, toleranceSeconds: Int = 3) -> CooldownEnds {
    func pick(_ old: Int, _ new: Int) -> Int {
        if old == 0 || new == 0 { return new }       // start / koniec cooldownu
        return abs(new - old) <= toleranceSeconds ? old : new
    }
    return CooldownEnds(
        drugEndsAt:    pick(drugEndsAt,    other.drugEndsAt),
        boosterEndsAt: pick(boosterEndsAt, other.boosterEndsAt),
        medicalEndsAt: pick(medicalEndsAt, other.medicalEndsAt)
    )
}
```

### Zmiana w AppState

`MacTorn/MacTorn/ViewModels/AppState.swift:1209-1214`:

```swift
// before
self.cooldownEnds = CooldownEnds.from(cooldowns: cooldowns, anchor: anchor)

// after
let fresh = CooldownEnds.from(cooldowns: cooldowns, anchor: anchor)
self.cooldownEnds = self.cooldownEnds?.merged(with: fresh) ?? fresh
```

### Co to NIE jest

- Nie dodajemy NTP/clock-sync. Skew Mac↔Torn istnieje, ale skoro każdy poll i tak dawał skoki w obie strony, stały offset to oddzielny (i pewnie pomijalny) temat.
- Nie wracamy do `duration − elapsed_local`. To nie naprawia jittera (każdy poll resetował `(duration, fetchTime)` z tymi samymi wahaniami).
- Nie ruszamy travel/hospital/jail/chain/OC — nie mają tej klasy problemu (źródło `endsAt` to bezpośrednio absolutny epoch z API).
- Nie ruszamy `LiveCooldownItem` w StatusView ani innych widoków. Oni czytają `appState.cooldownEnds` przez `TimelineView`; stabilizacja na poziomie modelu propaguje się automatycznie.

## Pliki do modyfikacji

| Plik | Zmiana |
|---|---|
| `MacTorn/MacTorn/Models/TornModels.swift` | Dodać `CooldownEnds.merged(with:toleranceSeconds:)` |
| `MacTorn/MacTorn/ViewModels/AppState.swift` | W `parseDataInBackground` użyć `.merged(with:)` zamiast nadpisywać |
| `MacTornTests/Models/` (nowy `CooldownEndsTests.swift` lub dopisanie do istniejącego) | Testy: (a) jitter ±2 s zachowuje stary `endsAt`, (b) skok ≥4 s podmienia, (c) `0 → nonzero` zawsze przyjmuje nowy (start), (d) `nonzero → 0` zawsze przyjmuje nowy (koniec) |

## Verification

1. **Unit testy** — `make test`. Nowe testy `CooldownEndsTests` muszą przejść; istniejące testy modeli i `AppStateTests` nie mogą się zepsuć.
2. **Manual smoke** — `make build`, podpiąć prawdziwy klucz API. W trakcie aktywnego boostera obserwować menubar:
   - Co ~30 s (interwał pollu) wartość `🧪 m:ss` ma tykać płynnie 1 s/s, **bez widocznego skoku** w momencie odświeżenia.
   - Po 5–10 minutach koniec boostera na Macu i na torn.com (`/preferences.php` lub `/factions.php` → cooldowns) ma wpaść w obrębie ±3 s.
3. **Reset cooldownu** — gdy ręcznie zaaplikujesz nowy booster (longer cooldown), menubar w ciągu ≤30 s (czyli następnego pollu) powinien podskoczyć do nowego, dłuższego liczenia. To weryfikuje że tolerance nie zacina się na "wiecznym" starym `endsAt`.
4. **Drift soak vs torn.com** — zostaw aplikację na 30 min z aktywnym boosterem + drug + medical. Wszystkie trzy mają tykać monotonicznie i kończyć się ±3 s synchronicznie z webem.
