# HANABI (花火) — Game Design Document

> Living reference for the project. Keep this file in the repo at `docs/GDD.md`; every implementation decision should follow it. Update it when a design decision changes.

## 1. Vision
**HANABI** is a VR melee survivor-like: Blade & Sorcery–style physics swordplay meets the Survivor.io loop, set in a dark, foggy, procedurally generated Japan full of torii gates. Every kill is a small "firework" of neon petals, lightning and ink, hence the name *hanabi* (fireworks).

- **Platform:** Meta Quest (standalone, OpenXR), plus PCVR for demo recording.
- **Engine:** Godot 4, GDScript.
- **Context:** Meta Global AI Developer Hackathon (submission due Nov 4, 2026, 9:00 PM ET). Indie developer track.
- **Tone:** dark action with neon beauty. It is not a horror game: atmosphere is moody, but the core feeling is satisfying, powerful combat.

## 2. Design pillars
1. **The sword feels real.** Physics-driven blade, weight, no clipping, real parries.
2. **One more run.** Constant drops, frequent level-ups and meaningful build choices.
3. **Neon in the dark.** Black fog and red torii, lit by pink sakura, blue lightning and black ink.
4. **The world is watching you.** Rare AI-"awakened" enemies that comment on and adapt to your playstyle (Meta AI, later phase).

## 3. Core loop
Spawn at the shrine, then fight waves, collect soul drops, level up, pick an ofuda upgrade, fight stronger waves and bosses, die, see your score, and start a new run to beat your high score.

- Runs are endless; difficulty scales with time.
- Death ends the run; the high score is saved locally.
- Target run length for the demo is about 5–10 minutes.

## 4. Combat and physics
- **Katana:** a `RigidBody3D` pulled toward the controller pose by a PD controller (force and torque). It is not parented to the hand.
- **Weight:** mass and inertia make heavier weapons lag behind the hand.
- **No clipping:** the blade stops on walls and bodies while the hand continues. Use continuous collision detection on the blade.
- **Damage:** scales with blade velocity at impact. Light swings make shallow cuts; full swings make heavy hits.
- **Parry:** emerges from blade-vs-blade physics. A clash with the right velocity and angle counts as a parry and triggers a short slow-mo and a counter window.
- **Feedback:** hit-stop (50–80 ms) on strong hits, haptics scaled by impact, and a blade trail colored by the active element.
- **Enemies:** active ragdolls (animation drives the body through forces). They stagger, react to hits and collapse.

## 5. Elements
There are four elements. Each has an upgrade tree, applies to the blade (trail, on-hit effect), and grants abilities.

| Element | Color | Fantasy | Example upgrades |
|---|---|---|---|
| **Sakura** 桜 | neon pink | beauty that cuts | cutting petals on swing, orbiting petal blades, petal storm, light healing |
| **Storm** 雷 | electric blue | speed and chain damage | chain lightning between enemies, charged strike, lightning dash |
| **Ink** 墨 | glossy black | control | paint traps and walls with the blade or hand, slowing ink pools, ink tendrils |
| **Shadow** 影 | dark violet | trickery | short teleport, invisibility, darkness that confuses enemies |

- **Slot limit (like Survivor.io):** max 2 elements per run and about 6 upgrade slots total, so every run plays differently.
- **Evolutions:** two maxed trees combine into a special ability (e.g. Storm + Ink = black lightning, Sakura + Shadow = phantom petals).

## 6. Progression and UI
- **Drops:** enemies drop many glowing soul orbs (hitodama), colored by element. Orbs fly to the player when nearby.
- **Level-up:** time slows and three **ofuda** (paper talismans) float in front of the player. The player chooses one by **slicing it with the sword**.
- **HUD:** minimal and diegetic: XP on the sword guard or wrist, health as a glowing charm, score and time on the wrist.
- **End screen:** score, time survived, kills, build used and high score.

## 7. Enemies
- **Basic yōkai:** swarm enemies, weak and numerous.
- **Elite enemies:** have element resistances and weaknesses and require parries or specific elements.
- **Oni boss:** appears periodically; heavy attacks, parryable combos.
- Local AI uses NavigationAgent3D and a state machine (FSM), with tactics and resistances defined as data and a swappable "brain" component (prepared for the AI phase).

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
- **Procedural world:** `FastNoiseLite` places red torii of many sizes, from small to gigantic, including long corridors of gates like Fushimi Inari's Senbon Torii. Also stone lanterns (tōrō), shrine props, sakura trees and rocks.
- **Palette:** near-black and deep blue-grey, red torii, with emissive neon accents: pink sakura, electric blue lightning, glossy black ink.
- **Spawn point:** a round stone platform under the largest torii. A glowing symbol on the floor is split into four parts (桜 雷 墨 影), one per element. Parts light up as elements are unlocked. It can double as an in-world element selector.
- **VFX:** GPU particles for petals, procedural lightning, an ink/darkness shader with noise, and blade trails (GPUTrail).
- **Performance:** on standalone Quest use simple fog and particles. Volumetric fog is a PCVR-only setting for recording.

### Training Arena (Dojo of the Storm)
The physics-test mannequin lives here. It is the dummy test level: its own scene, separate from the run's shrine. A serene, endless void under a slow purple storm.

- **Platform:** a circular dark-stone disc floating in the void. The floor and the surroundings read as a still mirror of water, reflecting the sky.
- **Sky:** deep violet fading to navy, clouds drifting slowly, and occasional silent lightning far off (Storm 雷).
- **Composition:** one giant torii behind the mannequin; several smaller torii around the disc, tilted and half-sunken; a single sakura tree shedding neon-pink petals (Sakura 桜).
- **Center:** the spawn seal on the floor, 桜雷墨影 — the same four-part mark as the run spawn.
- **Implementation:** use assets from `assets/` first; if something is missing, build a procedural Godot stand-in. Quest / Mobile renderer: fake the reflection in the floor material, no screen-space effects, cheap fog, and a tight `GPUParticles3D` budget. Keep the arena a separate scene so it can load alone as the dummy test level.
- **IP:** our own shapes and our own palette. No form, symbol or music that would be recognizable from another game.

## 10. Audio
- Sword swings, clashes and slices; thunder; wind; temple bell (bonshō); night ambience.
- Music: dark Japanese style (shakuhachi, koto, taiko).
- Asset licenses and credits are tracked in `LICENSES.md` and `CREDITS.md`. Never commit assets whose license forbids redistribution (e.g. the Vacuous BGM pack) to a public repo.

## 11. Roadmap
1. **Sword physics:** XR rig, physics katana, test room with walls and a sword-wielding dummy for parries. Do not move on until it feels good.
2. **Loop:** basic yōkai with ragdoll, wave spawner, soul drops, XP and high score.
3. **Elements:** ofuda level-up, upgrade trees, slot limit and evolutions.
4. **World:** procedural torii, fog, VFX and the spawn symbol.
5. **Meta AI:** `call_llm`, telemetry, awakened enemies, Oni brain and run memory. Reserve about 2 days before the deadline.
6. **Demo:** polish and record a 2–3 minute video, write the description and submit.

**Cut rule:** if behind schedule, cut content (fewer upgrades, simpler world), never the sword physics or the AI enemies.

## 12. Stretch goals (only if time remains at the end)
- **Stabbing / impaling (Blade & Sorcery style):** the blade tip enters a body when the hit velocity is along the blade axis; a slider joint locks it to that axis with friction; the blade is pulled out by retracting it past the entry point.

## 13. Open questions
- Locomotion: smooth only, or teleport as a comfort option? (Current build: smooth move on the left stick, snap turn on the right stick.)
- Placeholders in the test room (2026-10-26): the training dummy and both bokken are built from Godot primitives; the Quaternius base character / katana models are not used yet. Skinning the Quaternius mesh onto the active ragdoll is planned with the yōkai (milestone 2).
- Balance numbers for the dummy (first pass): damage = (relative speed − 1.5 m/s) × 9, cap 120; one full swing (~10 m/s) staggers, two quick heavy hits knock it down. Tune by feel in the headset.
- Active ragdoll muscles currently act like animation (no reaction torque on the parent) for stability; full momentum-conserving muscles are a later polish item.
- Combat feel, first pass (2026-10-26): player arm strength 260 N / 40 N·m (katana 1.1 kg settles in ~0.13 s, kanabō 4 kg in ~0.47 s); hit-stop on hits ≥ 40 damage; parry = clash with an *attacking* enemy blade at ≥ 1.5 m/s relative and ≥ 25° between blades, then slow-mo ×0.3 for 0.6 s with the player's blade kept real-time, enemy stunned 1.2 s, counter window 1.5 s at ×1.5 damage. Tune in the headset.
- Hit-stop freezes the whole world (including the player's blade) for 50–80 ms; in VR the head and hands keep tracking. If it feels bad in the headset, switch to a local hit-stop (only the hit enemy and the blade).
- Should enemy attacks that are *not* parried damage the player? Needs player HP (milestone 2).
- After a knockdown the dummy stands up where it fell instead of walking back; real stepping/locomotion comes with the enemy AI (NavigationAgent3D + FSM).
- Godot docs recommend the Compatibility renderer for Android XR; the project uses Mobile on PC and Compatibility on Quest. Revisit if Mobile on Quest becomes recommended (needed for some VFX).
- Number of upgrades per element for the hackathon version?
- Exact element and evolution balance numbers?
- Does Meta offer TTS, or do we use Piper?
- Which fields does the hackathon submission form require?
