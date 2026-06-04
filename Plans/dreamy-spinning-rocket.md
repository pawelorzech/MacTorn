# Plan — Sentry HTTPClientError 504 wciąż się pojawia

## Context

Paweł zgłosił, że `HTTPClientError: HTTP Client Error with status code: 504` (Sentry MACTORN-1) **nadal się pojawia**, mimo że w commicie `e54fc80` rzekomo to naprawiliśmy.

**Diagnoza: fix istnieje na `main`, ale nigdy nie został wydany.** Tag `v1.8.10` został utworzony **przed** commitem z fixem, więc binarka w rękach użytkowników nie zawiera zmiany. Sentry pokazuje issue jako "resolved in mactorn@1.8.10", ale eventy dalej napływają z 1.8.10 (count=71, 6 użytkowników, lastSeen=dzisiaj 2026-05-12 12:44Z), bo użytkownicy nadal odpalają tę samą binarkę.

To dokładnie ten sam wzorzec, który skill `sentry-fix` ostrzega w sekcji Step 9 ("Paweł noticed the gap once — fix didn't surface in ... page because we shipped without bumping").

## Evidence

| Co | Kiedy |
|---|---|
| Tag `v1.8.10` (commit `fd2ad37`) | przed `2026-04-30 21:02Z` (data uploadu release'u do Sentry) |
| Sentry release `mactorn@1.8.10` utworzony | `2026-04-30 21:02:51Z` |
| Issue MACTORN-1 firstSeen | `2026-05-01 00:00:45Z` (kilka godzin po release) |
| Commit `e54fc80` (fix) | `2026-05-01 14:06:36 +0200` ← **POST tag** |
| Najnowszy event MACTORN-1 | `2026-05-12 12:44:44Z` (dziś), release nadal `mactorn@1.8.10` |
| Issue status w Sentry | `resolved` in `mactorn@1.8.10` (semantyka Sentry: eventy z ≤1.8.10 nie regresują issue, więc nie ma alertów — ale licznik rośnie) |
| Sentry releases istniejące | tylko `1.8.9` i `1.8.10`. **Brak `1.8.11`.** |

Commity od `v1.8.10` do `HEAD`:
```
e54fc80 fix: don't auto-capture upstream HTTP failures in Sentry (MACTORN-1)
24cb2a6 chore: ignore .playwright-mcp/ session logs
```

Diff samego fixa (`MacTorn/MacTorn/Utilities/SentryManager.swift:66-67`):
```swift
+// Torn API 5xx are upstream noise, not MacTorn bugs — don't auto-capture them.
+options.enableCaptureFailedRequests = false
```

To poprawna opcja Sentry-Cocoa 9.x do wyłączenia auto-capture failed HTTP requests. Mechanism w evencie to dokładnie `HTTPClientError` — odpowiada tej opcji. Stacktrace `frames_in_app: []`, wszystkie ramki z `CFNetwork` / `libdispatch` — potwierdza, że capture pochodzi ze swizzlingu URLSession Sentry, nie z naszego kodu (`grep` po `SentrySDK.capture` w repo: zero trafień).

**Wniosek**: fix jest poprawny technicznie. Wystarczy go wydać.

## Recommended approach — wydać v1.8.11

Standardowy release flow tego repo (zgodny z poprzednimi 10 wersjami w `git log`). Skill `new-version` może to ogarnąć automatycznie, ale poniżej kroki gdyby trzeba ręcznie.

### Krytyczne pliki do edycji

1. **`MacTorn/MacTorn.xcodeproj/project.pbxproj`** — `MARKETING_VERSION` w 6 miejscach (linie 716, 743, 760, 778, 795, 812). Bump `1.8.10` → `1.8.11`. `CURRENT_PROJECT_VERSION = 1` można zostawić — to internal build number, nie wymaga zmiany przy patch bumpie. Wszystkie 6 wystąpień to ten sam string, więc `Edit replace_all` na `MARKETING_VERSION = 1.8.10;` → `MARKETING_VERSION = 1.8.11;`.

2. **`CHANGELOG.md`** — prepend sekcji na górze (zaraz po nagłówku, przed `## [1.8.10]`). Wpis krótki, user-facing framing (zgodny ze stylem poprzednich wpisów):

```markdown
## [1.8.11] - 2026-05-12

### Fixed
- **Stop wysyłania szumu Sentry dla błędów Torn API 5xx.** Sentry-Cocoa 9.x domyślnie auto-kaptury wszystkich odpowiedzi URLSession ze statusem 500–599 jako błędów aplikacji (`enableCaptureFailedRequests = true`). Gdy Torn API zwracał 504 Gateway Timeout (upstream przeciążenie, nie nasz bug), Sentry raportowało to jako błąd MacTorn — w 1.8.10 wpłynęło 71 takich eventów od 6 użytkowników. Teraz `enableCaptureFailedRequests = false`. Crashe i jawne `SentrySDK.capture()` nadal działają. Fix był w kodzie od commita `e54fc80`, ale tag `v1.8.10` powstał wcześniej i go nie zawierał — `v1.8.11` to faktyczna dystrybucja.
```

3. **`README.md`** — brak twardych referencji do wersji w treści (sprawdziłem `grep`em). Nie wymaga zmian.

### Build + release commands

```bash
make release            # Universal Binary (Intel + Apple Silicon)
# binarka ląduje w build/Build/Products/Release/MacTorn.app — manual DMG per deploy_target
```

### Commit + tag + push

```bash
git add MacTorn/MacTorn.xcodeproj/project.pbxproj CHANGELOG.md
git commit -m "Release v1.8.11: nie raportuj Torn API 5xx jako błędów MacTorn

Fix był w commicie e54fc80, ale tag v1.8.10 powstał wcześniej i nie
zawierał tej zmiany. v1.8.11 to faktyczna dystrybucja fixa, który
ustawia options.enableCaptureFailedRequests = false w SentryManager.

Fixes Sentry: https://mactorn.sentry.io/issues/116732630/ (MACTORN-1)"
git tag v1.8.11
git push origin main
git push origin v1.8.11
```

### Distribution

`deploy_target = manual-dmg` (z `~/.config/sentry/projects.json`). Po `make release` Paweł ręcznie pakuje DMG i wrzuca tam gdzie zwykle (GitHub Releases? Ad-hoc download? README mówi "ad-hoc signed direct download"). Ten plan nie automatyzuje uploadu — to osobny krok.

## Verification

1. **Sanity check przed releasem**: `grep "enableCaptureFailedRequests" MacTorn/MacTorn/Utilities/SentryManager.swift` zwraca linię z `false`. (Już potwierdzone — `SentryManager.swift:67`.)
2. **Build**: `make release` przechodzi czysto, `make test-all` zielony.
3. **Smoke test lokalny**:
   - Odpal nową binarkę, włącz Sentry w Settings.
   - Zasymuluj 504 (np. punkt-in-time gdy Torn rzeczywiście leży, albo czasowo wsadź `https://httpbin.org/status/504` w `TornAPI.userData` — i cofnij).
   - W konsoli Sentry sprawdź, że event NIE pojawia się w issue list dla `release:mactorn@1.8.11`.
4. **Post-deploy verification (T+24h)**:
   ```bash
   TOKEN=$(jq -r .personal.auth_token ~/.config/sentry/credentials.json)
   curl -s -H "Authorization: Bearer $TOKEN" \
     "https://sentry.io/api/0/projects/mactorn/mactorn/issues/?query=is:unresolved+release:mactorn@1.8.11&statsPeriod=24h"
   ```
   Oczekiwany wynik: brak `HTTPClientError` w `1.8.11`. Eventy z `1.8.10` mogą jeszcze kapać przez kilka dni, dopóki użytkownicy nie zaktualizują — to normalne i niegroźne (issue jest `resolved`, nie regresuje od starszej release'y).

## Sentry-side actions

**Żadne**. Issue jest już `status: resolved` w 1.8.10. Tail eventów z 1.8.10 nie spowoduje regression bo Sentry traktuje "events from <= resolved release" jako residual lag, nie nowy bug. Po ~7-14 dniach, gdy większość userów zaktualizuje, count się ustabilizuje.

Gdyby Paweł chciał ciszej widać licznik wcześniej: opcjonalnie po wydaniu można `PUT status:ignored` z `ignoreWindow: 10080` (7d) na MACTORN-1, ale to kosmetyka — alerty i tak nie lecą. **Domyślnie: nic nie ruszamy w Sentry.**

## Anti-rules

1. **Nie próbować "lepszego" fixa** — kod jest poprawny, problem to deployment gap. Zmiana w `SentryManager.swift` w tym planie = ZERO. Tylko version bump + changelog + tag + release.
2. **Nie usuwać `enableCaptureFailedRequests = false`** — to ten line, który rozwiązuje problem.
3. **Nie bumpować do 1.9.0** — nie ma nowej feature'y, to patch bugfix.
4. **Nie commitować bez zbumpowania `MARKETING_VERSION`** — inaczej "Release v1.8.11" commit miałby w środku binarkę 1.8.10 i Sentry znowu otagowałby eventy jako `1.8.10`, powtarzając ten sam problem.
5. **Nie zmieniać `CURRENT_PROJECT_VERSION`** — to internal build number, nieużywany przez Sentry release tagging (`releaseName = "mactorn@\(CFBundleShortVersionString)"` w `SentryManager.swift:50`, czyli czyta `MARKETING_VERSION`).
