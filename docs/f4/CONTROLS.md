# F4 — Controls: standard Quest mapping + start-of-run hint

Jakub (02.11): "sterowanie jest troche nie intuicyjne (chodzi o przyciski)".
Scope: small, no refactor. The OpenXR action map (`openxr_action_map.tres`) already binds
every physical Quest input to a generic action (`trigger`, `grip`, `ax_button`, `by_button`,
`menu_button`, `primary`, `primary_click`, …) on both hands, so it **did not need changes**;
what changed is what the game does with those actions (`src/player/xr_player.gd`,
`src/run/run_game.gd`) and the table in `src/ui/controls_map.gd` (`ControlsMap.SCHEME`),
which the menu's controls page, the hint and the tests all read.

## Before (up to F3)

| Input (right-dominant) | Action map | What it did in a run |
|---|---|---|
| Left stick | `primary` | walk |
| Right stick | `primary` | turn (snap/smooth per settings) |
| Trigger, katana hand | `trigger` | nothing (menus: pick) |
| Trigger, free hand | `trigger` | spend the oldest Torii charge (D21) |
| Grip | `grip` | grab / drop the katana |
| A / X | `ax_button` | **ability 1** (element throw), skip intro |
| B / Y | `by_button` | ability 2 with katana; grip + B/Y on an empty hand = recall; B/Y hold empty hand = recenter / eye height |
| Left Menu | `menu_button` | tap: menu / skill tree; hold 1 s: recenter |
| Stick click | `primary_click` | nothing in a run (dojo: cycle element) |
| Shrine / bell | — | hand touch only |

## After (F4, standard Quest)

| Input (right-dominant) | Action map | What it does |
|---|---|---|
| Left stick | `primary` | walk |
| Right stick | `primary` | turn (snap/smooth per settings) |
| **Trigger, katana hand** | `trigger` | **element throw (ability 1)** |
| Trigger, free hand | `trigger` | spend the oldest Torii charge (unchanged, D21) |
| Grip | `grip` | grab / drop the katana (unchanged) |
| **A / X** | `ax_button` | **interact**: the shrine altar / bell in reach (same reach rules as touch and desktop E), skip the intro |
| B / Y | `by_button` | element skill (ability 2) with the katana in hand |
| Grip + B/Y | `grip`+`by_button` | recall the katana (unchanged) |
| Left Menu | `menu_button` | tap: menu / skill tree; hold 1 s: recenter |
| **Left stick click** (move stick) | `primary_click` | **sprint** — emits `XRPlayer.sprint_requested`; the sprint itself is F6 |
| Right Meta | — | system (reserved) |

Left-dominant mirrors it: katana, turn stick and trigger-throw on the left hand; walk and
sprint click on the right stick (`ControlsMap.roles_for`, `XRPlayer.set_dominant_hand`).

Decisions:
- **Grip + B recall kept.** No conflict: B/Y fires the element skill only from a hand that
  holds the blade; recall only fires from an empty fist. The empty-hand B/Y hold
  (recenter / eye height) is also untouched.
- **Trigger on the blade hand is new**, on the free hand stays the charge (D21) — one trigger
  per role, the same edge detection, so no double fire.
- **Souls** are still collected by walking through them (no button); A/X only reaches
  shrines and bells. Item pick-up does not exist yet.
- The dojo (test room) keeps its dev mapping for A/X (reset / ability 1); only the run uses F4.
- The action map file is unchanged — all actions were already bound on both hands for the
  Touch profile; the test checks every table row against it.

## Start-of-run hint

`src/ui/controls_hint.gd`: when play begins (after the intro), a small dark plate with two
thin gilt rules and four Latin lines is set once in the world 1.35 m ahead, 0.22 m below the
eyes (world-anchored, not head-locked). It fades out after 6 s, or at once when the player
walks 0.6 m. Shown once per run (`RunGame.controls_hint_shown`). The same scheme is always
on the menu's CONTROLS page.

## Tests
- `tests/xr_input_test.gd` `_check_f4_standard_mapping("right"/"left")`: trigger / grip /
  A / X / B / Menu / stick click → the right signal for both dominant hands; the run-mode A
  check now expects `interact_requested` (replaces "A fires ability 1").
- `tests/vr_menu_pause_test.gd` `_test_controls_scheme_and_hint`: every table row is bound
  on both hands; the drawn map equals the table for both hands; the hint shows once and goes
  (time and walking).
- `tests/f4_controls_shots.tscn` (windowed): pixel check on run.tscn (hint in frame, readable,
  dark plate) + screenshots below.

## Screenshots (from the game, run.tscn, same camera)
- `before_01_run_start.png` / `after_01_run_start_hint.png`
- `after_02_controls_map.png`

## Round 1 fixes (review of b3df9b7)
- **Hint not in the shots**: the capture waited physics frames; on slow xvfb several
  physics frames fall into one rendered frame, so before/after were the same stale image
  (byte-identical, rain included). The shot now waits `RenderingServer.frame_post_draw`.
  The plate also faced away from the eyes (Label3D text would read mirrored in VR) — fixed;
  it is now 1.5 m ahead, drawn like the Oni speech bubble (`no_depth_test`, render
  priority 10–15, no fog) so trees/rain never hide it. Pixel check: 92 % dark plate px,
  5.5 % bright text px in its box (before: 0 %).
- **Controls map overlaps**: callout bodies are one line (short texts in `SCHEME`), rows at a
  74 px pitch, the three rule lines moved up (792/824/856) clear of the footer at 918.
- Open: on the 960×540 desktop shot the hint is small (≈13 % of the frame width); in the
  headset it is ≈21° wide at 1.5 m.
