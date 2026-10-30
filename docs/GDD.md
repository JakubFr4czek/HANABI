# HANABI (花火) — Game Design Document

> Living reference for the project. Keep this file in the repo at `docs/GDD.md`; every implementation decision should follow it. Update it when a design decision changes.

## 1. Vision
**HANABI** is a VR melee survivor-like: Blade & Sorcery–style physics swordplay meets the Survivor.io loop, set in a dark, foggy, procedurally generated Japan full of torii gates. Every kill is a small "firework" of neon petals, lightning and ink, hence the name *hanabi* (fireworks).

- **Platform:** Meta Quest (standalone, OpenXR), plus PCVR for demo recording.
- **Engine:** Godot 4, GDScript.
- **Context:** Meta Global AI Developer Hackathon (submission due Nov 4, 2026, 9:00 PM ET). Indie developer track.
- **Tone:** dark action with neon beauty. It is not a horror game: atmosphere is moody, but the core feeling is satisfying, powerful combat.
- **Lore (D18, decided 2026-10-29):** the run takes place during a summer matsuri, the village festival at the edge of the forest. The fireworks are seen above the trees and heard as far-off thunder. In the middle of the festival the yōkai wake: the music stops, the lanterns go out, and the dead come out of the fog. The fireworks are atmosphere, not a reward: the player hears them beyond the mist while something he cannot reach hunts him. The name works twice, since the matsuri fireworks are real and every kill is a small firework of petals, lightning and ink.

## 2. Design pillars
1. **The sword feels real.** Physics-driven blade, weight, no clipping, real parries.
2. **One more run.** Constant drops, frequent level-ups and meaningful build choices.
3. **Neon in the dark.** Black fog and red torii, lit by pink sakura, blue lightning and black ink.
   Distant matsuri fireworks (D18) add tension: far bursts behind the mist, muffled and random, that the player can never reach.
4. **The world is watching you.** Rare AI-"awakened" enemies that comment on and adapt to your playstyle (Meta AI, later phase).

## 3. Core loop
Spawn at the opening ritual, then fight waves. Enemies drop soul orbs that give XP; every level gives one skill point (D12). Walk out to find hokora shrines in the forest, place a hand on the offering to light a choice of three yellow Ofuda, and slice one for a timed buff (speed, damage or healing). Spend skill points on the skill tree, fight stronger waves and bosses, die, see your score, and start a new run to beat your high score. Skill points are the only currency for power; a shrine buff lasts a minute and is never a permanent upgrade (D12).

- Runs are endless; difficulty scales with time.
- Death ends the run; the high score is saved locally.
- Target run length for the demo is about 5–10 minutes.

## 4. Combat and physics
- **Katana:** a `RigidBody3D` pulled toward the controller pose by a PD controller (force and torque). It is not parented to the hand.
- **Weight:** mass and inertia make heavier weapons lag behind the hand.
- **No clipping:** the blade stops on walls while the hand continues (the hand model stays on the hilt). Use continuous collision detection on the blade.
- **Hand priority:** the weapon never visibly leaves the hand (grip within a few cm, a limited wrist twist that sells a heavy weapon's weight). On enemy bodies the blade collides and rests briefly; if the hand keeps going deep, the blade follows it through instead of wedging.
- **Grip:** a handle grip always seats the sword the natural way (cutting edge leading a cut), whatever angle the hand came in at.
- **Edge alignment:** the angle between the motion and the blade's edge decides the strike: edge or point ×1.0, flat ×0.3, blunt spine ×0.2, hilt ×0.3, each with its own sound and spark.
- **Damage:** scales with blade velocity at impact. Light swings make shallow cuts; full swings make heavy hits.
- **Parry:** emerges from blade-vs-blade physics. A clash with the right velocity and angle counts as a parry and triggers a short slow-mo and a counter window.
- **Feedback:** hit-stop (50–80 ms) on strong hits, haptics scaled by impact, and a blade trail colored by the active element.
- **Enemies:** active ragdolls (animation drives the body through forces). They stagger, react to hits and collapse.

## 5. Elements
There are four elements. Each grants 2 active abilities mapped to the two face buttons (A/B on the sword hand), alters the blade (trail, emissive aura), and has a dedicated 5-node upgrade tree bought with skill points (D12). Full technical specification is in [`docs/ELEMENTS_PLAN.md`](ELEMENTS_PLAN.md).

| Element | Color | Fantasy | Active Ability 1 (Button A) | Active Ability 2 (Button B) |
|---|---|---|---|---|
| **Sakura** 桜 | neon pink | beauty that cuts | **Senbonzakura** (razor fan of 6 cutting glass petals) | **Hanamai** (orbiting 4-petal barrier; cuts enemies & reduces damage) |
| **Storm** 雷 | electric blue | speed and chain damage | **Raikiri** (focused strike releasing 4-target chain lightning) | **Shiden** (instant forward dash & shockwave stagger) |
| **Ink** 墨 | glossy black | control | **Sumi-gaeshi** (ground ink sweep; 60% slow & continuous damage) | **Kage-nawa** (binding tendrils rooting 3 enemies & pulling to ma-ai) |
| **Shadow** 影 | dark violet | trickery | **Kagemusha** (smoke decoy clone redirecting enemy aggro) | **Yami-watari** (shadow step behind target with +60% critical strike) |

- **Single Element Imbue (~20 s Duration):** The katana holds at most ONE element at a time, imbued by walking the player body through an elemental Torii gate in the endless forest.
- **Counter ring (D17, decided 2026-10-30, [`docs/ELEMENT_COUNTERS.md`](ELEMENT_COUNTERS.md)):** the four schools form a ring. Each one beats exactly one and is beaten by exactly one: **Ink gasi Storm** (ink grounds the lightning), **Storm rozwiewa Sakura** (the storm scatters the petals), **Sakura przebija Shadow** (petal light burns out what hides in the dark), **Shadow omija Ink** (the shadow walks through ink traps). A counter hit deals **×1.5**, the same school **×0.5**, every other pair and plain steel **×1.0**. Plain steel is always the baseline. Yōkai do not hit harder for a counter: the ring only works for the blade and the abilities, never against the player. The table lives in `ElementBalance`; the enemy multiplier is zone × ring × resistance, in that order.
- **Counter feedback (D17):** a counter hit holds the world a little longer (+0.02 s), adds a second beat in the hand, flashes the body in the school's accent and throws sparks in its eye light. The same school gives a dull clink and few sparks. No numbers appear on screen.
- **Pacing & Gate Density:** Gates spawn within **18–32 m** of the player (mean ~24 m). Given realistic VR combat traversal speed (~1.4 m/s), traversal takes ~12–17 s, ensuring an elemental uptime of **65%–75%** of active run time. Verified via automated metric `element_uptime_ratio >= 0.65`.
- **Deterministic Gate Reactivation:** A passed gate deactivates instantly and reactivates if and only if the player moves **>= 45.0 m** away from its center.
- **Dynamic Re-Imbue & Refresh:** Passing a Torii gate of a different element immediately replaces the element and resets the 20s timer. Passing a gate of the same element refreshes the timer back to 20s. The final 3s pulse an expiration warning before reverting to plain steel.
- **Sword Hand Controls & Empty Steel:** Buttons A and B activate Ability 1 and 2. On plain steel, pressing A or B produces a quiet, muted haptic click with zero popups or error banners. Katana recall (`Grip + B`) only triggers when the hand is empty (`held == null`), preventing any conflict with Ability 2.
- **Finisher, the cut like butter (D4, decided 2026-10-28):** the tier-5 node of each tree adds a passive cut during the imbue: Hanadachi (Sakura), Raidachi (Storm), Sumidachi (Ink), Kagedachi (Shadow). A clean, fast edge cut splits a yōkai along the plane of the blade (normal = motion × blade axis) into two pieces that land where they were cut and dissolve into petals. Elites split only when the cut kills them; the Oni takes a glowing wound instead. Details and numbers: [`docs/ELEMENTS_PLAN.md`](ELEMENTS_PLAN.md), section D4.
- **Anti-Clipping UI Guarantee:** All UI panels and wrist HUD elements use depth-test-disabled materials (`flags_no_depth_test = true`, render priority 100) and adaptive forward raycasting to guarantee panels never clip through trees, rocks, or walls.

## 6. Progression and UI
- **Drops:**
  - **Hitodama (Soul Orbs):** Grant XP and score. Yōkai 24 XP, elites 48 XP, the Oni 64 XP (D12).
  - **Hokora (shrine):** a rare roadside shrine in the forest (about one per 216 m of walking). It is not a drop: a shrine is lit until used. Place a hand on its offering table to open the choice (D12).
- **Level-up:** every level gives **one skill point** (点) and a small heal. The XP threshold grows linearly (60 + 40 per level, D10: early levels come sooner because the calm opening spawns fewer yōkai). The level-up has haptics and a brief flash on the wrist; no card choice, no slow motion, no time scale.
- **Ofuda (御札), the yellow choice card:** the shrine offers three yellow talismans in front of the player. Slice one with the katana and it grants a buff. Speed +20 % for 60 s, damage +20 % for 60 s, or healing (35 % of max HP now, then 15 % over 10 s). Buffs of one kind refresh and do not stack, and max HP never grows. Opening it pauses the world exactly like the menu.
- **VR Skill Tree Menu (No Card Slicing for Power):** Progression is spent in the 3D VR Skill Tree Menu, opened with the off-hand Menu button. With no points the menu says where they come from. Opening the menu cleanly pauses game time (`get_tree().paused = true`, `process_mode = PROCESS_MODE_ALWAYS` for XR tracking/hands/UI), allowing deliberate spending of points on 4 per-element trees (5 nodes each with prerequisites, costs 1/1/1/2/3). Progress resets on death.
- **HUD (D14):** Minimal and diegetic with transparent background (no card/panel). A smooth anti-aliased HP ring (teal at 100% -> amber at 50% -> red with gentle pulse below 25%), an animated fire shader with a white calorie counter (kcal) inside the ring, a hairline outer arc for the active element timer, ability status glyphs, and engraved stats (rank, kills, score, XP, skill points, wave, active buffs). Shown ONLY when raising the wrist to the face (<0.35 m, <45° angle to eyes, within frustum; 0.15 s smooth fade, zero draw calls when lowered; H key on desktop). Zero clipping with hands, katana or environment.
- **End screen:** score, time survived, kills, level, build used, shrines visited and high score. The run-over plaque that restarts the run is a wooden **Restart Ema (絵馬)**, not a card, so it never reads as currency.

## 7. Enemies
- **Basic yōkai:** swarm enemies, weak and numerous.
- **Schools on the swarm (D17):** a swarm yōkai carries a school with a per-wave weight (`WaveProfile`, the "Fale" dock, group "Elements"): the plain share falls from 70 % at the calm start to 35 % at the ramp end, the rest is split by four weights (equal by default). The school shows as the light in the eyes and on the mask sigil, so a player reads it from about 8 m. The Oni has no school in D17 (see `docs/ELEMENT_COUNTERS.md`, decision 6).
- **Elite enemies:** have an element and a weakness (the school that beats them on the ring) and require parries or specific elements. Their element resistances are the ring plus plain-steel resistance (D17).
  - *Elite look (decided 2026-10-28):* no ring, halo or overlay drawn around the body (the old ring showed through trees and bodies and read as a UI marker). The element lives in the body instead: glowing eyes, the sigil on the mask, the sash and the claws in the element colour (saturated so the eye bloom does not wash them out to white), and a faint element tint in the skin. An elite adds no meshes over a swarm body, so it costs no extra draw calls.
- **Oni boss:** appears periodically; heavy attacks, parryable combos.
- Local AI uses NavigationAgent3D and a state machine (FSM), with tactics and resistances defined as data and a swappable "brain" component (prepared for the AI phase).
- **Duelist behavior (implemented on the training dummy, reused by elites and the Oni):** states idle → stalk → attack (wind-up → strike) → block / stagger → recover. Between attacks the sword arm is steered continuously by real-time IK (no pose snapping): the point stays on the player's throat and leans toward their blade. It sees the player's blade with a reaction delay and reads the wind-up: a sword lifted or drawn back to a side makes the guard cover that line (high, side, or low with the point down) before the cut comes; a cut on its way is met by laying the blade across its path, or it steps out of reach. A light cut into the guard is deflected (enemy parry) and answered with a riposte; a committed full-arm cut beats the guard aside and staggers it. It attacks into openings (after a missed swing, a blade held high / low / wide, the player stepping in without a cut ready, or when its patience runs out), winds up on planted feet and covers the gap with one decisive step, then steps back to ma-ai (zanshin). Footwork keeps ma-ai smoothly (follows a retreating player, gives ground to one rushing in, drifts slowly around them). Attacks: vertical cut, horizontal cut, thrust; combos, feints, varied tempo with occasional hesitation. A parry staggers it; a heavy hit during its wind-up interrupts it.
- **Fairness rules (VR):** every strike shows at least 0.4 s of wind-up inside the player's view (±40° from where they look) with three tells (pose, glowing eyes, rising whoosh); a wind-up is dropped if the player looks away for 0.8 s; circling drifts back into view instead of flanking.
- **Difficulty** is a data resource (wind-up and recovery scale, cooldowns, combo / feint / block / evade / riposte / hesitate chance, reaction time, wind-up reading (anticipation), arm speed, guard strength, interrupt poise, damage scale, move speed, stagger time) with easy / normal / hard presets. It never makes the enemy faster than the fairness rules allow.
- **Swing power:** a hit carries momentum: the weapon's effective mass at the contact point plus the arm behind it, which only counts for a committed swing (the hand travels with the arm, not a wrist flick). Damage scales from 25 % (flick) to 100 % (full arm) on top of the speed curve; the impulse knocks the enemy off balance and can beat its guard aside; heavier weapons hit harder.
- **Player HP:** 100, 0.6 s invulnerability after a hit; feedback is a red edge vignette, a heavy haptic pattern in both hands and a hurt sound. At 0 HP the player is down for 3 s, then revives at full health (run-over screen comes with the loop, milestone 2).

## 8. Meta AI features (LATER PHASE)
Do not implement during prototyping. Prepare the architecture: swappable enemy brain, data-driven tactics, and one central gameplay event log.

- **Telemetry:** slash directions, favorite element, parry rate, aggression vs retreat, time alive and upgrade picks.
- **Awakened enemies:** every 2–3 minutes one enemy "awakens" (glowing eyes, stops, turns to the player). An LLM (Meta Muse Spark via Meta Model API) receives telemetry and returns JSON with a short spoken line about the player's style (e.g. "You always cut from the right... like always.") plus a tactic it then actually uses. Keep it rare and short so it stays unsettling.
- **Oni tactical brain:** every 2–5 s or on events, the LLM returns a high-level plan (formation, targeted weakness, ability). Local AI executes it every frame; the LLM never drives per-frame movement.
- **Cross-run memory:** a short summary of previous runs lets awakened enemies reference them ("Last time you died near the eastern torii. I remember.").
- **Fourth-wall comments (optional):** play time, high score, unused elements.
- **Demo overlay (optional):** shows the boss's "thoughts" for the demo video.
- **Implementation:** all calls go through `call_llm(prompt, schema) -> Dictionary`, async via `HTTPRequest`, with swappable backends (Meta Model API; temporary Claude/Gemini for development). Keys come from config/env. The game never blocks on the network and has fallbacks.
- **Voice:** the LLM writes the lines; TTS is an optional separate module (e.g. local Piper).
- **Possible extra Meta usage:** Muse Image for ofuda art, textures and the spawn symbol.

## 9. World and art direction
- **Setting:** an endless night in a mythical Japan. Fog, darkness, cold light.
- **World Gen (D8, decided 2026-10-28):** every forest number lives in one `WorldGenProfile` (`data/worldgen/*.tres`), edited in the `World Gen` dock and the preview scene; the game reads the profile named in `project.godot`. Paths, Poisson-disk placement and the dusk palette are part of it. Guide, budgets and the honest review: [`docs/WORLDGEN_TOOL.md`](WORLDGEN_TOOL.md).
- **Procedural world:** an endless dark forest under fog, generated with `FastNoiseLite` (rolling hills, dense trees, stone lanterns, rocks) and walkable in every direction. Every so often the forest holds a full-size red torii (now and then a short Senbon-style row of them), met unexpectedly in the fog; they are part of the generated world and stay where they are (decided 2026-10-27).
- **Palette:** near-black and deep blue-grey, red torii, with emissive neon accents: pink sakura, electric blue lightning, glossy black ink.
- **Spawn point:** a small glade in the forest itself, with no platform or circle on the ground (decided 2026-10-27). The four-part 桜 雷 墨 影 seal stays in the Dojo of the Storm; in a run the build shows on the blade trail and wrist HUD.
- **VFX:** GPU particles for petals, procedural lightning, an ink/darkness shader with noise, and blade trails (GPUTrail).
- **Performance:** on standalone Quest use simple fog and particles. Volumetric fog is a PCVR-only setting for recording.

### Art direction rule: premium, never cheap/kitschy
Neon is a sparse accent on a dark, moody, desaturated base. Every new VFX is checked against this rule.

- **Palette:** violet/navy base, neon pink sakura, electric blue lightning, ink black. Stay inside it.
- **Focus:** a few strong focal accents, not glow everywhere. Restrained bloom. Contrast and silhouettes over rainbow effects.
- **Impact:** timing, easing, and sound design sell the hit.

### VFX target & performance
Near-realistic, in moody half-light. A dark sky, broken by a few bright events.

- **Lightning:** branching bolts with a bright core and a glow, plus a brief scene-wide flash. Bolts are mesh and shader, not particles.
- **Rain:** particles, with droplets that run down the blade.
- **Blade:** the katana reflects the dark sky and flares on lightning. The sky reflection is a baked cubemap. No realtime reflections and no SSR.
- **Sakura:** trees are over-the-top neon pink, with strong emission and glow. Falling petals read as slightly transparent liquid glass: a bright fresnel rim and a subtle iridescent sheen, faked in the shader (fresnel, alpha, emission). No real refraction and no screen-space effects. Petals count toward the particle budget.
- **Quest 3:** the arena is static, so bake its lighting and shadows with `LightmapGI` (Mobile renderer). Realtime work is only the short lightning flashes, particles, and the blade trail. Shared `GPUParticles3D` budget: about 2–4k alive particles for rain, petals, and blade droplets.

### Training Arena (Dojo of the Storm)
The physics-test mannequin lives here. It is the dummy test level: its own scene, separate from the run's shrine. A serene, endless void under a slow purple storm.

- **Platform:** a circular dark-stone disc floating in the void. The floor and the surroundings read as a still mirror of water, reflecting the sky.
- **Sky:** deep violet fading to navy, clouds drifting slowly, and occasional silent lightning far off (Storm 雷).
- **Composition:** one giant torii behind the mannequin; several smaller torii around the disc, tilted and half-sunken; a single sakura tree shedding neon-pink petals (Sakura 桜).
- **Center:** the spawn seal on the floor, 桜雷墨影 — the same four-part mark as the run spawn.
- **Implementation:** use assets from `assets/` first; if something is missing, build a procedural Godot stand-in. Quest / Mobile renderer: fake the reflection in the floor material, no screen-space effects, cheap fog, and a tight `GPUParticles3D` budget. Keep the arena a separate scene so it can load alone as the dummy test level.
- **IP:** our own shapes and our own palette. No form, symbol or music that would be recognizable from another game.

### Run intro
At the start of a run the player hovers about 0.5–1 m above the forest floor in a meditative cross-legged pose (seiza / lotus-like), then descends into the glade.

- **Descent:** slow and smooth (~3.1 s), sakura petals swirl around the player with glowing air steps rippling beneath the feet.
- **Touchdown:** a lightning flash lights the forest, ground seal glows, and an expanding shockwave ripple washes outward. Locomotion is unlocked at touchdown so the player can look around and walk freely. The player lands at their real standing height (in VR: hold B/Y to recenter, hold B + right stick to adjust eye height).
- **Title plate (D18, wstępnie: plansza tekstowa, tekst do redakcji):** after the boot splash and before the seiza intro, two or three lines of English on black (`docs/INTRO_TEXT.md`, drafted for Jakub to edit), fading in and out over about 9 s; one far firework is audible at the start. Skippable like the splash. The project has no separate main menu, so the plate sits where the menu would be.
- **Spirit Gate offering vs. Materialize on touchdown (DECISION FOR JAKUB):**
  - *Original GDD spec:* The katana instantly materializes in the player's hand on touchdown during the lightning flash.
  - *Implemented ritual (`src/run/run_intro.gd`, `tests/intro_grab_test.tscn`):* An ethereal spirit portal gate (`spirit_portal.gdshader`) opens in front of the player. The katana emerges handle-first from the gate, bathed in soft emissive light, before the portal dissolves. The katana hangs floating in mid-air at chest height. Grabbing the hilt physically (`HeldWeapon.is_held()`) acts as the tangible "start button" that finishes the intro, fades the glow, and begins the survival run / yōkai spawns. Pressing A/X provides an instant skip directly into the player's hand.
  - *Decision for Jakub:* Decide whether to keep the spirit gate offering with the physical grab-to-start ceremony as the permanent intro ritual, or revert to the original "instant materialize into hand on touchdown". The gate emergence adds ritual weight and tactile agency in VR, but adds ~4.3 s post-touchdown unless skipped.
- **Body:** no visible legs. The pose shows only as a shadow, or as a reflection in the water.
- **Comfort:** linear motion, no sudden deceleration, horizon stable. Nothing takes over the camera beyond the vertical offset. A few seconds at most, and skippable (A/X).

### Distant matsuri fireworks (D18, decided 2026-10-29, [`docs/FIREWORKS_PLAN.md`](FIREWORKS_PLAN.md))
Far fireworks behind the fog as a source of unease, not a goal. Bursts at random intervals (20–60 s, sometimes a short series of 2–4), 150–400 m away above the tree line, each in a new direction (≥ 70° from the last two). Every few minutes a rarer, nearer burst at 40–80 m, behind the trees, never closer than 40 m. The sound is the main element: a muffled, far thunder through a dedicated `Fireworks` bus (low-pass 300–800 Hz for far bursts, reverb, compressor, limiter), delayed by distance / 343 m/s. The glow is dim and fog-diffused, with no dynamic light (the fog ends at 11 m, so a light at 40 m would light nothing visible). Settings > ACCESS (flash) dims the glow; the sound stays. Parameters live in the World Gen profile ("Distant fireworks" group).

### Boot splash (D7, films from D7_fix1)
Played once per launch, before the run intro. The launch scene is `scenes/main.tscn` (sets `play_boot_splash`); tests and screenshot scenes that embed the run skip it.

- **Films (Nanjo, original):** `assets/splash/hanabi.ogv` then `assets/splash/nanjo.ogv`, Theora 1280x720, 30 fps, no sound. Both were encoded at 1280x720 from the 1920x1080 masters: a VR panel 4.8 m wide at 3.5 m is about 1000 device pixels across on a Quest 3, so 1080p only adds decode and upload cost (about 2.25x the pixels) that the headset cannot show. Desktop full screen upscales the 720p film to the window.
- **Engine boot splash:** `assets/splash/hanabi_boot.png`, a frame of the HANABI film at its burst (`application/boot_splash`).
- **HANABI film (4.4 s):** a black lead-in of about 0.9 s, the burst at 0.93 s (the soft pop plays on it), the firework blooms and the wordmark "HANABI" comes in under it as the firework fades.
- **Gap:** 0.3 s of black.
- **NANJO film (4.2 s):** the thread drops into the J and the logo unveils, then it fades to black.
- **Placement:** desktop, the board covers the whole window at 3.5 m (letterboxed in black if the window is not 16:9). VR, the board is a fixed 4.8 m x 2.7 m panel at 3.5 m, about 69 degrees across: a cinema-sized screen that leaves the edges of the view black. It is world-locked and yaw-only (horizon level), never a camera child, so it does not swim with the head. No camera motion, no time-scale tricks.
- **Look:** the film is drawn unshaded, with no fog, glow or camera effects on the splash camera, so the film keeps its own colours. The camera cull mask keeps only the splash layer, so no forest, sky, rain or hands show through.
- **Hand-over:** a black veil on the camera fades out over 0.6 s while the intro starts, so the forest comes up from black. The films end on black, so this is seamless.
- **Skip:** trigger, A/X, Space, Enter, Esc or a mouse click fades the film out in 0.4 s. The skip press cannot skip the intro: the intro only starts after the splash ends, and A/X skips the intro only from its own press.
- **Sound:** the splash is silent except for the firework pop. The Ambience (rain, forest wind) and World (thunder, impacts) buses are muted while the films play and come back when the intro starts (an instant unmute under the black veil, not a fade). The spawn, wave director and katana wait for the intro as before.

## 10. Audio
- Sword swings, clashes and slices; thunder; wind; temple bell (bonshō); night ambience.
- Music: dark Japanese style (shakuhachi, koto, taiko).
- Asset licenses and credits are tracked in `LICENSES.md` and `CREDITS.md`. Never commit assets whose license forbids redistribution (e.g. the Vacuous BGM pack) to a public repo.

## 11. Roadmap
1. **Sword physics:** XR rig, physics katana, test room with walls and a sword-wielding dummy for parries. Do not move on until it feels good.
2. **Loop:** basic yōkai with ragdoll, wave spawner, soul drops, XP and high score.
3. **Elements:** hokora Ofuda currency, one element tree per run (3 tiers).
4. **World:** procedural torii, fog, VFX and the spawn symbol.
5. **Meta AI:** `call_llm`, telemetry, awakened enemies, Oni brain and run memory. Reserve about 2 days before the deadline.
6. **Demo:** VR comfort and accessibility, polish, record a 2–3 minute video, write the description and submit. Only after that, and first to cut: the calories estimate (cherry on top).

**Cut rule:** if behind schedule, cut content (fewer upgrades, simpler world), never the sword physics or the AI enemies.

## 12. Stretch goals (only if time remains at the end)
- **Stabbing / impaling (Blade & Sorcery style):** the blade tip enters a body when the hit velocity is along the blade axis; a slider joint locks it to that axis with friction; the blade is pulled out by retracting it past the entry point.

## 13. Open questions
- **Intro ritual — Spirit Gate offering vs. Instant Materialize (DECISION FOR JAKUB):** Currently implemented in `src/run/run_intro.gd`: at touchdown a spirit portal gate opens, the katana emerges handle-first and hangs floating in mid-air, requiring the player to physically grab the hilt to start the run (skippable with A/X). Decision for Jakub: keep this physical ceremony or revert to GDD §9's original instant materialization directly into the hand on touchdown.
- Locomotion: decided in VR Comfort & Accessibility; build it in the final phase. Current build: smooth move on the left stick, snap turn on the right stick.
- Placeholders in the test room (2026-10-26): the training dummy and both bokken are built from Godot primitives; the Quaternius base character / katana models are not used yet. Skinning the Quaternius mesh onto the active ragdoll is planned with the yōkai (milestone 2).
- Balance numbers for the dummy (first pass): damage = (relative speed − 1.5 m/s) × 9, cap 120, × strike multiplier; poise damage 0.01 per damage point, balance regen 0.5/s: one full edge cut (~10 m/s) staggers, two or three quick heavy cuts knock it down. Tune by feel in the headset.
- Hand priority limits (first pass): grip 3.5 cm, twist 30° (kanabō 40°), rest on an enemy body up to 10 cm before the blade follows the hand through. Tune in the headset.
- Fog (first pass): depth fog 3.5–16 m, curve 1.4 (0% on the arena, ~44% at the giant torii, ~89% at 15 m), dark blue-violet fog color shared with the sky horizon.
- Active ragdoll muscles currently act like animation (no reaction torque on the parent) for stability; full momentum-conserving muscles are a later polish item.
- Combat feel, first pass (2026-10-26): player arm strength 260 N / 40 N·m (katana 1.1 kg settles in ~0.13 s, kanabō 4 kg in ~0.47 s); hit-stop on hits ≥ 40 damage; parry = clash with an *attacking* enemy blade at ≥ 1.5 m/s relative and ≥ 25° between blades, then slow-mo ×0.3 for 0.6 s with the player's blade kept real-time, enemy stunned 1.2 s, counter window 1.5 s at ×1.5 damage. Tune in the headset.
- Hit-stop freezes the world for 50–80 ms; the player's blade stays in the tracked hand (hand priority), so the bite is felt through the frozen enemy and haptics.
- Enemy damage, first pass (normal difficulty): vertical 18, horizontal 14, thrust 20 (easy ×0.6, hard ×1.4). Tune in the headset.
- After a knockdown the dummy stands up where it fell instead of walking back; the duelist AI walks back home when not sparring, but obstacle-aware navigation (NavigationAgent3D) comes with the yōkai.
- Godot docs recommend the Compatibility renderer for Android XR; the project uses Mobile on PC and Compatibility on Quest. Revisit if Mobile on Quest becomes recommended (needed for some VFX).
- Number of upgrades per element for the hackathon version?
- Exact element balance numbers?
- Does Meta offer TTS, or do we use Piper?
- Which fields does the hackathon submission form require?

## 14. VR Comfort, Accessibility & Settings (Implemented - Zadanie 6, D3)
The 安 tab of the pause menu is **SETTINGS** (labels in English, like the rest of the menu). It has six pages behind one sub-tab row; the tree is untouched, and the tab keeps the world paused like the tree does. Everything saves at once to `user://hanabi_vr.cfg`; each save keeps the other sections.

- **AUDIO** `[audio]`: Master, Music, SFX and Ambience, 0–100 % in 10 % steps, on the buses (Master, World, Music, Ambience). Music and Ambience keep their slow-mo and pause ducks on top of the chosen level. SFX plays a cue as it changes.
- **MOVEMENT** `[comfort]`: vignette on/off and four strengths; snap (15–90°) or smooth turn (1.0–4.0); walking pace SLOW ×0.7 / NORMAL / FAST ×1.3, which stacks with the ink boost; seated mode and eye height (±5 cm, reset).
- **ACCESS** `[access]`: lightning and firework flash FULL 100 % / SOFT 50 % / OFF 0 % (the scene-wide light and the firework lamps; the bolt and the thunder stay). Haptic strength OFF / HALF 50 % / FULL 100 % for every pulse, with a TEST pulse on the katana hand.
- **SANDBOX** `[sandbox]` (D9, demo and test mode): one switch, OFF by default. ON reads every node of all four schools as unlocked, tier 5 included, and buying costs nothing; OFF gives back the run's own unlocks and points exactly. A run that had the switch on at any time wears a small amber SANDBOX mark on the wrist and never becomes a record. Details in `docs/ELEMENTS_PLAN.md`, section D9.
- **CONTROLS**: the dominant-hand switch and both Quest 3 controllers, drawn from the project's own OpenXR action map (`openxr_action_map.tres`, profile `oculus/touch_controller`) by `ControlsMap`. Nothing is typed in by hand except what each input does. The katana hand, the walking stick, the turning stick and the wrist HUD follow the dominant-hand setting. Touch sensors, tracking poses and haptic output are listed as footnotes; the Meta button is marked as the system's.
- **Dominant hand:** Right (standard) or Left (southpaw). Switching reparents the movement stick (`MovementDirect`) to the off-hand and the turning stick (`MovementTurn`) to the dominant hand, moves the wrist HUD plate to the off-hand and puts the katana in the dominant hand.
- **Skipped on purpose (D3):** teleport locomotion (needs its own provider and a second stick mode that competes with the katana grip and the B/Y keys, not cheap); a text-size slider (every canvas size is fixed, and scaling it risks overflow in the tree); subtitles (the game has no speech to caption).

## 15. Cherry on top: calories (LATE, lowest priority)
Only at the very end, after comfort and the demo. First thing to cut. Do not implement during prototyping. The number is an estimate, not a medical measure. Follow the premium art-direction rule: a quiet diegetic mark, no fitness-app UI.

- **Estimate:** MET-style. kcal ≈ MET × body weight (kg) × hours. MET rises with headset motion (vertical and horizontal: squats, lunges, dodges), controller swing speed and acceleration, and the count of strong cuts. Body weight is an optional setting; default about 70 kg. Always label the figure as an estimate.
- **In session:** a small readout on the wrist or hand, glanceable, beside the existing time.
- **After the session:** kcal, time, swings, and parries, added quietly to the end screen.
- **Optional:** personal bests and a short local history.
- **Stretch:** a later link to Meta / Health apps. Not this pass.
