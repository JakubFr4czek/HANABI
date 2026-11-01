# N5 — las jak w koncepcie (stan po fix2, pomiary, co słabe)

Źródło: `docs/concept/forest_concept.jpg`. Zrzuty w oknie (xvfb), **PRZED** = HEAD sprzed N5 (`48dfe1c`), **PO** = ta gałąź; te same kamery i ta sama wersja testu: `docs/n5/before/`, `docs/n5/after/`.

Test wizualny: `tests/n5_forest_visual_test.tscn` (okienkowy, w headless SKIP). Widoki: **A** — stały punkt na ścieżce 9 m od polany (miara krawędzi, identyczny na HEAD i PO); **B** — ujęcie z paprocią 1,6–3 m od osi, 4–10 m od polany (`n5_fern_trail*`); zestaw przeglądowy: `n5_glade_dir0..3` (+ `_no_trees`), `n5_torii_35m`, `n5_sakura_24m`, `n5_border_frame_a/b`, `n5_trail_wide`.

## Co zrobione

| Obszar | Zmiana | Gdzie |
|---|---|---|
| Ściana lasu | Rodzaj `back_layer`: daleka sylwetka, rysowana od `draw_from`/`back_near` do zasięgu, bez układu bazowego, poza regułą koron. | `tree_entry.gd`, `worldgen_profile.gd` (`_back_entry`), `forest_world.gd` (`_back_spots`, `_populate_back_trees`) |
| Pas 8–14 m | Rodzaj **średni** (`_mid_entry`, `draw_from` 6 m, rozstaw 2,0 m, skala 0,7–1,0) z **kolizją pni**. Nie wchodzi na ścieżkę (hw + 3 m), na polanę, na torii (5 m) ani na spawn. | `worldgen_profile.gd` (`_mid_entry`), `default_profile.tres` (`Resource_mid`), `forest_world.gd` (`_populate_back_trees` — kolizje) |
| Wariacje sylwetek | 3 warianty kształtu (kolumna 3 pięter / wąska 4 piętra / 2 płaskie), losowy obrót (`random_yaw`), skala 0,8–1,3; wariant wybierany hashem punktu. | `forest_world.gd` (`_build_back_silhouette(variant)`, `back_key`, `BACK_VARIANTS`) |
| Krawędź ścieżki | Oś gładka: łańcuch segmentów w chunku zaokrąglany Chaikinem (2 rundy) przed uproszczeniem; sieć: Chaikin 4 rundy. Odległość per piksel z dokładnych odcinków. | `forest_world.gd` (`_simplify_chain`, `_chunk_ground_material`), `forest_paths.gd` |
| Paprocie | Krawędź ścieżki, cut-out po alfie, bez kolizji. Test B wymusza ich obecność w kadrze. | `undergrowth_entry.gd`, `worldgen_profile.gd` (`_fern_entry`) |
| Fade | Drzewa, sakury, paprocie i warstwy tylne gasną ditherem przed krawędzią rysowania. | `*.gdshader`, `forest_world.gd` (`_draw_fade`) |

Zachowane: torii, polana, spawn, D19 (niebo nad ścieżkami i polaną; testy „Path samples stay under open sky” i „Crown points stay 2.0 m from every path centre line” przechodzą), układ bazowy torii.

## Pomiary (ta sama wersja testu na HEAD i PO)

| Miara | HEAD (PRZED) | PO | próg | wynik |
|---|---|---|---|---|
| Ściana lasu z polany (średnia 4 kierunków, % pikseli pasma horyzontu zmienionych po ukryciu drzew) | 16,1% | **74,9%** (63 / 82 / 80 / 74) | ≥ 23,2% (1,5× PRZED) | PASS |
| Pas 8–14 m (pnie, także warstwy, na 100 m², test headless) | 0,48 | **7,48** | ≥ 4,0 | PASS |
| Krawędź ścieżki, widok A (druga różnica, mediana z 5 klatek, px) | 4,09 | **3,55** | ≤ 2,5 | **FAIL** |
| Paprocie w kadrze, widok B (px zmienione po pokazaniu paproci) | 0 | **852** | ≥ 150 | PASS |
| Paprocie stoją poza żwirem (≥ 1,6 m od osi, test headless) | — | min. 1,75 m | ≥ 1,6 m | PASS |
| Każdy chunk ≤ 48 odcinków ścieżki w shaderze (max 26) | — | 26 | ≤ 48 | PASS |

Miara krawędzi jest deterministyczna w tej wersji: pięć klatek z tej samej kamery daje tę samą wartość (na HEAD jedna klatka odstaje o 4,74). Test na HEAD **nadal FAILuje** (4,09 px), więc miara łapie to, co ma łapać.

**Budżet** (`quest_perf_test`, po warstwie średniej i wariantach): draw calls **293** (limit 345; z menu 51 zapasu), prymitywy lasu **252 703** (limit 315 000), prymitywy całości 295 933.

## Co zostało poza progiem (surowo)

- **Krawędź ścieżki: FAIL (3,55 px vs 2,5 px).** Diagnoza tej rundy:
  - Ząbki z siatki terenu są usunięte (odległość per piksel). Zmniejszenie z 4,09 do 3,55 px pochodzi z wygładzenia łańcucha i sieci.
  - Miara **nie widzi narożnika** z kadru `n5_trail_edge_near` (rząd ~225 px): jej okno pionowe to 62–92% wysokości kadru, a kąt jest wyżej.
  - Maksimum miary leży w wierszach 403–465 na granicy **cienia księżycowego** na żwirze (miękka krawędź cienia, wzmocniona przez teksturę żwiru). To nie jest oś ścieżki. Nie zmieniałem definicji miary ani progu. Trzeba zdecydować, czy granicę cienia w ogóle liczyć jako krawędź ścieżki; jeśli nie, potrzebna jest zmiana definicji, której nie robię samowolnie.
- **Ściana z jednym kształtem w trzech wariantach** wygląda jak powtarzany las z oddali, bez głębi koncepcji (brak ciemnych pni pierwszego planu).
- **Paprocie są małe** w kadrze B (20–60 px), w tle, przy krawędzi ścieżki. Nie są „zbite przy pniach”; mchu na pniach (`mossy_log`) nie dodałem.
- **Pas 8–14 m**: pnie średniego rodzaju mają kolizję i widoczność od 6 m (fade 6–10 m). Zostaje krótki odcinek, w którym gracz widzi pień dopiero przy 6 m; to kompromis wobec kolizji, nie idealne rozwiązanie.
- **Brama z 35 m** (`n5_torii_35m`) jest na osi, ale mała (~20 px), a bramy z bliska z boków zostają (nieusuwalne bez zmiany spawnu).
- **Pop-in na granicy chunka** nadal nie zmierzony pikselowo (dwie klatki z różnych pozycji kamery); oceniam wizualnie, bez widocznego nagłego pojawiania się.
- **Koszt shadera krawędzi** (pętla po ≤ 26 odcinkach na piksel gruntu) nie jest zmierzony na Quest.
- `xr_play_test`: znany flake (restart po śmierci), na HEAD też pada w tej asercji.

## Decyzje tej rundy

- **Widok A jest stały** (punkt 9 m), a nie wybierany pod paproć: pomiar musi być porównywalny z HEAD, a na HEAD nie ma paproci. Paprocie mają osobny widok B.
- Warstwa średnia ma **kolizję** (zgodnie z zadaniem), a warstwa tylna nie; obie są poza regułą koron, ale mają reguły: ścieżka, polana, torii i spawn.
- Miara krawędzi: **bez zmiany progu i definicji**. Zmieniono tylko wybór kamery (widok A stały, paproć w widoku B) i liczbę klatek (mediana z 5), żeby wynik był deterministyczny. Test na HEAD nadal FAILuje.
