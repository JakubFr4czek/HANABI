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
- [ ] **Oni:** maska **project CC0** (`oni_mask_run.glb`) — z bliska widać szczękę/rogi, nie gładką kulę; combat fog ~8 m.
- [ ] Parry / stagger Oni: czytelne, **bez zmiany chwytu** katany.
- [ ] Błyskawica za wielkim torii.

## Audio (§10 + §15)

- [ ] **CC0 deszcz** na Ambience (nie „syntetyczny szum”).
- [ ] Grzmot po błyskawicy; **stal** z nagrań (clash), nie procedural ring.
- [ ] **Muzyka** `orientalsomber` na szynie Music — cicho, nie zagłusza SFX.
- [ ] Swing katany: pitch z prędkością; kill stinger + soul; slow-mo: lekki low-pass ambience.

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
$GODOT --headless --path . --fixed-fps 90 res://tests/quest_perf_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/vfx_pool_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/firework_flash_cap_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/yokai_combat_motion_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/point12_readability_test.tscn -- --desktop
```

## Zrzuty desktop (porównanie z GDD przed Questem)

```bash
$GODOT --path . --fixed-fps 90 res://tests/point14_oni_screenshot.tscn -- --desktop --shots /tmp/hanabi_oni16
$GODOT --path . --fixed-fps 90 res://tests/point12_screenshots.tscn -- --desktop --shots /tmp/hanabi_point12_shots
```

Sprawdź: `3_oni_close_mask` (maska Oni), `4_firework_in_fog`, nadgarstek w `point15_wrist_screenshot`.
