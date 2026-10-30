# D6 — las widoczny z daleka (drzewa zasłaniają światło torii)

Zgłoszenie Jakuba: światło torii bije w las z daleka, a drzewa pojawiają się dopiero przy podejściu,
więc nic go nie przesłania. Ten dokument: diagnoza, co zmieniono, jakie są budżety, co jest słabe.

## Diagnoza (zweryfikowana w kodzie)

- Pierścień chunków 3×3 po 28 m gwarantował załadowany las tylko do ~28 m, a mgła była pełna przy 11 m.
- Drzewa rysowano do 11 m (`tree_draw_radius`), sakury do 14 m, a od 9,5 m co drugie drzewo było pomijane.
- Halo torii jest `fog_disabled`, ale nadal sprawdza głębokość. Przebija mgłę, a nic przed nim
  nie zasłania go, bo pnie za 11 m nie są rysowane. Stąd światło „wisi” nad pustką.
- Pomiar przed zmianą (headless, `quest_perf_test`): draw **303** (z menu 304), prymitywy ~91 k.
  `diag_draw_breakdown`: najwięcej to wrogowie (8 × 27 mesh), potem las (~45), kapliczka (13), bramy (16).

## Co zmieniono

1. **Pełne drzewa blisko, tańsza korona dalej.**
   - Pełna korona (skan `cherry_forest` z koroną CEDAR, ~2 100 trójkątów) do 8 m, z pasem przejścia 2 m.
   - Daleka korona (`_build_far_tree_mesh`): te same środki koron, ale jako niskie kule (5 segmentów, 2 pierścienie) i prosty pień,
     ~280 trójkątów (limit ≤ 500). Jeden MultiMesh na cały pierścień (jeden draw call), rysowany 8–40 m.
   - Przejście krzyżowe w `forest_diffuse.gdshader`: uporządkowany dither (interleaved gradient noise), tylko w paśmie
     `lod_band`. Poza pasmem `ALPHA_SCISSOR_THRESHOLD` zostaje 0,05 jak dotąd.
2. **Chunki 40 m, pierścień gwarantuje 40 m** (`WorldGenProfile.loaded_range()` = `chunk_radius × chunk_size`).
   Mgła kończy się przy 40 m (`fog_end`), `fog_start` 5 m, `fog_curve` 1,8. Przy 11 m mgła to ~6 %, przy 25 m ~37 %, przy 35 m ~75 %.
3. **Zasięg rysowania drzew = zasięg pierścienia (40 m).** Sakury rysowane do tego samego zasięgu (bez skoku na 14 m).
   Nie dodano osobnego LOD dla sakur: są 1–3 w pierścieniu, a jedna ma ~2 000 trójkątów. Dla nich LOD (impostor) zostaje na później.
4. **Halo torii:** nadal sprawdza głębokość (pnie je zasłaniają). Dodano lekkie przyciemnienie powyżej 18 m.
5. **Generowanie chunków nie przycina klatki:**
   - Teren próbkowany w wierszach: `TerrainBuild`, 2 wiersze siatki (82 zapytania o wysokość) na klatkę fizyki.
   - Przejście o jeden chunk kolejkuje nowy pierścień (jeden chunk naraz). Skok (teleport) o więcej niż jeden chunk buduje od razu.
   - Cache wysokości na siatce globalnej (`_lattice_height`), tańsze sadzenie drzew.
   - Test odstępów drzew na siatce kubełkowej (ten sam wynik: odcisk palca spotów identyczny przed i po).
   - Próbkowanie Poissona przygotowywane na `WorkerThreadPool` (funkcja czysta, ten sam wynik).
   - Pomiar headless: najdłuższy krok na klatkę ~8–11 ms (2 wiersze + ewentualnie finalizacja). Przed zmianą: ~80 ms na chunk (28 m), ~130 ms (40 m).
6. **Kapliczki w metrach:** `shrine_slot_size` = 112 m (zamiast `shrine_slot_chunks`). Rytm kapliczek z balansu (216 m) pozostaje, bo nie zależy od rozmiaru chunka.
7. **Bramy i kamienie:** więcej kandydatów (×3), bo 40-metrowy chunk odrzucał za dużo miejsc. Kamienie (boulders) trzymają
   tę samą odległość od ścieżki co pnie (`path_tree_clearance`), a nie 0,6 m. Test `worldgen_path_game_test` to wyłapał.
8. **Presety:** `quest_perf` i `dense_dusk` mają `fog_end` równe zasięgowi rysowania (inaczej drzewa wyskakiwały przed mgłą).
   Walidacja (`validate()`) pilnuje tego i zasięgu pierścienia.

## Budżety (headless, `quest_perf_test`, po zmianach)

| miara | przed | po | limit |
|---|---|---|---|
| draw calls (świat) | 303 | 308 | 345 |
| draw calls z menu | 304 | 309 | 345 (zapas 36) |
| prymitywy całości | 91 k | 295 k | 420 k |
| prymitywy lasu | – | 261 k | 315 k (¼ budżetu) |

Trójkąty daleki las: ~280 na drzewo (limit ≤ 500). Pełna korona: ~2 100.

## Testy

- `forest_world_test` (rozszerzone): daleki las w 14–40 m; pełne korony tylko w paśmie; nic nie rysowane za `tree_draw_radius`;
  daleka korona ≤ 500 trójkątów; drzewa w stożku widzenia; **80 m przez dwie granice chunków: każde drzewo w zasięgu rysowane w każdym kroku
  (0 brakujących, 0 nadmiarowych)**; nowy pierścień kolejkowany, nie budowany naraz; pień zasłania część światła torii 25 m dalej.
- `quest_perf_test`: udział lasu w prymitywach ≤ ¼ budżetu.
- `hokora_test`, `worldgen_*`: dopasowane do chunka 40 m i kapliczek w metrach (bez osłabiania progów).
- Zmieniono asercje, które kodowały stary zasięg 14 m (`VIEW_RANGE_END` → `loaded_range()`), i test zakładający 28 m w mapowaniu chunków.

## Zrzuty (okno, `tests/d6_forest_lod_screenshots.tscn`, `docs/d6/`)

- `d6_gate_30m_in_fog.png`: brama 30 m przed kamerą. Światło przebija mgłę. Pień po lewej zasłania ją tylko częściowo.
- `d6_panorama_from_glade.png`: panorama z polany.
- `d6_border_frame_a/b.png`: granica chunku, dwie klatki, ten sam widok.
- `d6_sakura_24m.png`: sakura z 24 m.

Ocena surowa (co jest słabe):
- **Las czyta się słabo z polany:** drzew jest mało na kadrze, a daleka korona to ciemna sylwetka bez detalu. Gęstość
  (1 drzewo na ~21 m²) i ciemna paleta wyglądają rzadko i płasko. Do poprawy: gęstość w paśmie 15–40 m, jaśniejsza korona w mgle.
- **Dither w paśmie 8–10 m jest widoczny** jako siatka kropek na pełnej koronie (`d6_panorama`). To nie jest premium.
  Lepsze będzie przejście alfa (z sortowaniem) albo dłuższe pasmo z mieszaniem kolorów.
- **Pień nie zasłania torii wyraźnie** w tym kadrze (głębokość działa, ale gęstość w 25–30 m jest mała).
- **Granica chunku:** dwie klatki wyglądają jak ten sam las, bez skoku (nie mierzone pikselami; sprawdzone danymi w teście).
- **Sakura z daleka** czytelna, neon ładnie przebija mgłę.
- **Pomiar na Quest nie jest zrobiony.** Liczby są headless (sterownik dummy). Czas klatki na goglach trzeba zmierzyć.

## Czego nie zrobiono (świadomie)

- Assety z `assets_incoming/` (D5) nie są podpięte: korona daleka jest proceduralna. Kandydaci na lepsze LOD: `cherry_tree_low.glb`, pakiety iglaste.
- Pełne przeniesienie generacji chunków na wątki (tylko Poisson idzie na wątki). Spoty drzew i wysokości zostają na głównym wątku.
- Impostory (billboard) dla sakur.
