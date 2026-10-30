# D13 — small details that make the game (status and decisions)

Approved by Jakub on 28 X ("the small details like the logo matter most"). Each point is a separate commit.
Hit-stop is intentionally left out ("think it through once the capacity is known").

## What shipped

| # | Point | Where | Decision |
|---|---|---|---|
| 1 | Katana sound | `src/core/sfx.gd`, `src/weapons/held_weapon.gd`, `tools/gen_d13_audio.py` | Steel whisper on the first grip (`grab`, procedural). Blade-tip whoosh: `HeldWeapon.whoosh_level` (silent below 7 m/s, then pitch and volume rise with speed, cap 1.0); 0.35 s cooldown; `CATEGORY_VOICE_LIMIT` = 2 voices. |
| 2 | Hit haptics per element | `held_weapon.gd` (`SCHOOL_HAPTIC_TAIL`, `KIRISUTE_HAPTICS`) | Neutral blows keep the existing force-scaled pattern. Each school adds a signature after the blow: sakura flutter, storm crackle, ink rumble, shadow double tap. Kirisute gets one long clean pull. Strength follows the ACCESS slider through `pulse()`. A block is the existing clash and parry pattern. |
| 3 | Ink trace on the blade | `src/shaders/katana_steel.gdshader` (`trace_level`), `src/weapons/blade_body.gd` (`mark_trace`) | A landed cut marks the cutting edge for 3 s, eases out. Colour is the school colour; plain steel gets ink blue. A thin stripe on the edge only. |
| 4 | Gloves and tsuka-ito | `src/player/xr_player.gd` (`glove_material`, `_dress_hands`), `katana_steel.gdshader` (`ito_zone`) | Hands wear dark indigo gloves (the XR Tools hand shape, new material; no glove asset in the pack). The grip has a diamond silk-cord lattice in the shader (handle y -0.30..-0.01, radius < 0.026). |
| 5 | Death screen | `src/core/time_controller.gd` (`death_fall`), `src/run/run_game.gd` | No `time_scale = 0`. The world sinks to 0.12 over 1.2 s and holds there. Music and ambience duck and low-pass (Sfx pause ducking). The title is one kanji 散 with "chiru". The stats are quieter. Restart is unchanged. |
| 6 | Forest ambience | `src/run/run_forest_ambience.gd` | Wind (existing loop) plus one spatial cricket emitter (crickets loop), and a far temple bell from a random direction every 40–90 s (`bonsho` cue, 70 m away). Silent under the splash and after death (`set_active`). |
| 7 | Quest icon and boot splash | `export_presets.cfg` (`launcher_icons/*`), `assets/icons/`, `assets/splash/hanabi_boot.png` | Launcher and adaptive icon (black, fireworks and wordmark). Boot splash is now the full logo art on black. The old splash was too dim to read. |

## Voice budget (Quest, ≤ 28)

Sfx pool 23 (was 24) + music 2 + rain 1 + forest wind 1 + cricket 1 = **28**.
`tests/audio_sfx_test.gd` checks both the design sum and the real count of playing voices under combat load.

## Tests (critical points only, all headless except the screenshots)

- `audio_sfx_test`: grab category loads; whoosh silent below threshold and capped at 1; whoosh voices capped at 2; forest bed plays exactly its 2 voices and is silent under a splash; real voices ≤ 28.
- `run_loop_test`: after death `time_scale` never reaches 0 and sinks to 0.12; Sfx ducking starts.
- `blade_feel_test`: a cut marks the blade, the trace is still strong at 1 s and gone by 3.5 s.
- `boot_splash_xr_test`: both XR hands use the glove material (checked on the XR rig).

## Screenshots

`docs/d13/` (windowed, from the real `run.tscn` via `tests/d13_details_screenshots.tscn`):
- `1_blade_trace_storm_grip.png` — storm imbue, fresh trace, indigo lattice on the grip.
- `2_blade_trace_fading.png` — trace 1.2 s from gone.
- `3_death_screen_chiru.png` — the end screen.
- `4_app_icon_512.png` — launcher icon.

## Honest critique (what is still weak)

- **Gloves are not seen in a screenshot.** The desktop rig draws no hands. The material is verified in the XR rig test only. A headset check is still needed.
- **The storm imbue sparks are blocky** (rectangular cells from `spark` in `katana_steel.gdshader`). This is the E3 design, not D13. They read as glitches on the blade in close-up. Next step: round or softer arcs.
- **Rain beads on the blade are square-ish** at close range (existing, `katana_steel.gdshader`).
- **The trace is subtle.** Against a bright storm imbue it is barely visible. It reads better on plain steel or a dim imbue.
- **Death screen stats are small** on purpose (discreet), so they are hard to read from a distance in VR. Check in the headset.
- **Sounds are procedural**, not recorded. A real saya draw and a real cicada recording would be more convincing. No CC0 recording was added, to keep the change small.
- **No `hit-stop`** (per Jakub).
