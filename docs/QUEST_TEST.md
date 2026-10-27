# Quest 3 — checklist poranna (Jakub)

Krótka lista do przejścia na goglach przed hackathonem. Profilowanie: uruchom run z `--perf-hud` albo w trakcie gry naciśnij **F3** (desktop / link z klawiaturą).

## Przed startem

- [ ] Build z `main`, urządzenie w Developer Mode, kabel lub Air Link stabilny.
- [ ] Włącz overlay: `godot` export / APK z tym samym co CI, albo editor deploy z `--perf-hud`.
- [ ] Cel: **≥72 fps** średnio w fali 8+ yōkai, draw calls **≤345**, particles **≤4000** (wartości z `quest_perf_test`).

## Run — pierwsze 3 minuty

- [ ] Intro seiza: płynne zejście, katana po touchdown, skip (jeśli jest) nie psuje runu.
- [ ] Diegetyczny HUD (tsuba + nadgarstek): czytelny, bez migotania bloomu.
- [ ] **Las CC0** (Quaternius / polyfork): drzewa i mniejsze torii czytelne do ~12 m; **za wielkim torii** tylko mgła — bez twardej linii horyzontu / „ściany” chunków.
- [ ] Hitodama: po killu lecą, spiralnie wciągane; zbieranie bez lag spike’a.
- [ ] Level-up ofuda: slow-mo, slice, wybór upgrade’u — bez freezu.

## Walka i VFX

- [ ] Trafienia: iskry czytelne, nie biały szum.
- [ ] **Śmierć yōkai:** krótki firework w kolorze żywiołu — **widoczny we mgle** (neon + krótki błysk), bez konfetti / tęczy.
- [ ] Elita: halo w kolorze żywiołu odróżnia od swarmu.
- [ ] **Oni boss:** z bliska widać **maskę, oczy, rogi, zbroję** (nie czarna sylwetka); w walce mgła w promieniu ~8 m od ciebie lekko się rozjaśnia — dalej nadal ciemno.
- [ ] Parry / stagger Oni: czytelne, bez zmiany chwytu katany.
- [ ] Błyskawica: widoczna za wielkim torii, nie tylko flash światła.

## Audio (punkt 10+)

- [ ] Swing katany: pitch rośnie z prędkością, bez metalicznego „zippera”.
- [ ] Kill: krótki stinger firework + soul collect; level-up chime po slice ofudy.
- [ ] Las: słychać wiatr / ambience, nie zagłusza SFX walki.
- [ ] Slow-mo (level-up / parry): lekki low-pass na ambience, bez wyciszenia całej sceny.

## Komfort VR

- [ ] Chwyt katany stabilny (brak dryfu dłoni > ~15 cm).
- [ ] Brak nausea przy level-up slow-mo i magnet orbs.
- [ ] Boundary platformy — nie wypadasz z dysku.

## Perf HUD (F3 / `--perf-hud`)

- [ ] FPS nie spada poniżej **65** w szczyt fali (krótkie spadki OK).
- [ ] **draw** stabilnie pod budżetem; skok przy level-up akceptowalny.
- [ ] **particles~** nie wisi na stałe > 3000 po walce.

## Po sesji

- [ ] Zanotuj falę / liczbę wrogów przy najgorszym fps.
- [ ] Zrzut ekranu z overlay (lub zapisz wartości z górnego lewego rogu).
- [ ] Jeśli coś padło: issue z tagiem `quest` + ostatni commit SHA.

## Headless (CI — nie zastępuje gogli)

```bash
GODOT=".tools/Godot.app/Contents/MacOS/Godot"
$GODOT --headless --path . --fixed-fps 90 res://tests/quest_perf_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/vfx_pool_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/point12_readability_test.tscn -- --desktop
```

## Zrzuty desktop (porównanie z GDD przed Questem)

```bash
$GODOT --headless --path . --fixed-fps 90 res://tests/point12_screenshots.tscn -- --desktop --shots /tmp/hanabi_point12_shots
```

Sprawdź: `2_beyond_giant_torii_fog` (nic za torii), `3_oni_close_mask`, `4_firework_in_fog`.
