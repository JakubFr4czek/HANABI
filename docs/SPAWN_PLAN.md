# Fale i spawn wrogów (D10): diagnoza, wybór modelu, krzywa

Zlecenie Jakuba (28 X, 13:07): na początku ma być mniej przeciwników; system
spawnowania ma być zaplanowany na sprawdzonym algorytmie, a w edytorze ma być
panel do strojenia fal. Ten dokument powstał przed zmianą kodu.

## 1. Diagnoza obecnego spawnowania

Pliki: `src/run/wave_director.gd` (cała logika), `src/run/run_game.gd`
(`step_director`, `recall_stragglers` w `_process`), `tools/balance_model.gd`
(duplikat formuł fal do symulacji ekonomii).

Obecna logika (wszystkie liczby to stałe `@export` w `WaveDirector`):

- **Populacja fali:** `wave_enemy_count = 2 + floor((wave-1)·0.9 + t/40)`.
  Numer fali i czas liczą się **dwa razy**, więc liczba wrogów w fali rośnie
  kwadratowo, nie w tempie krzywej.
- **Limit żywych** (`concurrent_cap`): `2 + t/20`, sufit 12. Sufit jest
  **powyżej** zmierzonej bazy Quest (`RunPerfBudget`: 8 yōkai = 338 draw calls,
  limit 345).
- **Fala się nie kończy:** następna fala rrusza, gdy `pending == 0` i (`alive == 0`
  albo minęło 18 s). W praktyce `pending` nigdy nie spada do zera, więc
  przerw między falami nie ma (zmierzone, patrz niżej).
- **Elity:** od fali 3, szansa `0.10 + 0.05·(w-3)`, sufit 0.42.
- **Oni:** pierwszy po `oni_spawn_min_run_time` = 120 s, potem co 100 s.
- **Pierścień spawnu:** 7,6–10,8 m od gracza, bez kontroli kierunku widzenia
  (może pojawić się przed twarzą gracza), kolizja tylko przez 1,3 m odstępu
  od innych yōkai. Brak sprawdzenia geometrii (drzewa, podszycie).

### Liczby zmierzone (skrypt diagnostyczny, jednorazowy, nie w repo)

Skrypt woła prawdziwe metody `WaveDirector` (`wave_enemy_count`, `concurrent_cap`,
`scaled_hp`) i symuluje gracza z profilu „average” z `tools/balance_model.gd`
(85 · 0,8 trafień/s · 0,75 uptime, przerwa 1,4 s między wrogami, jeden naraz).

| czas | fala | oczekuje | żywych / cap | pokonanych | razem zespawnowanych |
|---|---|---|---|---|---|
| 30 s | 3 | 1 | 2 / 3 | 6 | 8 |
| 60 s | 4 | 0 | 2 / 5 | 12 | 14 |
| 120 s | 7 | 8 | 7 / 8 | 24 | 31 |
| 180 s | 8 | 6 | 10 / 11 | 35 | 45 |
| 300 s | 10 | 17 | 12 / 12 | 53 | 65 |
| 480 s | 11 | 15 | 12 / 12 | 76 | 88 |

Średnio 9,9 żywych w 10-minutowym runie. Wnioski:

1. **Start nie jest spokojny.** Po 60 s zespawnowano 14 yōkai, a po 2 min 31.
   Jakub chciał mniej na początku. To jest główny problem.
2. **Brak oddechu.** Od ~5 min `pending` nie spada do zera, więc gracz ma
   stały, płaski napór na 12 żywych bez relaksu. To ściana, nie krzywa.
3. **Cap 12 jest powyżej zmierzonego budżetu Quest** (8 yōkai = 338 draw calls).
4. **Liczba w fali jest źle zbudowana** (podwójne liczenie wave × czas), więc
   nie da się jej sensownie stroić z panelu.
5. **Spawn może pojawić się w polu widzenia** i wewnątrz geometrii (drzewo,
   kamień). Nie ma na to testu.

Uwaga do modelu: symulacja nie uwzględnia wzrostu mocy ostrza z poziomem, więc
liczby kończenia fal są ostrożne. Zmierzone wartości służą do porównania
starego i nowego systemu, nie do bezwzględnej prognozy.

## 2. Przegląd sprawdzonych rozwiązań i wybór

- **AI Director z Left 4 Dead (Michael Booth, Valve, GDC 2009, „The AI Systems
  of Left 4 Dead”)** – slajdy: https://cdn.fastly.steamstatic.com/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf
  Dyrektor steruje intensywnością, nie pojedynczymi wrogami. Opis w prasie
  (Gamasutra, „The Discomfort Zone”): dyrektor patrzy na stan drużyny (zdrowie,
  tempo, intensywność walki) i zmienia liczbę wrogów. **Cyklu build-up/peak/relax
  nie udało mi się potwierdzić w samym PDF** (tekst ze streszczenia wyszukiwarki
  tego nie zawiera); przyjmuję go jako model ogólny, do weryfikacji w slajdach.
  Przejęte: stany dyrektora i cykl oddechu. Nie przejęte: śledzenie zdrowia gracza
  (to późniejszy krok, patrz §8).
- **Budżet punktów zagrożenia (credits) z Risk of Rain 2** – wiki gry,
  strona „Directors”: https://riskofrain2.wiki.gg/wiki/Directors
  Dyrektor zbiera kredyty w czasie, każdy wróg ma koszt, a grupa jest opłacana
  z budżetu. Nie ma tu sztywnego licznika per fala. Przejęte: **budżet kredytów
  na falę** (koszt wroga, waga typu, bufor). Pomijam model „do 4 w grupie”.
- **Krzywa trudności, sawtooth** – to samo źródło co L4D (pacing), w praktyce
  zapis na krzywej w profilu, a nie kod.
- **Vampire Survivors** (budżet liczony z czasu) – wzorzec gatunku bez publicznego
  postmortemu; nie biorę liczb z tego źródła.
- **Pierścień spawnu poza polem widzenia i poza geometrią** – standard gier
  z kamerą pierwszoosobową; w kodzie: kąt względem kamery (`player_head`, grupa
  już istnieje) i zapytanie fizyczne o kształt przed spawnem.

Odrzucone: model liczenia wrogów per fala z wzorem na numer fali (zgaduje
kształt krzywej w dwóch miejscach naraz); pełny system grup ze spawn cards
(zbyt dużo na jeden etap).

## 3. Docelowa krzywa (wartości z profilu „Domyślny”, zmierzone)

Czas t liczony w sekundach od startu runu. Wszystkie liczby są w `WaveProfile`
(zasób `.tres`), nie w kodzie. Tabela pochodzi z `WavePlanner.simulate`
(ten sam kod co gra), seed 7, stały DPS gracza (patrz §10).

| minuta | fala | żywych (śr.) / cap | zespawnowano (razem) | stara krzywa (razem) |
|---|---|---|---|---|
| 1 | 4 | 0,2 / 3 | 3 | 14 (przy 60 s) |
| 2 | 8 | 0,4 / 4 | 7 | 31 (przy 2 min) |
| 3 | 10 | 2,0 / 5 | 14 | 45 |
| 4 | 12 | 3,4 / 7 | 26 | – |
| 5 | 14 | 6,7 / 8 | 34 | – |
| 8 | 15 | 8,0 / 8 | 52 | 88 |

Fazy: **cisza** (0–75 s) – 1 kredyt na falę, przerwa 14 s, pierwszy yōkai po 5 s;
**narastanie** – budżet z 1 do 18 kredytów, przerwy z 14 s do 2,5 s, cap rośnie
co 45 s od 2 do 8; **pełny napór** od ~5 min – cap 8.

Cykl dyrektora (deterministyczny, sawtooth): fala 1 BUILD, fala 2 BUILD, fala 3
PEAK (kredyty ×1,5, przerwa ×0,5), fala 4 RELAX (kredyty ×0,5, przerwa ×1,8),
i tak dalej. Krzywa kredytów jest zależna od czasu przez `budget_curve` (Curve
z inspektora), więc panel może ją pokazać i edytować.

Typy i koszty: swarm koszt 1, elita koszt 4 (od 150 s, szansa 0 → 0,25 na końcu
rampy, tylko gdy wystarczy kredytów). Oni: pierwszy po 180 s, **na początku
najbliższej fali PEAK**, potem co 100 s (nie więcej niż jeden naraz).

HP i prędkość: `scaled_hp` i `scaled_speed` z tymi samymi współczynnikami co
przed zmianą (0,14 na falę, 0,004 na sekundę). Przy 6 min HP ≈ 4,4× bazowego,
dlatego symulacja z płaskim DPS gracza wchodzi na cap i zostaje tam (§11).

## 4. Jak to wpina się w resztę

- **Run loop:** `RunGame._process` nadal woła `step_director(delta, p_pos)`;
  dochodzi trzeci argument, kierunek widzenia gracza (z grupy `player_head`).
- **Torii i żywioły (D1, ELEMENTS_PLAN):** bez zmian; yōkai nie wchodzą w bramy.
  Odstęp od bram (14 m) sprawdza ForestWorld przy budowie chunków.
- **Kapliczki (D1):** bez zmian. Nagrody z zabójstw dalej idą przez `enemy_died`.
- **Sandbox (D9):** tryb odblokowania nie zmienia spawnu.
- **Budżet Quest:** cap domyślny 8 = zmierzona baza stresu (338 draw calls < 345).
  Presety różnią się krzywą i HP, nie liczbą ciał (`MAX_YOKAI_PHYSICS_BODIES` = 72,
  więc zapas jest). Panel ostrzega, gdy cap > 8.

## 5. Architektura kodu

- `src/run/wave_profile.gd` – `class_name WaveProfile extends Resource`.
  Pola `@export` w grupach (Pacing, Budget, Enemies, Director, Ring, Caps, Scaling,
  Oni). Metody: `validate() -> PackedStringArray` (błędy i ostrzeżenia), a także
  `default_profile()`.
- `src/run/wave_planner.gd` – `class_name WavePlanner extends RefCounted`.
  Czysta logika bez węzłów: stan dyrektora, kredyty, cap, typy i wybór wroga,
  przerwy, Oni. Używana przez `WaveDirector` i przez symulację.
- `src/run/wave_director.gd` – zostaje węzłem spawnu (pierścień, pula, zabójstwa,
  sygnały). Liczby czerpie z profilu i planera; stare `wave_enemy_count`,
  `elite_spawn_chance`, `concurrent_cap` znikają (albo oddają wynik planera).
- `data/waves/` – presety: `demo_gentle.tres` („Demo – łagodny”),
  `default.tres` („Domyślny”), `hardcore.tres` („Hardcore”). Generuje je
  `tools/waves/make_presets.gd`, tak jak presety lasu.
- `tools/balance_model.gd` – zamiast duplikatu formuł woła `WavePlanner`, więc
  symulacja ekonomii i gra czytają to samo.
- `addons/hanabi_spawn/` – `EditorPlugin` z dockiem „Fale” w stylu WorldGen
  (`plugin.gd`, `wave_dock.gd`). Dock buduje się w kodzie, więc testy tworzą go bez
  edytora.
- `docs/SPAWN_TOOL.md` – instrukcja dla Jakuba.

## 6. Walidacja i screenshoty

Walidacja profilu (`validate()`): cap > `QUEST_YOKAI_CAP` (8) ostrzeżenie;
`start_cap` > `cap_hard` błąd; krzywa budżetu musi być monotoniczna w przybliżeniu
(ostrzeżenie); `ring_min` ≥ `ring_max` błąd; `view_half_angle` poza 30–90° błąd;
`peak_every_waves` < 2 błąd (nie ma wtedy relaksu).

Testy krytyczne (patrz §7). Screenshoty z gry (nie z preview): początek runu
(mało wrogów), szczyt fali PEAK; plus zrzut docku z wykresem.

## 7. Plan testów (krytyczne, krótkie, krok czasu bez czekania)

Rozszerzamy `tests/run_loop_test.gd` (istnieje i już testuje falę), zamiast
mnożyć pliki:

1. Pierwsze 60 s: liczba zespawnowanych ≤ 4, naraz żywych ≤ 3.
2. Symulacja 8 min deterministyczna dla seeda (dwa przebiegi dają ten sam
   przebieg), a naraz żywych nigdy > `QUEST_YOKAI_CAP` (8).
3. Spawn nigdy w polu widzenia: na prawdziwej scenie `run.tscn`, dla każdego
   spawnu sprawdzamy `camera.is_position_in_frustum` (zero) i kąt względem
   kierunku widzenia > `view_half_angle`.
4. Spawn nigdy w kolizji: zapytanie o kształt (kula 0,5 m) na masce geometrii
   (warstwy 4|8, jak u yōkai) zwraca zero trafień w punkcie spawnu.
5. Presety przechodzą `validate()` bez błędów; Hardcore ma wyższy szczyt niż Demo.
6. Dock ładuje się headless bez błędów (`tests/worldgen_tool_test.gd` już
   tworzy dock w kodzie; dodajemy sprawdzenie docku fal w tym samym pliku, bo
   to ten sam wzorzec).

Testy wizualne (wymóg Jakuba): test 3 sprawdza to, co faktycznie jest w kadrze,
na scenie `run.tscn`, a nie dane.

## 8. Co zostaje poza zakresem (świadomie)

- Dyrektor reagujący na zdrowie gracza (L4D). Dodać po pierwszym playtestcie.
- Zmiana HP i balansu walki. Dziś zostają stare współczynniki; to osobny krok.
- Wykres z realnej gry (telemetria). Panel pokazuje symulację, nie pomiar.
- Warunki spawnu zależne od bramek ForestWorld poza odstępem 14 m.

## 9. Otwarte ryzyka

- Cykl sawtooth jest deterministyczny (co 3. fala). Przy szybkich falach
  szczyt może trwać krótko; zmierzyć w grze.
- Liczba fal rośnie przy szybkiej grze; HP rośnie z numerem fali. Patrz §3.
- Weryfikacja cyklu L4D w PDF Valve jest niedokończona (patrz §2).

## 10. Decyzje podjęte w trakcie wdrożenia

- **Budżet kredytów zamiast liczby per fala.** Fala ma pulę kredytów (zwykły
  yōkai 1, elita 4). Pula rośnie krzywą w czasie. Stary wzór (fala × czas) znika.
- **Cap 8 (Quest), nie 12.** Zmierzona baza stresu to 8 yōkai i 338 wywołań
  rysowania przy limicie 345. Presety różnią się krzywą i HP, nie liczbą ciał.
- **Przerwy i budżet startowy.** Cisza na start: 1 kredyt na falę, przerwa 14 s,
  pierwszy yōkai po 5 s. Test z §7 pilnuje, że w pierwszej minucie jest ≤ 4.
- **Progresja drzewka (D12) zmieniona w ślad za ciszą.** Mniej zabójstw na
  starcie oznacza, że pierwszy poziom (150 XP, 7 zabójstw) nie wypada w minutę.
  Zmieniono progi poziomów na 60 + 40 za poziom. XP za wroga (24/48/64) bez zmian.
  Cele drzewka z `tests/skill_tree_data_test.gd` przechodzą bez zmiany asercji.
- **Symulacja gracza ze stałym DPS.** Panel i testy używają 51 DPS (profil
  „average”), bez wzrostu mocy ostrza z poziomem. Stąd płaski szczyt przy capie
  po ~5 min: w grze moc rośnie z poziomem, więc to przybliżenie zawyża napór
  późnego runu. Do sprawdzenia na prawdziwym playtestcie.
- **Zamknięcie fali przy timeoucie 18 s.** Fala nie czeka na zabicie wszystkich,
  bo bez tego (stary błąd) przerwy nie istniały.
- **Cykl L4D potwierdzony tylko jako model.** Cyklu build-up/peak/relax nie
  znaleziono w tekście slajdów Valve dostępnym przez wyszukiwarkę; przyjęto go
  jako ogólny wzorzec i zrealizowano jako deterministyczny sawtooth (co 3. fala).

## 11. Ocena zrzutów (docs/d10, surowo)

Zrzuty: `1_run_start_first_minute`, `1b_run_start_turned_to_wave`,
`2_peak_wave`, `2b_peak_wave_turned_to_pack`, `3_spawn_ring_top_down`,
`4_fale_dock`.

Co jest dobre: w kadrze startu nie ma yōkai, bo spawn leży poza kątem widzenia
(zgodnie z celem). Po obrocie do fali widać je z czerwonymi oczami i przy
mgle czytelnie. Widok z góry pokazuje 40 punktów spawnu jako łuk z wolnym
klinem ~120° w kierunku widzenia. Dock: wykres, tabela i presety zgodne z grą.

Co jest słabe i zostaje otwarte:

- **Yōkai wyglądają prymitywnie** (bryłowate postacie z prymitywów). To są
  placeholdery z istniejącej sceny, nie efekt tej pracy, ale wpływają na
  wrażenie „premium”, które oceniamy.
- **Od ~5 min cap jest stale pełny** (8 z 8). To nie wina krzywej fal, tylko
  wzrostu HP (4,4× przy 6 min) przy stałym DPS w symulacji. W grze moc ostrza
  rośnie z poziomem, więc prawdziwy napór będzie niższy. Do sprawdzenia
  na playteście, a decyzja o HP należy do balansu.
- **Widok z góry** pokazuje punkty spawnu jako rzut, nie wysokość, bo korona
  cedrów zasłania ring z poziomu gruntu.
- **Brak relaksu widocznego w kadrze**: sawtooth jest w liczbach (fale 3 i 4),
  ale przy pełnym capie nie przekłada się na mniej wrogów w czasie.

