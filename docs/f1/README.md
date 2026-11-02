# F1: nadgarstek bez japońskich znaków (wrist HUD, Latin only)

Jakub (02.11): "dalej na rece sa jakies japonskie znaczki. prosilem o hp, kalorie, ladunki i ew czas rundy".

## Co zrobione
- Nadgarstek pokazuje teraz cztery wiersze, po łacinie, od góry:
  - **HP**: pasek (teal → bursztyn → czerwony, pulsuje poniżej 25%) i liczba `aktualne / max`;
  - **KCAL**: pasek (pełny przy 100 kcal, skala decyzja autora) i liczba;
  - **ŁADUNKI**: trzy kropki w kolorze żywiołu (najstarszy pierwszy), a przy zanurzonym ostrzu sekundy w kolorze żywiołu;
  - **CZAS**: czas rundy `mm:ss`. Awans na chwilę zamienia ten wiersz w `LV n` / `+1 PT`.
- API: `DiegeticHud.set_row(key, label, value, ratio, colour, pips, value_colour)`. Wiersz tworzy się przy pierwszym użyciu i ustawia się pod poprzednimi, więc F6 (STAMINA) i F7 (DUSZE) dopinają tylko wartość.
- Usunięte z nadgarstka: pierścień HP i kulki ładunków w shaderze (`src/shaders/wrist_ring.gdshader` skasowany, nie był używany nigdzie indziej), znaki żywiołów i glify umiejętności A/B, linia statystyk (ranga, zabójstwa, punkty, XP, fala), buffy z kapliczki (tekst kanji z `run_buffs.gd`). Nie są w wymaganiu F1; patrz "Słabe".
- Bez zmian: gest "spojrzenie na zegarek", histereza, fade, odległość/kąt, SANDBOX, zrzut kanji nie występuje w żadnym napisie HUD (sprawdza test).

## Testy
- `tests/wrist_hud_test.gd`: zerowe przecięcia dłoni i katany (także kontrola: test widzi dłoń, gdy odczyt zanurzy się w nią); wiersze w kolejności HP/KCAL/ŁADUNKI/CZAS; wartości i paski aktualizują się po zmianie HP, KCAL, ładunków i czasu; żaden Label3D w poddrzewie nadgarstka nie ma znaków U+3040–U+30FF ani U+4E00–U+9FFF (w spoczynku, z imbue, w fladze awansu, z buffem w kanji); kontrast tekstu do obrysu ≥ 4.5:1; wiersze mieszczą się w kolumnie i nie nachodzą; `set_row` dokłada wiersz pod CZASEM.
- Dostosowane (ta sama treść kontrolna, nowa treść): `element_abilities_test`, `run_loop_test`, `point17_diegetic_critical_test`, `quest_perf_test` (mesh budget), `xr_play_test` (widoczność wiersza czasu).

## Zrzuty (gra, `run.tscn`, ta sama kamera i stan HP/imbue)
- `pre_*` – przed zmianą (pierścień z kanji), `post_*` – po zmianie.
- `*_wrist_hp100_gesture.png`: HP 100%, kcal 42, imbue Storm 12 s. `*_wrist_hp15_gesture.png`: HP 15%, czerwony pasek. `*_wrist_lowered_hidden.png`: ręka opuszczona, nic nie rysowane.

## Ocena surowa
- **Dobre:** żadnego kanji na nadgarstku, czytelne etykiety łacińskie, paski HP i kcal widać na pierwszy rzut oka, kolor HP działa (teal/bursztyn/czerwony), kropki ładunków w kolorze żywiołu.
- **Słabe:**
  - Tekst jest mały w oknie 960×540: w goglach trzeba potwierdzić czytelność z ~40 cm na Quest 3. Nie mam gogli; to nie jest zweryfikowane.
  - Szary tekst na jasnym kamieniu ma słaby kontrast brzegów. Obrys podniosłem z 8 do 14; kontrast etykiet jest policzony tylko względem obrysu, nie tła.
  - Skala paska KCAL (100 kcal) to decyzja autora, nie zapisana w GDD.
  - Wycięte: statystyki biegu (ranga, zabójstwa, XP, fala), buffy z kapliczki, gotowość umiejętności A/B. Gracz ich już na nadgarstku nie zobaczy; trzeba je wrócić po latinizacji (F6/F7 albo osobne zadanie).
  - Pierścień był ładniejszy wizualnie; rzędy są czytelniejsze, ale mniej "premium". Do oceny Jakuba.
