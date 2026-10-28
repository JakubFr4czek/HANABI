# Quest 3 — checklist poranna (Jakub)

Krótka lista do przejścia na goglach przed hackathonem. Profilowanie: uruchom run z `--perf-hud` albo w trakcie gry naciśnij **F3** (desktop / link z klawiaturą). Overlay pokazuje też **lights** (OmniLight3D) i **audio~** (grające strumienie).

## Przed startem

- [ ] Build z `main`, urządzenie w Developer Mode, kabel lub Air Link stabilny.
- [ ] Włącz overlay: APK / deploy z `--perf-hud` (albo F3 po starcie runu).
- [ ] Cel: **≥72 fps** średnio w fali 8+ yōkai; headless `quest_perf_test` trzyma: draw **≤345**, particles **≤4000**, dynamic lights **≤12**, audio voices **≤28**.

## Run — pierwsze 3 minuty

- [ ] Intro seiza: płynne zejście, katana po touchdown, skip nie psuje runu.
- [ ] **Nadgarstek (§15):** HUD na dłoni, bez „pływającego pergaminu”; pierścień HP **tylko przy niskim HP**; tsuba XP czytelna.
- [ ] **Las CC0:** drzewa/torii do ~12 m; **za wielkim torii** tylko mgła (§14).
- [ ] Hitodama: po killu lecą, spiralnie wciągane; zbieranie bez lag spike’a.
- [ ] Level-up ofuda: slow-mo, slice, wybór upgrade’u — bez freezu.

## Walka i VFX

- [ ] **Yōkai (§16):** w podejściu pochylenie + krok (nogi), wind-up oczu/pazurów, slash czytelny; trafienie = stagger lub krótki flinch — bez „sztywnego ragdolla T-pose”.
- [ ] Trafienia: iskry czytelne, nie biały szum.
- [ ] **Śmierć:** firework w kolorze żywiołu we mgle; przy wielu killach naraz **max 2–3 błyski światła** (reszta emisja).
- [ ] Elita: halo w kolorze żywiołu.
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
- [ ] Zakup tylko z wystarczającą liczbą 札 i spełnionym wymaganiem; odmowa = drżenie przycisku + bzyk, bez utraty 札.
- [ ] Ink Node 5 (Abyssal Sea): +20% prędkości chodzenia w VR w swoim tuszu; nietykalność tylko 0.5 s po wejściu w tusz.

Zrzuty menu (okno, nie headless): `$GODOT --path . --fixed-fps 90 res://tests/skill_menu_screenshots.tscn -- --desktop --shots /tmp/hanabi_e2d`
(`canvas_*.png` = sama tafla 1600×1000 jak w goglach).

## Czytelność żywiołów (E3)

- [ ] Ostrze świeci **krawędzią** w kolorze żywiołu (nie płaską plamą); imbue przebiega od jabłka do czubka w ~0.4 s; po wygaśnięciu światło spływa (~0.6 s).
- [ ] Ostatnie 3 s: ostrze, smuga i pierścień na nadgarstku pulsują razem (3 Hz).
- [ ] Nadgarstek (podniesiony): kanji żywiołu + pierścień czasu, liczba sekund, dwa pierścienie A / B z glifami (pełny jasny = gotowe), 札×N. Stal bez żywiołu: przygaszone 門.
- [ ] Brama aktywna widoczna we mgle z ~25 m jako pionowa smuga światła w kolorze żywiołu; po przejściu rozbłysk i wygaszenie; nieaktywna ginie we mgle.
- [ ] Dźwięk przy nasyceniu (inny per żywioł, cichy) i miękkie „zgaśnięcie” przy końcu.
- [ ] Menu wsuwa się płynnie; stopka pokazuje żywioł, sekundy, A/B i 札. Zrzuty: `godot --path . --fixed-fps 90 res://tests/e3_readability_screenshots.tscn -- --desktop --shots /tmp/hanabi_e3`.

## Komfort VR

- [ ] Chwyt katany stabilny (brak dryfu dłoni > ~15 cm).
- [ ] Brak nausea przy level-up slow-mo i magnet orbs.
- [ ] Boundary platformy — nie wypadasz z dysku.

## Perf HUD (F3 / `--perf-hud`)

- [ ] FPS nie spada poniżej **65** w szczyt fali (krótkie spadki OK).
- [ ] **draw** stabilnie pod budżetem; skok przy level-up akceptowalny.
- [ ] **particles~** nie wisi na stałe > 3000 po walce.
- [ ] **lights** podczas fali z killami: zwykle **≤6** (limit pool 3 flash + światło sceny); alarm jeśli **>10** stale.
- [ ] **audio~** skacze przy wielu killach, ale wraca < 20 po 2 s ciszy.

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
