# F5 – boss = szermierz z kataną sterowany przez AI

Decyzja (Jakub 02.11): bossem runu jest przeciwnik z sali testowej (`TrainingDummy` + `DuelistBrain`
z `scenes/training_arena.tscn`), nie 2,7-metrowy Oni z kanabō.

- `WaveDirector.boss_katana_duelist = true` (domyślnie): `spawn_oni_boss` stawia `RunOniBoss` z
  `katana_duelist = true` – ludzka sylwetka i ostrze szermierza, maska demona z N3 jako jedyny wyróżnik,
  ostrze w stalowym materiale (bokken z sali ginął w mgle). HP i moment pojawienia jak stary Oni
  (profil demo: ~2:00–2:30, w teście 144,5 s). Nazwa: „Masked Ronin”.
- Sterowanie AI: `OniBossBrain.katana_mode` co 2–5 s pyta `OniAiClient` (`katana_mode`, Meta Model API,
  klucz z Settings). Whitelist taktyk: `aggressive, defensive, feint, flank_left, flank_right, retreat`
  (`OniAiClient.DUELIST_TACTICS`); taktyka trwa 4,5 s, potem wraca `duel`. Bez klucza / błąd →
  fallback `duel` = dotychczasowa logika DuelistBrain, plus kwestia w dymku.
- Stary Oni: kod i testy zostają; testy kanabō ustawiają `boss_katana_duelist = false`.

Testy: `tests/oni_boss_ai_test.gd` → `_test_f5_katana_boss_in_run` (run demo w krokach 0,1 s, atrapa
AI zmienia taktykę flank_left → retreat i jest wykonana, brak klucza → fallback bez czekania, HP→0 =
koniec walki). Wizualny: `tests/f5_katana_boss_shots.tscn` (boss z 4 m w kadrze, katana, maska, dymek).

Zrzuty z gry, ta sama kamera: `before_*` = stary Oni, `after_*` = szermierz.

Słabe (uczciwie): korpus szermierza jest ciemny (drewniane bryły z sali testowej) i w ciemnym
lesie czyta się głównie jako sylwetka; ostrze w gardzie stoi pionowo i z 4 m ma 1–2 px szerokości.
Do zrobienia: lepszy model ciała/zbroi szermierza, delikatny rim light na ostrzu.
