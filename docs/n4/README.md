# N4 – atmosfera pod koncept

Zrzuty z gry (`res://scenes/run.tscn`, Compatibility, xvfb/llvmpipe, 960×540), ta sama kamera PRZED/PO.
Odtworzenie: `tests/n4_atmosphere_shots.tscn` (`-- --desktop --shots=docs/n4 --prefix=final`).
Pomiary: `tests/atmosphere_metrics.gd` (ta sama logika w zrzutach i w suite).
Wszystkie parametry są w `WorldGenProfile` (`data/worldgen/default_profile.tres` + domyślne w skrypcie).

Pliki: `before_*.png` (PRZED, kod sprzed N4), `final_*.png` (PO, ten commit),
`contact/` + `n4_contact_sheet.png` (koncept obok PRZED i PO).

## Co zmieniono (profil)

| parametr | było | jest | po co |
|---|---|---|---|
| `night_blue` | (0.12, 0.26, 0.34) | (0.13, 0.12, 0.32) | mgła indygo zamiast płaskiego fioletu |
| `dusk_mix` | 0.30 | 0.12 | mniej różu w mgle; róż zostaje w sakurze |
| `ground_fill` (nowe) | 0.08 (w kodzie) | 0.60 | ziemia czytelna, nie czarna |
| `shaft_intensity` (nowe) | 0.20 (w kodzie) | 0.12 | snop księżyca subtelniejszy |
| `lod_fade` | 2.0 | 0.5 | kurtyna dithera LOD węższa (≈0.5 m zamiast 2 m) |
| `crown_haze_low/high/amount` (nowe) | brak | 8 / 22 m / 0.45 | wysokościowa mgła: górne korony rozmywają się w mgle |
| `distance_haze_start/end/max` (nowe) | 14 / 40 m / 0.5 (w shaderze) | 20 / 40 m / 0.5 | pnie 20 m+ nie zlewają się z mgłą od 14 m |
| `torii_glow_strength` | 0.12 | 0.50 | poświata bramy (cyjan dla żywiołu STORM) |

Shadery: `forest_diffuse.gdshader` (wysokościowa i odległościowa mgła, parametry z profilu),
`forest_ground.gdshader` bez zmian (używa `ambient_fill` z profilu).

## Pomiary PRZED → PO (display luminance; ta sama kamera)

| kadr | miara | PRZED | PO | próg testu |
|---|---|---|---|---|
| polana | RMS kadru | 1.15 | 1.46 | ≥ 1.20 |
| polana | ziemia obok ścieżki (średnia) | 0.065 | 0.130 | 0.08 … 0.25 |
| z bliska (20 m, −30°) | ziemia | 0.001 | 0.016 | ≥ 0.012 |
| torii 30 m (żywioł STORM) | udział cyjanu w oknie wokół bramy | n/a* | 0.022 | ≥ 0.015 |
| torii 30 m | odcień bramy − odcień mgły | n/a* | 10.4° | ≥ 8° |
| polana | snop: szerokość / szczyt | 0.010 / 0.18 | 0.013 / 0.21 | ≤ 0.10 / ≤ 0.30 |

\* PRZED bramy były losowego żywiołu (często różowego sakury), więc nie są porównywalne; tu podano PO.
Progi ustalone z tych pomiarów; kilka z nich (ziemia, RMS) jest celowo wąskich, żeby wyłapać powrót do czarnej ziemi i wypranego kadru.

## Co NIE jest zrobione (otwarte)

- **Pień vs mgła 8–20 m** (część testu 1): sprawdzenie jest w suite jako INFORMACYJNE, nie jako PASS/FAIL.
  Powód: punkty „mgły" obok pnia często trafiają w ciemny grunt za pniem, a nie w mgłę, więc pomiar nie
  mierzy kontrastu pień–mgła. Do zrobienia: maska mgły (kolor/jasność z tła nieba) zamiast punktu obok.
- **Mgła gradientowa / height fog z Environment**: NIE użyto. Wysokościowa mgła jest zrobiona w shaderze koron
  (`crown_haze_*`). Nie sprawdzono, czy Compatibility obsługuje `fog_height_density`, więc nie włączano go.
- **Chmury**: w biegu nie ma nieba z chmurami (`Arena/SkyDome` jest w `DOJO_ONLY_NODES`); „chmury" z CI to
  płaty koron. Zmniejszone wysokościową mgłą, ale geometria koron (cedr proceduralny) jest nadal kanciasta.
- **Róż sakury w mgle**: różowa „kula" sakury na pierwszym planie jest nadal mocna (osobny problem, nie N4).
- **Snop**: metryka snopu (kolumny z góry kadru) nie wyizolowała jasnej kolumny; zamiast tego pilnuje, żeby nie
  było szerokiego pasa. Do potwierdzenia na Queście.
- Wszystko powyżej renderowane w llvmpipe (CI). **Do potwierdzenia na Queście**: jasność ziemi, kontrast i
  wygląd cross-fade LOD.

## Testy

- `tests/worldgen_path_visible_test.gd` (windowed, SKIP w headless): po istniejących sprawdzeniach ścieżki dodano
  sprawdzenia N4 (RMS kadru, ziemia z polany, ziemia z bliska, cyjan i odcień bramy, snop). Pioruny są zamrożone
  (ich timer idzie na prawdziwym czasie), więc wyniki są powtarzalne. Wynik: ALL PASSED (10/10 sprawdzeń
  okienkowych; sprawdzenie pnia informacyjne).
- Headless: pełny zestaw `tools/run_tests.sh` (patrz commit).
- `xr_play_test` jest niestabilny także na HEAD (przechodzi raz, pada raz); znany flake do N7.
