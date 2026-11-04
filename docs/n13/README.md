# N13 – wejście Oni (boss z kataną) pod filmik

Decyzje (4.11, supervisor): zmieniony tylko boss i moment jego wejścia, las/światło/sakura bez zmian.

- **Kiedy:** profil demo (`-- --demo`, `data/waves/demo.tres`) `oni_first_seconds` 120 → **60 s**;
  boss pojawia się na pierwszym szczycie po 60 s (test: 66–87 s). Profil domyślny zostaje (180 s) –
  zmiana psuła balans hardcore vs default. **Do nagrania filmiku uruchamiaj grę z `-- --demo`.**
- **Gdzie:** `WaveDirector.spawn_oni_boss` z kierunkiem widoku stawia bossa **przed graczem**
  (±22° od widoku, 6–7,5 m, poza pniami); bez wolnego miejsca – stary pierścień 9,2 m.
- **Większy:** `TrainingDummy.body_scale` = 1,15 dla bossa (≈2,05 m): części, hitboxy, stawy i chwyt
  rosną razem (masy/momenty/ostrze bez zmian). Maska skalowana razem z głową.
- **Rim:** żarowy fresnel (`rim_tint`) tylko na materiale drewna bossa, mocniejszy z bliska. Zero nowych świateł.
- **Wejście:** 1,8 s stoi w gardzie, patrzy na gracza, dymek „Koniec twojej drogi!”, dzwon `bonsho_oni`
  (istniejący). Cios gracza lub pierwsza decyzja AI kończą wejście. Kamera gracza nieruszana.

Zrzut z gry (run.tscn, 5 m): `after_boss_5m.png`, `after_ai_bubble_5m.png`
(`tests/f5_katana_boss_shots.tscn -- --shots docs/n13 --tag after --distance 5`).

## fix1 (review 68b826c)

- **Rim/fill tylko na materiale bossa:** `rim_tint` (1,0; 0,5; 0,24), `rim_power` 1,3, `fog_rim` 1,6,
  `fill` 2,8 (szermierz z sali: 1,6). Oświetlenie sceny i lasu bez zmian.
- **Plansza sterowania:** w grze żyje tylko 6 s od startu runu (lub do 0,6 m ruchu), a boss wchodzi
  najwcześniej po ~60 s, więc **w prawdziwej grze nie zasłania wejścia**. Zasłaniała tylko w scenie
  zrzutów (run startuje tuż przed spawnem) – tam jest teraz wyłączona (`controls_hint_shown = true`).
- **Ruch większego ciała:** momenty stawów ×k² (`scale_part_defs`), promienie `_blocked_toward` ×k.

Ocena (surowo): z 5 m boss stoi na ścieżce, cały w kadrze. Żarowy rim obrysowuje ramiona, nogi
i bark, więc sylwetka wyraźnie odcina się od lasu, a maska i dymek są czytelne. Słabe: przód torsu
dalej jest ciemną bryłą (drewniane kloce z sali testowej), a rim w kolorze żaru wygląda trochę
„neonowo” na krawędziach nóg. To czytelne, ale nie premium. Lepszy model ciała/zbroi to osobne zadanie.
Brak zrzutu PRZED z tej samej kamery.

Testy (fix1): back_spawn_test – pass. oni_boss_ai_test – nadal **FAIL „retreat”**: boss cofa się
o 0,17 m w 1 s (próg >0,3 m, nie osłabiony). Log: `move_velocity` dochodzi do ~1 m/s wstecz po
0,5 s, ale ciało nie nadąża za kotwicą. Momenty ×k² i `anchor_gain` ×k² (cofnięte) nic nie dały,
więc przyczyna leży gdzie indziej (stopy/tarcie lub balans przy wyższym pelvisie) – do dalszej
diagnozy. Stare faile: HP→0 (był przed N13), Phase 3 windup i „requests every 2–5 s”
są niestabilne (przechodzą/padają między przebiegami; baseline przed N13: 5 faili).

## fix2 (review bdf3e5a)

- `DUELIST_BODY_SCALE` 1,15 → **1,08** (≈1,93 m; test wzrostu 1,85–2,3 m przechodzi). Momenty ×k² zostają.
- Rim przygaszony: `rim_tint` (0,86; 0,42; 0,21), `rim_power` 1,6 (węższa, mniej „neonowa” krawędź).
  Na nowym `after_boss_5m.png` tors i kończyny dalej odcinają się od lasu. Przód torsu jest ciemny.
- **Retreat nadal FAIL** (cofa się o 0,14 m, próg >0,3 m, nie osłabiony). Bisekcja (oni_boss_ai_test, po 1 przebiegu):
  skala 1,08 → 0,14 m; **skala 1,0** → 0,14 m; demo 120 s zamiast 60 s → 0,14 m; **bez wejścia (intro)** → 0,21 m.
  Żadna z tych zmian osobno nie przywraca progu, więc skala nie jest przyczyną. Baseline sprzed N13 przeszedł ten
  check w jednym przebiegu. Nie sprawdziłem jeszcze: kombinacji zmian, wpływu frontowego spawnu w symulacji dema
  i niestabilności samego checku (kilka przebiegów baseline).
- Stare faile: HP→0 (był przed N13). Phase 3 windup i „requests every 2–5 s” są niestabilne, padają w części przebiegów.
