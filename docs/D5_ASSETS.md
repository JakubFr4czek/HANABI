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
