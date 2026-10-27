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

## 8. Quest pools, forest GI look, on-device profiling
- Pool soul orbs, spark bursts and elemental death rings (`VfxPool` autoload) so
  waves do not allocate VFX nodes mid-fight.
- Procedural forest chunks do not bake LightmapGI (recycling, no UV2); use shader
  cavity AO / wet-surface fill for a convincing static look on Quest.
- Toggleable perf overlay (`--perf-hud`, F3) and `docs/QUEST_TEST.md` morning
  checklist for headset validation.
