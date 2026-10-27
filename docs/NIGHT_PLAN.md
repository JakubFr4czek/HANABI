# Night plan (2026-10-27)

Priorities for tonight, in order, following `docs/GDD.md`. Each item is done
only when its headless tests pass, it is committed and pushed to `main`, and it
passed a harsh self-review: screenshots compared with the GDD and the
"premium, never cheap" rule, weak spots listed and fixed. A placeholder is not
a finished item.

Out of scope tonight: everything marked LATE in the GDD (VR comfort &
accessibility, calories), Meta AI features, and bringing the sakura tree back.

## Starting point
- Done: physics katana (PD, hand priority, free / two-handed grip, edge
  alignment, swing power), training dummy duelist (IK guard, parries,
  openings), player HP with hurt feedback, Dojo of the Storm arena (water
  mirror, storm sky, lightning, rain), element colors on the blade trail and
  spawn seal, central event log.
- Missing: the whole run loop, element abilities, the procedural world, yōkai
  and bosses, the run intro, a Quest performance pass.

## 1. Run loop
Spawn at the shrine, fight waves, collect souls, level up, pick an ofuda, die,
see the score, run again (GDD §3, §6, roadmap 2).
- Run scene of its own (`scenes/run.tscn`), separate from the training arena,
  starting on the spawn platform. The arena keeps working as the dummy level.
- Basic yōkai: a cheap active-ragdoll swarm enemy (no sword) that closes in
  and claws; stagger, collapse, dissolve. Light enough for a dozen at once.
- Wave director: spawns in rings outside view in the fog, pressure scales with
  run time (count, speed, health), endless.
- Soul drops (hitodama): glowing orbs, many per kill, drift to the player when
  near, give XP.
- XP and levels with a rising curve; level-up: time slows, three ofuda float
  in front of the player, slicing one with the sword picks it.
- First upgrade pool (generic, element trees come in item 2): damage, max HP,
  heal, soul magnet radius, attack speed of the blade (arm strength), regen.
- Diegetic HUD: XP ring on the tsuba / wrist, HP as a glowing charm, time and
  score on the wrist. No floating screen-space UI.
- Death ends the run: end screen in the world (score, time, kills, level,
  upgrades taken, high score), high score saved locally, restart by cutting.
- Desktop rig can play it all (keys for testing), headless tests for waves,
  drops, XP, level-up choice by cut, death and high score.

## 2. Elements: Sakura, Storm, Ink, Shadow
Upgrade trees, slot limit (2 elements, ~6 slots), evolutions (GDD §5).
- Element upgrades in the ofuda pool once item 1 exists; picking the first
  upgrade of an element binds it to the blade (trail, on-hit effect).
- Sakura: cutting petals on swing, orbiting petal blades, light healing.
- Storm: chain lightning between enemies, charged strike.
- Ink: slowing ink pools painted by the blade, ink tendrils.
- Shadow: short blink, darkness that confuses enemies.
- Two evolutions from the GDD: Storm + Ink = black lightning, Sakura + Shadow
  = phantom petals.
- Spawn seal parts light up as elements are taken.

## 3. World: endless forest illusion
Hills, trees and torii in fog around the run (GDD §9).
- Chunked terrain around the player from `FastNoiseLite` (rolling hills),
  recycled as the player moves so it never ends; the shrine platform sits in a
  clearing.
- Torii of many sizes, including Senbon-style corridors, trees, stone lanterns
  and rocks scattered by noise; the fog hides chunk edges.
- Cheap on Quest: shared meshes / MultiMesh, fog instead of draw distance.

## 4. Enemy variants and AI
- Elite yōkai with element resistances / weaknesses, needing a parry or a
  specific element.
- Oni boss on a timer: heavy, parryable combos, reusing the duelist brain.
- NavigationAgent3D (or simple steering around props) for the swarm.

## 5. Run intro: levitation in seiza
GDD §9 "Run intro": hover above the seal, slow linear descent, petals swirl,
lightning ripple across the floor on touchdown, katana materializes; skippable.

## 6. Quest 3 performance (72+ fps)
- Profile the run with many enemies: physics bodies per enemy, particle
  budget (2–4k), draw calls, shader cost on Compatibility.
- Pooling for enemies, orbs and VFX; LODs; cheaper ragdolls at distance.

## 7. VFX polish
- Hits, deaths ("firework" bursts per element), level-up ofuda, souls; checked
  against the premium rule (sparse neon on a dark base, restrained bloom).

## 10. Kill-feel audio + VfxPool allocation guard
- Spatial Sfx pool (swing pitch from speed, yokai/firework/soul/ofuda/level-up),
  forest wind bed, flash-synced thunder crack, slow-mo ambience low-pass; hard-capped
  VfxPool with zero-growth test after warmup.

## 9. Premium reads in fog + real forest meshes
- Oni mask/armor/rim and elite halo readable in run fog; CC0 forest tree/torii
  meshes in MultiMesh within Quest budgets; capture death firework + hitodama shots;
  stabilize flaky `grip_stability_test` without changing grip logic.

## 11. GDD loop audit (§3, §4, §5, §6, §9)
Close gaps vs `docs/GDD.md` for the survivor loop (skip LLM, comfort, calories,
sakura trees; do not touch grip/hand logic).
- End run in-world: score, time, kills, **element build**, upgrades, local high
  score, Restart Ofuda slice → `run_game.gd`, `run_loop_test.gd`.
- Diegetic HUD: tsuba XP, wrist HP charm, **score (pt) + kills (斬) + time**;
  brief tsuba flare on parry.
- Spawn seal 桜雷墨影 on stone platform; quadrants + evolution star via
  `set_seal_progress` — `gdd_loop_test.gd`, `elements_test.gd`.
- Two elements / six upgrade slots, Storm+Ink and Sakura+Shadow evolutions —
  `element_system.gd`, `upgrade_pool.gd`, `elements_test.gd`.
- Parry slow-mo + counter window on duelists (dummy / Oni) — `combat_test.gd`,
  `held_weapon.gd`; elite yōkai respect `counter` hits in `yokai.gd`.
- Headless: `gdd_loop_test.tscn`; visual: `run_screenshots.gd` shot 7.

## 21. Premium Oni silhouette + yōkai secondary motion
- Oni: hide ragdoll primitives; procedural body shell + kanabō visual (wet PBR).
- Yōkai: torso lag overlay + recover pose after attacks.
- Desktop fog shots 2 m / 6 m; full test suite.

## 19. Oni/yōkai combat closure (shots, mask sculpt, pose blend)
- Desktop shots: Oni ~2 m / ~6 m in wave fog, yōkai approach + flinch (`point19_combat_screenshots`).
- Oni mask sculpt v2 (~1k verts, sockets/kły/brwi, normal map).
- Smoother yōkai pose blends on ActiveRagdoll; QUEST_TEST morning §19.

## 18. Combat CC0 SFX, music loop/duck, Quest perf (lights/audio)
- Kenney/OGA recordings for cut/slap/hurt/tell; swing/clash already CC0; CREDITS/LICENSES.
- `StormMusic` crossfade loop + level-up duck; forest wind on Ambience bus.
- Oni rim cull, Sfx voice soft-cap, stressed `quest_perf_test` flash lights; `QUEST_TEST.md` §18.

## 17. Sculpted Oni mask, torii fog shot, §15 polish closure
- Procedural sculpted mask + normal map (`gen_oni_mask_glb.py`) or document no external CC0 found.
- Giant torii silhouette in fog (`point12_screenshots` shot 2).
- Wrist contrast + critical HP test; Yuji Boku stele; extra CC0/Kenney thunder layers.

## 16. Oni mask audit, yōkai motion, Quest perf pass
- Oni mask: verified project CC0 (`ONI_MASK_LICENSE.txt`, regenerated mesh).
- Yōkai: approach / flinch poses blended with ActiveRagdoll (`yokai_combat_motion_test`).
- Quest: perf probe lights/audio + `QUEST_TEST.md` morning checklist §9–§15.

## 15. Polish after point 13 (premium HUD, stele, CC0 audio)
- Wrist HUD: billboard readout, HP ring only when critical, shrine palette (`diegetic_hud.gd`).
- Memorial stele: larger VR type, shorter 拾得 upgrade line (`run_game.gd`).
- CC0 rain/thunder/steel clashes + subdued Music loop (`cc0_storm/`, `cc0_run/orientalsomber.ogg`).

## 14. Close gaps from points 12–13
- Oni: dedicated mid-poly mask mesh + PBR (`oni_mask_run.glb`, `run_oni_boss.gd`).
- Firework death VFX: cap dynamic flash lights (`VfxPool.MAX_FIREWORK_FLASH_LIGHTS`).
- Fog past giant torii: tighter env fog + forest view range / ground discard (`point14_fog_torii_test`).

## 8. Quest pools, forest GI look, on-device profiling
- Pool soul orbs, spark bursts and elemental death rings (`VfxPool` autoload) so
  waves do not allocate VFX nodes mid-fight.
- Procedural forest chunks do not bake LightmapGI (recycling, no UV2); use shader
  cavity AO / wet-surface fill for a convincing static look on Quest.
- Toggleable perf overlay (`--perf-hud`, F3) and `docs/QUEST_TEST.md` morning
  checklist for headset validation.
