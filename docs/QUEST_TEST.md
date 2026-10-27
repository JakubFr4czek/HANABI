# Quest 3 — checklist poranna (Jakub)

Krótka lista do przejścia na goglach przed hackathonem. Profilowanie: uruchom run z `--perf-hud` albo w trakcie gry naciśnij **F3** (desktop / link z klawiaturą).

## Przed startem

- [ ] Build z `main`, urządzenie w Developer Mode, kabel lub Air Link stabilny.
- [ ] Włącz overlay: `godot` export / APK z tym samym co CI, albo editor deploy z `--perf-hud`.
- [ ] Cel: **≥72 fps** średnio w fali 8+ yōkai, draw calls **≤345**, particles **≤4000** (wartości z `quest_perf_test`).

## Run — pierwsze 3 minuty

- [ ] Intro seiza: płynne zejście, katana po touchdown, skip (jeśli jest) nie psuje runu.
- [ ] Diegetyczny HUD (tsuba + nadgarstek): czytelny, bez migotania bloomu.
- [ ] Las w fogu: chunki bez „pop-in” klocków; drzewa/torii czytelne w promieniu ~12 m.
- [ ] Hitodama: po killu lecą, spiralnie wciągane; zbieranie bez lag spike’a.
- [ ] Level-up ofuda: slow-mo, slice, wybór upgrade’u — bez freezu.

## Walka i VFX

- [ ] Trafienia: iskry czytelne, nie biały szum.
- [ ] Śmierć yōkai: krótki „firework” w kolorze żywiołu (nie confetti).
- [ ] Elita: halo w kolorze żywiołu odróżnia od swarmu.
- [ ] Oni boss: groźna sylwetka (nie drewniany manekin), parry/stagger czytelne.
- [ ] Błyskawica: widoczna za wielkim torii, nie tylko flash światła.

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
- [ ] Zrzut ekru z overlay (lub zapisz wartości z górnego lewego rogu).
- [ ] Jeśli coś padło: issue z tagiem `quest` + ostatni commit SHA.

## Headless (CI — nie zastępuje gogli)

```bash
GODOT=".tools/Godot.app/Contents/MacOS/Godot"
$GODOT --headless --path . --fixed-fps 90 res://tests/quest_perf_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/vfx_pool_test.tscn -- --desktop
```
