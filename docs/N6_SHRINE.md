# N6: kapliczka i latarnia (focal point)

Czarny prymityw kapliczki zamieniony na dom z assetu, z ciepłą świecą. Latarnia Sahir ma ciepły papier.

## Co się zmieniło

- **Kapliczka** (`src/world/hokora_shrine.gd`): dom SamRi „Small Japanese Shrine” (CC BY 4.0,
  2787 tris, zapieczony w metrach przez `tools/prep_forest_assets.py --scale 1.0 --atlas 2048`,
  `assets/models/environment/shrine/shrine_samri_baked.glb`). `MODEL_OFFSET` ustawia podłoże
  na y = 0 i front (lina shimenawa, +z) tam, gdzie oczekują stałe `ALTAR_LOCAL`, `BELL_LOCAL`, `LANTERN_LOCAL`.
  Dom dostaje shader `wet_surface` z atlasem skanu: mokry, z omszałymi górnymi powierzchniami
  (`moss_amount`), z lekkim `sky_lit` i `fog_rim`, żeby ciemne drewno zachowało formę w nocy.
  Stół ofiarny, obrus, suzu i interakcja dłonią (D12) zostają bez zmian.
- **Świeca i jedno światło**: płomień za kratą (emisja) plus `OmniLight3D` (zasięg 3.5 m,
  energia 7, bez cieni), przed domem nad stołem, tylko dla najbliższej zapalonej kapliczki w promieniu 30 m.
  W scenie jest najwyżej jedno takie światło (budżet ≤ 12).
- **Latarnia** (`src/run/forest_world.gd`, `_lantern_mat`): `paper_gate` (nowy parametr shadera) pozwala
  świecić tylko jasnemu, nasyconemu papierowi. Kamień i ciemne drewno nie świecą, więc kamień nie
  wychodzi już rdzawy. Dodane: `moss_amount` 0.5 (omszałe czapy), `sky_lit` 0.3, `fog_rim` 1.0.
  Bez dynamicznego światła.
- Rezerwa pnia (`reserve_shrine`), placement P4 i ofuda nie zmienione.

## Testy

- `tests/hokora_test.gd` (headless): dom to mesh z assetu (nie BoxMesh, ≤ 3000 tris, shader z atlasem);
  jedno światło świecy w całym przebiegu; zgaszona kapliczka gasi światło. Dotyk nadal otwiera 3 ofuda,
  drugi nic nie daje.
- `tests/hokora_test.gd` (okienkowy, pixele, SKIP headless):
  - 20 m: halo ciepłe (hue 30°) i jaśniejsze od nieba (glow 0.60, niebo 0.01): **PASS**.
  - 3 m: średnia luminancja bryły 0.105 przy progu 0.10: **PASS**. Margines jest cienki (0.005).
  - 10 m latarnia: papier warm (41°) i jaśniejszy od kamienia (papier 0.62, kamień 0.00): **PASS**.
- `tests/d5_assets_test.gd`: licencje (w tym `assets/models/environment/shrine`): **PASS**.
- Pomocnicze funkcje pikseli są w `tests/hokora_test.gd` (usunięto osobny `tests/shot_probe.gd`).

Progu 0.10 nie obniżono. Wynik osiągnięto przez światło, emisję i `sky_lit`.

## Zrzuty (`docs/n6/`)

- `pre/`: stan przed zmianą (ten sam kadr i kamera).
- `post/`: stan po zmianie, z `run.tscn` (`tests/hokora_screenshots.gd`):
  00 daleko we mgle, 01 z ~3 m w nocy, 02–03 wybór ofuda, 08 latarnia z 10 m.

## Słabe punkty (uczciwie)

- **Kamień latarni wychodzi ciemnobrązowy, nie szary.** Przyczyna leży w atlasie: części kamienia
  próbkują ciemnobrązowy kwadrat atlasu (ok. 31,18,10), a szary kwadrat (ok. 95,94,94) nie jest
  przypisany do korpusu. Materiał tego nie naprawi. Trzeba poprawić bake (`tools/prep_forest_assets.py`)
  albo mapowanie UV. Nie zrobiłem tego w tej rundzie.
- **Próg 3 m przechodzi o 0.005.** Bryła jest czytelna, ale nie jest „premium” oświetlona.
  Ciemne drewno lepiej wygląda z ciepłym światłem niż z wyższą luminancją.
- **Światło dotyka pobliskiego pnia** (ok. 4–5 m): tan refleks. Zmniejszony zasięgiem, ale nie wyzerowany.
- **Ciemny ołtarz i czerwone krawędzie dachu** (kolor skanu) mogą się gryźć z resztą lasu.
- `hokora_screenshots.gd`: „damage buff runs after the cut” zwraca FAIL także przed N6 (nie N6).
- `xr_play_test` (`cutting the restart ema`) jest niestabilny też na czystym `HEAD`. Zaparkowany do N7.
