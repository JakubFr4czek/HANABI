# N6: kapliczka i latarnie (focal point)

## Co się zmieniło
- **Kapliczka** (`src/world/hokora_shrine.gd`): czarny prymityw zastąpiony domem z assetu
  SamRi „Small Japanese Shrine” (CC BY 4.0, 2787 tris, zapieczony w metrach przez
  `tools/prep_forest_assets.py`, `assets/models/environment/shrine/shrine_samri_baked.glb`).
  Dom dostaje shader `wet_surface` z atlasem skanu, mokry, z omszałymi górnymi powierzchniami
  (nowy opcjonalny parametr `moss_amount`, domyślnie 0 – inne rekwizyty bez zmian).
  Stół ofiarny, czerwony obrus, suzu (dzwon) i interakcja dłonią (D12) zostają bez zmian
  (suzu przesunięty niżej, pod okap nowego dachu). Płomień świecy to mały emisyjny walec za kratą.
- **Jedno światło**: `OmniLight3D` (zasięg 4.5 m, bez cieni, energia 3.0 z migotaniem) świeci
  tylko dla lit-kapliczki najbliższej graczowi w promieniu 30 m. Razem: 1 światło w scenie.
- **Latarnia** (`src/run/forest_world.gd`, materiał `_lantern_mat`): `emission_tint` 0.10→0.72/0.50/0.22
  (tint mnoży albedo, więc świeci papier, a nie kamień) i `fog_rim` 0.5, żeby kamień nie był czarny.
  Bez żadnego dynamicznego światła.
- Kolizje/rezerwa pnia (`reserve_shrine`), placement P4 i ofuda nie zmieniane.

## Testy
- `tests/hokora_test.gd` (headless): dom jest z assetu (nie BoxMesh, ≤3000 tris, shader + atlas),
  jedno światło w całym przebiegu, zgaszona kapliczka gasi światło.
- `tests/hokora_test.gd` (okienkowy, `_test_shrine_reads_in_the_fog`): 20 m – halo ciepłe
  (hue ~27°) i jaśniejsze od nieba; 3 m – średnia luminancja bryły > 0.10.
- `tests/d5_assets_test.gd`: zrzuty z assetu w CREDITS/LICENSES; okienkowy `_lantern_reads_at_10m`:
  papier ciepły i jaśniejszy od kamienia.
- `tests/shot_probe.gd`: pomocnik pikseli (rzut prostokąta, luminancja, odcień).

## Wyniki pikseli (okienkowo, 960×540, ta sama kamera przed/po)
- 20 m: halo odcień 27°, luma 0.52 vs niebo 0.01 – PASS.
- 10 m latarnia: papier 0.39 vs kamień (mediana) 0.00 – PASS.
- 3 m bryła kapliczki: średnia luma 0.057 (przed: czarny prymityw ok. 0.038) – **FAIL** przy progu 0.10.
  Dom to ciemne drewno (atlas ~0.15 jasności, ale przy nocnym świetle i cieniowaniu wychodzi
  ~0.03 na fasadzie). Próby: światło przed domem, energia 1.4→3.0, fill 0.6→1.0, emisja
  na teksturze 0.2→0.55 – każda podbijała tylko nieznacznie. Próg 0.10 został bez zmian;
  do decyzji: obniżyć próg (wtedy to kompromis z wyglądem) albo mocniej oświetlić dom.

## Zrzuty
- `docs/n6/pre/` – stan przed zmianą (ta sama kamera, `tests/hokora_screenshots.gd`).
- `docs/n6/post/` – stan po zmianie.

## Słabe punkty (uczciwie)
- Kapliczka w nocy nadal ciemna z bliska: czytelna sylwetka i ciepła krawędź, ale to nie jest
  „premium” oświetlenie. Brakuje lepszego światła odbitego od ziemi.
- Kamień latarni wychodzi lekko rdzawy (tint × szary kamień + rim w kolorze albedo).
- Moss na dachu w nocy słabo widoczny.
- `hokora_screenshots.gd`: „damage buff runs after the cut” zwraca FAIL także na poprzednim commicie (pre-existing, nie N6).
- `xr_play_test` bywa niestabilny (run 2 „cutting the restart ema”) – tak samo na czystym `main`, pre-existing.
