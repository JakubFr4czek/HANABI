# F6 – Stamina

Decision (GDD spirit, Jakub 02.11: "żeby nie mógł cały czas uciekać"): one small component,
`src/player/stamina.gd` (`Stamina`, all tuning constants in one place), stepped by `RunGame`
every physics tick and multiplied into the locomotion speed (with ink boost and shrine buff).

| constant | value |
|---|---|
| MAX | 100 |
| DRAIN_PER_SEC (sprint, stick pushed) | 20 → empty after 5 s |
| SPRINT_SCALE | ×1.5 walking pace |
| EXHAUSTED_SCALE (empty) | ×0.6 until the bar is back at 30 % |
| REGEN_DELAY_SEC / REGEN_PER_SEC | 1 s / 15 per s → full in ~7.7 s |

Input: VR – move-stick click latches the sprint until the stick is let go or the bar empties;
desktop – Shift held. Exhausted = short soft double haptic pulse on both hands (comfort
setting scales it); no breath SFX in the asset packs, no vignette, turning/seated untouched.
Wrist: row STAMINA under CZAS, pale cool bar, amber value + bar when winded.

Shots (game, `tests/point15_wrist_screenshot.tscn`, same camera as F1):
`pre_wrist_hp100_gesture.png` (= docs/f1 post, before F6), `post_wrist_stamina_full.png`,
`post_wrist_stamina_empty.png`. The scene also checks pixels: row in frame, bar luminance
full 0.816 vs empty 0.003.

Weak / todo: label "STAMINA" and the value "100" touch (no gap, like "HP100 / 100" already);
the desktop shot crops the bottom of the plate (DUSZE row). xr_play_test / wrist_hud_test
extended (sprint 5 s → 0 and ×0.6, rest → 100 in ~7.7 s, HUD value) but not run to the end here.
