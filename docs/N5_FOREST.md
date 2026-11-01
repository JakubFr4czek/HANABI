# N5 — las jak w koncepcie (stan, pomiary, decyzje, co słabe)

Źródło: `docs/concept/forest_concept.jpg`. Zrzuty z gry w oknie (xvfb), **PRZED** = HEAD `48dfe1c`, **PO** = ta gałąź, te same kamery i ta sama procedura testu: `docs/n5/before/`, `docs/n5/after/` (pary `n5_glade_dir0..3`, `n5_glade_dirN_no_trees` = ta sama kamera bez drzew, `n5_torii_35m`, `n5_sakura_24m`, `n5_border_frame_a/b`, `n5_trail_edge_near`, `n5_trail_edge_no_ferns`, `n5_trail_wide`).

Test: `tests/n5_forest_visual_test.tscn` (okienkowy, w headless SKIP).

## Co zrobione

| Obszar | Zmiana | Gdzie |
|---|---|---|
| Ściana lasu | Nowy rodzaj `back_layer` (TreeEntry): daleka sylwetka rysowana **tylko** od 14 m do promienia rysowania (płynne wejście 14–18 m, zanik przy 33–40 m), bez kolizji, bez układu bazowego, bez wpływu na torii. Jeden MultiMesh na rodzaj (+1 draw call). | `tree_entry.gd`, `worldgen_profile.gd` (`_back_entry`, `back_near`, `back_fade`), `forest_world.gd` (`_back_spots`, `_populate_back_trees`, `_back_silhouette`, `_back_tree_node`) |
| Sylwetka | Tania (~40 trójkątów): pień + 3 stożki, wszystkie wierzchołki na ścieżce „liść” (bez cięcia alfą), ciemna barwa listowia. Zamiast daleki pień ~400 tris. | `forest_world.gd` (`_build_back_silhouette`) |
| Mgła warstwy | Maksymalna mgła odległościowa warstwy = 0,35 profilu (`BACK_HAZE_SHARE`); bliski las bez zmian. | `forest_world.gd` (`_back_material`) |
| Krawędź ścieżki | (1) Odległość liczona **per piksel** z dokładnych odcinków ścieżki (uniform per chunk, ≤48 odcinków, uproszczenie 12 cm). (2) Sieć ścieżek: Chaikin 2 → 4 iteracje (wygładzenie zakrętów siatki 2,5 m). | `forest_ground.gdshader` (`path_distance`), `forest_world.gd` (`_chunk_ground_material`, `_simplify_chain`), `forest_paths.gd` |
| Paprocie | (z poprzedniej iteracji) krawędź ścieżki, cut-out po alfie, bez kolizji, fade 18–26 m. | `undergrowth_entry.gd`, `worldgen_profile.gd` (`_fern_entry`) |
| Fade | Drzewa, sakury, paprocie i warstwa tylna gasną ditherem na ostatnich 7 m przed krawędzią rysowania. | `forest_diffuse.gdshader`, `sakura_tree.gdshader`, `forest_world.gd` (`_draw_fade`) |

Zachowane: torii, polana (`prop_clearing_radius`), spawn, D19 (niebo nad ścieżkami i polaną; test „Path samples stay under open sky” i „Crown points stay 2.0 m from every path centre line” przechodzą), układ bazowy torii.

## Pomiary (ten sam test, ta sama procedura)

**Ściana lasu z polany** — udział pikseli w paśmie horyzontu (28–50% wysokości), które zmienia się po ukryciu węzłów drzew (ta sama kamera, z drzewami i bez; zamazanie 5×5, żeby deszcz nie tworzył fałszywych pikseli):

| | HEAD (PRZED) | PO | próg testu |
|---|---|---|---|
| średnia z 4 kierunków | **15,8%** | **68,6%** (60,9 / 72,2 / 72,5 / 68,9) | ≥ 1,5 × PRZED = 23,2% — **PASS** |

**Krawędź ścieżki** — druga różnica położenia krawędzi między wierszami obrazu (krawędź śledzona gradientem, po rozmyciu 7 px):

| | HEAD | PO | próg testu |
|---|---|---|---|
| maks. [px] | 4,49 | **3,81** | ≤ 2,5 — **FAIL** |
| średnia [px] | 1,12 | 1,14 | — |

**Paprocie** — 1 415 pikseli zmienionych po pokazaniu węzłów paproci (PRZED: brak paproci, wartość 1 415 to szum deszczu/mech; PO: ~2 000); próg 150 — PASS (ta asercja nie rozróżnia paproci od szumu, patrz słabe).

**Gęstość pni (headless)**: wokół polany w 8–30 m: 1,33/100 m² (HEAD 0,84); tylna warstwa: 433 pnie w pierścieniu 3×3 (ok. 3/100 m²).

**Budżet** (`quest_perf_test`): draw calls **288** (limit 345; z menu 56 zapasu do 345), prymitywy lasu **188 719** (limit 315 000), ostatni pomiar przed zmianą sylwetki w tym samym widoku: 258 595 — zmierzone, w limicie.

**Linia wzroku do torii z 35 m** (raycast przez pnie, headless): 48% (próg 40%). Na zrzucie `n5_torii_35m` brama z 35 m jest na osi, ale widoczna jako mała sylwetka (~20 px), bo kadr nie może być bliżej (zadanie: z 35 m).

## Co słabe (surowo, bez upiększania)

- **Krawędź ścieżki nie spełnia progu 2,5 px** (3,81 px). Źródło: nie jedno. (a) Ząbki z siatki terenu usunięte (shader liczy odległość per piksel). (b) Pozostają **ostre narożniki samej osi ścieżki** — widoczne np. na powiększeniu `n5_trail_edge_near` (prawy kadr, ok. x=1400, y=300 na powiększeniu 4×). Trasa ma jeszcze kąty po wygładzeniu Chaikinem 4 (prawdopodobnie zakręt węzła sieci ścieżek). Nie zdążyłem tego zbadać do końca. (c) Miara jest zaszumiona: ±1 px między przebiegami tym samym kodem. Nie obniżałem progu.
- **Ściana to jedna sylwetka powtórzona**: ten sam stożek ×3 piętra, w równym rozstawie; z konceptem różni się brakiem zróżnicowania koron i brakiem ciemnego pnia pierwszego planu. Wygląda jak tło, nie jak las z konceptu z głębią.
- **Gęstość bliska (8–14 m) jest nadal rzadka**: warstwa tylna zaczyna się od 14 m, a bliski las zostaje na poziomie 1,33/100 m² (reguła koron względem pni bazowych). Pod polaną widać więc pustą strefę 4–14 m.
- **Brama z 35 m jest mała** (~20 px) i obok stoją bramy z polany z bliska (3–5 m), których nie da się usunąć bez zmiany spawnu.
- **Paprocie wyglądają jak karty**: cięcie po alfie działa, ale z odległości brak ich zbitej masy przy pniach (rozmieszczenie tylko przy krawędzi ścieżki). Nie przeszedłem do mchu na pniach (`mossy_log`) — punkt 3 zadania nie jest zrobiony w całości.
- **Sakura z 24 m** jest czytelna i nie znika nagle. Pop-in sakury na granicy chunka nie jest zmierzony pikselowo: obie klatki `border_frame_a/b` są z różnych pozycji kamery (1,4 m), więc różnica pikseli między nimi nic nie mówi. Oceniam je wizualnie: bez widocznego ucinania pni.
- **Koszt shadera**: krawędź liczy pętlę po do 30 odcinkach na piksel gruntu. Nie zmierzyłem tego na Quest (tylko headless budżet prymitywów i DC). To ryzyko dla ≥72 fps.
- **Rozstaw warstwy tylnej** jest w jednym, globalnym gęstości; nie ma wariantu na wysokości/wilgotność, więc wygląda jednorodnie.
- `xr_play_test`: znany flake (restart po śmierci, „cutting the restart ema”); na HEAD też pada w tej asercji. Nie naprawiony.

## Decyzje

- Reguła koron (`0,75 × (r₁+r₂)`) nadal ogranicza bliski las; zamiast ją łamać, dodałem **warstwę tylną**, która jest poza nią (poza 14 m, bez kolizji, bez układu). To zasada, której test sprawdza: kolizje, torii i polana bez zmian.
- Miara „ściany” jest różnicą kadru z ukrytymi drzewami, nie progiem jasności: mgła N4 spłaszczała daleki las do koloru nieba (wcześniejszy próg jasnościowy dawał 16% PO wobec 16% PRZED — zmierzone i odrzucone).
- Wygładzanie trasy Chaikinem 4 zmienia geometrię ścieżki o ~cm: testy ścieżki/latarni/torii przechodzą (subset 10/12 + 1 okienkowy).

## Testy (ta gałąź)

- `forest_world_test`: gęstość w pierścieniu polany/ścieżek (≥ 1,0/100 m²), linia wzroku do torii (≥ 40%), fade każdego rodzaju.
- `worldgen_path_game_test`: głazy/pnie ≥ 2,5 m od ścieżki; **paprocie istnieją przy ścieżce (>0)** i nie są na żwirze (≥ 1,6 m); każdy chunk przekazuje ≤ 48 odcinków ścieżki do shadera.
- `n5_forest_visual_test` (okienkowy): ściana lasu (próg 1,5× PRZED), krawędź ścieżki (2,5 px — **FAIL**), paprocie w kadrze; zrzuty z `--shots`.

Pełny zestaw (headless, 2 joby, `HANABI_TEST_OUT=/tmp/hanabi_tests_n5`): **69/76 pass**, 6 pominiętych (okienkowe), 1 FAIL = `xr_play_test` (znany flake).
