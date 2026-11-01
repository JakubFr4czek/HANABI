# N5 — las jak w koncepcie (runda 3: pomiary, decyzje, co zostało)

Źródło: `docs/concept/forest_concept.jpg`, palecie i wizji: `docs/GDD.md` (§ „Neon in the dark”, „Palette”: czerwone torii z neonowymi akcentami).

Zrzuty w oknie (xvfb), **PRZED** = HEAD sprzed N5 (`48dfe1c`), **PO** = ta gałąź; te same kamery i ta sama wersja testu: `docs/n5/before/`, `docs/n5/after/`. Test: `tests/n5_forest_visual_test.tscn` (okienkowy, w headless SKIP).

## Co zrobione w tej rundzie

| Punkt | Zrobione | Gdzie |
|---|---|---|
| 1. Krawędź ścieżki | Miara przeniesiona na **maskę ścieżki** (tryb testowy `debug_mask` w shaderze gruntu: płaski, nieoświetlony biały żwir na czarnym). Cień księżycowy i tekstura nie wchodzą do miary. Okno objęte 40–92% wysokości (w tym narożnik ~225 px). Trasy sieci łączone w węzłach stopnia 2 i wygładzane razem (Chaikin), potem upraszczane (12 cm). | `forest_ground.gdshader` (`debug_mask`), `forest_paths.gd` (`smooth_segments_in_rect`), `forest_world.gd` (`_chunk_ground_material`), test |
| 2. Pas średni 6–14 m | Rodzaj średni **z kolizjami pni**. Wykluczenie wokół kapliczek: kapliczka zgłasza pozycję (`connect_shrine` → `reserve_shrine`), promień 6 m; już postawione sylwetki i ich kolizje są usuwane w zbudowanych chunkach, nowe chunki je pomijają. | `forest_world.gd` (`reserve_shrine`, `_strip_back_near`, `_build_back_colliders`, `_reserved`), `worldgen_profile.gd`, `default_profile.tres` |
| 3. Turkusowe słupy | Diagnoza: to **emisja poświaty bramy** (cyjan, `torii_glow_strength` 0,5), która zalewała czerwony korpus; w nocy oświetlenie jest prawie czarne, więc sama emisja dawała płaski turkus. GDD: „red torii”, neon tylko jako akcent. Poświata obniżona do akcentu (0,12, dolna granica zakresu z `docs/n4/README.md`). | `worldgen_profile.gd` (`torii_glow_strength`), `forest_world.gd` (`_torii_mat`) |
| 3. Asercja materiałów | Każdy MultiMesh lasu ma shader; korpus bramy ma czerwony kolor bazowy (r > g, r > b). | `forest_world_test.gd` |
| 4. Pełny zestaw, budżet, licencje | Patrz niżej. | — |

## Pomiary (ta sama wersja testu na HEAD i PO)

| Miara | HEAD (PRZED) | PO | próg | wynik |
|---|---|---|---|---|
| Ściana lasu z polany (średnia 4 kierunków, % pikseli pasma horyzontu zmienionych po ukryciu drzew) | 16,2% | **74,9%** | ≥ 23,2% (1,5× PRZED) | PASS |
| Pas 8–14 m (pnie wszystkich warstw, na 100 m², headless) | 0,48 | **7,48** | ≥ 4,0 | PASS |
| **Krawędź ścieżki na masce** (druga różnica x krawędzi między wierszami, mediana z 5 klatek, px) | 0,67 | **0,59** | ≤ 2,5 | PASS (oba) |
| Krawędź ścieżki w kolorowym kadrze (**tylko informacja**, zawiera cień i teksturę żwiru) | 4,09 | 3,55 | — | — |
| Paprocie w kadrze (px zmienione po pokazaniu paproci, widok B) | 0 | **833** | ≥ 150 | PASS |
| Każdy MultiMesh lasu ma shader (56 węzłów) | — | 0 bez shadera | 0 | PASS |
| Chunk ≤ 48 odcinków ścieżki (max 26) | — | 26 | ≤ 48 | PASS |
| Odległość odcinków po uproszczeniu od surowej osi | — | błąd ≤ 0,15 m (zaokrąglenie łuku) | — | informacja |

**Uczciwy wynik dla punktu 1:** miara maski **nie odróżnia HEAD od PO**: oba przechodzą 2,5 px (0,67 i 0,59). Wcześniejsze „4 px” z kolorowego kadru i wyniki bliskie 3,5 px wynikały z granicy cienia i tekstury żwiru, a nie z osi ścieżki. Zostaje tu wątpliwość, czy gładkość osi w ogóle była problemem przy tym widoku; nie mam miary, która by to rozstrzygnęła, a nie podniosłem progu ani nie zmieniłem definicji. Pierwotny warunek „test musi FAILować na HEAD” nie jest spełniony tą miarą.

**Co wyjaśniłem przy okazji:**
- Ostry pionowy uskok na masce (x≈385 w kadrze) to **granica mgły**: grunt poza ok. 60–70 m od kamery jest odrzucany przez `fog_fade`, a nie geometria ścieżki. Wykluczyłem szew między chunkami (sonda: zbiory odcinków każdego chunka są kompletne przy ścieżce, błąd 0 m przy brakach).
- Kapliczka na masce daje czarną sylwetkę na trasie; ukrywana w trybie maski (nie w grze).

## Budżet (`quest_perf_test`, finalna konfiguracja)

- Draw calls: **293** (limit 345; z menu 51 zapasu).
- Prymitywy lasu: **251 671** (limit 315 000).
- Prymitywy całości: 294 901.

## Testy (pełny zestaw, headless, 2 joby, `HANABI_TEST_OUT=/tmp/hanabi_tests_n5`)

- Pierwsza połowa: 30/33 (3 okienkowe pominięte).
- Druga połowa: 38/43 (3 pominięte), **2 FAIL**:
  - `xr_play_test` — znany flake (restart po śmierci), na HEAD też pada.
  - `oni_boss_ai_test` — **pada też na HEAD sprzed N5** (w izolacji: 3 FAIL na worktree `48dfe1c` z tą samą wersją shadera testowego, na obecnym drzewie 2 FAIL). Nie jest to regresja tej serii; wymaga osobnej diagnozy czasów walki.
- Łącznie: **67/76 przeszło**, 6 pominiętych, 2 FAIL (1 znany flake, 1 istniejący przed N5).
- Licencje: `ci/check_licenses.py`: 0 braków, 0 licencji innych niż CC0/CC BY.

## Co słabe (surowo)

- **Krawędź ścieżki:** patrz wyżej. Test krawędzi przechodzi, ale nie wykrywa tego, co miał wykrywać; nie mogę uczciwie zaliczyć punktu 1 jako „naprawiony”.
- **Torii nocą:** czerwień korpusu jest ledwo czytelna (ciemnogranatowo-turkusowy odcień od niebieskiego oświetlenia palety). GDD wymaga czerwonego torii; w tej palecie nocą to wymaga osobnego strojenia światła/ekspozycji, nie zmieniłem tego.
- **Rodzaj średni z kolizją** może stać na krawędzi przy kapliczce tylko poza promieniem 6 m; kolizje są w chunkach i muszą się przeładowywać przy wykluczeniu. Test sprawdza, że nic nie stoi w promieniu zarejestrowanej kapliczki, ale nie gra gracza przez kapliczkę na żywo.
- **Sylwetki** nadal te same trzy kształty (warianty, obrót i skala są), wygląd jednolitej ściany z oddali.
- **Paprocie** małe i w tle (20–60 px), nie zbite przy pniach; mchu na pniach nie dodałem.
- **Brama z 35 m** jest na osi, ale mała (~20 px), a bramy z bliska z boków zostają.
- **Pop-in na granicy chunka** nie zmierzony pikselowo.
- **Koszt shadera krawędzi** (pętla po ≤ 26 odcinkach na piksel) nie zmierzony na Quest.
