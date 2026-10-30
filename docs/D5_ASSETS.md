# D5 — podmiana assetów (stan i decyzje)

Źródło: `assets_incoming/` (paczka Jakuba, `new_assets/HANABI_assets_pack.zip`). Wzorzec: `docs/concept/forest_concept.jpg`.

## Co weszło do gry (i jak)

| Kolejność (queue D5) | Asset | Gdzie w grze | Jak |
|---|---|---|---|
| 1 MECH | Moss002 (ambientCG, CC0) | warstwa mchu w `src/shaders/forest_ground.gdshader` (zbocza + plamy), wiązana w `ForestWorld._build_materials` | 1K JPG, `assets/textures/forest_ground/moss002/` |
| 3 LATARNIE | Japanese Stone Lantern (Sahir Virmani, CC BY 4.0) | `lantern_scene` w `data/worldgen/default_profile.tres` (+ `WorldGenProfile._init`); kolizja to plasterki wypukłe (`ForestWorld._lantern_slices`) | zapiekany przez `tools/prep_forest_assets.py`: metry (1.46 m), atlas 1K z 4 tekstur, 3.1k tris (bez decymacji, patrz niżej) |
| 4 LAS (częściowo) | Giant Redwood (rhcreations, CC BY 4.0) | wpis `TreeEntry` (crown SCENE, `min_spacing` 8 m, **waga 0**, czyli wyłączony) | 14k → 2k tris, trunk + karta liści (bez kępy krzewu), atlas 2K. **Wyłączony w profilu**, patrz niżej |

Nie weszło (CZĘŚCIOWO): ścieżki (generator już istniał, zostawiony rocky trail z D0), scots pine (wymaga wyciągnięcia jednego drzewa z 3-drzewkowego zestawu), kora sugi (redwood ma własną teksturę), mech na skałach (mossy_rock), toro_mossy, mgła/paleta (punkt 6), maski Oni, ciało troll, kapliczka (D1), torii_rusted, demon creature.

## Decyzje, które podjąłem sam

- **Bake zamiast surowych GLB.** Sketchfab-owe glb mają jeden materiał na część i skalę w cm. `ForestWorld._merge_scene_meshes` bierze tylko surface 0 i nie przenosi materiałów, więc bez tego lantern/drzewo renderowałyby się szarym blokiem. `tools/prep_forest_assets.py` skleja części w jeden mesh z jednym atlasem i zapisuje w metrach.
- **Decymacja z przeniesieniem UV.** `trimesh` upraszcza siatkę, ale gubi UV i materiał. Nowe wierzchołki biorą UV z najbliższego punktu na oryginale (interpolacja barycentryczna).
- **Waga rodzaju drzewa nie jest udziałem.** `ForestWorld._ordinary_entries` bierze tylko `weight > 0` (włącz/wyłącz). Każdy zwykły rodzaj ma własną próbkę Poissona, więc gęstość steruje `min_spacing`. Komentarz w `TreeEntry` mówi „udział wg wagi” i jest mylący; nie poprawiałem go tutaj.
- **Redwood wyłączony (waga 0).** Dodany rodzaj przesuwa układ torii (test `forest_world_test` „torii 20–36 m od spawnu” przestaje znajdować bramę, także przy 40 m i przy `min_spacing` 4 i 8 m). Wyłączenie przywraca poprzedni układ. Do włączenia trzeba obejrzeć i poprawić reguły torii (D6/D8), zanim wróci redwood.
- **Decymacja łamie kamienną latarnię.** `fast_simplification` gubi spójność nawinięcia części kamiennej (po naprawie `fix_winding` słup znika w renderze). Latarnia jest w pełnej rozdzielczości (3.1k tris).
- **Krzew z redwooda usunięty.** Część `Object_1`/`Object_2` (dwie karty liściowe z granatowym tłem) i biała karta z alfą gubioną przy konwersji do RGB. Po zapikselowaniu granat wygląda jak niebieskie słupy. Zostały trunk i karta z liśćmi; granat jest kluczowany na czarno w bake (`--key-blue`).
- **Drzewa ze sceny mają własny atlas i próg wycinania.** `forest_diffuse` dotąd zawsze próbkował teksturę cedru/sakury. Dla `Crown.SCENE` materiał dostaje atlas sceny, `cut_level` 0.08 (zamiast 0.05) i `normal_depth` 0.
- **Testy w profilu.** `make_default()` (kod) i `default_profile.tres` muszą się zgadzać (test sygnatury). Dopisałem redwooda i latarnię w obu miejscach. Test „tylko focal = błąd” zerował tylko `trees[0]`; teraz zeruje wszystkie zwykłe rodzaje (intencja ta sama).

## Co jest słabe (surowo)

- **Noc jest za ciemna, a mgła i deszcz zjadają detal.** Zrzuty pokazują las z cedrów i latarnię; redwood jest wyłączony, więc nie ma go na zdjęciach. Różu i błękitu z konceptu nie ma (punkt 6 niezrobiony). Paleta to dalej fiolet/szarość.
- **Mech ledwo widać.** Zmiana względem HEAD jest dostrzegalna tylko na zielonych zboczach w zbliżeniu. Ziemia przy ścieżce nadal szaro-brązowa. Trzeba mocniejszych plam i nasycenia albo mchu na pniach i korzeniach.
- **Latarnia jest ciemna** (kamień praktycznie czarny w nocy, papier i drewno lepiej czytelne). Potrzebne ciepłe światło w lampionie, które już jest w materiale; sprawdzić emisję.
- **Liście redwooda rzadkie i kanciaste** (wyłączony w grze, więc poza zrzutami): karty z atlasu RGB, bez alfy z oryginału. Lepszy wynik wymaga konwersji RGBA w bake.
- **Teal „duch” pnia** przy czarnym słupie (środek kadru w ujęciu z ziemi) jest **także w HEAD** (zrzut „before”). Nie jest to regresja D5; nie zbadałem źródła.

## Testy

- `tests/d5_assets_test.gd` (headless, `run.tscn`): każdy plik z katalogów D5 ma wpis w CREDITS.md/LICENSES.md; latarnia to zapiekany mesh ~1.46 m z albedo; podłoże wiąże Moss002; profil zawiera redwooda; redwood (gdy włączony) stoi w pierścieniu, ma 8–22 m i ≤ 6.5k tris; draw calls lasu ≤ 150.
- `tests/worldgen_profile_test.gd`, `tests/worldgen_tool_test.gd`: „tylko rodzaje focal = błąd” zeruje teraz wszystkie zwykłe rodzaje (kedr + redwood), nie tylko pierwszy.
- `tests/forest_world_test.gd`: ciągłość drzew na granicy chunków liczy też pnie redwooda (`drawn_scene_origins`), a nowa asercja pilnuje, że pnie sceniczne sięgają `tree_draw_radius` bez pasma LOD.
- `tests/prop_collision_test.gd`: latarnia zgodna z rysowaniem (0 m na zewnątrz i w środku), kolizja z plasterków.
- `tests/quest_perf_test.gd`: prymitywy lasu (kedr dalekich koron + latarnie) mieszczą się w ¼ budżetu.
- Zrzuty w oknie: `tests/d5_assets_screenshots.tscn` → `docs/d5/before/` (HEAD), `docs/d5/after/` (ta gałąź).

## Budżety (zmierzone headless)

Ostatni przebieg `quest_perf_test`: prymitywy lasu 302 768 (limit ¼ budżetu 315 000), prymitywy całości 337 238 (limit 420 000), draw calls 308 (menu otwarte: zapas 36, minimum 30). Latarnia 3.1k tris × 18 instancji ≈ 56k prymitywów lasu.

## Dalej

1. Redwood: najpierw reguły torii (D6/D8), dopiero potem włączyć wagę 1.0. Poprawić liście (RGBA w bake).
2. Mech: mocniejsze plamy i kolor, mech na korzeniach (moss_wood) i skałach (mossy_rock), warstwa `Ground037`.
3. Scots pine: wyciąć jedno drzewo ze `scots_pine_set` w `prep_forest_assets.py` (`--part`), dodać jako wpis SCENE.
4. Mgła/paleta: lokalny róż/cyjan (punkt 6), jaśniejsza noc, emisja latarni (teraz ciemna).
5. Decymacja bez łamania części (np. dekompozycja na szczelne siatki) i wtedy latarnia/redwood ≤ 3k.
6. Oni/maska/troll (punkty 7–8) i kapliczka (D1).

## Runda 2: mgła i paleta, próby reszty

- **Mgła i paleta (punkt 6), zrobione częściowo.** `night_blue` przesunięty w teal/indygo (0.12, 0.26, 0.34), `dusk_pink` w mauve-róż (0.46, 0.22, 0.42), `fog_curve` 1.8 → 2.1 (mgła rzednie między 15 a 30 m zamiast gęstnieć). Zrzut: `docs/d5/after/` jest sprzed tej rundy; nowy stan w zrzutach z konceptem. Brakuje lokalnego różu i cyjanu mieszających się w mgle (`dusk_mix` 0.3 zostawia niebiesko-indygo bez różu). Testy palety porównują z wartościami profilu, więc nie wymagały zmian.
- **Latarnia i redwood bez zmian** względem rundy 1.
- **Torii_rusted (punkt 9): nieudane, wycofane.** Model ma 7.2k tris i cienkie, otwarte powłoki (słupy, deski, lina). Decymacja do 1.5k i do 3k usuwa słupy w renderze (ta sama przyczyna co latarnia: spójność nawinięcia). Pełnej rozdzielczości nie da się zmieścić w budżecie ¼ (≈12 bram w scenie perf × 7.2k). Model wycofany z repo, a `tools/prep_forest_assets.py` dostał opcję `--rotate-y` (zostaje do późniejszego użycia).
- **Scots pine (punkt 4) i paprocie: nie zrobione.** Każdy nowy zwykły rodzaj drzew (także redwood) i nowy rodzaj ozdobnika (paprocie jako undergrowth) przesuwa układ torii. `forest_world_test` (brama 20–36 m od spawnu) wtedy przestaje znajdować bramę, a progu nie wolno zmieniać. Rozwiązanie wymaga zmiany reguł torii (D6/D8), nie podmiany assetu.
- **Ścieżki (punkt 2): nie zrobione.** Generator (`forest_paths.gd`) już łączy bramy i kapliczkę; nie zmieniałem go w tej rundzie.
- **Oni: maska i ciało (punkty 7, 8): nie zrobione.** Podmiana zmienia testy wrogów (`enemy_variants`, `ragdoll`) i wymaga porównania na zrzutach z obecnym proceduralnym Oni, którego nie wykonałem.

## Runda 3: układ torii niezależny od nowych drzew

- **Zrobione: scots pine i redwood jako drzewa „po bramach”.** Nowe pole `TreeEntry.base_layout` (domyślnie tak). Rodzaje z `base_layout = false` nie wchodzą do planu bazowego: `_ordinary_entries` bierze tylko bazowe, a `_populate_extra_trees` rozstawia je po torii (`_make_chunk`), omijając pnie bazowe (3 m), bramy w 3×3 chunkach (5 m) i własny rozstaw. Plan torii widzi więc ten sam las co przed zmianą i test linii wzroku (brama 20–36 m) przechodzi bez zmiany progu. Redwood jest teraz włączony (waga 1, rozstaw 8 m), pine (wysokość 13.9 m, 1.8k tris, rozstaw 9 m).
- **Zastrzeżenie:** zwykłe lantern/undergrowth nadal liczą pnie tylko bazowe, więc latarnia może trafić w pień „po bramach”. Test latarni przechodzi, ale kolizja w tym miejscu nie była sprawdzana.
- **Test ciągłości** (`forest_world_test`): oczekiwane drzewa to teraz wszystkie rodzaje `xfs_Trees*` z meta chunka, a nie tylko `tree_local_xfs` (bazowe). To rozszerzenie oczekiwanego zbioru, progi bez zmian.
- **Jakość pine i redwooda: słaba.** Z daleka korona to rzadkie karty liści, pnie są ciemne. Spełniają budżet i testy, nie spełniają poziomu premium.
- **Paprocie (undergrowth): zablokowane.** Materiał undergrowthu to `WET_SHADER` bez alfa-cięcia; liście paproci wyszłyby jako nieprzezroczyste karty. Potrzebny shader liści (np. `forest_diffuse` z cięciem) i test, że ich nie widać przez ściany. Nie zrobione.
- **Ścieżki (2): nie zrobione.** Generator (`forest_paths.gd`) już łączy bramy i kapliczkę; zmiana wymaga przeglądu sieci i nie była w zakresie tej rundy.
- **Oni maska i ciało (7, 8): nie zrobione.** Maska `oni_mask_run.glb` i ciało są używane przez boss i testy wrogów (`enemy_variants`, `ragdoll`). Zamiana wymaga porównania na zrzutach z obecnym Oni i decyzji o licencji/tekstur (troll ma 8 animacji, ale rig i przemalowanie to osobna praca). Nie zrobione.
- **Mgła z różem i cyjanem (6): nie zrobione.** Obecna mgła to teal/indygo; róż i cyjan w mgle wymagają lokalnych źródeł światła lub emisji (halo sakury, cyjan bram). Zmiana `dusk_mix` podniosłaby róż w całej mgle i dałaby szarofiolet, a nie koncept. Potrzebny osobny przebieg shadera i sprawdzenie budżetu świateł (≤12) i draw calls.
- **Torii rusted (9): zablokowane.** Model 7.2k tris z cienkimi, otwartymi powłokami. Decymacja (1.5k i 3k) usuwa słupy w renderze (ta sama przyczyna co latarnia). Pełna rozdzielczość: ≈12 bram w scenie perf × 7.2k ≈ 87k prymitywów, co przekracza budżet lasu (315k) razem z resztą. Do odblokowania potrzeba decymacji zachowującej otwarte powłoki albo ręcznej redukcji modelu.

## D5_fix: poprawki po review

- **Pnie layout-after chronią latarnie i podszyt (zrobione).** Błąd był realny: test na sześciu stanowiskach znalazł głaz 1.21 m od pnia sekwoi (podłoga 1.43 m). `ForestWorld._prop_trunk_points` dokłada pnie layout-after z 3×3 pierścienia do latarni i podszytu. Torii dalej liczą tylko pnie bazowe, bo plan bram nie może się przesunąć. Cache `_extra_spot_cache` jest przycinany jak cache drzew, więc wędrówka nie rośnie w pamięci. Test: `forest_world_test`, „Lanterns / Undergrowth stand clear of layout-after trunks”. Odstęp mierzony od osi pnia, tak jak pnie bazowe; promień pnia (chest) nie jest tu uwzględniony.
- **Cut-out liści (zrobione w shaderze).** `forest_diffuse` ma `ALPHA_SCISSOR_THRESHOLD = cut_level`. Nowy opt-in `alpha_from_texture` (domyślnie `false`) pozwala ciąć po kanale alfa tekstury, a nie po jasności RGB. Paprocie to RGBA, więc potrzebują tego trybu. Istniejące materiały bez zmian. Test: „Foliage shader …” w `forest_world_test`.
- **Paprocie: nie podpięte (CZĘŚCIOWO).** Assety są w `assets_incoming/undergrowth/` (`fern_zvanstone.glb` 524 tris, `fern_polypody.glb`, `fern_grass02.glb`). Brakuje trzech kroków:
  1. Bake do `assets/` przez `tools/prep_forest_assets.py` (dziś bake obsługuje latarnię i redwooda) z atlasem RGBA.
  2. Materiał liści dla wpisu podszytu: dziś każdy wpis dostaje `_rock_material()` (`WET_SHADER`, bez cut-out). Potrzebny `forest_diffuse` z `alpha_from_texture = true`, `cut_level = 0.5`, a `lod_band` poza zasięgiem rysowania, bo inaczej liście zanikają od ~9 m.
  3. Podgląd w oknie przed wpięciem w `default_profile.tres`. Bez zrzutu nie oceniam, czy paproć pasuje do koncepcie, a dodatkowy wpis podszytu dokłada co najwyżej jeden draw call na chunk.
