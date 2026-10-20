# Torn API — audyt MacTorn, 20.10.2026

Last verified: v1.16.0 | 2026-10-20

## Wynik

Spec OpenAPI: **6.13.6 → 6.13.8**. Ostatnie ogłoszenie admina w wątku „Upcoming API changes” jest z 11.09.2026 (6.13.5), więc 6.13.7 i 6.13.8 to ciche poprawki schematu. Żaden endpoint MacTorn nie zmienił kształtu.

Weryfikacja: porównanie modeli Swift z każdym schematem odpowiedzi w spec + żywe zapytania (klucz z `~/.config/torn/config.json`) do wszystkich 21 endpointów aplikacji. Wszystkie odpowiadają, v1 (bars, chain, travel, cooldowns, ataki, faction basic/chain) bez zmian.

## Poprawione w 1.16.0

- `user/competition` to `oneOf` czterech wariantów; aplikacja modelowała tylko Elimination. Na żywo trwa Rock, Paper, Scissors (`status`, `hp`), od 25.10 Halloween (`treats_collected`, `basket`). Dodane wszystkie warianty.
- Kody błędów 32 (endpoint zamknięty do następnego okresu ataków) i 33 (brak konkursu) wpadały w `.temporaryBackend`: komunikat o awarii i czerwony endpoint w Diagnostics. Nowa klasa `.notAvailable`, bez backoffu i bez błędu zdrowia; 33 czyści nieaktualny konkurs.
- Nowa funkcja: `torn/calendar` + opcjonalnie `user/calendar` (osobista godzina startu).

## Pułapka w `torn/calendar`

Dla aktywności, które w tym roku już minęły, Torn zwraca `start` z następnego roku i `end` z bieżącego (`end < start`), np. Elimination start 2027-09-05, end 2026-09-18. `CalendarEntry` normalizuje to do następnego wystąpienia.

## Odrzucone fałszywe alarmy

Spec ma `dirtbombs` i brak `organizedcrimes` w enumach nazw selekcji, ale żywe `key/info` zwraca `dirtybombs` i `organizedcrimes`. To literówki w spec, aplikacja jest poprawna.

## Bez zmian, do pilnowania 1.01.2027

- `faction/warfare` znika: MacTorn używa już osobnych selekcji.
- `torn/items` `value.vendor`/`buy_price`/`sell_price` znikają: MacTorn czyta `value.shops`.
- `attacks.chain` może być `null`: parser v1 tego pola nie czyta.
