# HANABI (花火) — hackathon submission

> Paste-ready text for the Meta Global AI Developer Hackathon 2026 form (Indie developer track).
> Every name and number below was checked against `docs/GDD.md` and the code on 2026-11-03
> (see "Consistency check" at the end). Video plan: [`docs/submission/SHOT_LIST.md`](submission/SHOT_LIST.md).
> Screenshots: [`docs/submission/`](submission/).

## Tagline
A physics-katana VR survivor-like for Quest 3: cut your way through a foggy, endless yōkai forest while a Meta AI–driven Oni studies how you fight.

## Description (≈200 words)
HANABI is a VR melee survivor-like set on the night of a village matsuri. The fireworks still burst
somewhere beyond the mist, but the lanterns have gone out and the yōkai are walking out of the fog.
You have one katana and an endless, procedurally generated forest.

The sword is a real physics object: it has weight and inertia, it stops on walls instead of
clipping, and damage comes from how you swing it. A full-arm cut with the edge leading splits an
enemy; a wrist flick or a slap with the flat barely moves it. Blades clash, and a fast cross-cut
into an attack is a parry with a short slow-motion and a counter window.

Walk through an elemental torii to imbue the blade with Sakura, Storm, Ink or Shadow for 20 seconds.
The four schools form a counter ring, and each has two abilities on A/B and a five-node skill tree.
Kill yōkai, collect soul orbs, level up, find roadside shrines and slice an ofuda for a one-minute
buff, and free the five villager souls sealed in stone statues.

Every few minutes an Oni with a kanabō walks out of the trees. Its tactics come from Meta's Muse
Spark model, which reads how you fight and tells you so — "You always cut from the right."

## How we used Meta AI
Only what actually runs in the build is listed here.

- **Oni tactical brain (Muse Spark via the Meta Model API).** `src/ai/oni_ai_client.gd` sends an
  async chat-completions request (`https://api.meta.ai/v1/chat/completions`, model `muse-spark-1.3`,
  `max_tokens` 100) every 2–5 s while the boss is fighting — never per frame, one request at a time.
- **What the model sees:** boss and player HP, distance, fight phase (1–3), the player's last
  actions (`cut` / `parry`) and a `player_style` summary built from the central gameplay event log
  (`GameEvents`): which side the player usually cuts from, their favourite element, number of cuts.
  No personal data, no recordings, no device identifiers.
- **What it returns:** JSON with `tactic`, `attack`, `target_distance` and a short `speech` line.
  The local duelist AI executes it (e.g. `flank_left` makes the Oni step aside); the LLM never
  drives per-frame movement. The line appears in a speech bubble over the Oni's head.
- **Guard rails:** tactics and attacks are whitelisted (anything else falls back to the local
  `duel` logic), the standoff is clamped to 1.4–1.9 m (the kanabō's real reach), speech is one line
  of at most 60 characters, a tactic holds for 4.5 s.
- **Never blocks the game:** with no key, a 3 s timeout (counted in game frames), HTTP 401/500, a
  network error or malformed JSON, the Oni falls back in the same frame to its local state machine
  and prewritten EN/PL lines. The fight works 100 % offline.
- **For the video:** an optional "Oni thinks" overlay (Settings → META AI, off by default) shows the
  chosen tactic and whether it came from Muse Spark or the local fallback.
- **Key handling:** the player pastes their own Meta Model API key from the clipboard in Settings;
  it is stored only in the local `user://` settings and shown masked. No key ships with the APK.

Details: [`docs/META_AI.md`](META_AI.md).

## Features
- **Physical katana.** A rigid body pulled to the hand by a PD controller: weight, inertia, no
  clipping (continuous collision), free grip anywhere on handle, guard or spine, two-handed grip,
  and the blade never visibly leaves the hand. Edge alignment matters: edge or point ×1.0, flat ×0.3,
  spine ×0.2, hilt ×0.3. Hit-stop, per-event haptics, real blade-on-blade parries.
- **Four elements and a counter ring.** Sakura 桜, Storm 雷, Ink 墨, Shadow 影, imbued for 20 s by
  walking through an elemental torii. Ink beats Storm, Storm beats Sakura, Sakura beats Shadow,
  Shadow beats Ink: a counter hit ×1.5, the same school ×0.5, plain steel ×1.0. Two abilities per
  element (Senbonzakura / Hanamai, Raikiri / Shiden, Sumi-gaeshi / Kage-nawa, Kagemusha /
  Yami-watari). Yōkai carry a school you can read in their eyes and mask sigil.
- **Cut like butter.** The tier-5 node of each tree (Hanadachi, Raidachi, Sumidachi, Kagedachi) lets
  a clean, fast edge cut split a yōkai along the plane of the blade into two pieces that dissolve
  into petals.
- **Skill trees.** Every level gives one skill point; four trees of five nodes, costs 1/1/1/2/3,
  in a 3D menu that pauses the world.
- **Procedural forest.** An endless chunked forest (`FastNoiseLite` hills, paths, cedars, rocks,
  stone lanterns, rare neon sakura, full-size red torii), closed in by fog; distant matsuri
  fireworks you hear and glimpse but never reach.
- **Shrines and ofuda.** Roadside hokora: touch the offering, three yellow ofuda rise, slice one for
  speed +20 % or damage +20 % for 60 s, or a heal (35 % of max HP now, 15 % over 10 s).
- **Waves and the Oni.** A wave director with a calm opening that ramps up, elites, and a periodic
  2.7 m Oni boss with telegraphed kanabō attacks. A run goal: free 5 villager souls; death ends
  the run on a memorial stele, and slicing the Restart Ema starts a new one.
- **Splash and opening strike.** HANABI and NANJO films, a 3-second in-engine opening strike
  (six yōkai cut in half, ending in a white flash), then the seiza intro: you descend into the
  glade and take the katana from a spirit gate.
- **VR comfort and settings.** Snap (15–90°) or smooth turn, tunnelling vignette, walking pace,
  seated mode and eye height, left/right-handed play, audio buses, flash reduction for lightning and
  fireworks, haptic strength, a controls map drawn from the OpenXR action map. Diegetic wrist HUD
  (HP, element timer, stamina, souls, kcal estimate) that appears only when you look at your wrist.

## Requirements
- **Meta Quest 3** (standalone, OpenXR). Installed as an APK via sideloading (Developer Mode +
  `adb install` or Meta Quest Developer Hub): see [`docs/QUEST_TEST.md`](QUEST_TEST.md).
- Optional: your own Meta Model API key for the AI-driven Oni (without it the Oni uses its local AI).
- PCVR / desktop: Godot 4.7.2 runs the project directly (desktop rig with mouse and keyboard).

## Known limitations (honest)
- **Enemy art is stylised and low-detail.** Yōkai bodies are simple low-poly humanoids with
  sculpted masks; next to the scanned katana and torii they look the cheapest part of the game.
- **Meta AI is only the Oni.** The GDD's "awakened" swarm enemies, cross-run memory and voice (TTS)
  are not built. The Muse Spark integration is tested end-to-end against a local mock server of the
  chat-completions API; a live run needs a valid key, and the request format follows our reading of
  the Meta Model API.
- **Performance on device** is held to budgets by automated headless checks (≤345 draw calls,
  ≤12 dynamic lights, ≤28 audio voices, ≤4000 particles); the 72 fps target still has to be
  confirmed in the headset in every new build.
- Lighting is mostly real-time and simple (Compatibility renderer on Quest); the forest reads dark
  and flat in places.
- No teleport locomotion and no subtitles (the only speech is the Oni's bubble, which is text).
- The calorie number is a rough MET estimate, not a measurement.

## Credits
All third-party assets are CC0 or CC-BY; the full list with authors and licenses is in
[`CREDITS.md`](../CREDITS.md) and [`LICENSES.md`](../LICENSES.md). Built with Godot 4.7, godot-xr-tools
and the Godot OpenXR Vendors plugin.

## Team
**Jakub Frączek / Nanjo** — design, development, splash films.

---

## Consistency check (N11, 2026-11-03)
| Claim | Source |
|---|---|
| Finisher names Hanadachi / Raidachi / Sumidachi / Kagedachi | GDD §5; `src/run/skill_tree_data.gd` tier-5 subtitles |
| Ability names (Senbonzakura, Hanamai, Raikiri, Shiden, Sumi-gaeshi, Kage-nawa, Kagemusha, Yami-watari) | GDD §5 table; strings in `src/` |
| Imbue 20 s | `ElementBalance.IMBUE_SECONDS = 20.0` (tier-1 node adds 4 s) |
| Buffs 60 s, +20 % speed / damage, heal 35 % + 15 % over 10 s | `ElementBalance.BUFF_SECONDS`, `BUFF_*_MULTIPLIER = 1.2`, `BUFF_HEAL_*`; GDD §6 |
| Tree costs 1/1/1/2/3 | `skill_tree_data.gd` `"cost"`; GDD §6 |
| Counter ring ×1.5 / ×0.5 / ×1.0 | GDD §5 (D17); `ElementBalance.BEATS` |
| Player HP 100 | `PlayerHealth.max_hp = 100.0`; GDD §7 |
| Oni 2.7 m, kanabō | `src/enemies/run_oni_boss.gd` header |
| Muse Spark endpoint/model, 2–5 s, 3 s timeout, 60 chars, 1.4–1.9 m | `src/ai/oni_ai_client.gd`; `docs/META_AI.md` |
| 5 soul vessels | `SoulVesselManager.COUNT`; `docs/f7/README.md` |
| Edge ×1.0, flat ×0.3, spine ×0.2, hilt ×0.3 | GDD §4 |

