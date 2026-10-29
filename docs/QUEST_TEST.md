# Quest 3 — checklist poranna (Jakub)

Krótka lista do przejścia na goglach przed hackathonem. Profilowanie: uruchom run z `--perf-hud` albo w trakcie gry naciśnij **F3** (desktop / link z klawiaturą). Overlay pokazuje też **lights** (OmniLight3D) i **audio~** (grające strumienie).

## Przed startem

- [ ] Build z `main`, urządzenie w Developer Mode, kabel lub Air Link stabilny.
- [ ] Włącz overlay: APK / deploy z `--perf-hud` (albo F3 po starcie runu).
- [ ] Cel: **≥72 fps** średnio w fali 8+ yōkai; headless `quest_perf_test` trzyma: draw **≤345**, particles **≤4000**, dynamic lights **≤12**, audio voices **≤28**.

## Run — pierwsze 3 minuty

- [ ] Intro seiza: płynne zejście, katana po touchdown, skip nie psuje runu.
- [ ] **Nadgarstek (§15, D14):** HUD na nadgarstku z przezroczystym tłem (bez panelu); gładki pierścień HP (teal -> bursztyn -> czerwony + puls przy <25%), w środku animowany ogień i biały licznik kalorii (kcal); żywioł na cienkim zewnętrznym łuku; widoczny TYLKO przy geście spojrzenia na zegarek (dystans <0.35 m, kąt <45°, w polu widzenia, fade 0.15 s; zero draw calls przy opuszczonej ręce); brak clippingu z dłonią/rękawicą/kataną.
- [ ] **Las CC0:** drzewa/torii do ~12 m; **za wielkim torii** tylko mgła (§14).
- [ ] Hitodama: po killu lecą, spiralnie wciągane; zbieranie bez lag spike’a.
- [ ] **Level-up (D12):** bez slow-mo i bez wyboru; haptyka obu dłoni, błysk na nadgarstku (~0.6 s), tekst „位 LV n · +1 点" przez 1.5 s.

## Walka i VFX

- [ ] **Yōkai (§16):** w podejściu pochylenie + krok (nogi), wind-up oczu/pazurów, slash czytelny; trafienie = stagger lub krótki flinch — bez „sztywnego ragdolla T-pose”.
- [ ] Trafienia: iskry czytelne, nie biały szum.
- [ ] **Śmierć:** firework w kolorze żywiołu we mgle; przy wielu killach naraz **max 2–3 błyski światła** (reszta emisja).
- [ ] Elita: oczy, sigil, szarfa i pazury w kolorze żywiołu; **bez** okręgu ani halo na ciele (D2).
- [ ] **Oni (§19):** maska `oni_mask_run.glb` (sculpt v2 ~1k v) — **~2 m**: biały lakier, oczodoły, kły/rogi; **~6 m**: sylwetka + czerwone oczy we mgle; nie „gładka kula”.
- [ ] **Yōkai (§19):** przejście stalk→approach płynne (bez szarpnięcia); trafienie = krótki **flinch** z lekkim kołysaniem, potem powrót do stalk.
- [ ] Parry / stagger Oni: czytelne, **bez zmiany chwytu** katany.
- [ ] Błyskawica za wielkim torii.

## Audio (§10 + §15 + §18)

- [ ] **CC0 deszcz** na Ambience (nie „syntetyczny szum”); wiatr lasu też na **Ambience**, nie Music.
- [ ] Grzmot po błyskawicy; **stal** z nagrań (clash), nie procedural ring.
- [ ] **Cięcie / trafienie / obrażenia**: Kenney Impact (`cc0_combat/`), 2–3 warianty + pitch — nie `assets/audio/generated/`.
- [ ] **Muzyka** `orientalsomber` na szynie Music — cicho (~−23 dB + limiter), **crossfade** na końcu utworu (bez kliku), **duck −9 dB** na level-up.
- [ ] Swing katany: pitch z prędkością; kill stinger + soul; slow-mo: lekki low-pass ambience.

## Wydajność §18 (po §16.3)

- [ ] Fala 8+ yōkai + 1 kill firework: **lights ≤ 3** (pool flash), **audio~** wraca < 20 po 2 s (Sfx soft-cap na tell/ring).
- [ ] Oni w walce: rim Omni **tylko < 14 m** (poza zasięgiem wyłączony).
- [ ] Headless `quest_perf_test` z symulacją 3× `VfxPool.spawn_firework_flash` + `ElementFirework` — draw ≤ 345, lights ≤ 12.

## Menu drzewka umiejętności (E2d)

- [ ] **Lewy Menu (tap)** otwiera menu 1.1 m przed twarzą; drugi tap zamyka. Przytrzymanie 1 s = recenter (nie otwiera menu).
- [ ] Świat **stoi** (yōkai, deszcz, timer żywiołu, cooldowny), ale głowa, dłonie i katana ruszają się płynnie; katana nie wypada z ręki po zamknięciu.
- [ ] Muzyka przygasa i staje się „zamknięta” (low-pass), po zamknięciu wraca w ~0.25 s.
- [ ] Wskaźnik z **obu** kontrolerów (spust = wybór): zakładki żywiołów, węzły, przycisk UNLOCK; hover daje krótki puls haptyczny.
- [ ] Menu otwarte przy drzewie / ścianie / torii: panel **nie wchodzi w geometrię**, jest czytelny w mgle (nie zamglony), dłonie i ostrze zasłaniają go poprawnie.
- [ ] Zakup tylko z wystarczającą liczbą 点 (punktów z poziomów) i spełnionym wymaganiem; odmowa = drżenie przycisku + bzyk, bez utraty punktów.
- [ ] Ink Node 5 (Abyssal Sea): +20% prędkości chodzenia w VR w swoim tuszu; nietykalność tylko 0.5 s po wejściu w tusz.

Zrzuty menu (okno, nie headless): `$GODOT --path . --fixed-fps 90 res://tests/skill_menu_screenshots.tscn -- --desktop --shots /tmp/hanabi_e2d`
(`canvas_*.png` = sama tafla 1600×1000 jak w goglach).

## Czytelność żywiołów (E3)

- [ ] Ostrze świeci **krawędzią** w kolorze żywiołu (nie płaską plamą); imbue przebiega od jabłka do czubka w ~0.4 s; po wygaśnięciu światło spływa (~0.6 s).
- [ ] Ostatnie 3 s: ostrze, smuga i pierścień na nadgarstku pulsują razem (3 Hz).
- [ ] Nadgarstek (podniesiony): kanji żywiołu + pierścień czasu, liczba sekund, dwa pierścienie A / B z glifami (pełny jasny = gotowe), linia „XP a/b · 点 N · 波 w”. Stal bez żywiołu: przygaszone 門.
- [ ] Brama aktywna widoczna we mgle z ~25 m jako pionowa smuga światła w kolorze żywiołu; po przejściu rozbłysk i wygaszenie; nieaktywna ginie we mgle.
- [ ] Dźwięk przy nasyceniu (inny per żywioł, cichy) i miękkie „zgaśnięcie” przy końcu.
- [ ] Menu wsuwa się płynnie; stopka pokazuje żywioł, sekundy, A/B i 点. Zrzuty: `godot --path . --fixed-fps 90 res://tests/e3_readability_screenshots.tscn -- --desktop --shots /tmp/hanabi_e3`.

## Kapliczka i żółta ofuda (D12)

- [ ] Podejście do kapliczki **nic nie robi**: dźwięk suzu i światło, bez pauzy.
- [ ] **Dłoń bez katany** na ofierze (ołtarz, 0.35 m) i stojąc blisko: otwiera się wybór. Dłoń z kataną nie otwiera.
- [ ] Wróg w 3.5 m: wybór **odmówiony**, suzu cicho, kapliczka dalej zapalona.
- [ ] Wybór: trzy żółte ofudy w wolnej przestrzeni przed tobą, **bez przenikania** przez drzewo, skałę, latarnię ani wroga.
- [ ] Świat **stoi** jak w menu (wróg, pociski, timery, buffy); nie idziesz i się nie obracasz; katana nie krzywdzi wrogów.
- [ ] Cięcie ofudy: buff z timerem na nadgarstku, dwie pozostałe znikają, świat rusza płynnie, kapliczka gaśnie na stałe.
- [ ] Nieużyta kapliczka po odejściu i powrocie świeci dalej.
- [ ] Zrzuty: `godot --path . --fixed-fps 90 res://tests/hokora_screenshots.tscn -- --desktop --shots /tmp/hanabi_d12`.

## Cięcie jak masło (D4, tachi)

- [ ] Węzeł 5 drzewka (Hanadachi / Raidachi / Sumidachi / Kagedachi) odblokowany, imbue żywiołu trwa: czyste, szybkie cięcie krawędzią (≥ 8 m/s) rozcina yōkai na dwie części w płaszczyźnie ostrza (poziomo przy cięciu w pasie).
- [ ] Przekrój od pierwszej klatki widać jako świecąca linia w kolorze żywiołu (Ink: ciemna czerń z indygo, nie biała plama); żarzenie gaśnie w ~1.6 s.
- [ ] Połówki leżą w miejscu cięcia, rozpadają się w płatki sakury i znikają po ~3.4 s. Nic nie blokuje ostrza ani gracza (kolizja tylko z terenem).
- [ ] Ostrze nie szarpie się w dłoni po cięciu (odpór ~¼ zwykłego cięcia); spam kilku cięć na klatkę nie zapycha sceny (≤ 8 kawałków, ≤ 2 podziały na klatkę).
- [ ] Elita: mocne cięcie to rana, dopiero zabójstwo ją rozcina. Oni: świecąca szczelina (~2 s) na korpusie zamiast rozcięcia.
- [ ] Zrzuty: `godot --path . res://tests/element_abilities_screenshots.tscn -- --shots /tmp/hanabi_kirisute` (bez `--headless`). Ocena surowa: przekrój jest płaską plamą bez żarzącej się krawędzi (do poprawy).

## World Gen (D8, las z profilu)

- [ ] Las rysuje się z `default_profile` (lub presetu z `project.godot`) bez skoków klatek przy przejściu między chunkami (zrzut: ~80–120 ms na nowy chunk to znany koszt, zob. docs/WORLDGEN_TOOL.md).
- [ ] Ścieżka jest czytelna jako kamienna wstęga, nie wchodzi w pnie; bramy mają czerwony korpus z delikatną cyjanową poświatą.
- [ ] **Ścieżka widoczna od razu w VR** z spawnu (0,0,1.8) i 20 m dalej, w nocy i mgle, bez szukania wzrokiem. Pulpitowy test renderu tego nie zastępuje (zob. docs/WORLDGEN_TOOL.md, „Ścieżka w grze”).
- [ ] Tōrō przy ścieżce (co ok. 15–25 m) są widoczne jako kamienie z ciepłą, słabą poświatą, słabszą od bram.
- [ ] Mgła zaczyna się około 3,5 m i jest pełna przy 11 m; krawędź chunków nie jest widoczna.
- [ ] Zmierzch: róż i błękit mieszają się bez skoku; nie ma lawendowej mgły.
- [ ] Sakura (focal) jest jedna co kilka chunków i czytelna z daleka.

## Komfort VR

- [ ] Chwyt katany stabilny (brak dryfu dłoni > ~15 cm).
- [ ] Brak nausea przy level-up slow-mo i magnet orbs.
- [ ] Boundary platformy — nie wypadasz z dysku.

## Ustawienia (D3)

- [ ] Menu **5 / 安 SETTINGS** otwiera się na AUDIO; zakładka trzyma pauzę (świat stoi), zamknięcie wznawia.
- [ ] **DŹWIĘK:** każdy suwak co 10 %; Master gasi wszystko, SFX gra krótki sygnał przy zmianie; po ponownym uruchomieniu poziomy wracają z `hanabi_vr.cfg`.
- [ ] **RUCH:** tempo SLOW / NORMAL / FAST działa i sumuje się z mocą atramentu; wignieta i obrót bez zmian.
- [ ] **UŁATWIENIA:** `OFF 0 %` błysku: brak rozbłysku lampy pioruna i fajerwerku, łuk pioruna i grzmot zostają. Haptyka `OFF`: cisza; `TEST`: impuls w dłoni z kataną.
- [ ] **STEROWANIE:** każdy przycisk Questa z mapy jest opisany; po zamianie ręki dominującej katana, drążek ruchu, drążek obrotu i HUD zmieniają strony (pigułki i podsumowanie u góry).
- [ ] Przycisk Meta opisany jako systemowy; nic z tekstu nie wychodzi poza kafelek przy 0,8–1 m.

Zrzuty (okno, nie headless): `$GODOT --path . --fixed-fps 90 res://tests/skill_menu_screenshots.tscn -- --desktop --shots /tmp/hanabi_d3` (`canvas_07` … `canvas_11`).

## D3_fix1 — otwarcie menu nie przesuwa gracza

Zgłoszenie Jakuba (28 X): po odpaleniu menu czasem „przesuwało mnie w bok”, jakby w świecie gry.

**Przyczyna (potwierdzona testem):** menu zatrzymuje providery ruchu (`MovementDirect`, `MovementTurn`), ale nie ciało gracza (`XRToolsPlayerBody`). Rig ma `PROCESS_MODE_ALWAYS`, więc ciało dalej wykonuje krok fizyki podczas pauzy i całkuje ostatnią prędkość z tłumieniem. Origin jedzie razem z nim: przy otwarciu w pełnym kroku (drążek wychylony) rig zjeżdżał ~0,57 m, przy strafe + snap turn ~0,51 m, i zostawał przesunięty po zamknięciu. Pauza miała zerowe wejście, ale zerowanie prędkości nigdy nie nastąpiło.

**Sprawdzone i odrzucone:**
- *Drążek i przycisk menu na tym samym kontrolerze:* drążek jest ignorowany w pauzie; zjazd trwa też przy drążku w spoczynku.
- *Recenter:* nie jest wywoływany przez otwarcie (tylko przytrzymanie MENU 1 s albo B 0,6 s, a przy trzymanej katanie B nie działa).
- *Panel kolizją z ciałem:* panel nie ma żadnego `CollisionObject3D`; `UiPlacement` tylko czyta świat. Test to sprawdza.
- *Ruch fizyczny głowy (roomscale):* ciało podąża za głową, a origin nie jest przesuwany (czytane z `XRToolsPlayerBody._physics_process`).
- *Desktop:* `DesktopPlayer` już zeruje prędkość przy `get_tree().paused`; błąd był tylko w XR.

**Naprawa** (`src/player/xr_player.gd`, `set_locomotion_enabled`): przy wyłączeniu lokomocji (otwarcie menu) zerujemy prędkość ciała i parkujemy je flagą `enabled` (ta sama ścieżka co zawieszenie w intro). Ciało nie wykonuje kroku fizyki, origin stoi, a po zamknięciu nie ma pędu do zaaplikowania. `Engine.time_scale` bez zmian.

**Test** (`tests/vr_menu_pause_test.gd`, „2b”, 16 sprawdzeń): menu otwierane przyciskiem Left Menu przy wychylonym drążku, przy trwającym snap turn (strafe + obrót, ~180° w klatkach przed naciśnięciem) i przy prędkości ~2–3 m/s. Pozycja i rotacja origin oraz ciała są porównywane z pozą w chwili otwarcia (1 mm, 0,1°): po 45 klatkach w pauzie, przy zamknięciu i 30 klatek po zamknięciu. Test sprawdza też, że panel nie ma ciała kolizyjnego. Na kodzie sprzed naprawy 6 z 16 sprawdzeń failuje (zjazd 0,57 m / 0,51 m); po naprawie wszystkie przechodzą, a prędkość po zamknięciu wynosi 0,00 m/s.

- [ ] Na goglach: idź drążkiem i naciśnij MENU w biegu. Po zamknięciu stoisz tam, gdzie stałeś w chwili otwarcia; nic nie ślizga się w pauzie ani po zamknięciu.
- [ ] Ten sam test z obrotem snap w trakcie otwarcia: brak przeskoku po zamknięciu.

## Perf HUD (F3 / `--perf-hud`)

- [ ] FPS nie spada poniżej **65** w szczyt fali (krótkie spadki OK).
- [ ] **draw** stabilnie pod budżetem; skok przy level-up akceptowalny.
- [ ] **particles~** nie wisi na stałe > 3000 po walce.
- [ ] **lights** podczas fali z killami: zwykle **≤6** (limit pool 3 flash + światło sceny); alarm jeśli **>10** stale.
- [ ] **audio~** skacze przy wielu killach, ale wraca < 20 po 2 s ciszy.

## Boot splash (D7, filmy D7_fix1)

- [ ] Start: czarne tło, panel z filmem HANABI (fajerwerk, potem napis), nie logo Godota; ekran startowy silnika to klatka z filmu.
- [ ] Panel ~3,5 m przed oczami, na wysokości oczu, 4,8 m szerokości (ok. 69° pola widzenia); nie porusza się z głową; po bokach czarna pustka.
- [ ] Ostrość: film 1280x720 wyświetlony w panelu ~1000 px na Quest 3 (bez mory, bez zamglenia); fajerwerk bez poświaty od tła.
- [ ] Dekodowanie Theora: płynne 30 fps, bez spadków przy starcie (HUD perf: fps ≥ 72 w pierwszych 9 s). Jeśli spadki: zapisać w docs, rozważyć jeszcze mniejszy film. Proxy na Macu (ffmpeg, sama dekompresja): 1080p ≈ 0,27 ms/klatkę, 720p ≈ 0,16 ms/klatkę; na goglach nie mierzono.
- [ ] Cisza pod filmami (bez deszczu, wiatru i grzmotu); deszcz i wiatr wracają razem z intro.
- [ ] Przerwa 0,3 s czerni, potem NANJO: nić spływa z góry w literę J, logo ostre, bez migotania.
- [ ] Trigger / A / X kończy splash od razu (krótki fade); intro nie startuje od razu i nie pomija się tym samym wciśnięciem.
- [ ] Po splashu: las wychodzi z czerni płynnie (~0,6 s), intro seiza jak wcześniej.
- [ ] Komfort: brak ruchu kamery, brak migotania, brak wejścia gracza ani wrogów w tle.

## Po sesji

- [ ] Zanotuj falę / liczbę wrogów przy najgorszym fps.
- [ ] Zrzut ekranu z overlay (wartości draw / lights / particles).
- [ ] Jeśli coś padło: issue z tagiem `quest` + ostatni commit SHA.

## Headless (CI — nie zastępuje gogli)

```bash
GODOT=".tools/Godot.app/Contents/MacOS/Godot"
# Pełny zestaw README (26 scen): wszystkie powinny kończyć się ALL PASSED (0 failed).
$GODOT --headless --path . --fixed-fps 90 res://tests/quest_perf_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/yokai_combat_motion_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/run_loop_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/vfx_pool_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/firework_flash_cap_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/yokai_combat_motion_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/point12_readability_test.tscn -- --desktop
```

## Zrzuty desktop (porównanie z GDD przed Questem)

```bash
GODOT=".tools/Godot.app/Contents/MacOS/Godot"
$GODOT --path . --fixed-fps 90 res://tests/point19_combat_screenshots.tscn -- --desktop --shots /tmp/hanabi_point19_combat
$GODOT --path . --fixed-fps 90 res://tests/point14_oni_screenshot.tscn -- --desktop --shots /tmp/hanabi_oni16
$GODOT --path . --fixed-fps 90 res://tests/point12_screenshots.tscn -- --desktop --shots /tmp/hanabi_point12_shots
```

Sprawdź §19: `oni_fog_2m_wave`, `oni_fog_6m_wave`, `yokai_approach_stride`, `yokai_flinch_hit`. Starsze: `3_oni_close_mask`, firework, nadgarstek (`point15_wrist_screenshot`).

## D15 Oni boss — zrzuty (ręczne, NIE w suicie)

`tests/oni_boss_screenshots.tscn` nie jest częścią `tools/run_tests.sh` (suita działa wyłącznie headless). Scena wymaga renderowanego okna (framebuffer): w `--headless` kończy się `exit 1` bez zapisu PNG i nie nadpisuje `docs/d15/`. Każdy zrzut przechodzi twarde asercje kadru (głowa, stopy, kanabō i dymek w kadrze; sylwetka różni się od tła), inaczej nie zapisuje PNG. Domyślnie zapis do `/tmp/hanabi_shots`; `--shots docs/d15` tylko świadomie, po zatwierdzeniu wyniku.
