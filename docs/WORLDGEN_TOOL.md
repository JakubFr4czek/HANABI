# World Gen – narzędzie do generacji lasu (D8)

Cel: ustawiasz i podglądasz cały las w edytorze Godota, bez kodu. Jeden zasób
(`WorldGenProfile`) jest jedynym źródłem prawdy dla generatora lasu: gra
i podgląd czytają z niego te same liczby, więc to, co widzisz w edytorze, jest
tym, co zobaczysz w grze (ten sam seed, ten sam profil → ten sam las).

Kryterium wizualne: `docs/concept/forest_concept.jpg` (zmierzch, wysokie cedry
na omszałych wzgórzach, połączone ścieżki, rzadka neonowa sakura, torii
z cyjanową poświatą, lekka mgła, mieszanie różu i błękitu).

## Jak otworzyć

1. **Podgląd:** otwórz scenę `tools/worldgen/worldgen_preview.tscn`. Las
   przebudowuje się chwilę po każdej zmianie w inspektorze (debounce ~0,35 s).
   Przyciski w inspektorze: *Regeneruj*, *Losuj seed*.
2. **Dock:** plugin `HANABI World Gen` (włączony w `project.godot`) dodaje dock
   po prawej stronie. Ma: *Regeneruj*, *Losuj seed*, *Zapisz preset*,
   *Screenshot* (zrzut widoku 3D edytora do `user://worldgen_shots`), wybór
   grupy z przyciskiem *Przywróć domyślne* (tylko ta grupa), licznik budżetu
   Quest i listę uwag (błędy na czerwono).
3. **Mgła w podglądzie:** `show_fog` wyłącza mgłę tylko w podglądzie, żeby
   zobaczyć układ ścieżek i bram z góry. Gra zawsze ma mgłę.
4. **Które profile:** `data/worldgen/default_profile.tres` (wygląd z konceptu),
   `dense_dusk.tres` (gęstszy, więcej sakur i bram), `quest_perf.tres` (lżejszy,
   do testów na gogle). Gra używa profilu wskazanego w `project.godot`
   (`hanabi/worldgen/profile`). Zmiana profilu gry to jedna linijka.

Uwaga: profil w podglądzie to kopia edytowalna. Gdy chcesz zapisać zmiany,
użyj *Zapisz preset* (zapisuje `data/worldgen/preset_seedN.tres`). Presety
generuje też `tools/worldgen/make_presets.gd`, więc każdy preset jest
odtwarzalny z kodu.

## Grupy profilu

| Grupa | Co steruje | Najważniejsze pola |
|---|---|---|
| **Seed** | powtarzalność lasu | `world_seed`, `chunk_size` (28 m), `chunk_radius` (1 = 3×3), `clearing_radius` (polana startu), `prop_clearing_radius` |
| **Terrain** | wzgórza i grunt | `hill_amplitude`, `hill_frequency`, `hill_octaves`, `bump_*`, `pocket_amount`, `root_amount`, `terrain_resolution` |
| **Trees** | gatunki drzew | `trees` (lista `TreeEntry`), `density_frequency`, `tree_keep_min/max` (gęstość i prześwity) |
| **Undergrowth** | podszycie (kamienie, a od D5 paprocie, pniaki, kłody) | `undergrowth` (lista `UndergrowthEntry`) |
| **Torii** | bramy w lesie | `torii_scene`, `torii_chunk_chance` (rzadkość), `torii_max_per_chunk`, `torii_group_keep`, `torii_height_*`, `torii_min_spacing`, `torii_row_*` (rzędy senbon), `torii_glow_*` |
| **Lanterns** | tōrō wzdłuż ścieżek | `lantern_scene`, `lantern_max_per_chunk`, `path_lantern_spacing`, `lantern_clearance` |
| **Shrines** | kapliczki z ofudą (D1) | `shrine_slot_size` (rozmiar slotu w metrach; rytm kapliczek, niezależny od chunka), `shrine_slot_chance` (rzadkość). Musi być rzadziej niż torii – sprawdza walidacja |
| **Lights and sky** | światło, mgła, paleta | `shafts_*` (promienie księżyca), `fog_start`, `fog_end` (≤ zasięg pierścienia, `loaded_range()`), `fog_curve`, `dusk_pink`, `night_blue`, `dusk_mix` (0 = noc, 1 = róż), `ambient_energy`, `moon_*`, `exposure`, `glow_intensity`, `volumetric_fog` (tylko PC) |
| **Ground** | materiał terenu | `ground_wetness`, `ground_cavity_ao`, `ground_normal_strength`, `ground_roughness_wet` |
| **Paths** | ścieżki | `paths_enabled`, `path_node_spacing`, `path_width`, `path_loop_chance`, `path_curviness`, `path_tree_clearance`, `torii_on_path`, `lantern_on_path` |
| **Sky** | niebo nad ścieżkami i polaną (D19) | `sky_path_half` (pas otwartego nieba od osi ścieżki), `sky_glade_radius` (koło nad polaną startową) |
| **Distance and LOD** | zasięg rysowania | `tree_draw_radius`, `focal_draw_radius`, `lod_near_radius`, `lod_fade`, `ground_fade_start/end` |

**Mgła i „gęstość”:** gęstość mgły to `fog_start` (gdzie mgła zaczyna gęstnieć)
i `fog_curve`. Gęstość `Environment.fog_density` zostaje 1,0: przy 1,0 krawędź
załadowanego pierścienia jest nieprzezroczysta, a test Quest tego pilnuje.
`fog_end` musi zostać w obrębie załadowanego pierścienia (`loaded_range()` =
`chunk_radius × chunk_size`, domyślnie 40 m), inaczej widać krawędź chunków.
Od D6 mgła nie jest pełna od razu: `fog_curve` 1,8 rozpuszcza las stopniowo.

**Paleta:** jeden miks między nocnym błękitem a zmierzchowym różem (`dusk_mix`).
Mgła, tło, ambient i światło księżyca idą razem. Gradientu nieba nie ma:
tło jest kolorem mgły (decyzja z GDD §9, bez krawędzi lasu).

## Jak dodać asset drzewa (D5)

1. W `trees` dodaj wpis `TreeEntry`.
2. `scene` – scena lub `.gltf` z meshem (np. sosna z `assets/`).
3. `crown` – `SCENE` dla gotowego modelu (mesh używany jak jest). `CEDAR` i
   `SAKURA` przebudowują korę skanu cedru w pełną koronę (stary potok).
4. `weight` – udział w zwykłym lesie. `min_spacing` – najmniejszy odstęp
   między pniami tego gatunku (metry, Poisson-disk). `scale_min/max` – skala.
5. **Sakura (focal):** wpis z `focal_chance > 0` (np. 0,18 = jeden chunk na
   ~5–6) wybiera najwyższy pień w chunku i robi z niego neonowe focal drzewo.
   Kolor: `neon_color`, `petal_color`, `rim_color`, `emission`, `neon_sparsity`.
6. `obstacle` – czy pień blokuje gracza (ostrze też się zatrzymuje).

Walidacja zgłasza wpis bez sceny (ostrzeżenie: rysuje się proceduralny cedr).

## Budżety Quest

Las ma swój udział w budżecie 345 wywołań rysowania i 420 000 prymitywów (zob.
`RunPerfBudget`). `WorldGenBudget` przyznaje lasowi: **96 wywołań**,
**150 000 trójkątów w widoku**, **980 instancji**. Liczby są z pomiaru
`ForestWorld.stats()`: domyślny profil rysuje ~30 wywołań (9 chunków × teren,
dwa gatunki drzew, bramy, latarnie, kamienie, promienie), a trójkątów w widoku
ok. 52 000. Dock pokazuje to na czerwono, gdy profil przekracza udział.

Zbiorcza kontrola: `tests/quest_perf_test.gd` (cała scena biegu, budżety
w `RunPerfBudget`) i `tests/worldgen_tool_test.gd` (udział lasu dla profilu
domyślnego).

Koszt budowy: 9 chunków ~0,73 s (przed D8 ~1,13 s). Nowy chunk podczas biegu
kosztuje ~80–120 ms (synchronicznie, jak wcześniej). To znany punkt do
rozłożenia na klatki (zob. „Ograniczenia”).

## Algorytmy i źródła

- **Poisson-disk (Bridson 2007):** `src/forest/poisson_disk.gd`. Drzewa,
  bramy, latarnie i kamienie: odstęp na rodzaj (`min_spacing`,
  `torii_min_spacing`, `path_lantern_spacing`). Kandydaci drzew to funkcja
  czysta chunka i seeda: sąsiedzi widzą te same kandydaty, więc las nie zależy
  od kolejności ładowania. Źródło: R. Bridson, „Fast Poisson Disk Sampling in
  Arbitrary Dimensions”, SIGGRAPH 2007 sketch.
- **FastNoiseLite (wbudowany w Godota):** fBm do wzgórz, osobne szumy do
  gęstości lasu, kieszeni gruntu, rzędów bram i meandrów ścieżek. Seed każdego
  szumu = stała XOR `world_seed`.
- **Ścieżki:** węzły na siatce `path_node_spacing` (jitter z haszowania);
  każdy węzeł ma rodzica o krok bliżej startu (losowy schodkowy wzorzec), więc
  każdy węzeł łączy się ze startem z konstrukcji; ułamek krawędzi daje pętle.
  Trasa: **A*** (Hart, Nilsson, Raphael 1968) po siatce 2,5 m z kosztem
  nachylenia i szumu, wygładzanie **Chaikin** (1974) i próbkowanie co 1 m.
  Kolor terenu: waga ścieżki w `COLOR.r` wierzchołka. Shader gruntu kładzie na
  pasie **własny materiał** (ubita ziemia Ground067, ambientCG, CC0; osobny
  albedo, normal i ciepły tint z `path_tint` × `path_gain`). Na pasie nie
  mieszają się kamień, trawa ani gleba; krawędź jest miękka i zaszumiona.
  Zero dodatkowych wywołań rysowania.
- **Korytarz:** szerokość `path_width` = 2,0 m, prześwit od pni `path_tree_clearance`
  = 2,0 m (pnie i głazy stoją poza pasem plus prześwit). Odnoga kapliczki
  jest trasowana tym samym A* i próbkowana co metr, więc leży na zboczu.
- **Niebo (D19):** korona nie może wejść w pas `sky_path_half` (2,0 m) od osi
  ścieżki ani w koło `sky_glade_radius` (3,5 m) nad polaną. Reguła liczy
  kępy korony (`_crown_discs_for`) w przestrzeni pnia i przekłada je przez tę
  samą bazę co sadzenie (`_trunk_basis`: pochylenie ze zboczem, obrót, skala).
  Pole ścieżki (`_path_field`) ma zasięg na najszerszą koronę. Test
  `forest_world_test` sprawdza wierzchołki narysowanych koron, nie same dyski.
  Cedr ma `min_spacing` 5 m (było 2,7 m), żeby korony nie zlewały się w jedną
  masę: otwarte niebo nad podłożem lasu ~34 % (asercja ≥ 30 %).
- **Korony w zmierzonym lesie (`canopy_visual_quality_test`, bez okna):** zasięg
  korony liczony z kęp i skali to 9–14 m. Niebo w stożku zenitalnym nad ścieżką
  ~97 % otwarte, zenit czysty (przechodzi). Skłębienie nie: 59 % sąsiednich par
  ma korony wchodzące głębiej niż 25 % promienia (cedr 0/0, sekwoje 0/2). Próg
  0 % wymagałby odstępu ~15 m zamiast 5 m, czyli ~9× mniej drzew: to zmiana
  gęstości z GDD, a nie strojenie. Decyzja otwarta; test jest czerwony do tego czasu.
- **Determinizm:** losowania per punkt to `hash([x, z, sól, seed])`, per chunk
  to `hash([coord, rodzaj, seed])`. Brak zależności od kolejności ładowania.

Żadnego zewnętrznego kodu ani addonu nie dodano: wszystko napisane w projekcie
według podanych źródeł. Brak nowych assetów w tym kroku (LICENSES/CREDITS bez
zmian).

## Testy

Dwie suity, razem ok. 30 s, bez długich czekań w czasie rzeczywistym:

- `tests/worldgen_profile_test.tscn`: ustawienie projektu, presety, round trip
  `.tres` (bez utraty pól), walidacja (błędy i ostrzeżenia), reset grupy,
  paleta, Poisson (odstęp, wypełnienie, determinizm), sieć ścieżek (każdy
  węzeł dociera do startu, trasa zaczyna się i kończy w węzłach, co 1 m),
  determinizm lasu i zmiana seeda.
- `tests/worldgen_tool_test.tscn`: każda grupa rusza las tak, jak mówi jej
  nazwa (gęstość, bramy, sakura, ścieżki i prześwit, latarnie przy ścieżce,
  LOD, mgła i paleta w Environment, poświata bram), rzadkość kapliczek względem
  bram, budżet domyślnego profilu, podgląd (bez osieroconych węzłów po 5
  przebudowach), dock (statystyki, uwagi, reset grupy, zapis presetu), plugin
  się kompiluje i jest włączony, a gra rysuje ten sam las co podgląd.

- `tests/worldgen_path_game_test.tscn`: w `run.tscn` ścieżka jest w glade i zaczyna się
  w 6 m od spawnu, lampiony stoją na ścieżce, co najmniej 15 m od siebie w chunku i nie
  bliżej niż 3,5 m od bramy, a pnie i kamienie nie wchodzą w pas ścieżki.
- `tests/worldgen_path_visible_test.tscn`: **okno, nie headless.** Kontrast ścieżki z
  pikseli klatki gry, ze spawnu i 20 m dalej (zob. „Ścieżka w grze” niżej).

Testy sąsiednie, które pilnują lasu: `forest_world_test`, `quest_perf_test`,
`hokora_test`, `torii_placement_test`, `point14_fog_torii_test`,
`xr_forest_anchor_test`.

Uwaga o testach: bramy rozgrywki (`ToriiManager`) są stawiane z zapytaniami
o kolizje w całej przestrzeni fizycznej. Dwa lasy w tej samej scenie dostają
inne bramy, więc testy porównują lasy zbudowane osobno (zob. `_isolated_digest`).

Zrzuty do oceny: `tools/worldgen/worldgen_screenshots.tscn` (okno, nie headless):
`godot --path . --fixed-fps 90 res://tools/worldgen/worldgen_screenshots.tscn -- --desktop --shots /tmp/hanabi_d8`.

## Ścieżka w grze (poprawka po testach Jakuba)

Ścieżka miała być czytelna w grze, nie tylko w danych. Co zrobiono i jak to sprawdzamy:

- **Nawierzchnia:** żwir `rocky_trail` (Poly Haven, CC0), chłodny, prawie neutralny
  odcień (`path_tint`) i wzmocnienie `path_gain` 2,2. Stara ziemia `ground067` była
  brązowa na brązowym gruncie i w renderze wypadała ciemniej od poboczy.
- **Krawędź:** węższy przejściowy pas wagi ścieżki (0,75–1,2 × szerokość) i mniej
  szumu na brzegu, więc krawędź jest ostra. Rzadkie płaskie kamienie leżą tuż za
  krawędzią (w shaderze, bez nowych obiektów).
- **Lampiony (tōrō):** kamienny tōrō ok. 1 m zastępuje dawną bryłę z trzech pudełek.
  Stoją **tylko przy ścieżce**, co najmniej `path_lantern_spacing` (15 m) od siebie
  w jednym chunku, najwyżej 2 na chunk, i nigdy bliżej niż 3,5 m od bramy tego chunku.
  Świecą słabym, ciepłym kolorem (emisja, bez źródła światła), słabszym od poświaty
  bramy. Lampiony nadal rysują się jednym MultiMeshem na chunk, bez nowych świateł.
- **Podłoże:** bez zmian poza krawędzią; las i ścieżka nadal nie dzielą materiału.

**Test renderu** (`tests/worldgen_path_visible_test`, okno, nie headless; uruchamia go
`tools/run_one_test.sh` bez `--headless`). Czyta piksele klatki z `run.tscn` (mgła i nocna
paleta profilu), z kamery 1,6 m nad spawnem patrzącej wzdłuż ścieżki, a potem 20 m dalej.
Dla odległości 2–12 m rzutuje oś ścieżki na ekran i uśrednia jasność liniową: pas ścieżki
(przesunięcia ±0,6 m) z pasem gruntu po obu stronach (±2,4 do ±3,2 m). Próg: **≥ 25%** w
obu kadrach.

| Build | Kadr ze spawnu | Kadr 20 m dalej | Wynik |
|---|---|---|---|
| `fc42a47` (przed poprawką) | −15% | +4% | FAIL |
| ta poprawka | +43% | +59% | PASS |

Zrzuty z gry (`run.tscn`, mgła, noc): `docs/worldgen/shots/game_path_from_spawn.png`
i `game_path_20m_along.png` (po poprawce), `*_before.png` (build `fc42a47`).
Robi je `tools/worldgen/game_path_screenshots.tscn` (okno).

**Czy gracz od razu widzi ścieżkę?** Tak, na zrzucie z pulpitu: ze spawnu jasny, ostro
odcięty pas żwiru zaczyna się przy dolnej krawędzi kadru i prowadzi w głąb, a podłoże
po bokach jest wyraźnie ciemniejsze. Zastrzeżenia, które zostają:
- **VR nie sprawdzone.** Nie mam gogli w tej sesji. Test mierzy okno 75° bez stereo,
  więc ostateczne słowo należy do Jakuba na goglach (pkt w `docs/QUEST_TEST.md`).
- Pas wygląda bardziej jak żwirowa droga niż ubita ziemia. To kompromis za czytelność;
  koncept dopuszcza taki wariant, ale to kwestia gustu.
- Przy 20 m poświata bram (niebieska i fioletowa) nadal przyciąga wzrok mocniej niż
  ścieżka, choć ścieżka jest już widoczna.
- Lampiony nie wchodzą w kadry z zrzutów. Ich rozmieszczenie sprawdza
  `tests/worldgen_path_game_test` (na ścieżce, rozstaw, z dala od bram), nie oko.
- Rozstaw lampionów sprawdzany jest w obrębie chunku. Między sąsiednimi chunkami może
  być mniejszy.

**Koszt bramy (pkt 7 poprawek).** `find_gate_spot` (samo szukanie) mierzy
`tests/torii_placement_test` w izolacji, mediana z 5 przebiegów: 0,034 ms
(3 z 3 przebiegów; próg 2,0 ms bez zmian). Sam `spawn_gate_at` w
`tests/diag/torii_spawn_cost.tscn` (mediana z 9, ta sama pozycja, bramę usuwamy
po pomiarze): 0,60 ms na obecnym buildzie (2 bramy w scenie) i 0,68–0,71 ms na
buildzie sprzed D8 (`7fad688`, 1 brama). Spawn nie wzrósł. Pierwsze wywołanie na
buildzie sprzed D8 trwało 253 ms (maksimum w tym pomiarze); nie zbadałem, czy to
jednorazowe ładowanie sceny bramy, bo mediana go nie obejmuje.

## Samoocena (surowo)

Porównanie `default_profile` z konceptem (zrzuty z 28.10.2026):

- **Działa:** ścieżka czytelna jako kamienna wstęga na zieleni; bramy czerwone
  z cyjanową poświatą (po zmniejszeniu siły z 0,35 na 0,12 – wcześniej bramy
  były turkusowe); sakura jako różowy blask w rzucie z góry; nocna paleta
  z różem i błękitem; podgląd i gra rysują ten sam las.
- **Słabe, ważne:**
  1. **Dystans.** Od D6 (docs/D6_FOREST_LOD.md) las czyta się do 40 m: chunki
     40 m w pierścieniu 3×3, daleka korona przy 8–40 m, mgła pełna przy 40 m.
     Daleka korona jest jeszcze prosta i ciemna (docs/D6_FOREST_LOD.md, ocena).
  2. **Korony drzew** (skan cedru + skupiska kulek) wyglądają jak ciemne
     bryły, a nie jak igliwie. To stary wygląd sprzed D8; poprawią go
     assety D5 (`crown = SCENE`).
  3. **Podłoże** jest płaskie i zielonkawo-brązowe; koncept ma mech i ciemną
     ziemię. Do poprawy w D5 (tekstury moss_ground).
  4. **Ścieżka** jest czytelna z bliska, ale z daleka ginie w gruncie.
- **Quest (`quest_perf`):** rzadszy las, tylko kilka pni w zasięgu. Dobry jako
  preset do gogli, ale za pusty na pokaz.

## Ograniczenia i decyzje

- **Pierścień 3×3 i `fog_end ≤ loaded_range()`:** od D6 pierścień ma 40 m (chunk 40 m), a mgła kończy się na jego krawędzi.
- **Kapliczki i ścieżki:** węzły sieci leżą na siatce, nie na kapliczkach.
  Kapliczka dostaje krótki odcinek (spur) do najbliższej ścieżki w zasięgu
  40 m. To spełnia „połączone”, ale nie gwarantuje, że ścieżka prowadzi
  dokładnie do drzwi kapliczki.
- **Wrogowie** nie są w profilu: należą do `WaveDirector` (rozgrywka, nie
  generacja). Decyzja świadoma.
- **LOD (D6) i assety (D5):** daleka korona jest proceduralna (`lod_near_radius`,
  `lod_fade`); integracji assetów D5 jeszcze nie ma. Impostorów sakury też nie.
- **Budowa chunków:** przy przejściu granicy nowy pierścień powstaje w kilku
  klatkach (wiersze wysokości, `TERRAIN_ROWS_PER_FRAME`); skok o więcej niż jeden
  chunk buduje od razu. Próbkowanie Poissona idzie na wątkach.
- **Zmiany wyglądu względem przed-D8:** drzewa rozstawione Poissonem (średnio
  41 na chunk przy 43 wcześniej), ścieżki wycinają drzewa i kamienie, mgła
  zaczyna się później (3,5 m zamiast 0,4 m), paleta ciemniejsza, bramy z lekką
  poświatą. Naprawiony błąd: po usunięciu pnia przez bramę rozgrywki kopiec
  korzenia zostawał pod nieistniejącym drzewem.
