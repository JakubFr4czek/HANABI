# Elements & Skill Tree Architecture Plan (ELEMENTS_PLAN.md)
*Status: Approved Design & Specification (Task E1)*
*Author: Jakub Frączek / Antigravity*
*Date: 2026-10-27*
*Target Hardware: Meta Quest 3 standalone (72+ fps, ≤345 draw calls, ≤12 dynamic lights, ≤28 audio voices)*

---

## (a) Codebase Inventory & System Diagnosis

### 1. Existing Systems & File Responsibilities

| File Path | Core Classes & Key Functions | Current Role | Problems Identified |
|---|---|---|---|
| `src/core/elements.gd` | `class_name Elements`<br>`color()`, `accent_color()`, `seal_index()`, `build_label()` | Element definitions (Sakura, Storm, Ink, Shadow, evolutions) and color palette queries. | Static definitions with hard-coded colors; assumes permanent dual-element combinations ("black_lightning", "phantom_petals") rather than dynamic single-element combat states. |
| `src/run/element_system.gd` | `class_name ElementSystem extends Node3D`<br>`setup()`, `reset()`, `apply_upgrade()`, `on_blade_hit()`, `on_enemy_died()`, `try_shadow_blink()`, `paint_ink()`, `debug_release_petals()`, `_rebuild_orbit_petals()` | Combat effects engine for elements; handles passive triggers on sword strikes and manages particle/mesh pools (`MAX_PETALS = 12`, `MAX_INK_POOLS = 6`, `MAX_TRANSIENT_MESHES = 18`). | **Passive and random**: effects trigger automatically on sword hit without player intent. Locks player into a single element for the whole run (`active_elements.size() >= 1`). Only Shadow has an active trigger (`try_shadow_blink`), which was hooked to thumbstick click. |
| `src/run/ofuda_talisman.gd` | `class_name OfudaTalisman extends Node3D`<br>`setup()`, `slice()`, `dismiss()`, `_build_labels()`, `_build_collider()` | Floating 3D paper talisman sliced by the blade during slow-motion level-up to pick an upgrade. | Used exclusively as a level-up reward card selection mechanism rather than a collectible currency for a deliberate skill tree. |
| `src/run/upgrade_pool.gd` | `class_name UpgradePool extends RefCounted`<br>`GENERIC_UPGRADES`, `ELEMENT_UPGRADES`, `pick_choices()`, `available_element_upgrades()` | Generates 3 random choices upon level-up from generic cards and 3 tiers of element upgrades. | Randomizes element acquisition; mixing element unlocks with generic stat buffs makes element builds feel accidental rather than mastery-driven. |
| `src/run/diegetic_hud.gd` | `class_name DiegeticHud extends Node3D`<br>`attach()`, `update_hud()`, `_orient_wrist_face()` | Left wrist plate rendering HP ring, lacquer charm, soul XP bar, and stats (`rank`, `wave`, `score`, `kills`). | Accepts `active_element: String` in `update_hud` but **never renders or communicates the active element or remaining duration** to the player. No cooldown indicators. |
| `src/run/run_game.gd` | `class_name RunGame extends TestRoom`<br>`_present_level_up()`, `_on_ofuda_sliced()`, `_apply_upgrade()`, `collect_soul()` | Orchestrates run loop, soul drops, wave progression, level-ups, slow-mo transitions, and end screen. | Couples element acquisition directly to soul level-ups. Uses `TimeController.slow_motion(0.2, 120.0, true)` for card slicing. |
| `src/run/forest_world.gd` | `class_name ForestWorld extends Node3D`<br>`_populate_multimesh()`, `nearest_torii_position()`, `_build_torii_mesh()` | Infinite procedural terrain and prop streamer (trees, boulders, decorative torii). | Torii gates are static MultiMesh decorations with collider posts; they have no element affinity, no passing detection plane, and no interaction logic. |
| `src/weapons/held_weapon.gd` | `class_name HeldWeapon extends RigidBody3D`<br>`set_element()`, `on_blade_hit()` | Katana physics, PD controller, blade emission, and collision reporting. | Element is just a string that sets `BladeTrail` color; no state machine for expiration, warnings, or ability triggers. |

### 2. Full Controller Bindings Inventory

#### OpenXR Bindings (`openxr_action_map.tres` & `XRPlayer.gd`)

| Hand | Physical Control | OpenXR Action | Current Game Binding | Status / Conflict for New System |
|---|---|---|---|---|
| **Right (Sword Hand)** | **A Button** | `ax_button` | Triggers `reset_requested` (dev reset) | **CONFLICT**: Must be freed for **Ability 1 (Primary / Fast)**. Move dev reset to keyboard or debug menu. |
| **Right (Sword Hand)** | **B Button** | `by_button` | Tap without grip: `toggle_attacks`<br>Hold: `recenter_view`<br>Hold + Stick Y: eye height<br>Grip + B: weapon recall | **CONFLICT**: Must be freed for **Ability 2 (Special / Tactical)**. Move recenter to long-press Menu or Pause UI. Recall is only active when hand is empty. |
| **Right (Sword Hand)** | **Grip (Squeeze)** | `grip`, `grip_click` | Grab katana / hold katana (threshold > 0.6) | **RESERVED**: Core swordplay grip. When holding katana, grip stays squeezed. |
| **Right (Sword Hand)** | **Trigger (Index)** | `trigger`, `trigger_click` | Unused in sword hand (or poke interaction) | Available for secondary interaction / UI pointer when menu open. |
| **Right (Sword Hand)** | **Thumbstick** | `primary` | Snap turn (`MovementTurn.tscn`) | **RESERVED**: VR Locomotion (Snap Turn). |
| **Right (Sword Hand)** | **Thumbstick Click** | `primary_click` | Triggers `element_ability_requested` / cycles element in test room | Awkward ergonomics during combat swings. Deprecate for abilities. |
| **Right (Sword Hand)** | **Oculus / System Button** | `/user/hand/right/input/system/click` | Reserved by Meta OS | **FORBIDDEN**: System reserved. |
| **Left (Off-Hand)** | **X Button** | `ax_button` | Triggers `reset_requested` | Available. Mirror for left-handed players: Ability 1. |
| **Left (Off-Hand)** | **Y Button** | `by_button` | Tap: `toggle_attacks`<br>Hold: `recenter_view` | Mirror for left-handed players: Ability 2. Or secondary Tree Menu toggle. |
| **Left (Off-Hand)** | **Grip (Squeeze)** | `grip`, `grip_click` | Two-handed grip on katana handle | **RESERVED**: Two-handed katana grip. |
| **Left (Off-Hand)** | **Trigger (Index)** | `trigger`, `trigger_click` | Unused in gameplay | **UI SELECT**: Pointer trigger for selecting skill tree nodes in VR Menu. |
| **Left (Off-Hand)** | **Thumbstick** | `primary` | Smooth locomotion (`MovementDirect.tscn`) | **RESERVED**: Smooth movement. |
| **Left (Off-Hand)** | **Thumbstick Click** | `primary_click` | Cycles element in test room | Unused in run. |
| **Left (Off-Hand)** | **Menu Button** | `menu_button` (`/user/hand/left/input/menu/click`) | Unbound in gameplay | **DEDICATED**: Open / Close VR Skill Tree Menu (Pause). |

#### Desktop Rig Bindings (`DesktopPlayer.gd`)

| Key / Mouse Input | Current Action | Planned Mapping for New System |
|---|---|---|
| **1 / 2** | Switch weapon (Katana / Kanabō) | Retain for weapon selection. |
| **Q** | High block (Parry pose) | Retain. |
| **F / G / T** | Slash horizontal / Overhead / Thrust | Retain scripted swings. |
| **X** | Wrist flick | Retain. |
| **Z** | Cycle element | Legacy test tool; replace with simulated Torii gate walk-through. |
| **1 (Keypad) / Num 1** or **Key 1 / Key 2** | New: Ability 1 / Ability 2 | **Mapped to `[J]` (Ability 1) and `[K]` (Ability 2)** for ergonomic desktop testing. |
| **Tab / M** | New: Open Skill Tree Menu | **Mapped to `[Tab]` or `[M]`** (toggles pause & tree menu). |

### 3. Root Cause Analysis: Why the Current System Feels Random

1. **Passive RNG Level-Up Distribution**: Elements are offered as random cards among stat cards when leveling up via soul orbs. The player cannot choose when or which school they enter; it depends purely on random card draws.
2. **Permanent Run Lock-In**: Once an element is picked, the player is locked into it for the remainder of the run. There is no rhythm of hunting, gaining, utilizing, and exhausting power.
3. **Passive Strikes vs. Active Agency**: In the current code, element effects fire as probabilistic or cooldown-based procs on blade contact (e.g. passive chain lightning on hit, passive ink splatter). The player swings their sword normally and things randomly explode or slow down, removing the feeling of intentional mastery.
4. **Complete Lack of In-Game Communication**: The blade changes color, but the HUD provides zero information about charges, cooldowns, or why an effect occurred. There is no feedback loop between player action and elemental release.

---

## (b) Game Design Rules & Mechanics

### 1. The Core Imbue Principle
- **One Element Limit**: The katana holds at most **ONE** element at a time (Sakura, Storm, Ink, or Shadow). Plain steel is the baseline default state (`Elements.NONE`).
- **Duration**: An element imbue lasts exactly **20.0 seconds** (`const ELEMENT_DURATION: float = 20.0`).
- **Decay & Fade Warning**: In the final 3.0 seconds, the blade's emissive intensity pulses (3 Hz oscillation), a faint hiss/whisper audio cue plays in 3D at the blade hilt, and the wrist element ring flashes before cleanly reverting to plain polished steel.
- **Empty Blade Behavior**: When the blade is plain steel, pressing Ability 1 or Ability 2 does **nothing mechanical**:
  - No popups, no floating error text, no red warning banners (anti-kitsch rule).
  - A subtle, muffled "empty" haptic click (`[[0.12, 0.04]]`) delivers instant tactile confirmation that the blade has no elemental energy.

### 2. The 4 Elements & 8 Active Abilities Specification

```
[Katana Imbued via Torii Gate]
           │
           ├─ Button A (Sword Hand) ──► Ability 1 (Offensive / Rapid / Ma-ai Control)
           └─ Button B (Sword Hand) ──► Ability 2 (Tactical / Mobility / Ultimate Stance)
```

#### Element 1: Sakura (桜) — "Beauty that cuts; glass petals and dance"
*Palette Accent: Neon Pink `Color(1.0, 0.30, 0.70)`*

- **Ability 1 (Button A): Senbonzakura (千本桜 / Thousand Petal Slash)**
  - **Effect**: A swift swing releases a razor-thin fan of 6 crystalline glass petals outward in the blade's cut direction, slicing through front-line enemies.
  - **Numbers**: 6 petals, 16 damage each (pierces up to 2 yōkai), effective range 8.0 m, arc spread 32°.
  - **Cooldown**: 4.0 seconds.
  - **VFX**: 6 QuadMeshes with `sakura_petal.gdshader`, luminous pink edges, 0.5 s lifetime, strictly pooled (`MAX_PETALS = 12`). Zero dynamic lights.
  - **SFX**: Sharp, crystalline glass whoosh (`res://assets/audio/combat/cc0_glass_slice.wav` equivalent, pitch 1.15, −6 dB).
  - **Haptics**: Crisp multi-pulse on sword hand: `[[0.75, 0.03], [0.35, 0.04], [0.15, 0.02]]`.

- **Ability 2 (Button B): Hanamai (花舞 / Petal Dance Barrier)**
  - **Effect**: Summons 4 glass petal blades that orbit closely around the player's torso at a 1.2 m radius for 6 seconds, cutting any enemy that steps into melee reach and reducing incoming claw damage by 30%.
  - **Numbers**: 4 orbiting petal meshes, 10 damage per contact (internal hit tick 0.35 s per enemy), 6.0 s duration.
  - **Cooldown**: 12.0 seconds.
  - **VFX**: 4 rotating unshaded quads with subtle pink trail ribbons; no light passes.
  - **SFX**: Gentle resonant wind chime with pink noise flutter.
  - **Haptics**: Warm rhythmic pulse in both hands upon activation: `[[0.5, 0.08], [0.25, 0.12]]`.

#### Element 2: Storm (雷) — "Speed, lightning arcs, and decisive thunder"
*Palette Accent: Electric Blue `Color(0.32, 0.82, 1.0)`*

- **Ability 1 (Button A): Raikiri (雷切 / Lightning Cutter)**
  - **Effect**: Electrifies the blade and releases a searing arc of chain lightning from the tip toward the nearest enemy in line-of-sight, which then forks to up to 3 nearby enemies.
  - **Numbers**: 32 damage to primary target, 18 damage to up to 3 chain targets within 5.0 m.
  - **Cooldown**: 3.5 seconds.
  - **VFX**: Instantaneous segmented `ImmediateMesh` bolt quads (white core + blue outer halo), 0.16 s lifetime. Pooled transient meshes (≤18).
  - **SFX**: Dry, high-voltage spark snap followed by a distant low-end thunder rumble.
  - **Haptics**: Intense, jagged haptic burst on sword hand: `[[0.9, 0.05], [0.4, 0.06], [0.8, 0.03]]`.

- **Ability 2 (Button B): Shiden (紫電 / Thunder Step)**
  - **Effect**: Instantaneous high-velocity dash 4.2 m forward in the look direction, passing through yōkai. Leaves a shockwave at the starting location that staggers surrounding enemies for 1.4 seconds.
  - **Numbers**: 4.2 m dash distance (clamped to terrain and stopped 0.5 m before tree colliders via raycast), 1.4 s stagger in 2.8 m radius at departure point.
  - **Cooldown**: 8.0 seconds.
  - **VFX**: Linear electric trace ribbon connecting departure and arrival points; 8 spark burst particles.
  - **SFX**: Sonic crack / thunder whip.
  - **Haptics**: Heavy simultaneous jolt in both controllers: `[[0.85, 0.04], [0.7, 0.08]]`.

#### Element 3: Ink (墨) — "Control, sumi-e wash, and lingering traps"
*Palette Accent: Glossy Deep Ink with Indigo Edge `Color(0.56, 0.68, 0.94)`*

- **Ability 1 (Button A): Sumi-gaeshi (墨返し / Ink Sweep)**
  - **Effect**: Horizontal wave of heavy black ink slashes along the ground in a 60° forward cone, painting a slowing ink pool that persists for 5.0 seconds.
  - **Numbers**: Cone range 4.5 m, 60° arc. Slows enemy movement speed by 60% and deals 7 damage/sec to enemies standing on the ink.
  - **Cooldown**: 5.0 seconds.
  - **VFX**: Decal-style terrain mesh with `ink_pool.gdshader` (normal blend, dark fluid look, max 6 pools active).
  - **SFX**: Heavy calligraphic brush stroke sound + wet fluid splash.
  - **Haptics**: Smooth, dense, low-frequency rumble: `[[0.6, 0.14]]`.

- **Ability 2 (Button B): Kage-nawa (影縄 / Ink Binding Tendrils)**
  - **Effect**: Dark calligraphic tendrils erupt from the ground beneath up to 3 enemies within 7.0 m, rooting them in place for 2.8 seconds and dragging them 1.5 m toward the player for an execution cut.
  - **Numbers**: Up to 3 targets in 7.0 m range. 2.8 s root duration, 14 impact damage, 1.5 m pull toward player.
  - **Cooldown**: 10.0 seconds.
  - **VFX**: 3 dark ink rope meshes with indigo highlights extending from floor to enemy chest for 0.4 s.
  - **SFX**: Tightening wet rope friction / silk tearing sound.
  - **Haptics**: Progressive pulling sensation: `[[0.3, 0.06], [0.5, 0.08], [0.8, 0.06]]`.

#### Element 4: Shadow (影) — "Trickery, mist, and sudden assassination"
*Palette Accent: Deep Violet `Color(0.78, 0.34, 1.0)`*

- **Ability 1 (Button A): Kagemusha (影武者 / Shadow Decoy)**
  - **Effect**: Leaves behind a life-sized silhouette of smoke and shadows at the player's current spot while cloaking the player in shadow-mist for 3.0 seconds. Enemies redirect their attacks to the decoy.
  - **Numbers**: Decoy lasts 3.0 s or until struck twice. Aggro redirect radius 9.0 m.
  - **Cooldown**: 9.0 seconds.
  - **VFX**: Semi-transparent dark violet silhouette mesh with `shadow_darkness.gdshader`, dissolves into drifting dark smoke when expired.
  - **SFX**: Subdued low resonant hum and faint shadow whisper.
  - **Haptics**: Soft double-pulse: `[[0.35, 0.04], [0.2, 0.08]]`.

- **Ability 2 (Button B): Yami-watari (闇渡り / Shadow Step & Cleave)**
  - **Effect**: Disappears into the floor shadows and instantly re-emerges behind the nearest target (or 4.0 m forward if no target), priming a guaranteed critical strike (+60% damage) on the next sword hit within 1.8 seconds.
  - **Numbers**: Target teleport distance up to 4.5 m (placed 1.1 m behind enemy back facing enemy). +60% damage buff on next hit within 1.8 s.
  - **Cooldown**: 7.5 seconds.
  - **VFX**: Violet shadow sinkhole at departure; quick flash of dark violet mist at arrival.
  - **SFX**: Vacuum suction pop followed by a sinister blade unsheathing tone.
  - **Haptics**: Inward dip followed by sharp exit snap: `[[0.25, 0.04], [0.9, 0.06]]`.

### 3. Controller Mapping Decision & Hand Ergonomics

- **Sword Hand (Primary Hand, Default Right)**:
  - **Button A (`ax_button`)** = **Ability 1 (Rapid / Tactical)**
  - **Button B (`by_button`)** = **Ability 2 (Special / Mobility)**
  - *Conflict Resolution*:
    - The old `ax_button` trigger for `reset_requested` is restricted to desktop debug mode (`F5` or `R`).
    - The old `by_button` single-tap toggle for enemy attacks is removed from VR gameplay (accessible via Pause UI).
    - The old `by_button` hold for `recenter_view` is moved to a 1.0-second long press on the **Left Menu Button**.
    - Weapon recall (`grip` + `by_button`) is preserved **only when the hand is empty** (`held == null`). Once the katana is grasped, A and B are strictly dedicated to abilities.
- **Off-Hand (Default Left)**:
  - **Menu Button (`menu_button`)** = **Open / Close Skill Tree Menu (Pause)**. Single tap cleanly pauses and unpauses the game.
  - **Button Y (`by_button` left)** = Secondary toggle for Skill Tree Menu (for players who prefer face buttons over the recessed menu button).
  - **Trigger (Index)** = VR Laser Pointer Select / Node Buy action inside the menu.
  - **Grip (Squeeze)** = Two-handed katana grip when brought close to the handle.
- **Left-Handed Accessibility**:
  - If the player grabs the katana with their left hand as their primary weapon hand, the roles mirror automatically: Left Hand X = Ability 1, Left Hand Y = Ability 2; Right Hand B = Skill Tree Menu.

### 4. Edge Cases: Explicit Decisions

| Edge Case Scenario | Formal Design & Technical Decision |
|---|---|
| **Gate of different element crossed while already imbued** | The **new element immediately replaces the old one**. The 20.0 s timer completely resets to 20.0 s. Old lingering transient effects (e.g. active ink pools) naturally finish their lifetime, but active abilities switch to the new element immediately. Cooldowns of abilities reset. |
| **Gate of the same element crossed while imbued** | The 20.0 s timer **refreshes back to 20.0 s**. Visual flash and chime confirm the replenishment. Existing ability cooldowns are reduced by 50% as a bonus. |
| **Element expires mid-ability execution** | **The active ability always completes its entire sequence**. For example, if Hanamai (Petal Barrier) has 2 seconds remaining when the 20 s imbue expires, the existing barrier finishes its 2 seconds, but the katana returns to plain steel and subsequent button presses trigger the empty click. |
| **Katana dropped or holstered** | **The timer and element KEEP RUNNING in real time**. Elements belong to the world and physics; an electrified or flaming blade lying on the wet moss continues to crackle and dissipate its charge. This prevents player exploits (e.g. dropping the sword to "save" an element for a boss). |
| **Player dies or run ends** | **Full instantaneous wipe**. Element resets to `NONE`, active abilities cancel, timer resets to 0.0 s, and all transient VFX pools are cleared immediately. |
| **The Oni Boss Fight** | Gates **remain active and functional during the Oni fight**. Two dedicated Torii gates spawn on the outer perimeter of the boss battle ring (~18–22 m from center), rotating elements every 45 seconds. This creates critical tactical choices: do you maintain close-quarters ma-ai with Oni, or disengage, sprint through a Torii gate under boss pressure, and return with a 20-second elemental advantage? |

---

## (c) Torii Gates: World Spawning & Streaming

### 1. Visual Aesthetics & GDD Art Direction
- **Authentic Shinto Architecture**: Built from the Bazylonator scanned PBR asset / procedural timber mesh with authentic vermilion wood, black lintel caps (*kasagi*), and stone bases (*kamebara*).
- **Element Accents (Never Gaudy, Never Disco)**:
  - **Sakura Torii**: Weathered dark vermilion lacquer, subtle pale blossom petals caught in gentle eddies at the lintel corners; soft rose lantern glow.
  - **Storm Torii**: Lightning-blackened petrified timber, faint hairline static discharges creeping along the beam; cool cyan paper lantern glow.
  - **Ink Torii**: Matte jet-black sumi lacquer, base shrouded in dark ground-clinging mist; deep indigo wash lantern.
  - **Shadow Torii**: Aged grey cypress (*hinoki*) timber with deep purple grain patination; soft violet lantern with smoke wisps.
- **Fog Readability without Cheap UI**:
  - **No floating arrows or radar markers**.
  - Readability through the fog is achieved diegetically via:
    1. A hanging stone lantern on the side of the gate with an authentic paper *andon* emission glow visible up to 35 m through the milk fog.
    2. A distinct vertical silhouette framed against the moonlight.
    3. A spatialized 3D audio fūrin (wind chime) + subtle elemental hum positioned at the gate lintel (`max_distance = 40.0 m`).

```
          [ Kasagi / Top Beam - Dark Slate ]
     ═════════════════════════════════════════════
          [ Shimaki / Tie Beam - Element Carving ]
     ─────────────────────────────────────────────
         │ │                               │ │
     (Lantern)                         (Lantern)
      [Glow]                            [Glow]
         │ │                               │ │
         │ │    ◄─── CLEAR PASSAGE ───►    │ │
         │ │        (≥ 2.8m width)         │ │
         │ │                               │ │
     ────┴─┴───────────────────────────────┴─┴────
                     [ Moss Terrain ]
```

### 2. Spawning & Collision Prevention Algorithm in `ForestWorld`
- **Minimum Clearance Zone**: A gate requires a clear bounding cylinder of **radius = 3.2 m, height = 4.5 m**.
- **Collider Mask Validation**:
  - Before committing a Torii gate transform, a multi-point spatial raycast / sphere cast is performed against `ForestWorld.TRUNK_LAYER` (layer 4) and environment obstacles.
  - Any procedural trees, lanterns, or boulders within 3.5 m are suppressed from the chunk's MultiMesh instance buffer.
- **Placement relative to paths**: Torii gates are oriented perpendicularly to the local slope gradient, creating natural arches over navigable paths.
- **Separation from Combat Spawns**: Torii gates must never spawn within 14 m of an active yōkai spawn node or the initial shrine spawn disc.

### 3. Infinite Forest Streaming & Guaranteed Availability
- **The Torii Gate Manager (`ToriiManager`)**:
  - Independent of individual chunk unloads. While forest foliage chunks stream in and out based on player distance, Torii gates are tracked in a persistent global coordinate registry.
  - **Distance Guarantee**: There is **always at least one active gate within 25–55 m** of the player at any given time.
  - If the player moves into an area where no gate is within 55 m, the world generator prioritizes spawning one in the next adjacent clearing ahead of the player's movement vector.
- **Fair Distribution (Shuffle Bag)**:
  - Gates draw their element from a 4-element shuffle bag `[Sakura, Storm, Ink, Shadow]`.
  - All 4 elements are guaranteed to appear across any 4 consecutive gate spawns. No annoying streaks of 3 identical gates.

### 4. Gate Crossing Plane Detection & Reactivation
- **Head/Body Crossing Only (No Sword Taps)**:
  - The gate defines a planar trigger volume: width 2.8 m, height 3.2 m, thickness 0.4 m.
  - The crossing is evaluated against the player's physical body tracking node (`PlayerBody` / `XRCamera3D`), **explicitly filtering out weapon colliders, held items, and hand controllers**.
  - A crossing event is registered when the vector between previous frame body position $P_{t-1}$ and current body position $P_t$ intersects the gate plane with a positive forward dot product:
    $$\text{sign}\left((P_{t-1} - G_\text{pos}) \cdot G_\text{normal}\right) \neq \text{sign}\left((P_t - G_\text{pos}) \cdot G_\text{normal}\right)$$
    and $P_t$ lies within the horizontal and vertical aperture bounds.
- **Deactivation & Reactivation Rule**:
  - Upon valid crossing:
    1. Imbue triggers immediately (sound stinger, katana glow ignition, haptic rush).
    2. The gate lantern extinguishes and the gate runes dim.
    3. The gate enters an **inactive state for 75 seconds** OR until the player travels **at least 80 meters away** from it and returns.
    4. An inactive gate cannot re-imbue the player, preventing cheesy back-and-forth oscillation.

---

## (d) Ofuda Currency & Per-Element Skill Tree

### 1. Ofuda Economy & Drop Balancing (5–10 min Run)

```
[Defeat Yōkai] ──► Drops Hitodama Orbs (XP) + Paper Ofuda Talismans (Currency)
                         │
                         ▼
             [Player Collects Ofuda via Magnet]
                         │
                         ▼
        [Open VR Skill Tree Menu via Left Menu Button]
                         │
                         ▼
            [Spend Ofuda to Unlock / Upgrade Nodes]
```

- **Drop Rates**:
  - Standard Yōkai: 35% chance to drop 1 Ofuda.
  - Claw / Armored Variant: 100% chance to drop 1 Ofuda.
  - Elite Yōkai: Guaranteed 3–4 Ofuda.
  - Oni Boss Phase / Defeat: Guaranteed 8–10 Ofuda.
  - *Expected Run Yield*: In a 5–7 minute run (approx. 35–50 kills), a player gathers **20–30 Ofuda**.
- **Collection Mechanism**:
  - Ofuda float slightly above ground as glowing paper charms with red cinnabar kanji.
  - They are drawn to the player using the existing `SoulMagnet` system, with a distinctive crisp paper rustle sound upon pickup.
- **Progression Scope**:
  - **Per-Run Progression (Roguelite)**: Ofuda and unlocked nodes reset upon player death or run completion, ensuring every run has a clean arc from raw steel to an ascendant elemental build.

### 2. Node Structure & Prerequisites (5 Nodes per Element Tree)

Each element has a dedicated 5-node tree. Upgrades are purchased in the VR Menu.

```
                  [Node 1: School Awakening] (Cost: 2 Ofuda)
                             │
            ┌────────────────┴────────────────┐
            ▼                                 ▼
   [Node 2: Ability 1 Focus]       [Node 3: Ability 2 Focus]
       (Cost: 4 Ofuda)                 (Cost: 4 Ofuda)
            │                                 │
            └────────────────┬────────────────┘
                             ▼
               [Node 4: Elemental Resonance]
                       (Cost: 6 Ofuda)
                             │
                             ▼
                [Node 5: Master Technique]
                       (Cost: 8 Ofuda)
```

#### Total Tree Cost: 24 Ofuda per Element.
In a single run, an attentive player can max out one entire elemental tree or split points across two schools.

#### Sakura (桜) Skill Tree
1. **Node 1: Petal Sense (花気)** — *Cost: 2 Ofuda*. Base damage of Senbonzakura (Ability 1) +25%; increases Sakura imbue duration from 20 s to 24 s.
2. **Node 2: Razor Petals (刃花)** — *Cost: 4 Ofuda* (Req: Node 1). Senbonzakura releases 8 petals instead of 6 and cuts through all targets in its path.
3. **Node 3: Storm of Hanami (花宴)** — *Cost: 4 Ofuda* (Req: Node 1). Hanamai (Ability 2) duration extended to 8.5 s; damage reduction increased to 45%.
4. **Node 4: Life Bloom (命咲)** — *Cost: 6 Ofuda* (Req: Node 2 or 3). Slashing any enemy while Sakura is active heals the player for 4 HP per hit; kill grants 12 HP.
5. **Node 5: Senbonzakura Kageyoshi (千本桜景厳)** — *Cost: 8 Ofuda* (Req: Node 4). Activating Senbonzakura while Hanamai is active causes all 4 orbiting petals to detonate in a 360° razor blossom burst (80 damage).

#### Storm (雷) Skill Tree
1. **Node 1: Static Conduit (導電)** — *Cost: 2 Ofuda*. Raikiri (Ability 1) chain targets increased from 3 to 5; Storm imbue duration increased to 24 s.
2. **Node 2: Thunder Splitter (雷破)** — *Cost: 4 Ofuda* (Req: Node 1). Raikiri cooldown reduced from 3.5 s to 2.5 s; primary target hit creates an instant stun.
3. **Node 3: Flash Stride (瞬歩)** — *Cost: 4 Ofuda* (Req: Node 1). Shiden (Ability 2) dash distance increased to 6.0 m; stagger duration increased to 2.2 s.
4. **Node 4: Overcharge (過負荷)** — *Cost: 6 Ofuda* (Req: Node 2 or 3). While Storm is active, standard katana cuts discharge minor chain lightning (12 dmg) on every strike.
5. **Node 5: Ikazuchi Avatar (雷神化身)** — *Cost: 8 Ofuda* (Req: Node 4). Shiden leaves a permanent lightning barrier between start and end points for 4 seconds that electrocutes any yōkai attempting to cross.

#### Ink (墨) Skill Tree
1. **Node 1: Sumi Mastery (墨法)** — *Cost: 2 Ofuda*. Ink pool slow effect increased from 60% to 75%; Ink imbue duration increased to 24 s.
2. **Node 2: Splatter Tide (墨浪)** — *Cost: 4 Ofuda* (Req: Node 1). Sumi-gaeshi (Ability 1) cone width increased to 90° and damage over time doubled.
3. **Node 3: Black Bind (黒縛)** — *Cost: 4 Ofuda* (Req: Node 1). Kage-nawa (Ability 2) can snare up to 5 targets simultaneously and pulls them directly into melee range.
4. **Node 4: Dragon Calligraphy (墨龍)** — *Cost: 6 Ofuda* (Req: Node 2 or 3). Enemies standing in ink take +35% damage from all sword strikes.
5. **Node 5: Abyssal Sea (墨海不尽)** — *Cost: 8 Ofuda* (Req: Node 4). Walking onto your own ink pools grants the player 20% movement speed boost and brief invulnerability (0.5 s).

#### Shadow (影) Skill Tree
1. **Node 1: Night Veil (夜帳)** — *Cost: 2 Ofuda*. Shadow Decoy (Ability 1) duration increased to 5.0 s; Shadow imbue duration increased to 24 s.
2. **Node 2: Phantom Retaliation (幻影報復)** — *Cost: 4 Ofuda* (Req: Node 1). When Shadow Decoy expires or is destroyed, it explodes in a shadow vortex dealing 45 damage to all nearby enemies.
3. **Node 3: Umbral Reach (影界)** — *Cost: 4 Ofuda* (Req: Node 1). Yami-watari (Ability 2) range increased to 6.5 m and cooldown reduced to 5.5 s.
4. **Node 4: Backstab Execution (暗殺極意)** — *Cost: 6 Ofuda* (Req: Node 2 or 3). Striking an enemy from behind while Shadow is active deals 2.5x critical damage and generates 1 bonus Ofuda.
5. **Node 5: Shadow Clones (影分身)** — *Cost: 8 Ofuda* (Req: Node 4). Yami-watari spawns two transient shadow clones that mimic the player's next sword cut on adjacent targets.

---

## (e) The VR Menu & Clean Pause Architecture

### 1. The Pause State Machine (`get_tree().paused = true`)
- **Strict Prohibition of `Engine.time_scale = 0`**:
  - `Engine.time_scale = 0` halts all delta updates, which causes tracking stutters, weapon jerks, and freezes XR rendering loops.
  - **Solution**: Use Godot's built-in scene tree pausing (`get_tree().paused = true`).
- **Node `process_mode` Classification**:

| Node Subsystem | `process_mode` Setting | Justification |
|---|---|---|
| **XR Rig (`XRPlayer`, `XROrigin3D`, `XRCamera3D`)** | `PROCESS_MODE_ALWAYS` | Must track player head and controllers in real-time at 90/72 Hz with zero latency during pause. |
| **VR Controllers & Hand Models** | `PROCESS_MODE_ALWAYS` | Hands must move fluidly to operate the UI pointer or poke interface. |
| **Skill Tree UI Panel & Pointer** | `PROCESS_MODE_ALWAYS` | UI animations, laser pointer raycasts, and button clicks must process smoothly. |
| **Held Katana (`HeldWeapon`)** | `PROCESS_MODE_ALWAYS` (Kinematic Freeze) | Rigidbody physics is temporarily frozen (`freeze = true`), and the weapon transform is locked directly to the hand anchor to prevent jitter. |
| **Yōkai Enemies & Active Ragdolls** | `PROCESS_MODE_PAUSABLE` | Completely frozen in place. No AI ticks, no movement, no physics solver execution. |
| **Wave Director & Spawn Timers** | `PROCESS_MODE_PAUSABLE` | No waves or enemy reinforcements spawn while menu is open. |
| **Element Imbue Timer** | Custom Timer in `ElementSystem` | Timer checks pause state or runs on pausable process; 20 s timer **halts completely while menu is open**. |
| **Environmental VFX & Rain Particles** | `PROCESS_MODE_PAUSABLE` | VFX freezes; zero draw call churn or particle budget inflation while browsing skills. |

### 2. Interaction with `TimeController` (Slow-Motion)
- If the game is already in slow-motion (e.g. from a parry or event):
  1. `SkillTreeMenu` records the current `Engine.time_scale` and the remaining duration on `TimeController`.
  2. Sets `get_tree().paused = true`.
  3. Upon menu close: `get_tree().paused = false`, and restores the exact stored `time_scale` and remaining slow-mo duration. No sudden time skips or physics explosions.

### 3. Audio Atmosphere During Pause
- **Low-Pass Filter Ducking**:
  - Automatically enables a `LowPassFilter` on the `Music` bus (cutoff frequency 750 Hz, resonance 1.0) and ducks music volume by −8.0 dB.
  - Ambience (rain, wind) is ducked by −6.0 dB.
  - Sfx bus remains crisp for menu UI clicks and paper rustles.
  - On unpause, audio parameters smoothly tween back to normal over 0.25 seconds.

### 4. Intro Guard
- `SkillTreeMenu` checks `RunGame.state`. The menu **cannot be opened during the Seiza Run Intro** (`RunGame.RunState.INTRO`). Any Menu button press is ignored until touchdown and katana draw are complete.

### 5. Anti-Clipping & Spatial Placement Architecture

```
                      [Eye Level / HMD]
                             │
                  Vector Forward (Yaw Only)
                             │
                             ▼  ~1.1 m
     ┌─────────────────────────────────────────────────┐
     │            VR SKILL TREE PANEL (3D)             │
     │  - Material: flags_no_depth_test = true         │
     │  - Render Priority: 100 (Always on top)         │
     │  - SphereCast Ray: Shortens distance if trunk   │
     │    is within 1.1m (e.g. settles at 0.75m)       │
     └─────────────────────────────────────────────────┘
```

- **Material Overlay (Always-On-Top Rendering)**:
  - The UI panel mesh uses a custom unshaded shader material with `render_mode unshaded, depth_test_disabled` (or `material_override.no_depth_test = true`) and `render_priority = 100`.
  - The laser pointer and cursor share this priority.
  - Result: **Even if the player opens the menu while standing nose-to-bark against a pine tree or boulder, the UI text, lines, and buttons never clip into or get occluded by the bark**.
- **Adaptive Forward Placement**:
  - When the Menu button is pressed, a forward sphere-cast (radius 0.25 m) checks space directly in front of the HMD up to 1.2 m.
  - If unobstructed, panel spawns at `HMD.origin + forward * 1.15 m`, with `y = clamp(HMD.origin.y - 0.05, 1.2, 1.7)`.
  - If a tree trunk or rock is detected at distance $D < 1.15\text{ m}$, the panel distance is safely clamped to $D - 0.2\text{ m}$ (minimum comfortable distance 0.65 m).
  - The panel is oriented towards the player using **Yaw only** (no pitch or roll tilt), creating a calm, grounded architectural posture.

### 6. Interaction Mode: Laser Pointer & Haptic Poke
- Left hand (or free hand) projects an elegant, thin crimson/gold laser beam (0.003 m width) terminating in a tiny reticle dot.
- Pointing at a node triggers a gentle hover tick (`[[0.15, 0.02]]`).
- Pulling the index trigger on an affordable node plays an ink-stamp sound stinger, executes the purchase, and fires a rewarding haptic confirmation (`[[0.6, 0.08]]`).

---

## (f) Readability & Diegetic In-Game Feedback

Everything the player needs to know is conveyed naturally in the game world without intrusive screen-space HUDs:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ DIEGETIC READABILITY CHANNELS                                               │
├───────────────────────┬─────────────────────────────────────────────────────┤
│ Current Element       │ 1. Blade trail, edge emissive glow, and mist coat.  │
│                       │ 2. Kanji crest glowing on the left wrist plate.     │
├───────────────────────┼─────────────────────────────────────────────────────┤
│ Remaining Time (20s)  │ 1. Circular countdown arc around the wrist crest.   │
│                       │ 2. Last 3 seconds: blade edge & trail pulse (3 Hz). │
├───────────────────────┼─────────────────────────────────────────────────────┤
│ Ability 1 & 2 Status  │ Two tiny engraved runes on the wrist mount next to  │
│                       │ the sword hand, filling like hourglasses as ready.  │
├───────────────────────┼─────────────────────────────────────────────────────┤
│ Ofuda Balance         │ Diegetic tally on the left wrist: "御札 × N".       │
├───────────────────────┼─────────────────────────────────────────────────────┤
│ Next Torii Gate       │ 1. Lintel lantern beam cutting through the fog.     │
│                       │ 2. 3D spatialized fūrin (wind chime) audio cue.     │
└───────────────────────┴─────────────────────────────────────────────────────┘
```

1. **Active Element on the Blade**:
   - Plain Steel: Clean, reflective PBR metal with rain droplets. No emission.
   - Sakura: Razor-bright neon pink edge luminescence and floating petal motes.
   - Storm: Crackling blue electric arcs running continuously between guard and tip.
   - Ink: Viscous, dripping black liquid with an indigo rim coating the blade bevel.
   - Shadow: Shifting dark violet haze with subtle refraction.
2. **Time Remaining Gauge**:
   - The left wrist plate (`DiegeticHud`) is upgraded with an elemental radial ring.
   - The ring starts at 100% full (360°) upon gate crossing and smoothly drains clockwise over 20.0 seconds.
   - In the last 3.0 seconds, the ring and the katana blade edge rhythmically flash bright/dim, signaling that reversion to steel is imminent.
3. **Button Ability Status**:
   - Two understated engraved symbols on the wrist plate represent Button A (Ability 1) and Button B (Ability 2).
   - If on cooldown, the symbol is dimly backlit; when ready, it flares with a crisp lacquer sheen.
4. **Ofuda Currency Counter**:
   - Displayed diegetically on the raised wrist face: `御札 [count]` in gold leaf calligraphy alongside existing soul and kill tallies.
5. **Torii Gate Direction**:
   - Seen at distance as a soft, atmospheric lantern spire in the milk fog.
   - Heard from up to 40 m away as an authentic copper temple chime (*fūrin*) ringing in the wind.

---

## (g) Legacy Code Deletion & Test Migration Strategy

### 1. Code to Delete or Majorly Refactor

- **`src/run/upgrade_pool.gd`**:
  - Delete `ELEMENT_UPGRADES` array and all code tying element schools to level-up choices (`available_element_upgrades`, `element_slot_count`, `ELEMENT_SLOT_LIMIT`).
  - Keep `GENERIC_UPGRADES` (damage, max HP, heal, soul magnet, attack speed, regen) for standard soul level-ups, or shift them to general stats.
- **`src/run/element_system.gd`**:
  - Remove `active_elements` array and "One element per run" permanent lock logic.
  - Implement single `current_element: String = Elements.NONE` and `element_timer: float = 0.0`.
  - Remove passive random procs from `on_blade_hit`.
  - Add explicit ability executors: `execute_ability_1()` and `execute_ability_2()`.
- **`src/run/run_game.gd`**:
  - Decouple `_apply_upgrade` from elemental binding.
  - Wire Torii gate crossing events directly to `element_system.imbue(element)`.
  - Add pause handling and `SkillTreeMenu` instantiation.
- **`src/run/forest_world.gd`**:
  - Replace static non-interactive torii multimesh placement with interactive `ToriiGate.tscn` scene instances managed by `ToriiManager`.

### 2. Tests to Replace in `tests/elements_test.gd`

| Old Test Assumption | Why Invalid | New Replacement Test in `tests/elements_test.gd` |
|---|---|---|
| `"A run locks into a single element; later elements are refused"` | In the new design, walking through a different gate intentionally replaces the element! | `"Walking through a different Torii gate immediately replaces current element and resets timer"` |
| `"One complete tree occupies three element slots"` | Element slots are removed in favor of the 20s dynamic gate imbue. | `"Torii gate imbues katana with 20.0s timer and reverts to plain steel upon expiry"` |
| `"Every eligible Ofuda hand exposes an element choice"` | Elements are no longer drawn in Ofuda cards. | `"Ofuda is earned as currency and spent strictly in the VR Skill Tree"` |
| `"Storm chains through several nearby yōkai"` (passive hit proc) | Now triggered actively by Button A (`execute_ability_1`). | `"Button A triggers Raikiri on Storm katana; does nothing on plain steel"` |
| `"Button on plain steel triggers empty feedback"` | New critical UX check. | `"Pressing Ability 1/2 on plain steel fires empty haptic pulse without errors"` |

---

## (h) Step-by-Step Implementation Roadmap (E2a – E2d)

```
┌────────────────────────────────────────────────────────────────────────┐
│ IMPLEMENTATION WORKFLOW                                                │
│                                                                        │
│  [E2a: Core Imbue & Torii Gates]                                       │
│       │ 20s state machine, ToriiGate scene, ForestWorld streaming      │
│       ▼                                                                │
│  [E2b: 8 Active Abilities & Controller Input]                          │
│       │ Buttons A & B, cooldowns, VFX/SFX pools, remove legacy procs   │
│       ▼                                                                │
│  [E2c: Ofuda Currency & Skill Tree Data]                               │
│       │ Enemy drops, 4x5 node prerequisite tree, ability upgrades      │
│       ▼                                                                │
│  [E2d: VR Menu, Clean Pause & Anti-Clipping]                           │
│       │ Tree panel, process_mode pause, laser pointer, no-clip shader  │
└────────────────────────────────────────────────────────────────────────┘
```

### Phase E2a: Element Core & Torii Gate World Spawning
- [ ] **E2a.1: Katana Imbue State Machine**: Update `HeldWeapon` and `ElementSystem` with `current_element`, `element_time_remaining`, `const ELEMENT_DURATION = 20.0`, fade warning state, and clean reversion to `Elements.NONE`.
- [ ] **E2a.2: Torii Gate Interactive Scene (`scenes/world/torii_gate.tscn`)**: Build authentic PBR gate with element-specific lantern/rune, body crossing detector (plane normal crossing), 75 s reactivation cooldown, and spatial chime audio.
- [ ] **E2a.3: Torii World Streaming & Clearance**: Integrate `ToriiManager` into `ForestWorld`. Ensure gates spawn 25–55 m from player, never collide with trees/rocks (sphere clearance 3.2 m), and persist through chunk streaming.
- [ ] **Critical Tests**:
  - `tests/torii_gate_test.tscn`: Crossing plane triggers imbue; sword touch alone does not trigger; same gate refreshes timer; different gate replaces element; 20 s timer expires to plain steel.
  - `tests/torii_placement_test.tscn`: No gate spawns overlapping trunk/boulder colliders; at least one gate exists in 55 m radius.
- [ ] **Quest Perf Risk**: MultiMesh terrain must cleanly exclude trees in the gate radius without regenerating entire chunk meshes. Torii lanterns must use unshaded emissive materials + ambient fill (zero dynamic OmniLight3D additions).

### Phase E2b: The 8 Active Abilities & Controller Bindings
- [ ] **E2b.1: Input Architecture**: Bind Button A (`ax_button`) to Ability 1 and Button B (`by_button`) to Ability 2 on the sword hand in `XRPlayer.gd` and `DesktopPlayer.gd` (`J` and `K`).
- [ ] **E2b.2: Empty Steel Protection**: Implement empty haptic click on unimbued katana with zero popup messages.
- [ ] **E2b.3: Ability Implementations**:
  - Sakura: Senbonzakura (6 glass petals) & Hanamai (orbiting barrier).
  - Storm: Raikiri (chain arc) & Shiden (dash & stagger).
  - Ink: Sumi-gaeshi (ground ink cone) & Kage-nawa (root tendrils).
  - Shadow: Kagemusha (decoy clone) & Yami-watari (blink & cleave).
- [ ] **E2b.4: Remove Old Procs**: Clean out legacy probabilistic hit procs from `element_system.gd`.
- [ ] **Critical Tests**:
  - `tests/element_abilities_test.tscn`: Each ability fires on the correct button, respects cooldown, consumes no element charges, and does nothing on plain steel.
  - `tests/vfx_pool_test.tscn`: All ability VFX respect Quest bounds (`MAX_PETALS <= 12`, `MAX_INK_POOLS <= 6`, `MAX_TRANSIENT_MESHES <= 18`).
- [ ] **Quest Perf Risk**: ImmediateMesh lightning and petal quads must be pooled and recycled. Maximum 2 transient meshes alive simultaneously.

### Phase E2c: Ofuda Currency & Skill Tree Data Architecture
- [ ] **E2c.1: Ofuda Item & Drops**: Create collectible 3D paper talisman drop; update `Yokai` death logic to drop Ofuda; integrate with `SoulMagnet`.
- [ ] **E2c.2: Skill Tree Data Model (`src/run/skill_tree_data.gd`)**: Implement 4 trees x 5 nodes with strict prerequisite validation and per-run reset.
- [ ] **E2c.3: Stat & Ability Wiring**: Connect unlocked nodes to modify ability parameters (cooldowns, damage, durations, healing).
- [ ] **Critical Tests**:
  - `tests/skill_tree_data_test.tscn`: Cannot purchase without sufficient Ofuda; cannot purchase Node 2 without Node 1; purchase correctly alters ability stats.
  - `tests/ofuda_drop_test.tscn`: Enemies drop correct Ofuda tallies; magnet draws them into player inventory.
- [ ] **Quest Perf Risk**: Ofuda pickups use shared QuadMesh with custom shader; maximum 16 active on-ground instances before auto-merging into high-value talismans.

### Phase E2d: VR Skill Tree Menu, Pause System & No-Clipping
- [ ] **E2d.1: Pause Manager**: Wire Left Menu button to `get_tree().paused = true`. Configure `process_mode = PROCESS_MODE_ALWAYS` on XR rig, controllers, hands, and UI. Kinematically freeze katana.
- [ ] **E2d.2: Audio Pause Ducking**: LowPassFilter (750 Hz) and −8 dB ducking on Music bus during pause.
- [ ] **E2d.3: 3D VR Panel & Laser Pointer**: Spatial UI panel positioned 1.1 m in front of player (yaw only). Left-hand laser pointer with trigger selection and hover haptics.
- [ ] **E2d.4: Anti-Clipping Guarantees**: UI panel and pointer materials set to `no_depth_test` / `render_priority = 100`. Forward sphere-cast adjusts panel distance if standing near obstacles.
- [ ] **Critical Tests**:
  - `tests/vr_menu_pause_test.tscn`: Opening menu freezes yōkai and element timer; XR tracking and UI continue processing smoothly; closing resumes cleanly; TimeController slow-mo state is preserved across pause.
  - `tests/ui_clipping_test.tscn`: Spawning panel inside/near a tree collider never renders geometry in front of the UI text.
- [ ] **Quest Perf Risk**: UI panel rendered as a single quad sampling a SubViewport or constructed with unshaded QuadMeshes to keep draw calls under 4.

---

## Harsh Self-Review & Integrity Audit

1. **Is it fun?**
   - *Yes*: Shifting from passive random procs to active button-press abilities (slashing razor petals, teleporting behind foes, chain lightning) gives players deep mechanical agency and mastery. The rhythm of hunting Torii gates in the foggy forest creates exhilarating natural micro-objectives during survival runs.
2. **Is it clear and readable?**
   - *Yes*: Zero screen-space clutter. The sword's blade aura, wrist circular countdown, and distant Torii lanterns tell the player everything at a glance without reading walls of text mid-combat.
3. **Is it premium and non-kitsch?**
   - *Yes*: No cartoon damage popups, no floating disco arrows, no "OUT OF AMMO" banners. Everything is framed through authentic Japanese swordsmanship, calligraphy (*sumi-e*), stone lanterns, weathered timber, and temple bells.
4. **Is it strictly Quest 3 compliant?**
   - *Yes*: All VFX are hard-capped and pooled. Torii gates use baked lighting and emissive textures rather than dynamic realtime point lights. The pause system preserves 90/72 Hz tracking without frame drops.
5. **Is it achievable in the hackathon timeframe?**
   - *Yes*: The modular separation into E2a, E2b, E2c, and E2d ensures clean, incremental, fully testable steps that build upon the existing solid physics and terrain architecture.
