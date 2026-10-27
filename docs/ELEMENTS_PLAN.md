# Elements & Skill Tree Architecture Plan (ELEMENTS_PLAN.md)
*Status: Approved Design & Specification (Task E1 — Post-Review Revision)*
*Author: Jakub Frączek / Antigravity*
*Date: 2026-10-27*
*Target Hardware: Meta Quest 3 standalone (72+ fps, ≤345 draw calls, ≤12 dynamic lights, ≤28 audio voices)*

---

## (a) Codebase Inventory & System Diagnosis

### 1. Existing Systems & File Responsibilities

| File Path | Core Classes & Key Functions | Current Role | Problems & Migration Target |
|---|---|---|---|
| `src/core/elements.gd` | `class_name Elements`<br>`color()`, `accent_color()`, `seal_index()`, `build_label()` | Element definitions (Sakura, Storm, Ink, Shadow, evolutions) and color palette queries. | Static definitions with hard-coded colors; assumes permanent dual-element combinations ("black_lightning", "phantom_petals") rather than dynamic single-element combat states. |
| `src/run/element_system.gd` | `class_name ElementSystem extends Node3D`<br>`setup()`, `reset()`, `apply_upgrade()`, `on_blade_hit()`, `on_enemy_died()`, `try_shadow_blink()`, `paint_ink()`, `debug_release_petals()`, `_rebuild_orbit_petals()` | Combat effects engine for elements; handles passive triggers on sword strikes and manages particle/mesh pools (`MAX_PETALS = 12`, `MAX_INK_POOLS = 6`, `MAX_TRANSIENT_MESHES = 18`). | **Passive and random**: effects trigger automatically on sword hit without player intent. Locks player into a single element for the whole run (`active_elements.size() >= 1`). Only Shadow has an active trigger (`try_shadow_blink`), which was hooked to thumbstick click. |
| `src/run/ofuda_talisman.gd` | `class_name OfudaTalisman extends Node3D`<br>`setup()`, `slice()`, `dismiss()`, `_build_labels()`, `_build_collider()` | Floating 3D paper talisman sliced by the blade during slow-motion level-up to pick an upgrade. | **DEPRECATED / REMOVED**: Slicing cards mid-combat breaks combat flow. Will be completely removed and replaced by physical collectible Ofuda currency spent in the VR Skill Tree Menu. |
| `src/run/upgrade_pool.gd` | `class_name UpgradePool extends RefCounted`<br>`GENERIC_UPGRADES`, `ELEMENT_UPGRADES`, `pick_choices()`, `available_element_upgrades()` | Generates 3 random choices upon level-up from generic cards and 3 tiers of element upgrades. | Randomizes element acquisition; mixing element unlocks with generic stat buffs makes element builds feel accidental rather than mastery-driven. |
| `src/run/diegetic_hud.gd` | `class_name DiegeticHud extends Node3D`<br>`attach()`, `update_hud()`, `_orient_wrist_face()` | Left wrist plate rendering HP ring, lacquer charm, soul XP bar, and stats (`rank`, `wave`, `score`, `kills`). | Accepts `active_element: String` in `update_hud` but **never renders or communicates the active element or remaining duration** to the player. No cooldown indicators. |
| `src/run/run_game.gd` | `class_name RunGame extends TestRoom`<br>`_present_level_up()`, `_on_ofuda_sliced()`, `_apply_upgrade()`, `collect_soul()` | Orchestrates run loop, soul drops, wave progression, level-ups, slow-mo transitions, and end screen. | Couples element acquisition directly to soul level-ups. Uses `TimeController.slow_motion(0.2, 120.0, true)` for card slicing. |
| `src/run/forest_world.gd` | `class_name ForestWorld extends Node3D`<br>`_populate_multimesh()`, `nearest_torii_position()`, `_build_torii_mesh()` | Infinite procedural terrain and prop streamer (trees, boulders, decorative torii). | Torii gates are static MultiMesh decorations with collider posts; they have no element affinity, no passing detection plane, and no interaction logic. |
| `src/weapons/held_weapon.gd` | `class_name HeldWeapon extends RigidBody3D`<br>`set_element()`, `on_blade_hit()` | Katana physics, PD controller, blade emission, and collision reporting. | Element is just a string that sets `BladeTrail` color; no state machine for expiration, warnings, or ability triggers. |

### 2. Full Controller Bindings Inventory & Migration Path

#### OpenXR Bindings (`openxr_action_map.tres` & `XRPlayer.gd`)

| Hand | Physical Control | OpenXR Action | Current Game Binding | New Target Binding & Migration Plan |
|---|---|---|---|---|
| **Right (Sword Hand)** | **A Button** | `ax_button` | Triggers `reset_requested` (dev reset) | **DEDICATED TO ABILITY 1 (Primary / Fast)**.<br>Old `reset_requested` moved to desktop keyboard `[R]` / `[F5]` and to the "Reset Stance / Run" button in the Pause Menu. |
| **Right (Sword Hand)** | **B Button** | `by_button` | Tap without grip: `toggle_attacks`<br>Hold: `recenter_view`<br>Hold + Stick Y: eye height<br>Grip + B: weapon recall | **DEDICATED TO ABILITY 2 (Special / Tactical)**.<br>- `recenter_view`: moved to 1.0s long press of the **Left Menu Button** and a button in the Pause Menu.<br>- Eye height: moved to Pause Menu Comfort settings.<br>- `toggle_attacks`: moved to `[P]` on desktop and debug menu.<br>- **Weapon Recall (`grip` + `B`)**: Works **ONLY when hand is empty** (`held == null`, see `WeaponHolder.gd:164`). When sword is in hand (`held != null`), B triggers Ability 2 with zero conflict. |
| **Right (Sword Hand)** | **Grip (Squeeze)** | `grip`, `grip_click` | Grab katana / hold katana (threshold > 0.6) | **RESERVED**: Core swordplay grip. When holding katana, grip stays squeezed. |
| **Right (Sword Hand)** | **Trigger (Index)** | `trigger`, `trigger_click` | Unused in sword hand (or poke interaction) | Available for secondary interaction / UI pointer when menu open. |
| **Right (Sword Hand)** | **Thumbstick** | `primary` | Snap turn (`MovementTurn.tscn`) | **RESERVED**: VR Locomotion (Snap Turn). |
| **Right (Sword Hand)** | **Thumbstick Click** | `primary_click` | Triggers `element_ability_requested` / cycles element in test room | Deprecated for combat abilities (unreliable ergonomics during full-arm swings). |
| **Right (Sword Hand)** | **Oculus / System Button** | `/user/hand/right/input/system/click` | Reserved by Meta OS | **FORBIDDEN**: System reserved. |
| **Left (Off-Hand)** | **X Button** | `ax_button` | Triggers `reset_requested` | Available. Mirror for left-handed players: Ability 1. |
| **Left (Off-Hand)** | **Y Button** | `by_button` | Tap: `toggle_attacks`<br>Hold: `recenter_view` | Mirror for left-handed players: Ability 2. Also acts as secondary Tree Menu toggle. |
| **Left (Off-Hand)** | **Grip (Squeeze)** | `grip`, `grip_click` | Two-handed grip on katana handle | **RESERVED**: Two-handed katana grip. |
| **Left (Off-Hand)** | **Trigger (Index)** | `trigger`, `trigger_click` | Unused in gameplay | **UI SELECT**: Pointer trigger for selecting skill tree nodes in VR Menu. |
| **Left (Off-Hand)** | **Thumbstick** | `primary` | Smooth locomotion (`MovementDirect.tscn`) | **RESERVED**: Smooth movement. |
| **Left (Off-Hand)** | **Thumbstick Click** | `primary_click` | Cycles element in test room | Unused in run. |
| **Left (Off-Hand)** | **Menu Button** | `menu_button` (`/user/hand/left/input/menu/click`) | Unbound in gameplay | **DEDICATED**: Tap = Open / Close VR Skill Tree Menu (Pause). Hold 1.0s = Recenter HMD View. |

#### Desktop Rig Bindings (`DesktopPlayer.gd`)

| Key / Mouse Input | Current Action | Planned Mapping for New System |
|---|---|---|
| **1 / 2** | Switch weapon (Katana / Kanabō) | Retain for weapon selection. |
| **Q** | High block (Parry pose) | Retain. |
| **F / G / T** | Slash horizontal / Overhead / Thrust | Retain scripted swings. |
| **X** | Wrist flick | Retain. |
| **Z** | Cycle element | Legacy test tool; replace with simulated Torii gate walk-through. |
| **J / K** | New: Ability 1 / Ability 2 | **Mapped to `[J]` (Ability 1) and `[K]` (Ability 2)** for ergonomic desktop testing. |
| **Tab / M** | New: Open Skill Tree Menu | **Mapped to `[Tab]` or `[M]`** (toggles pause & tree menu). |

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

### 3. Edge Cases: Explicit Decisions

| Edge Case Scenario | Formal Design & Technical Decision |
|---|---|
| **Gate of different element crossed while already imbued** | The **new element immediately replaces the old one**. The 20.0 s timer completely resets to 20.0 s. Old lingering transient effects (e.g. active ink pools) naturally finish their lifetime, but active abilities switch to the new element immediately. Cooldowns of abilities reset. |
| **Gate of the same element crossed while imbued** | The 20.0 s timer **refreshes back to 20.0 s**. Visual flash and chime confirm the replenishment. Existing ability cooldowns are reduced by 50% as a bonus. |
| **Element expires mid-ability execution** | **The active ability always completes its entire sequence**. For example, if Hanamai (Petal Barrier) has 2 seconds remaining when the 20 s imbue expires, the existing barrier finishes its 2 seconds, but the katana returns to plain steel and subsequent button presses trigger the empty click. |
| **Katana dropped or holstered** | **The timer and element KEEP RUNNING in real time**. Elements belong to the world and physics; an electrified or flaming blade lying on the wet moss continues to crackle and dissipate its charge. This prevents player exploits (e.g. dropping the sword to "save" an element for a boss). |
| **Player dies or run ends** | **Full instantaneous wipe**. Element resets to `NONE`, active abilities cancel, timer resets to 0.0 s, and all transient VFX pools are cleared immediately. |
| **The Oni Boss Fight** | Gates **remain active and functional during the Oni fight**. Two dedicated Torii gates spawn on the outer perimeter of the boss battle ring (~18–22 m from center), rotating elements every 45 seconds. This creates critical tactical choices: do you maintain close-quarters ma-ai with Oni, or disengage, sprint through a Torii gate under boss pressure, and return with a 20-second elemental advantage? |

---

## (c) Torii Gates: Spawning, Spacing, & Reactivation

### 1. Visual Aesthetics & Element Appearance (GDD Art Direction)
- **Authentic Shinto Architecture**: Built from classical timber construction with vermilion posts, black lintel caps (*kasagi*), and stone bases (*kamebara*).
- **Muted Element Appearance in GDD Palette Accents (Never Gaudy, Never Disco)**:
  - **Sakura Torii**: Weathered dark vermilion lacquer, subtle pale blossom petals caught at lintel corners; soft rose lantern glow `Color(1.0, 0.32, 0.74)`.
  - **Storm Torii**: Lightning-blackened petrified timber, faint hairline static discharges; cool cyan lantern glow `Color(0.32, 0.82, 1.0)`.
  - **Ink Torii**: Matte jet-black sumi lacquer, base shrouded in dark ground-clinging mist; deep indigo wash lantern `Color(0.56, 0.68, 0.94)`.
  - **Shadow Torii**: Aged grey cypress (*hinoki*) timber with deep purple grain patination; soft violet lantern glow `Color(0.78, 0.34, 1.0)`.
- **Fog Readability without UI Clutter**:
  - **No floating 2D arrows or mini-maps**.
  - Readability through the 10.5 m milk fog across 18–32 m distances is achieved diegetically via:
    1. **Volumetric Lantern Glow**: Hanging paper/stone *andon* lantern with unshaded emissive halo cutting through the milk fog up to 35 m.
    2. **Silhouette Framing**: Distinct vertical architectural silhouette framed against the moonlit canopy.
    3. **Spatialized 3D Audio Cue**: Authentic *fūrin* (wind chime) resonance on gate lintel (`max_distance = 40.0 m`).

### 2. Pacing & The 20-Second Loop Math

- **Movement Speed Analysis**:
  - Maximum linear locomotion speed: `3.0 m/s` (`movement_direct.gd: max_speed = 3.0`).
  - Realistic VR traversal speed (weaving through forest trunks, uneven terrain, and engaging yōkai): **1.2 – 1.6 m/s** (average **1.4 m/s**).
- **The Spacing Problem & Recalculation**:
  - If a gate were 55 m away, traversal at 1.4 m/s would require **~39 seconds**! With a 20 s imbue, the player would spend almost 20 seconds without an element, dropping element uptime to under 40%.
- **Corrected Gate Spacing**:
  - Gates are guaranteed to spawn within **18 – 32 meters** of the player (mean distance **~24 m**).
  - Traversal time at 1.4 m/s: `24 m / 1.4 m/s = ~17.1 seconds`.
- **Target Elemental Uptime**:
  - **Target: 65% – 75% of active run time spent imbued with an element**.
  - A player pushing steadily forward through the forest will have their element active almost continuously (refreshing or swapping), while a player standing ground to spar with yōkai has a brief, deliberate window of plain steel (5–9 seconds) before the next visible lantern draws them forward.
- **Verification & Measurement Metric**:
  - `RunGame` records `element_active_seconds` and `total_run_seconds`.
  - Uptime ratio: `element_uptime_ratio = element_active_seconds / max(total_run_seconds, 1.0)`.
  - Automated headless test (`tests/elements_test.gd`) simulates a standard 120-second combat-traversal segment and asserts:
    $$\text{element\_uptime\_ratio} \ge 0.65$$

### 3. Spawning & Collision Prevention Algorithm in `ForestWorld`
- **Minimum Clearance Zone**: A gate requires a clear bounding cylinder of **radius = 3.2 m, height = 4.5 m**.
- **Collider Mask Validation**:
  - Before committing a Torii gate transform, a multi-point spatial raycast / sphere cast is performed against `ForestWorld.TRUNK_LAYER` (layer 4) and environment obstacles.
  - Any procedural trees, lanterns, or boulders within 3.5 m are suppressed from the chunk's MultiMesh instance buffer.
- **Placement relative to paths**: Torii gates are oriented perpendicularly to the local slope gradient, creating natural arches over navigable paths.
- **Separation from Combat Spawns**: Torii gates must never spawn within 14 m of an active yōkai spawn node or the initial shrine spawn disc.
- **Shuffle Bag Guarantee**: Elements rotate via a 4-item shuffle bag `[Sakura, Storm, Ink, Shadow]` ensuring all 4 elements appear every 4 gates.

### 4. Gate Crossing Plane Detection
- **Head/Body Crossing Only (No Sword Taps)**:
  - The gate defines a planar trigger volume: width 2.8 m, height 3.2 m, thickness 0.4 m.
  - The crossing is evaluated against the player's physical body tracking node (`PlayerBody` / `XRCamera3D`), **explicitly filtering out weapon colliders, held items, and hand controllers**.
  - A crossing event is registered when the vector between previous frame body position $P_{t-1}$ and current body position $P_t$ intersects the gate plane with a positive forward dot product:
    $$\text{sign}\left((P_{t-1} - G_\text{pos}) \cdot G_\text{normal}\right) \neq \text{sign}\left((P_t - G_\text{pos}) \cdot G_\text{normal}\right)$$
    and $P_t$ lies within the horizontal and vertical aperture bounds.

### 5. Single Deterministic Reactivation Rule

```
[Active Gate] ──(Player Body Crosses Plane)──► Katana Imbued (20s)
                                                      │
                                                      ▼
[Inactive Gate: Lantern Dims, Chime Silenced] ◄───────┘
       │
       │ Player moves away through forest...
       ▼
 [Distance Check: player.global_position.distance_to(gate.pos) >= 45.0m]
       │
       ▼
[Gate Reactivates: Lantern Lights Up, Ready for Pass-Through]
```

- **The Single Rule: 45.0-Meter Distance Clearance**:
  - Upon valid crossing, the gate immediately deactivates: its lantern extinguishes, runes dim, and the spatial chime goes silent.
  - **The gate reactivates if and only if the player moves at least 45.0 meters away from it**:
    $$\text{player\_dist} = \|\vec{P}_\text{player} - \vec{P}_\text{gate}\| \ge 45.0\text{ m}$$
  - **No timers, no compound 'OR' conditions**:
    - Prevents camping in place (a player cannot stand under a gate and wait for it to recharge).
    - Fully deterministic and easily validated in unit tests (`gate.distance_to(player) >= 45.0 -> gate.is_active == true`).
    - If the player kites yōkai around a wide circle and returns to the gate, it will be recharged and ready to provide an escape imbue.

---

## (d) Ofuda Currency & Per-Element Skill Tree

### 1. Clarification & Removal of Legacy Level-Up Cards

- **Complete Elimination of the Old Card System**:
  - The legacy mechanic of slowing time on level-up and slicing three floating `OfudaTalisman` cards (`src/run/ofuda_talisman.gd`) is **completely deleted**.
  - Slicing cards broke combat immersion and confused the role of Ofuda.
- **Unambiguous Nomenclature & System Roles**:
  1. **Hitodama (Soul Orbs)**: Pure XP & score items. Collected magnetically, raising player level, scoring, and HP gauge on the wrist. They do **not** trigger slow-motion card slicing.
  2. **Ofuda (御札)**: **Physical collectible currency items**. Small 3D paper talismans (0.08 m x 0.16 m) with cinnabar ink seals dropped onto the ground by defeated yōkai.
  3. Gracz zbiera Ofuda do swojego ekwipunku (stan widoczny na nadgarstku jako `御札 × N`) i wydaje je **wyłącznie w 3D VR Skill Tree Menu**.

### 2. Ofuda Economy (5–10 min Run)

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

### 3. Node Structure & Prerequisites (5 Nodes per Element Tree)

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

### 4. Anti-Clipping & Spatial Placement Architecture
- **Material Overlay (Always-On-Top Rendering)**:
  - The UI panel mesh uses a custom unshaded shader material with `render_mode unshaded, depth_test_disabled` (or `material_override.no_depth_test = true`) and `render_priority = 100`.
  - The laser pointer and cursor share this priority.
  - Result: **Even if the player opens the menu while standing nose-to-bark against a pine tree or boulder, the UI text, lines, and buttons never clip into or get occluded by the bark**.
- **Adaptive Forward Placement**:
  - When the Menu button is pressed, a forward sphere-cast (radius 0.25 m) checks space directly in front of the HMD up to 1.2 m.
  - If unobstructed, panel spawns at `HMD.origin + forward * 1.15 m`, with `y = clamp(HMD.origin.y - 0.05, 1.2, 1.7)`.
  - If a tree trunk or rock is detected at distance $D < 1.15\text{ m}$, the panel distance is safely clamped to $D - 0.2\text{ m}$ (minimum comfortable distance 0.65 m).
  - The panel is oriented towards the player using **Yaw only** (no pitch or roll tilt), creating a calm, grounded architectural posture.

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

---

## (g) Legacy Code Deletion & Test Migration Strategy

1. **Delete `src/run/ofuda_talisman.gd`**: Slicing cards mid-combat is obsolete. Replace with `src/run/ofuda_pickup.gd` (collectible currency drop).
2. **Refactor `src/run/upgrade_pool.gd`**: Remove `ELEMENT_UPGRADES` array and level-up slot limits.
3. **Refactor `src/run/element_system.gd`**: Remove permanent run element lock. Implement dynamic single-element 20s state machine with button executors `execute_ability_1()` and `execute_ability_2()`.
4. **Refactor `tests/elements_test.gd`**: Replace legacy test assertions with new suite (20s timer, Torii crossing, element swap, button activation, plain steel empty feedback).

---

## (h) Step-by-Step Implementation Roadmap (E2a – E2d)

### Phase E2a: Element Core & Torii Gate World Spawning
- [x] **E2a.1: Katana Imbue State Machine**: Update `HeldWeapon` and `ElementSystem` with `current_element`, `element_time_remaining`, `const ELEMENT_DURATION = 20.0`, fade warning state, and clean reversion to `Elements.NONE`.
- [x] **E2a.2: Torii Gate Interactive Scene (`scenes/world/torii_gate.tscn`)**: Build authentic PBR gate with element-specific lantern/rune, body crossing detector (plane normal crossing), 45.0m distance reactivation rule, and spatial chime audio.
- [x] **E2a.3: Torii World Streaming & Clearance**: Integrate `ToriiManager` into `ForestWorld`. Ensure gates spawn 18–32 m from player, never collide with trees/rocks (sphere clearance 3.2 m), and persist through chunk streaming.
- [x] **Critical Tests**:
  - `tests/torii_gate_test.tscn`: Crossing plane triggers imbue; sword touch alone does not trigger; same gate refreshes timer; different gate replaces element; 20 s timer expires to plain steel; gate reactivates after 45m distance.
  - `tests/torii_placement_test.tscn`: No gate spawns overlapping trunk/boulder colliders; at least one gate exists in 18–32m radius; uptime ratio >= 0.65 in 120s test.
- [x] **Quest Perf Risk**: MultiMesh terrain must cleanly exclude trees in the gate radius without regenerating entire chunk meshes. Torii lanterns must use unshaded emissive materials + ambient fill (zero dynamic OmniLight3D additions).

### Phase E2b: The 8 Active Abilities & Controller Bindings
- [ ] **E2b.1: Input Architecture**: Bind Button A (`ax_button`) to Ability 1 and Button B (`by_button`) to Ability 2 on the sword hand in `XRPlayer.gd` and `DesktopPlayer.gd` (`J` and `K`). Ensure recall only activates when hand is empty (`held == null`).
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

### Phase E2c: Ofuda Currency & Skill Tree Data Architecture
- [ ] **E2c.1: Ofuda Item & Drops**: Create collectible 3D paper talisman drop (`src/run/ofuda_pickup.gd`); update `Yokai` death logic to drop Ofuda; integrate with `SoulMagnet`. Remove old `OfudaTalisman` level-up slicing.
- [ ] **E2c.2: Skill Tree Data Model (`src/run/skill_tree_data.gd`)**: Implement 4 trees x 5 nodes with strict prerequisite validation and per-run reset.
- [ ] **E2c.3: Stat & Ability Wiring**: Connect unlocked nodes to modify ability parameters (cooldowns, damage, durations, healing).
- [ ] **Critical Tests**:
  - `tests/skill_tree_data_test.tscn`: Cannot purchase without sufficient Ofuda; cannot purchase Node 2 without Node 1; purchase correctly alters ability stats.
  - `tests/ofuda_drop_test.tscn`: Enemies drop correct Ofuda tallies; magnet draws them into player inventory.

### Phase E2d: VR Skill Tree Menu, Pause System & No-Clipping
- [ ] **E2d.1: Pause Manager**: Wire Left Menu button to `get_tree().paused = true`. Configure `process_mode = PROCESS_MODE_ALWAYS` on XR rig, controllers, hands, and UI. Kinematically freeze katana.
- [ ] **E2d.2: Audio Pause Ducking**: LowPassFilter (750 Hz) and −8 dB ducking on Music bus during pause.
- [ ] **E2d.3: 3D VR Panel & Laser Pointer**: Spatial UI panel positioned 1.1 m in front of player (yaw only). Left-hand laser pointer with trigger selection and hover haptics.
- [ ] **E2d.4: Anti-Clipping Guarantees**: UI panel and pointer materials set to `no_depth_test` / `render_priority = 100`. Forward sphere-cast adjusts panel distance if standing near obstacles.
- [ ] **Critical Tests**:
  - `tests/vr_menu_pause_test.tscn`: Opening menu freezes yōkai and element timer; XR tracking and UI continue processing smoothly; closing resumes cleanly; TimeController slow-mo state is preserved across pause.
  - `tests/ui_clipping_test.tscn`: Spawning panel inside/near a tree collider never renders geometry in front of the UI text.

---

## Harsh Self-Review & Integrity Audit (Rule 9)

### 1. Pacing & Downtime Risk: "Boring plain steel running"
- **Critical Flaw in Initial Draft**: The original draft specified gates 25–55 m away. At 1.4 m/s in combat, reaching a 55 m gate takes ~39 seconds. With a 20 s duration, players spent ~50%–60% of their time running around with plain steel without any abilities, breaking the action-survivor power loop.
- **Root Remedy Applied in Plan**: Decreased gate spacing to **18–32 m** (average 24 m). Traversal time drops to 12–17 s. A player actively fighting and moving maintains **65%–75% elemental uptime**, transforming plain steel into a brief tactical tension window rather than a boring marathon. Added explicit automated test metric `element_uptime_ratio >= 0.65`.

### 2. Fog Navigation & Frustration Risk: "Lost in the milk fog"
- **Critical Flaw in Initial Draft**: The milk fog cuts visibility at 10.5 m (`RUN_FOG_END = 10.5`). While banning cheap 2D floating arrows respects the GDD, a gate at 28 m would be completely invisible in the fog, leaving the player lost and guessing which way to walk.
- **Root Remedy Applied in Plan**: Torii lanterns receive an unshaded volumetric emissive halo piercing the fog up to 25 m, paired with a spatialized 3D audio cue (*fūrin* wind chime, 40 m max reach) placed on the gate lintel. The player tracks gates through directional audio and atmospheric lantern glow, keeping navigation 100% diegetic and immersive without visual clutter.

### 3. Controller Ergonomics & Conflict Risk: "Accidental abilities & dropped swords"
- **Critical Flaw in Initial Draft**: Binding abilities to A and B risked breaking existing essential interactions: weapon recall, dev resets, and view recentering.
- **Root Remedy Applied in Plan**:
  - Verified `WeaponHolder.gd:164`: `recall` requires `held == null`. When holding the katana, pressing B activates Ability 2 with zero ambiguity. Recall only functions when disarmed.
  - `recenter_view` moved to a deliberate 1.0s long press of the Left Menu Button and a dedicated button in the Pause Menu.
  - Dev reset moved off VR buttons onto keyboard `[R]` and pause menu.

### 4. Quest 3 Thermal & Fill-Rate Bottleneck Risk
- **Critical Flaw in Initial Draft**: Adding interactive Torii gates as standard scene nodes with scripts and collision checks every frame could rapidly exceed the Quest 3 CPU/GPU frame budget (especially with tree raycasts during world generation).
- **Root Remedy Applied in Plan**:
  - Torii gates share a single instanced ArrayMesh and the existing static PBR `_torii_mat` (zero dynamic OmniLight3D nodes; illumination is pure unshaded emission and fog tinting).
  - Clearance checking runs only once when a gate is spawned into a chunk, caching valid transforms in the `ToriiManager`.
  - All ability VFX pools (`MAX_PETALS = 12`, `MAX_INK_POOLS = 6`, `MAX_TRANSIENT_MESHES = 18`) are pre-allocated and strictly capped.

### 5. Scope Bloat & Hackathon Feasibility Risk
- **Critical Flaw in Initial Draft**: Attempting to implement complex branching skill trees with 10+ nodes and intricate prerequisites would jeopardize shipping within the hackathon timeline.
- **Root Remedy Applied in Plan**: Limited each element tree to exactly 5 focused nodes (1 awakening, 2 ability augments, 1 passive, 1 master synergy). Every upgrade modifies existing properties on `HeldWeapon` or `ElementSystem` (damage multiplier, cooldown, radius, duration) rather than requiring whole new subsystems.
