# N6: kapliczka i latarnia (focal point)

Czarny prymityw kapliczki zamieniony na dom z assetu, z ciepłą świecą. Latarnia Sahir ma ciepły papier.

## Co się zmieniło

- **Kapliczka** (`src/world/hokora_shrine.gd`): dom SamRi „Small Japanese Shrine” (CC BY 4.0,
  2787 tris), zapieczony w metrach przez `tools/prep_forest_assets.py --scale 1.0 --atlas 2048`,
  `assets/models/environment/shrine/shrine_samri_baked.glb`. `MODEL_OFFSET` ustawia podłoże na y = 0
  i front (lina shimenawa, +z) tam, gdzie oczekują `ALTAR_LOCAL`, `BELL_LOCAL`, `LANTERN_LOCAL`.
  Materiał: shader `wet_surface` z atlasem skanu, mokry, z omszeniem górnych powierzchni (`moss_amount`),
  `sky_lit` 1.0 (podnosi albedo ciemnego drewna w nocy), `fog_rim` 0.6, `emission_tint` (0.9, 0.55, 0.28).
  Stół ofiarny, obrus, suzu i interakcja dłonią (D12) bez zmian.
- **Świeca i jedno światło**: płomień za kratą (emisja) plus `OmniLight3D` (zasięg 4.0 m, energia 8,
  bez cieni), przed domem nad stołem, tylko dla najbliższej zapalonej kapliczki w promieniu 30 m.
  W scenie najwyżej jedno takie światło (budżet ≤ 12).
- **Latarnia** (`src/run/forest_world.gd`, `_lantern_mat`): `paper_gate` (nowy parametr shadera) pozwala
  świecić tylko jasnemu, nasyconemu papierowi. Kamień nie świeci. `sky_lit` 0.8, `fog_rim` 1.0,
  `moss_amount` 0.5 (omszałe czapy). Bez dynamicznego światła.
- **Przyczyna brązowego kamienia (naprawiona w bake'u)**: `tools/prep_forest_assets.py` układał wiersze
  atlasu od góry, a trimesh zapisuje V odwrócone. W grze korpus latarni próbkował ciemnobrązowy
  kwadrat (lattice, ok. 31,18,10) zamiast szarego (ok. 95,94,94). Poprawka: `uv[:,1] = 1 - (r + 1 - v) / rows`.
  Po ponownym bake'u latarnia (3140 tris, 1.46 m) i kapliczka (2787 tris) mają poprawne komórki
  (sprawdzone w Godot: kamień = szary kwadrat). `stone_lantern_sahir_0.png` i `shrine_samri_baked_0.png`
  zaktualizowane.
- Rezerwa pnia (`reserve_shrine`), placement P4 i ofuda nie zmienione.

## Testy

- `tests/hokora_test.gd` (headless): dom to mesh z assetu (nie BoxMesh, ≤ 3000 tris, shader z atlasem);
  jedno światło świecy w całym przebiegu; zgaszona kapliczka gasi światło. Dotyk nadal otwiera 3 ofuda,
  drugi nic nie daje.
- `tests/hokora_test.gd` (okienkowy, pixele, SKIP headless), wynik ostatniego przebiegu:
  - 20 m: halo ciepłe (hue 31°, sat 0.55), jaśniejsze od nieba (glow 0.58, niebo 0.01): **PASS**.
  - 3 m: średnia luminancja bryły **0.125** przy progu 0.10 (cel 0.12): **PASS**. Zapas nad progiem 0.025.
  - 10 m latarnia, papier warm (46°) i jaśniejszy od kamienia (papier 0.84 vs mediana kamienia 0.01): **PASS**.
  - 10 m latarnia, kamień szarawy: nasycenie średniego koloru trzonu **0.11** (próg < 0.25): **PASS**.
- `tests/d5_assets_test.gd`: licencje (w tym `assets/models/environment/shrine`): **PASS**.
- Funkcje pikseli są w `tests/hokora_test.gd`. Osobny `tests/shot_probe.gd` usunięto.

Progu 3 m (0.10) nie obniżono. Wynik osiągnięto światłem, emisją i `sky_lit`.
Pierwsza wersja testu kamienia liczyła średnią nasycenia pikseli. Zawyżał ją szum w ciemnych pikselach,
więc przeszedłem na nasycenie średniego koloru.

## Zrzuty (`docs/n6/`)

- `pre/`: stan przed zmianą (ten sam kadr i kamera).
- `post/`: stan po zmianie, z `run.tscn` (`tests/hokora_screenshots.gd`):
  00 daleko we mgle, 01 z ~3 m w nocy, 02–03 wybór ofuda, 08 latarnia z 10 m.

## Otwarte problemy

- **Bake drzew, podszytu i reszty zrobiony starym kodem.** Poprawka V dotyczy tylko nowych bake'ów.
  Assety zapieczone wcześniej (drzewa, paprocie, toro, kamienie) mogą mieć ten sam błąd komórek
  atlasu. Wymagają ponownego bake'u i sprawdzenia w Godot, zanim uznamy je za poprawne.
- **Światło dotyka pobliskiego pnia** (ok. 4–5 m): tan refleks. Zasięg zmniejszony do 4 m, ale nie wyzerowany.
- **Zapas 3 m to 0.025 nad progiem.** Ciemne drewno jest czytelne, ale wciąż nie jest mocno oświetlone.
- **Pomiar kamienia w teście 10 m** (`stone 0.01`) bierze prostokąt z tłem, więc jest słabym miernikiem jasności.
  Sprawdzana jest tylko szarość, a nie jasność kamienia.
- `hokora_screenshots.gd`: „damage buff runs after the cut” zwraca FAIL także przed N6 (nie N6).
- `xr_play_test` (`cutting the restart ema`) jest niestabilny, także na czystym `HEAD`. Zaparkowany do N7.
