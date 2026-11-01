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


## fix1 (po review supervisora 77757c9)

### Decyzja techniczna: mgła w Compatibility
- Environment depth fog działa, ale wszystko zlewa się na 40 m naraz (jedna płaska ściana) – za mało warstw.
- Height fog z Environmentu: NIE użyto (nie potwierdzono obsługi w Compatibility; nie chcę ryzykować bez pomiaru).
- **Wybrane:** własna mgła w `src/shaders/atmosphere.gdshaderinc` (wspólna dla koron i gruntu):
  - odległościowa: `1 - exp(-(d - start) * k)`, od 8 m (czysto) przez ~50% przy 20 m do ~0.7 przy 40 m;
  - niska (między pniami): `exp(-y / low_mist_height) * low_mist_amount`, od ~4 m odległości;
  - gradient barwy: indygo blisko, teal (`haze_far_color`) od 15 m.
- **Kluczowe odkrycie:** mgła mieszana w `ALBEDO` była mnożona przez ciemne nocne oświetlenie, więc daleki
  grunt wychodził czarny (0.004). Mgła idzie teraz przez `EMISSION` (samoświecenie), `ALBEDO` tylko gaśnie.
- Parametry w `WorldGenProfile`: `distance_haze_start/end/max` (8/40/0.8), `low_mist_amount/height` (0.5/3 m),
  `haze_far_color` (teal), `crown_haze_*` (8/22 m, 0.6).

### Pozostałe punkty fix1
1. Mgła z głębią – ZROBIONE jako warstwy na gruncie (8 m < 20 m: 0.041 < 0.047). Na contact sheet NIE wygląda
   jak koncept: drzewa nie cofają się w kadrze, bo polana jest świadomie otwarta (`sky_glade_radius`). To decyzja
   worldgenu/gęstości, nie samej mgły (N5).
2. Height fog – CZĘŚCIOWO: niska mgła w shaderze (gęściej przy ziemi). Brak gradientu róż/cyjan w stronę bramy/sakury
   (tylko gradient odległościowy indygo→teal).
3. Test progowy warstw – ZROBIONE dla ziemi (8 m < 20 m). 40 m zostało INFORMACYJNE: pagórki (±4.6 m) często
   zasłaniają ten punkt czarnym stokiem. Test pnia vs mgła (8–20 m) nadal INFORMACYJNY (próbka trafia w ciemny grunt).
4. Chmury/korony – CZĘŚCIOWO: wysokościowa mgła koron (`crown_haze_amount` 0.6) zmiękcza górne sylwetki, ale
   geometria koron (cedr proceduralny) jest nadal kanciasta. Brak nieba z chmurami w biegu (SkyDome ukryty).
5. Ostra krawędź cienia i sakura – CZĘŚCIOWO:
   - cień księżyca wyłączony (`shadow_enabled = false` w `WorldGenLook.apply_moon`), ale ostra krawędź na ścieżce
     nadal jest (widać na kadrze 'c_final_glade'). Nie ustalono źródła (prawdopodobnie krawędź pasa ścieżki, nie cień).
   - sakura: `emission` 1.35 → 0.9 (TreeEntry). Różowa kula jest nadal mocna – do N5 (materiał sakury).
6. Kadry: `final_*` + `n4_contact_sheet.png` (koncept, PRZED, PO z tych samych kamer).

### Surowa ocena (co dalej słabe)
- Tło: nadal płaska indygo ściana; brak wrażenia głębokiej przestrzeni z pniami w warstwach (to wymaga gęstszego
  lasu w kadrze, nie samej mgły).
- Ziemia: czytelna i ciemna, ale zielony plaster bez struktury mgły; ostra krawędź ścieżki.
- Sakura: jaskrawa kula na pierwszym planie, nie jak w koncepcie (mgiełka, rozproszony róż).
- Bramy: cyjan czytelny (share 0.025), ale mały i w tle; w koncepcie cyjan rozlewa się w mgle.
- Wrogowie w szczycie fali zasłaniają las – kadr 'peak' to walka, nie atmosfera.
- Wszystko w llvmpipe (CI). **Na Queście do potwierdzenia**: kontrast mgły, jasność ziemi, LOD.

### Testy (fix1)
- Okienkowy `worldgen_path_visible_test` (windowed, 960x540): ALL PASSED (12 sprawdzeń PASS; informacyjne:
  pień 8–20 m, warstwa 40 m).
- Headless: pełny zestaw `tools/run_tests.sh 2` – patrz commit.
