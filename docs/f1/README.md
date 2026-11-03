# F1: nadgarstek bez japońskich znaków (wrist HUD, Latin only)

Jakub (02.11): "dalej na rece sa jakies japonskie znaczki. prosilem o hp, kalorie, ladunki i ew czas rundy".

## Co jest na nadgarstku
Cztery wiersze po łacinie, od góry, na ciemnej płytce (granat, alfa 0.72, bez cieniowania, bez wpływu na mgłę świata):
- **HP**: pasek (teal → bursztyn → czerwony, pulsuje poniżej 25%) i `aktualne / max`;
- **KCAL**: pasek (pełny przy 100 kcal, skala to decyzja autora, nie ma jej w GDD) i liczba;
- **ŁADUNKI**: trzy kropki w kolorze żywiołu (najstarszy pierwszy); przy zanurzonym ostrzu sekundy w kolorze żywiołu, po prawej na linii kropek;
- **CZAS**: czas rundy `mm:ss`. Awans na chwilę zamienia ten wiersz w `LV n` / `+1 PT`.

Rozmiar czcionek: etykiety 31 px (było 22), wartości 39 px (było 28), czyli +40%. Tekst kremowy (etykiety) i biały (wartości).

API: `DiegeticHud.set_row(key, label, value, ratio, colour, pips, value_colour)`. Wiersz tworzy się przy pierwszym użyciu, ląduje pod poprzednimi, a płytka dopasowuje się do liczby wierszy. F6 (STAMINA) i F7 (DUSZE) dopinają tylko wartość.

Usunięte z nadgarstka (nie są w wymaganiach F1): pierścień HP i shader `wrist_ring.gdshader` (nigdzie indziej nieużywany), znaki żywiołów, glify umiejętności A/B, linia statystyk (ranga, zabójstwa, punkty, XP, fala), buffy z kapliczki (tekst kanji z `run_buffs.gd`). Trzeba je wrócić po latinizacji.

## Kadr i ręka (dlaczego na zrzutach nie widać dłoni)
Zrzuty robi `tests/point15_wrist_screenshot.gd` w `run.tscn` w trybie desktopowym. Ta scena **nie ma modelu dłoni**: nadgarstek w desktopie nie istnieje, a odczyt jest przypięty do kamery (`DESKTOP_OFFSET`, trzymany na H). Dlatego blok "wisi" przed kamerą, a nie na ręce. Ręka z modelem jest w `xr_player.tscn` (test clearance w `wrist_hud_test` mierzy jej siatkę i sprawdza, że płytka jej nie przecina). Zrzut z dłonią wymagałby sceny XR bez HMD, co w tym zadaniu nie zostało zrobione. Kamera jest ta sama PRZED/PO.

## Testy
- `tests/wrist_hud_test.gd` (headless, w suite):
  - zero przecięć dłoni i katany, z kontrolą (test widzi dłoń, gdy odczyt zanurzy się w nią); obszar sprawdzania obejmuje płytkę;
  - wiersze w kolejności HP/KCAL/ŁADUNKI/CZAS; wartości i paski aktualizują się po zmianie HP, KCAL, ładunków i czasu;
  - żaden Label3D w poddrzewie nadgarstka nie ma znaków U+3040–U+30FF ani U+4E00–U+9FFF (w spoczynku, z imbue, w fladze awansu, z buffem w kanji);
  - kontrast tekstu do obrysu ≥ 4.5:1; wiersze mieszczą się w kolumnie i nie nachodzą; `set_row` dokłada wiersz pod CZASEM.
- `tests/wrist_hud_test.gd`, **test pikseli** (tylko z oknem, pod xvfb; headless drukuje SKIP): na scenie `run.tscn` z podniesionym nadgarstkiem odczytuje klatkę i mierzy kontrast tekstu HP (najjaśniejsze 10% pikseli prostokąta etykiety i wartości) względem tła (mediana pierścienia 6 px wokół). Wymóg: ≥ 4.5:1.
  - **Wynik na nowym kodzie: 11.7:1.**
  - **Wynik na 3bfc84f (poprzedni commit): 4.1:1, test FAIL** (sprawdzone, worktree w /tmp, usunięty).
- `quest_perf_test`: wizualne meshe nadgarstka ≤ 9 (płytka 1, paski HP i KCAL 4, kropki 3).
- Dostosowane wcześniej (ta sama treść kontrolna, nowa treść): `element_abilities_test`, `run_loop_test`, `point17_diegetic_critical_test`, `xr_play_test` (widoczność wiersza czasu).

## Zrzuty (gra, `run.tscn`, ta sama kamera i stan HP/imbue)
- `pre_*`: przed zmianą (commit bebe49c, pierścień z kanji). `post_*`: po zmianie (ta runda).
- `*_wrist_hp100_gesture.png`: HP 100%, kcal 42, imbue Storm 12 s. `*_wrist_hp50_gesture.png`: HP 50%, bursztynowy pasek. `*_wrist_hp15_gesture.png`: HP 15%, czerwony pasek. `*_wrist_lowered_hidden.png`: ręka opuszczona, nic nie rysowane.

## Ocena surowa (runda 2)
- **Dobre:** tekst czytelny na pierwszy rzut oka, kontrast 11.7:1 w pikselach (poprzednio 4.1:1); paski HP i KCAL mają sens; kropki i sekundy ładunków nie zlewają się z etykietą (po przesunięciu sekund na linię kropek).
- **Słabe:**
  - Płytka to prosty prostokąt z ostrymi rogami. Wygląda jak karta, nie jak element zegarka. Zaokrąglone rogi wymagałyby shadera; zostawiam jako decyzję Jakuba.
  - Brak ręki w zrzucie: to ograniczenie sceny desktopowej, nie pokazuje, jak blok leży na nadgarstku w goglach. Wymaga weryfikacji na Quest 3.
  - Czytelność z 40 cm nie jest zmierzona w goglach. Pomiar pikseli dotyczy 960×540 na desktopie.
  - Test "H released: the readout hides" przechodzi headless, ale w oknie pada też na 3bfc84f (przyczyna: `_frames` czeka na physics_frame, a fade liczy się w process). To problem istniejący, nie z tej zmiany.
