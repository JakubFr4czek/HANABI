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

Ocena (surowo): boss stoi w kadrze na ścieżce, maska i dymek czytelne; ciało nadal ciemne (drewniane
bryły) i z 5 m czyta się głównie jako sylwetka, rim jest subtelny. Na zrzucie środek ciała zasłania
plansza sterowania (overlay sceny testowej, nie wejścia). Brak zrzutu PRZED z tej samej kamery (limit czasu).

Testy: back_spawn_test, run_loop_test – pass. oni_boss_ai_test: 3 fail, z czego 2 (Phase 3 windup,
HP→0) padały już przed zmianą (baseline: 5 fail); nowy fail: „retreat” – większy boss cofa się
0,15 m zamiast >0,3 m (te same momenty przy dłuższych kończynach). Do poprawy: moment/masa ×scale.
