# N4 – atmosfera pod koncept (stan: CZĘŚCIOWO)

Zrzuty z gry (`run.tscn`, Compatibility, llvmpipe w xvfb, 960×540), ta sama kamera PRZED/PO:
`before_*.png` / `after_*.png`. Odtworzenie: `tests/n4_atmosphere_shots.tscn`
(`-- --desktop --shots=docs/n4 --prefix=before|after`). Pomiary: `tests/atmosphere_metrics.gd`.

## Pomiary (display luminance, 0..1; wartości z przebiegów PRZED/PO)

| kadr | ziemia PRZED | ziemia PO | uwagi |
|---|---|---|---|
| polana (glade) | 0.065 | 0.092 | mech czytelny, nie czarny |
| torii 30 m | 0.009 | 0.024 | nadal ciemno |
| ziemia z bliska (20 m, −30°) | 0.001 | 0.007 | nadal czarne – do dalszej pracy |
| szczyt fali (peak) | 0.056 | 0.205 | |

Zmiany (wszystkie w `WorldGenProfile`, nie hardkodowane):
- `ground_fill` (Ground, domyślnie 0.30; było 0.08 w kodzie) – światło wypełniające grunt.
- `shaft_intensity` (Lights and sky, domyślnie 0.12; było 0.20 w kodzie) – intensywność snopów księżyca.

## Stan punktów z zadania

- (a) mgła płaska – NIE ZROBIONE. Paleta nadal `dusk_mix` 0.3 (fiolet). Propozycja: niższe `dusk_mix` + teal/indygo w `night_blue`; sprawdzić, czy Compatibility obsługuje `fog_height_density` (dziś ustawiane na 0.0 w `WorldGenLook`).
- (b) ziemia – CZĘŚCIOWO: podniesiona w polanie i na szczycie fali, z bliska nadal czarna.
- (c) „chmury" – NIE ZROBIONE. Kanciaste płaty nad kadrem to korony drzew (cedr proceduralny), a nie niebo: `Arena/SkyDome` jest w `DOJO_ONLY_NODES`, więc w biegu nie ma chmur shaderowych. Wymaga przeróbki geometrii koron albo włączenia miękkiej warstwy nieba.
- (d) snop – CZĘŚCIOWO: jasna kolumna z PRZED/PO nie jest już tak mocna (`shaft_intensity` 0.12), ale metryka `shaft` (kolumny top 25%) nie wyizolowała snopu w kadrze polany (nadwyżka 0.18 → 0.19 mimo spadku intensywności) – do sprawdzenia na Queście.
- (e) kurtyna po prawej – NIE ZROBIONE. Źródło: ditherowany cross-fade LOD koron (`forest_diffuse.gdshader`, `lod_band` 9–11 m), a nie deszcz.
- (f) róż sakury / cyjan torii w mgle – NIE ZROBIONE. Torii 30 m: odcień 325° (różowy) vs mgła 228°; cyjan nie dominuje (`torii_glow_strength` 0.12).

## Testy

Dodane do suite jeszcze NIE. Plan: rozszerzyć `tests/worldgen_path_visible_test.gd` (windowed, SKIP w headless) o progi z tych pomiarów: kontrast RMS, luminancja ziemi w [min,max], hue bramy, detektor snopu.

Pełny zestaw (headless, `tools/run_tests.sh 3`): 69/75, jedyny błąd `xr_play_test` (restart ema).
Ten test NIE jest regresją z N4: na czystym HEAD (worktree) też raz przeszedł i raz padł (exit 0, potem exit 1).
