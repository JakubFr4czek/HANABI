# Project brief: HANABI (花火) — VR Japanese dark-fantasy sword survivor (Meta Global AI Developer Hackathon)

**The full design reference is `docs/GDD.md` (provided alongside this prompt). Put it in the repo at `docs/GDD.md`, read it before every task, and follow it. If this prompt and the GDD disagree, the GDD wins.**

You are the lead developer starting this project from scratch. Build a playable prototype in **Godot 4 (GDScript)** for **Meta Quest via OpenXR** (also runnable on PCVR for recording). Work in small, testable steps and commit after each milestone.

## Hackathon constraints (important)
- Submission deadline: Nov 4, 2026, 9:00 PM ET. Demo video (2–3 min) counts for 25% of the score.
- Judging: Impact 30%, **Use of Meta AI tooling 25%** (must go beyond a basic integration), Technical depth 20%, Demo 25%.
- **A Meta model must eventually run inside the game** (added in a later phase, see section 4) (Meta Model API: Muse Spark etc.). API credits are not active yet, so put every LLM call behind one abstraction, `call_llm(prompt, schema) -> Dictionary`, with swappable backends (Meta Model API, plus a temporary Claude/Gemini backend for development). The provider and API key come from config/env, never hardcoded.
- All LLM calls are async (`HTTPRequest`). The game must never block waiting for a response, and it needs graceful fallbacks when the API is slow or down.

## Core concept
A VR melee "survivor-like" (Survivor.io loop) with **Blade & Sorcery–style physics swordplay**, set in a **procedurally generated dark Japan**: endless red torii gates of varying sizes, thick fog, dark moody lighting, neon accents. You fight waves of yōkai with a katana until you die, then chase your high score.

## 1. Physics sword combat (TOP PRIORITY, build first)
- The katana is a `RigidBody3D` driven toward the controller pose by a PD controller (force and torque), not parented to the hand. Hitting a wall stops the blade while the hand keeps moving, so there is no clipping.
- Mass and inertia matter: heavier weapons lag behind the hand.
- Continuous collision detection on the blade for fast swings.
- Damage scales with blade velocity at impact. Add hit-stop (50–80 ms) on strong hits, controller haptics, and a blade trail colored by the active element.
- Parrying emerges physically (blade vs blade). Detect a "parry" from relative velocity and angle, then trigger a short slow-mo and a counter window.
- Enemies are active ragdolls (animation drives the body through forces) so they stagger and react to hits.
- Use `godot-xr-tools` for the XR rig, locomotion and grabbing where it helps.

## 2. Survivor loop
- Waves of yōkai spawn continuously and escalate over time.
- Enemies drop lots of glowing soul orbs (hitodama, colored by element) that fly to the player as XP.
- Level up: time slows, 3 **ofuda** (paper talismans) float in front of the player, and the player **picks one by slicing it with the sword**.
- Limited upgrade slots (e.g. max 2 elements per run or 6 upgrade slots), so each run differs.
- Run ends on death, with a score/time screen and a persistent high score.

## 3. Four elements (each with an upgrade tree, applied to the blade and as abilities)
- **Sakura**: neon pink petals. Slicing petals, an orbiting blade ring, a petal storm, light healing.
- **Storm**: electric blue lightning. Chain lightning between enemies, charged strikes.
- **Ink (sumi-e)**: sticky black ink. Traps and walls painted with the sword or hand, slowing pools.
- **Shadow**: dark/purple. Short teleports, invisibility, darkness that confuses enemies.
- Evolutions: two maxed trees combine (e.g. Storm + Ink = black lightning).

## 4. Meta AI features — LATER PHASE, DO NOT IMPLEMENT NOW
Context only, so the architecture leaves room for it. During prototyping, do not build any of this: no LLM calls and no `call_llm` yet. Just keep the enemy AI modular (a swappable "brain" component per enemy, with tactics/resistances as data) and log gameplay events in one place, so telemetry and LLM-driven behavior can plug in later.

- **Telemetry**: silently track playstyle: slash directions, favorite element, parry rate, aggression vs retreating, time alive, upgrade picks.
- **"Awakened" enemies**: every 2–3 minutes one normal enemy "awakens" (eyes glow, it stops, turns to the player). Send telemetry to the LLM and get back JSON: `{ "line": "...", "tactic": {...}, "resistances": [...] }`. It speaks a short line commenting on the player's style (e.g. "You always cut from the right... like always.") and then actually adapts (e.g. blocks right-side cuts). Keep it rare and short so it stays creepy.
- **Oni boss "tactical brain"**: every 2–5 s or on events, the LLM returns a high-level plan (formation, target weakness, ability to use). Fast local AI (NavigationAgent3D + FSM) executes it every frame, so the LLM never drives per-frame movement.
- **Cross-run memory**: store a short summary of previous runs locally so awakened enemies can reference them ("Last time you died near the eastern torii. I remember.").
- Optional fourth-wall comments (play time, high score, unused element).
- Optional debug/demo overlay showing the boss's "thoughts" (useful for the demo video).
- Voice: the LLM writes the lines. TTS is a pluggable separate module (e.g. local Piper) and is optional.

## 5. World and art direction
- Procedural world: `FastNoiseLite` places torii of many sizes, including corridors of gates like Fushimi Inari; also stone lanterns (tōrō).
- Thick fog and a dark, cold palette, with neon pink sakura, electric blue lightning and glossy black ink as accents (emissive + glow).
- **Spawn point**: a round stone platform under the largest torii, with a glowing symbol on the floor split into 4 parts (one per element, e.g. kanji 桜 雷 墨 影). Parts light up as elements unlock. It can double as an in-world element selector.
- Performance: standalone Quest uses simple fog + particles. Volumetric fog is a PCVR-only setting for recording.

## Assets
Use the downloaded free assets in `assets/` first (Quaternius monsters/characters/animations, katana and torii models, Poly Haven textures/HDRI, Kenney packs, SFX, fonts; see `assets/README.md` and `LICENSES.md`). If a needed asset is missing or unusable, generate it procedurally in Godot (primitives/CSG/ArrayMesh for torii, lanterns, rocks; shaders and particles for VFX) or use a clear placeholder, and note it in `docs/GDD.md` open questions. Never download new assets without recording their license.

## Asset licensing
Keep `LICENSES.md` and `CREDITS.md` in the repo and update them whenever an asset is added. Do not commit the Vacuous BGM music files (their license forbids redistributing the raw files); keep them in a git-ignored folder.

## Milestone order (do not reorder)
1. Godot 4 + OpenXR project boots on Quest/PCVR; physics katana works and feels good (walls, parry with a dummy sword).
2. Basic yōkai with ragdoll, wave spawner, soul drops, XP, high score.
3. Elements, ofuda level-up, upgrade trees with slot limit.
4. Procedural torii world, fog, VFX, spawn symbol.
5. (LATER, only when asked) `call_llm` abstraction, telemetry, awakened enemies, Oni boss brain, run memory.
6. Polish for the demo recording.

If time runs short, cut content (fewer upgrades, simpler world) but never cut the sword physics or the AI enemies.

## First task now
First check the installed Godot version and what is in `assets/`. Then set up the repository (project name `hanabi`, private for now) with `docs/GDD.md` and the Godot 4 project with OpenXR and godot-xr-tools, plus a README with run instructions (Quest and PCVR).

Then build ONLY a **physics test dummy** in a simple test room with walls: a humanoid training dummy (Quaternius base character or a primitive body) as an active ragdoll that reacts physically to hits, staggers, and recovers; it holds a physics sword so parries can be tested later. Add a debug display of hit velocity and damage per hit. For now, a simple grabbable physics stick/sword in the player's hand is enough to hit it. The full PD-controlled katana comes in the next task.

Show me a plan first and wait for approval before writing code. Report what works, what is stubbed, and how to run it.
