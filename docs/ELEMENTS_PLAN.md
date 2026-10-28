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
| **Left (Off-Hand)** | **X Button** | `ax_button` | Triggers `reset_requested` | Mirror for left-handed players: Ability 1. |
| **Left (Off-Hand)** | **Y Button** | `by_button` | Tap: `toggle_attacks`<br>Hold: `recenter_view` | Mirror for left-handed players: Ability 2. (Strictly ability only; Tree Menu toggle is EXCLUSIVELY the Left Menu Button). |
| **Left (Off-Hand)** | **Grip (Squeeze)** | `grip`, `grip_click` | Two-handed grip on katana handle | **RESERVED**: Two-handed katana grip. |
| **Left (Off-Hand)** | **Trigger (Index)** | `trigger`, `trigger_click` | Unused in gameplay | **UI SELECT**: Pointer trigger for selecting skill tree nodes in VR Menu. |
| **Left (Off-Hand)** | **Thumbstick** | `primary` | Smooth locomotion (`MovementDirect.tscn`) | **RESERVED**: Smooth movement. |
| **Left (Off-Hand)** | **Thumbstick Click** | `primary_click` | Cycles element in test room | Unused in run. |
| **Left (Off-Hand)** | **Menu Button** | `menu_button` (`/user/hand/left/input/menu/click`) | Unbound in gameplay | **DEDICATED MENU TOGGLE**: Tap = Open / Close VR Skill Tree Menu (Pause). Hold 1.0s = Recenter HMD View. NEVER triggers abilities. |

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
  - **Numbers**: Target search radius 4.5 m (placed 1.1 m behind enemy back facing enemy); **designed blink displacement is clamped to ≤ 2.8 m** (bounded combat blink, never a long teleport). +60% damage buff on next hit within 1.8 s.
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
- [x] **E2b.1: Input Architecture**: Bind Button A (`ax_button`) to Ability 1 and Button B (`by_button`) to Ability 2 on the sword hand in `XRPlayer.gd` and `DesktopPlayer.gd` (`J` and `K`). Ensure recall only activates when hand is empty (`held == null`). Left Y is strictly Ability 2 mirror; tree menu toggle is exclusively the Left Menu button (`menu_button`).
- [x] **E2b.2: Empty Steel Protection**: Implement empty haptic click (`[[0.12, 0.04]]`) on unimbued katana with zero popup messages.
- [x] **E2b.3: Ability Implementations**:
  - Sakura: Senbonzakura (6 glass petals) & Hanamai (orbiting barrier).
  - Storm: Raikiri (chain arc) & Shiden (dash & stagger).
  - Ink: Sumi-gaeshi (ground ink cone) & Kage-nawa (root tendrils).
  - Shadow: Kagemusha (decoy clone) & Yami-watari (blink & cleave).
- [x] **E2b.4: Remove Old Procs & Ensure Ongoing Expiry Completion**: Clean out legacy probabilistic hit procs from `element_system.gd`. Ensure ongoing abilities (Hanamai, ink pools, decoy) finish their full duration upon element expiration.
- [x] **Critical Tests**:
  - [x] `tests/element_abilities_test.tscn`: Each ability fires on the correct button, respects cooldown, consumes no element charges, does nothing on plain steel, and finishes execution if element expires mid-ability.
  - [x] `tests/vfx_pool_test.tscn`: All ability VFX respect Quest bounds (`MAX_PETALS <= 12`, `MAX_INK_POOLS <= 6`, `MAX_TRANSIENT_MESHES <= 18`).

### Phase E2c: Ofuda Currency & Skill Tree Data Architecture
- [x] **E2c.1: Ofuda Item & Drops**: Create collectible 3D paper talisman drop (`src/run/ofuda_pickup.gd`); update `Yokai` death logic to drop Ofuda; integrate with `SoulMagnet`. `OfudaTalisman` (`src/run/ofuda_talisman.gd`) is **kept** as the slice-to-choose presenter for the six generic level-up cards and the restart talisman; what was removed is only the element/skill acquisition through those cards (`UpgradePool.ELEMENT_UPGRADES`). Ofuda currency never appears on a card: it is spent only in the tree menu.
- [x] **E2c.2: Skill Tree Data Model (`src/run/skill_tree_data.gd`)**: Implement 4 trees x 5 nodes with strict prerequisite validation and per-run reset.
- [x] **E2c.3: Stat & Ability Wiring**: Connect unlocked nodes to modify ability parameters (cooldowns, damage, durations, healing).
- [x] **Critical Tests**:
  - `tests/skill_tree_data_test.tscn`: Cannot purchase without sufficient Ofuda; cannot purchase Node 2 without Node 1; purchase correctly alters ability stats.
  - `tests/ofuda_drop_test.tscn`: Enemies drop correct Ofuda tallies; magnet draws them into player inventory.

#### E2c implementation decisions (2026-10-28)
- **Level-up keeps only generic cards.** The E2b review found element cards in
  `UpgradePool` were dead no-ops in `RunGame._apply_upgrade`. E2c removes
  `ELEMENT_UPGRADES` from the pool entirely: level-up offers only the six
  generic stat upgrades, each with a real effect, and `_apply_upgrade`
  ignores unknown ids without stacking them. `tests/elements_test.gd`
  asserts seeded hands contain no element/dead card and that every generic
  applies its effect. The `OfudaTalisman` slicing UI therefore remains only
  as the generic-choice and restart presenter; element acquisition through
  slicing is gone, and Ofuda currency is spent exclusively via the tree.
- **Currency vs. cards are physically distinct.** Ofuda currency is the new
  `OfudaPickup` (0.08 m × 0.16 m ground drop, cinnabar seal), dropped by
  yōkai (swarm 35% ×1, elite 3–4, Oni 8–10; expected 20–30 per 5–7 min run)
  and magnet-collected with the Hitodama rule. The wallet is
  `RunGame.ofuda_count`; the single spending path is
  `RunGame.unlock_skill(node_id)`, which returns the `SkillTreeData`
  verdict (`ok` / `missing_prerequisite` / `insufficient_ofuda` /
  `already_unlocked` / `unknown_node`) plus the balance — the exact API the
  E2d VR menu will call. The wrist plate shows `札×N`.
- **Tree shape & economy.** 4 trees × 5 nodes, costs 2/4/4/6/8 = 24 Ofuda
  for a full tree: affordable in one 5–10 minute demo run without making
  the first node a grind (Node 1 after ~6 swarm kills on average). Node 4
  requires Node 2 OR Node 3; Node 5 requires Node 4. Bank and unlocks are
  per-run: reset on run start and on death.
- **Wiring, not flags.** `ElementSystem` reads upgraded parameters live via
  `SkillTreeData.effect_value` (imbue 20→24 s, Senbonzakura 6→8 petals and
  16→20 dmg, Raikiri cooldown 3.5→2.5 s and 3→5 chains, Shiden 4.2→6.0 m
  plus the Ikazuchi barrier, ink slow 60%→75%, Kage-nawa 3→5 targets,
  decoy 3→5 s with retaliation explosion, backstab ×2.5 + bonus Ofuda,
  shadow clones, Life Bloom healing, Abyssal ward + speed). Torii gates now
  call `imbue(element)` so the duration node applies; explicit durations
  (tests, refresh) are still honoured.

### Phase E2d: VR Skill Tree Menu, Pause System & No-Clipping
- [x] **E2d.1: Pause Manager** (`src/ui/pause_controller.gd`): Left Menu tap (and `Tab`/`M` on desktop) toggles the menu and `get_tree().paused`. XR rig, controllers, hands, pointer, menu, wrist HUD, music/ambience are `PROCESS_MODE_ALWAYS`; `PlayerHealth` opts back out. The held katana is frozen kinematic and glued to the hand's target pose each frame, then `snap_to_hand()` on close.
- [x] **E2d.2: Audio Pause Ducking** (`Sfx.set_pause_ducking`): LowPassFilter 750 Hz + −8 dB on Music, −6 dB Ambience, World/Sfx bus untouched, 0.25 s real-time fade both ways; composes with the slow-mo duck.
- [x] **E2d.3: 3D VR Panel & Laser Pointer** (`src/ui/skill_tree_menu.gd`, `skill_tree_canvas.gd`): panel 1.1 m in front (yaw only), the whole tree of every element (costs, prerequisites, owned/available/locked, balance 札). Pointers on **both** controllers (trigger = select; hover haptics); desktop uses the view centre or the mouse. Buying is a two-step action (select node → UNLOCK) and goes only through `RunGame.unlock_skill()`.
- [x] **E2d.4: Anti-Clipping Guarantees** (`src/ui/ui_placement.gd`): see decisions below.
- [x] **Critical Tests**:
  - `tests/vr_menu_pause_test.tscn` (real `XRPlayer` through `XrSim`, `-- --xr-sim`): Left Menu tap opens/closes; yōkai, element timer, cooldowns, run clock, regeneration, waves, particles stand still; A/B fire nothing, stick and snap turn are off; headset, hand and the frozen katana keep tracking; both-hand pointers switch school, select and buy; locked/unaffordable refused for free; slow-mo survives a pause with the exact remaining time; the menu refuses INTRO/LEVEL_UP/GAME_OVER and closes on death; music low-pass/duck; Abyssal Sea XR speed and the brief ward; UI code has no second spending path.
  - `tests/ui_clipping_test.tscn`: panel next to a tree (nose-to-bark and arm's length), walls at three distances, torii pillars from nine stances, a standing yōkai, hills (24 stances) — nothing within 5 cm of the panel, otherwise flagged and drawn on top; level-up cards hang clear of a tree, a boulder and a torii gate; material flags (fog, priority).
  - `tests/quest_perf_test.tscn` extended: menu open adds ≤ 6 draw calls, no lights, viewport updates on change only.

#### E2d implementation decisions (2026-10-28)
- **Pause = `get_tree().paused`, plus `TimeController.suspend()`.** Slow-mo effects are parked (their clock stops) and `Engine.time_scale` reads 1.0 while paused, so the always-processing rig is not slowed by a parry slow-mo; `resume()` restores the exact scale and remaining time. The menu does not open during INTRO, LEVEL_UP (card choice is modal) or GAME_OVER; a death/restart closes it.
- **Physics.** `SceneTree.paused` also deactivates the physics space; XR Tools' `PlayerBody` keeps working under it (verified: no sinking), locomotion providers are switched off. `WeaponHolder` skips grab/release while paused (applies on close). `XrSim` is `ALWAYS` like a real runtime.
- **Depth testing: normal by default, on-top as the fallback.** The plan asked for `no_depth_test` everywhere. A panel drawn over its depth would also be drawn over the player's own hand and blade in front of it — an occlusion violation that is uncomfortable in stereo. So the panel is depth-tested (hands and blade correctly occlude it) and **guaranteed clear of geometry by placement**; `no_depth_test` + `render_priority 100` is engaged only when placement finds no clear spot (`blocked`). The pointer beam/reticle (priority 103/104) and the panel (100) never test depth against the world and `disable_fog` is on, so the menu stays crisp in the milk fog.
- **Placement (`UiPlacement.place`).** Straight ahead at 1.1 m if free; otherwise pulled in front of the obstacle (obstacle distance − 0.2 m, never nearer than 0.65 m) and **scaled** by distance/1.1 so it keeps its apparent size; otherwise turned up to ±50° (more would leave the field of view); otherwise `blocked`. Each candidate must pass a box query (panel size + 0.1 m side margin, 0.4 m deep) and nine sight lines from the eyes, against static world, trunks, gates, boulders and yōkai bodies. A thin wall between player and panel is caught by the sight lines (found by the test). Height: eye level − 0.12 m within 1.1–1.7 m above the ground under the player and ≥ 0.25 m above the ground under the panel (hills).
- **Level-up cards.** `RunGame._clear_frame` now also probes the physics world (static world, trunks, gates) at each card spot, not only the forest's trunk registry — a torii gate (not in that registry) could swallow a card (found by the test, mutation-checked). Yōkai are deliberately not part of that probe (an enemy walking by must not swing the cards around). The wrist plate is an object on the player's own arm and is not placed by this code.
- **Typography.** Cinzel (SIL OFL, 125 KB) for Latin text with Yuji Boku as the kanji fallback: Yuji Boku's Latin was hard to read at menu sizes. Credits and licence updated. The panel uses toned-down school colours (rose, steel, slate, amethyst), not the neon VFX accents.
- **Abyssal Sea review fixes.** `RunGame.apply_locomotion_speed` drives desktop `move_speed` and the XR `MovementDirect.max_speed` (test: ×1.2 in own ink, back to ×1.0 outside). The ward was full immunity for as long as the player stood in ink; the plan says "brief invulnerability (0.5 s)", so it is now 0.5 s granted on **entering** ink and re-arms after 4 s.
- **Known limits.** Nothing is occluded by the menu except through depth (an enemy that moves between player and panel is impossible while paused). On a Quest the always-on `MenuButton` hold-for-recenter still takes 1 s; a tap is ≤ 0.35 s (real time, also in slow-mo).

---

### Phase E3: Readability & Feel
- [x] **E3.1: Blade light per element** (`katana_steel.gdshader`, `blade_body.gd`): an edge light on the cutting edge plus a faint rim, never a flat wash. Sakura rose + slow breathing, Storm cyan with short crackling arcs, Ink a wet black coat with an indigo hairline, Shadow violet breath with rising wisps. The imbue runs guard-to-tip in 0.38 s with a brief front, a gate top-up only flashes, expiry drains over 0.6 s (real time). Last 3 s: blade, trail and wrist crest beat at 3 Hz from the *imbue clock* (so they hold in a pause).
- [x] **E3.2: Imbue sound**: five procedural CC0 cues (`imbue_sakura/storm/ink/shadow`, `element_fade`; `scripts/generate_hanabi_proc_audio.py --imbue-only`), played quietly at the sword hand; a refresh is softer and higher.
- [x] **E3.3: Wrist element strip** (`wrist_element.gdshader`, `diegetic_hud.gd`): under the HP row, towards the elbow. Crest (kanji; ring = imbue left, clockwise from 12), the seconds left, and one ring per button (A left, B right) with the ability's glyph (千舞 切電 返縄 武渡): full bright ring = ready, partial = recharging. Plain steel: dim 門 ("seek a gate") and empty rings. The 札×N tally stays on the raised-wrist text. Still one quad + three labels; the gilt frame is now one mesh (net −3 meshes).
- [x] **E3.4: Gate light** (`torii_lantern_halo.gdshader`, `torii_gate.gd`): the halo is *mixed* over the fog (additive washed out to white), with a thin vertical shaft so a gate is a line in the mist, scaling with distance past 9 m so it keeps its apparent size at 28 m, a slow breath, per-gate phase. Lit lantern is an unshaded paper andon that ignores fog; a spent gate flares for 0.7 s, drains in 0.9 s to a dull lantern that fades into the fog, and wakes over 2 s when it reactivates.
- [x] **E3.5: Menu**: eases in over 0.16 s (alpha only, hit-testing unaffected); the footer carries the blade's element, seconds left and both buttons (A/B, glyph, name, ready or seconds), the header the Ofuda.
- [x] **E3.6: Draw-call headroom**: `RunPerfProbe.estimate_scene_cost` counted every node with its own `visible` flag, including whole hidden subtrees (arena props, the stowed kanabō, the finished intro: ~55 meshes). It now counts `is_visible_in_tree()`. Stressed run: 341 → 287 estimated draws (menu open 288 of 345); a new check keeps ≥ 30 of headroom with the menu open and the wrist plate ≤ 9 meshes.
- [x] **Tests (extended, none added)**: `element_abilities_test` (blade kind/colour per element, crest/glyphs, arc and ring values, A empties on firing, 3 Hz warning on blade and crest, refresh, expiry fade + cue, plain steel), `torii_gate_test` (flare, drain, wake, fog flags), `vr_menu_pause_test` (ease-in, footer state, same state when drawn on top), `quest_perf_test` (headroom, plate meshes, no gate lights), `wrist_hud_test` (whole new plate clears the hand).

#### E3 implementation decisions (2026-10-28)
- **On-top menu vs the wrist plate.** An opaque plate cannot be drawn *after* a no-depth-test panel without changing its materials, and forcing it over the panel would also draw it through the hand. Instead nothing important lives only on the plate: the panel footer/header repeat element, time, A/B and Ofuda, so the on-top fallback hides nothing the player needs. In the normal (depth-tested) mode the raised wrist, being nearer than the panel, correctly occludes it.
- **Fog.** Fog stays. Gate light is mixed (not added), saturated per element (the Ink gate's dark indigo is darker than the fog), lit lanterns and halos ignore fog, spent ones do not. Yōkai silhouettes in fog were not touched.
- **Known weak spots (honest).** Seen from behind, the thin blade reads as coloured steel more than an edge light; Storm is pastel rather than electric. The 6 m lantern is a flat paper box. The sound cues are synthesised and untested on real headphones. Pip glyphs are ~7 mm: legible on a raised wrist, not at arm's length.

### Phase E4: Balance, Economy, Visual Polish & Cleanup
- [x] **E4.1: Central ElementBalance constants** (`src/run/element_balance.gd`): Single authority for all tuning numbers (`const IMBUE_SECONDS := 20.0`, `IMBUE_NODE_BONUS_SECONDS := 4.0`, `FADE_WARNING_SECONDS := 3.0`, `REFRESH_COOLDOWN_KEEP := 0.5`, `POWER_PER_RANK := 0.04`, damage, cooldowns, durations, ranges, Ofuda drop rates). Read by `ElementSystem`, `SkillTreeData`, `BladeBody`, and `tools/balance_model.gd` — code and balance model cannot drift.
- [x] **E4.2: Ability Tuning & School Identity**:
  - **Sakura 桜**: Pack cutter and sustain. Senbonzakura (A1: 4.0 s cd, 6→7 petals, 12→15 dmg, 2→all pierce, 32°/8 m fan) & Hanamai (A2: 13.0 s cd, 4 petals, 6.0→8.5 s duration, 7 dmg/hit, 30%→45% damage reduction, Life Bloom 4/12 HP heal, Kageyoshi 100 dmg 3.2 m detonation).
  - **Storm 雷**: Fast burst and repositioning. Raikiri (A1: 3.5→2.5 s cd, 45 dmg primary, 24 dmg to 3→5 chain targets within 5 m, 1.0 s stun on T2) & Shiden (A2: 8.0 s cd, 4.2→6.0 m dash, 1.4→2.2 s stagger in 2.8 m radius, Overcharge 14 dmg katana arcs, Ikazuchi 4.0 s / 20 dmg line barrier).
  - **Ink 墨**: Battlefield zoning and control. Sumi-gaeshi (A1: 5.0 s cd, 4.5 m 60°→90° cone, 7 dmg, 60%→75% slow, 5 s ground pool with 8→16 DPS) & Kage-nawa (A2: 10.0 s cd, 3→5 targets rooted 2.8 s, 20 dmg, 1.5 m pull, Dragon Calligraphy +35% sword damage on inked yōkai, Abyssal Sea +20% run speed + 0.5 s ward).
  - **Shadow 影**: High-lethal duelist. Kagemusha (A1: 9.0 s cd, 4.0→6.0 s decoy, absorbs 2 claw strikes, 60 dmg / 3.0 m vortex explosion on expiry) & Yami-watari (A2: 6.5→5.0 s cd, 4.5→6.5 m shadow blink, ×2.2 crit multiplier on next cut within 2.5 s, Backstab ×2.5 crit + 1 bonus Ofuda [6 s throttle], 2 shadow clones copying blade cut).
- [x] **E4.3: Soul Rank & Razor Edge Scaling** (`ElementSystem.ability_power`): Abilities scale dynamically via `razor_edge_multiplier * (1.0 + POWER_PER_RANK * (soul_rank - 1))`. At Soul Rank 10 (~10 min run), ability potency reaches ~1.36× (or ~2.0×+ with Razor Edge stacks), keeping up with yōkai wave HP growth (+14%/wave) while ensuring sword momentum remains the primary killing force.
- [x] **E4.4: Ofuda Economy & Progressive Pacing**:
  - Drop rates: Swarm yōkai 25% chance of 1 Ofuda, Elite yōkai 1–2 Ofuda, Oni boss 5–6 Ofuda.
  - Node costs: 3, 5, 5, 8, 12 Ofuda per tier (total 33 Ofuda per school, 132 Ofuda for all 4 trees).
  - Pacing verified by `tools/balance_sim.gd`:
    - ~1 min: Node 1 (3 Ofuda, ~15 kills) — early school awakening.
    - ~2–3 min: Node 2 & 3 (8–13 Ofuda, ~30–40 kills) — core ability upgrades.
    - ~5 min: Node 4 (21 Ofuda, ~60 kills) — major passive synergy.
    - ~5–6 min: Node 5 (33 Ofuda, ~70–80 kills) — ultimate avatar capstone.
    - 10 min demo run: 75–100+ Ofuda accumulated, enabling one complete master tree plus deep progression into a second school.
- [x] **E4.5: Dead Code Removal**:
  - Purged deprecated dual-element evolution system (`black_lightning`, `phantom_petals`, `evolution_mask`) from `src/core/elements.gd` and `src/weapons/blade_body.gd`.
  - Removed dead state variables: `storm_charge`, `blink_cooldown`, legacy `try_shadow_blink` aliases.
  - Removed outdated screenshot test scenes (`tests/run_screenshots.tscn`, `tests/run_screenshots.gd`).
- [x] **E4.6: Visual & Asset Polish (Addressing E3 Review)**:
  - **Electric Storm Arcs**: Enhanced `src/shaders/katana_steel.gdshader` and `src/run/element_system.gd` to render saturated electric cyan/blue arcs and outline (`Color(0.2, 0.65, 1.0)` / `Color(0.4, 0.85, 1.0)`) with white highlights only at the highest peaks, eliminating the pastel appearance.
  - **Blade Fresnel Rim Pass** (`src/shaders/blade_rim.gdshader`): Added a dynamic mixed fresnel rim pass to `BladeBody` active exclusively while imbued (+1 draw call, tracked by `RunPerfProbe`). Ensures the katana edge is vividly defined and reads as glowing cutting light from all camera angles, including behind the spine.
  - **Hexagonal Torii Lantern**: Replaced the placeholder 6 m cubic box with an authentic 6-sided hexagonal paper andon featuring pitched roof eaves and structural paper rib frames (`src/world/torii_gate.gd`), matching Edo-period shrine aesthetics without adding draw calls.
- [x] **E4.7: Headless Balance Model & CI Guardrails**:
  - Created `tools/balance_model.gd` and `tools/balance_sim.gd` (<1 s execution time).
  - Extended `tests/skill_tree_data_test.gd` and `tests/element_abilities_test.gd` with guardrails verifying kit power budgets, ability-to-sword damage ratios, cooldown health, and tree prerequisites.
  - Updated `tools/run_tests.sh` to enforce zero script errors.

#### E4 implementation decisions (2026-10-28)
- **Single Source of Truth (`ElementBalance`).** Previously, imbue duration was hard-coded in multiple files (`HeldWeapon`, `ElementSystem`, `SkillTreeData`). All elemental numbers are now unified in `ElementBalance`. The baseline imbue is strictly 20.0 s, Node 1 extends it to 24.0 s, and the last 3.0 s trigger the 3 Hz sensory warning.
- **Abilities as Accelerators, Not Replacements.** The balance model ensures abilities complement physical swordplay. For a single enemy, an elemental kit contributes 15%–40% of baseline sword damage; against packs of 4 enemies, AoE abilities scale up to 75%–160% of sword output. Katana strikes remain the core kinetic loop.
- **Kagemusha Decoy Durability.** Fixed a bug where the decoy was immortal during its timer; it now properly absorbs up to 2 direct claw strikes before detonating, creating high tactical value without breaking enemy AI.
- **Headroom & Performance Verification.** All visual upgrades (rim pass, hexagonal lantern, high-contrast arcs) strictly respect Quest 3 limits: `quest_perf_test` verifies 288/345 peak draw calls (57 draw calls of headroom), 0 dynamic OmniLights added by gates, and ≤9 meshes on the wrist plate.

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

---

## D1 – ofuda z kapliczek (Hokora)

### Krok 0: diagnoza (wszystkie miejsca, gdzie gracz widzi lub zbiera „ofuda" / 御札)

Zweryfikowane w kodzie. Cztery źródła, jedna nazwa:

| # | Miejsce | Co gracz widzi | Stan przed D1 |
|---|---------|----------------|---------------|
| a | `RunGame._present_level_up()` (`run_game.gd`) | 3 latające `OfudaTalisman` z 御札 w nagłówku, slow-mo 0.2×, wybór staty (`UpgradePool`) | **aktywne**, mimo że GDD §6 mówi, że to wycofane |
| b | `ofuda_drop_count_for()` + `_spawn_ofuda_drops()` (yōkai 25 %, elita 1–2, Oni 5–6) | fizyczne 御札 na ziemi po każdym zabiciu | aktywne |
| c | węzeł `backstab_execution` → `backstab_ofuda` (`element_system.gd`) | bonusowe 札 przy ciosie od tyłu | aktywne |
| d | `RunGame._build_end_screen()` → `restart_ofuda` | kartka „御札 · NEW RUN" na ekranie śmierci | aktywne |

Dodatkowo: tekst błędu drzewka `skill_tree_menu.gd` („Gather more Ofuda from slain yōkai") wprost mówi, że walutę daje zabijanie.

**Co dokładnie myli gracza (2–3 zdania):** to jest jedno słowo na dwie różne rzeczy. Kartki z 御札 wybierane w slow-mo dają *ulepszenia*, a fizyczne 御札 na ziemi i licznik `札×N` na nadgarstku to *waluta* do drzewka – ale wyglądają tak samo i oba się zbierają/tną. Do tego ekran śmierci pokazuje kartkę 御札 „NEW RUN", a w drzewku ta sama nazwa oznacza wydawanie. Gracz nie wie, czy kartka to nagroda, koszt, czy restart, i dlaczego zabicie czegoś daje walutę, skoro level-up też „daje ofuda".

### Krok 1: zasady (decyzje)

1. **Ofuda pochodzą wyłącznie z kapliczek (hokora)** w lesie. Jedna waluta, jeden sink: drzewko.
2. **Usunięte:** dropy z yōkai/elit/Oni (`OFUDA_SWARM_CHANCE`, `OFUDA_ELITE_*`, `OFUDA_ONI_*`), `backstab_ofuda`, cięcie kart przy level-upie (`OfudaTalisman` jako wybór), `UpgradePool` (sześć statystyk), klawisze 1–3 i stan `LEVEL_UP`, slow-mo przy level-upie.
3. **Backstab:** efekt węzła zostaje, ale bez ofuda: mnożnik ciosu od tyłu **×2.5 → ×3.0** („Rear strikes ×3 damage").
4. **Level-up:** zostaje jako **ranga/wynik** (krzywa XP bez zmian) + **leczenie 10 HP** (`RunGame.LEVEL_UP_HEAL_HP`) + dźwięk `level_up`. Bez wyboru, bez slow-mo, bez stanu. Statystyki z `UpgradePool` **usunięte** (nie przeniesione: drzewko ma już 20 węzłów; dwa systemy ulepszeń to dokładnie ten zamęt). Moc rośnie wyłącznie z drzewka i z rangi duszy (`POWER_PER_RANK`).
5. **Restart na ekranie śmierci:** kartka 御札 → **絵馬 (ema)**, drewniana tabliczka, nagłówek „絵馬 · NEW RUN". Nie jest walutą, nie ma kanji 御札, ma inny kształt i kolor (drewno, nie papier). Klasa `OfudaTalisman` → `VotiveTablet` (`votive_tablet.gd`).
6. **Koszty drzewka: bez zmian (3/5/5/8/12 = 33 na żywioł).** Zmienia się wydajność: zamiast ~30 ofuda z 5 min walki (dropy) jest ~6 z kapliczki i kapliczek jest mało – szczegóły w „Krok 3: balans".

### Interpretacja „rzadko" (niejednoznaczność)

Jakub napisał: „ta ofuda ... bedzie wystepowac duzo zardziej niz torii dosc bardzo rzadko". Przyjęta interpretacja: **„zardziej" = „rzadziej"**, czyli kapliczki są **dużo rzadsze niż torii**.
- Torii żywiołów: co 18–32 m (średnio 24 m).
- Kapliczka: **średnio co ~216 m marszu** (zmierzone w teście chodzenia 1.5 km: 7 kapliczek, ~214 m), czyli **~80 s marszu** w średnim tempie (2.6 m/s). To ~9× rzadziej niż torii.
- Pierwsza kapliczka: **otwierająca**, 30 m przed startem (widoczna od razu, ~12 s marszu) – spełnia gwarancję „w zasięgu w ciągu ~60 s".

Jeśli Jakub miał na myśli coś innego, zmiana to jedna stała: `ElementBalance.HOKORA_SLOT_CHANCE` / `HOKORA_SLOT_CHUNKS`.

### Kapliczka (hokora) – specyfikacja

- **Diegetyczna**: ciepłe, bursztynowo-czerwone światło lampionu (halo `torii_lantern_halo.gdshader`, `fog_disabled`, bez `OmniLight3D` – zero świateł w budżecie Quest), czytelne z ~20–30 m przez mgłę (mgła pełna od 10.5 m, halo do ~35 m).
- **Dźwięk**: dzwoneczek **suzu** (`hokora_suzu`, generowany w `scripts/generate_hanabi_proc_audio.py`) przy zbliżeniu do 14 m, co 6 s.
- **Bez strzałek UI.**
- **Model**: proceduralny drewniany hokora na kamiennym cokole. Punkt podmiany: węzeł `ModelSlot` w `scenes/world/hokora_shrine.tscn` (D5 podmieni na asset z `assets_incoming/shrine/`).
- **Odbiór**: **podejście** – ciało gracza w promieniu **1.4 m** od ołtarza. Bez cięcia kataną. Feedback: dźwięk suzu, 6 ofuda wypływa z ołtarza i **leci do etykiety licznika na nadgarstku** (`OfudaPickup.fly_to`), licznik `札×N` rośnie o 1 dopiero po dolocie, a lewa dłoń dostaje krótki impuls haptyczny (`WeaponHolder.pulse`). Kapliczka gaśnie **na stałe** (bez farmienia, na czas runu).
- **Liczba z jednej kapliczki: 6** (`ElementBalance.OFUDA_PER_HOKORA`).

### Placement (wzór: torii E2a)

- Slot = 4×4 chunki (112 m). Pozycja kandydata = deterministyczny seed z `(slot, seed świata)` → ta sama mapa w każdym runie.
- Dlaczego 4×4, a nie 6×6: gracz widzi kapliczki w pasie ±34 m wokół trasy, więc gęstość na metr marszu to (pas 68 m) × (szansa × udział poprawnych slotów) / (bok slotu)². Pierwsza wersja (6×6 = 168 m, z kandydatami 2.4 m) dawała **2 kapliczki na 1.5 km** (ok. 750 m), za rzadko. 3×3 dało 15 (ok. 100 m), za gęsto. 4×4 → 7 na 1.5 km. Udział slotów z poprawnym punktem zmierzony: ~95 %.
- Przy wyborze punktu: promień czystości **1.6 m** (cokół ma ~0.75 m półszerokości; pień dolicza własny promień), wachlarz 25 kątów × 4 odległości dla otwierającej, 41 kandydatów na slot (torii mają 24 × 8).
- Walidacja **raz**, przy pierwszym zbliżeniu (≤ 34 m): `ForestWorld.is_clear_of_props(r=2.4)`, zapytanie fizyczne na warstwę pni (`TRUNK_LAYER`), odległość ≥ 10 m od torii (`ToriiManager.is_near_gate`), nachylenie terenu ≤ 0.5. Nieudany kandydat → 6 alternatywnych offsetów z tego samego hasha → inaczej slot pusty (cache `none`).
- Kandydat trafia do cache na czas runu; węzeł kapliczki powstaje w promieniu **34 m** i jest zwalniany dopiero w promieniu **60 m** (poza mgłą, bez „znikania przed graczem").
- Ponowne wejście w slot: ten sam węzeł (słownik `slot → węzeł`), **bez duplikatów**; odebrana kapliczka wraca jako ciemna (`claimed` trzymane w słowniku runu).
- Nigdy w kolizji z pniem, skałą, latarnią, bramą; ≥ 30 m od startu (poza pętlą spawnu wrogów 7.6–10.8 m).
- Otwierająca kapliczka (slot 0,0): pierwszy poprawny punkt w wachlarzu 28–34 m przed startem, co 15°.

### Krok 3: balans (symulacja w `tools/balance_model.gd`)

Model dostaje odległość marszu: `speed × walk_share` (profil: careful 2.2 m/s × 0.45, average 2.6 × 0.6, skilled 3.0 × 0.75). Każde przejście kolejnej pozycji kapliczki = +6 ofuda. Kille i poziomy dalej liczone walką (bez zmian).

Cele (z zadania Jakuba):
- w 8-minutowym runie **5–7 węzłów** (średni gracz),
- finał (węzeł 5 = „cięcie jak masło", D4) osiągalny w **dobrym** runie ~8–10 min.

### Wynik symulacji D1 (`tools/balance_sim.tscn`, 720 s, 6 Ofuda na kapliczkę, ~216 m)

| profil | 2 min | 4 min | 6 min | 8 min | 10 min | master (węzeł 5 jednej szkoły, 33 札) |
|---|---|---|---|---|---|---|
| careful (2.2 m/s × 0.45 marszu) | 6札 · 2 węzły | 6札 · 2 | 12札 · 4 | 18札 · **5** | 18札 · 5 | nie w 12 min |
| **average** (2.6 m/s × 0.6, cel) | 6札 · 2 | 12札 · 4 | 18札 · 5 | 24札 · **6** | 30札 · 7 | ~12 min |
| skilled, dobry run (3.0 m/s × 0.75) | 12札 · 4 | 18札 · 5 | 24札 · 6 | 30札 · 7 | 42札 · 10 | **8:20** |

- Cel „5–7 węzłów w 8 min" dla średniego gracza: **6** ✓.
- Cel „finał osiągalny w dobrym runie ~8–10 min": **8:20** ✓.
- Pierwszy węzeł (3札) w **0:20** (opening shrine 30 m od startu). Kapliczki: 1 na ~216 m.
- Koszty drzewka zostają **3/5/5/8/12**: przy tej gęstości kapliczek przelicznik wychodzi właśnie tu. Obniżenie kosztów albo zwiększenie wydajności za kapliczkę zmieniałoby tempo o ~2× i nie ma powodu.

Testy, które to pilnują: `tests/skill_tree_data_test.gd` (`_test_balance_targets`) i `tests/hokora_test.gd` (`_test_density_along_a_walk`: 5–11 kapliczek na 1.5 km).

---

## D4 – cięcie jak masło (Tachi: finał każdego żywiołu)

> Jakub: „finalna umiejętnosc dla danego zywiolu byla mozliwosc ciecia przeciwnikow jak masla… zeby zostawialo na nich slady w kolorze zywiolu i zeby sie rozpadali na czesci w miejscu gdzie zostali przecieci".

### 1. Co to jest

- **Ostatni węzeł (tier 5) każdego drzewka dostaje drugi efekt: 断ち (*tachi*, „przecinanie"), nazwany per żywioł:**
  | Żywioł | Nazwa | Kanji | Co zostaje na wrogu |
  |---|---|---|---|
  | Sakura | **Hanadachi** | 花断ち | róż neon na przekroju |
  | Storm | **Raidachi** | 雷断ち | elektryczny błękit, żarzenie z łukiem iskier |
  | Ink | **Sumidachi** | 墨断ち | lśniąca czerń z indygo |
  | Shadow | **Kagedachi** | 影断ち | ciemny fiolet |
- **Dodany, nie zamieniony.** Istniejące efekty tier 5 (Kageyoshi, Ikazuchi, Abyssal Sea, Shadow Clones) mają testy i wpis w `ElementBalance` / `tools/balance_model.gd`, więc zostają. Węzeł ma teraz dwa efekty w jednym opisie. Koszt (12 Ofuda) bez zmian.
- **Aktywacja: pasywna, w czasie imbue, bez nowego przycisku** (A/B zajęte). Działa tylko, gdy ostrze ma żywioł danej szkoły i węzeł jest odblokowany. Na zwykłej stali nic się nie dzieje.
- **Reguła trafienia:** cięcie krawędzią (`strike == "edge"`, `edge_alignment ≥ 0.85`, ×1.0) z prędkością względną **≥ 8 m/s** (real). Słabsze cięcia i płaskie/grzbietowe trafienia zostają zwykłym trafieniem.
- **Efekt na wrogach:**
  - **Yōkai (swarm):** cięcie zabija i rozdziela ciało na dwie części w miejscu cięcia (przekrój + kawałki).
  - **Elita:** dostaje dodatkowo 50 % max HP obrażeń. Rozcina się tylko przy zabiciu; inaczej zostaje rana (iskry, dźwięk, przekrój bez podziału).
  - **Oni (boss):** nie rozpada się od jednego cięcia. Dostaje **ranę**: emisyjną szczelinę w kolorze żywiołu na korpusie (~2 s) i zwykłe obrażenie cięcia. Pełny podział dopiero przy killu (patrz §8, poza zakresem tej iteracji, jeśli nie zdążę).
- **Cięcie nie zastępuje odcinania kończyn:** kawałki Kirisute mają pierwszeństwo, kończyna nie odlatuje osobno.

### 2. Płaszczyzna cięcia (wzór i znak)

Dane z trafienia (`HeldWeapon._handle_hit`, bez nowych rachunków):

- `P` = punkt kontaktu ostrza w chwili uderzenia (`hit.point`).
- `m` = jednostkowy kierunek ruchu ostrza względem celu (`hit.direction` = znormalizowane `v_ostrza − v_celu`).
- `a` = jednostkowa oś ostrza od jelca do czubka (`BladeBody.get_blade_axis()`, w świecie).
- **`n = normalize(m × a)`**. Płaszczyzna: `{x : n · (x − P) = 0}`. Zawiera `m` i `a`, czyli cięcie idzie wzdłuż długości ostrza i w kierunku ruchu, tak jak tnie prawdziwy miecz.
- **Znak:** strona **górna** = `n · (x − P) > 0`, strona **dolna** = `< 0`. Kawałek górny dostaje impuls `+n`, dolny `−n`. Oba dostają wspólny składnik `+0.8 m/s · m` (ostrze niesie je dalej).
- Kontrola w teście: `n·m ≈ 0`, `n·a ≈ 0`, `|n| = 1`.

### 3. Technika cięcia siatki

- **Stan obecny:** `SeveredLimb` odcina kończynę przez kopię części, a nie przez przecięcie. Kirisute to **prawdziwe cięcie siatki** płaszczyzną.
- **Geometria jest wypukła.** Ciało wroga to prymitywy (`box`, `capsule`, `sphere`, `yokai.gd::_define_parts`). Połowa wypukłej bryły też jest wypukła, więc przekrój to **jeden wielokąt** na część. Cap jest prosty do zbudowania i zamknięty.
- **Własny slicer w GDScript** (`src/enemies/mesh_slicer.gd`, `class_name MeshSlicer`, funkcje statyczne), bez addonu (zero ryzyka licencyjnego, zero obciążenia wersji Quest):
  1. Sutherland–Hodgman na każdym trójkącie: nowe wierzchołki na płaszczyźnie, z interpolowanymi normalami i UV.
  2. Krawędzie przecięcia łączone w zamknięte pętle po współrzędnych (kwantowanych).
  3. Każda pętla triangulowana w 2D (`Geometry2D.triangulate_polygon`) i zorientowana do normalnej strony (winding zgodny z normalą wierzchołków, jak w prymitywach źródłowych).
  4. UV przekroju: rzut planarny na płaszczyznę cięcia.
- **Kawałek = jeden `MeshInstance3D`** z powierzchniami pogrupowanymi wg materiału: skóra (oryginalny `_skin`), przekrój (`cap`), dekoracje (maska, rogi, oczy, pasek) przypisane do strony wg środka ciężkości. Jeden kawałek to jeden draw call na materiał.
- **Kolizja:** `ConvexPolygonShape3D` dla każdej połowy części, punkty przerzedzone do **≤ 32** (farthest-point sampling).
- **Koszt:** liczone **raz**, w chwili cięcia. Alokacje tylko przy cięciu (nie co klatkę). Każda klatka aktualizuje tylko parametry materiału przekroju.

### 4. Przekrój i ślad (materiał, nie kicz)

- **Cap:** `StandardMaterial3D`, albedo ciemne (ciało, nie plama). Emisja w kolorze żywiołu (`Elements.color`), energia **2.4 → 0.35 w 1.6 s** (żarzenie gaśnie). Ink: albedo czarne, roughness 0.15 (połysk), indygo `Elements.accent_color(INK)` w emisji.
- **Ślad na skórze:** iskry `SparkBurst` wzdłuż płaszczyzny w chwili cięcia (istniejący system, kolor żywiołu). Bez decala i bez dodatkowych świateł.
- **Nie dodajemy OmniLight.** Świecenie przekroju jest emisją, zgodnie z zasadą „neon jako akcent".

### 5. Fizyka rozpadu

- Kawałki: `RigidBody3D`, masa = Σ(masa części × udział objętości), tłumienie jak u `SeveredLimb`.
- **Kolizja: tylko z terenem** (`collision_layer = 0`, `collision_mask = 1`), jak u `SeveredLimb`. Kawałki **nie blokują ostrza, gracza ani innych wrogów**, więc ostrze przechodzi przez miejsce cięcia.
- Impuls: `±n · 1.2 m/s + m · 0.8 m/s + 0.5 × prędkość rodzica + 1.0 m/s w górę`, obrót wokół osi cięcia.
- **Rozpad w miejscu cięcia:** po ~2.6 s skala do zera w 0.8 s, a z miejsca przekroju wybuch płatków sakury (`SakuraScatter`, jak przy śmierci). Zniknięcie zawsze do 3.4 s.
- **Ciało wroga:** `die()` (dusze, log, zabicie), potem ukrycie wszystkich części i dekoracji, bez płatków. `dissolve_finished` idzie przez `call_deferred`, bo recykling nie może usunąć węzła w trakcie jego własnego `receive_hit`.

### 6. Wydajność Quest 3

- **≤ 8 aktywnych kawałków** (najstarsze znikają pierwsze). **≤ 2 cięcia na klatkę**; trzecie w tej samej klatce to zwykłe trafienie bez podziału.
- Convex ≤ 32 wierzchołków na połowę części.
- **Draw calls:** kawałek = 1 `MeshInstance3D` z N powierzchniami (≈ 2–6). Oryginał jest ukryty (0 draw). Pomiar w `quest_perf_test` podczas fali cięć: ≤ 345 i headroom ≥ 30, jak w E3.6.
- Brak puli kawałków: cięcia są rzadkie, a alokacja jest jednorazowa. Jeśli pomiar pokaże problem, dojdzie pula.

### 7. Chwyt (hand priority, GDD §4)

Cięcie **nie może szarpnąć katany ani wyrwać jej z ręki**:
1. Kawałki nie mają kolizji z ostrzem (layer 0), a części ciała zostają ukryte bez kolizji. Od następnej klatki ostrze nie ma czego przecinać i idzie za ręką.
2. Opór cięcia jak przy odcięciu kończyny: `_apply_cut_resistance(..., 0.25)`.
3. Test: po cięciu katana zostaje w ręce, `grip_error ≤ break_distance + 0.05`, `is_held()`.

### 8. Interakcje

- **Oni:** rana zamiast podziału (opisane w §1). Pełny podział przy killu to osobna praca (`RunOniBoss` ma inną ścieżkę śmierci); zapisana jako następny krok, nie w tej iteracji, chyba że czas pozwoli.
- **Elita:** +50 % max HP, rozcięcie tylko przy zabiciu (§1).
- **Słaba fala trafień:** progi są progami prędkości, nie liczbą trafień. Dwa mocne cięcia w krótkim czasie na jednego wroga = jedno zabicie i jeden podział.
- **Pauza:** kawałki zamrażają się jak reszta świata (`process_mode` jak u `SeveredLimb`). Pauza nie zmienia kształtu przekroju.

### 9. Ryzyka i plan awaryjny

- **Slicer za wolny na Quest (GDScript):** pomiar w teście (ms na cięcie). Fallback, jeśli nie zmieści się w budżecie: pre-pocięte warianty części (6 płaszczyzn bazowych na prymityw) z wyborem najbliższej płaszczyzny normalnej do `n`. Najpierw próbujemy prawdziwego cięcia, jak zapisał Jakub.
- **Płaszczyzna mija ciało** (cięcie tylko na brzegu) → brak ≥ 2 kawałków → zwykłe trafienie, bez podziału (test).
- **Cięcie zgubi dekorację** (maska, róg): dekoracja jest przypisana do strony wg środka; przy dużym cięciu może przeciąć się na granicy, co akceptujemy (bez sliceowania dekoracji).

### 10. Dane do testów (krytyczne, szybkie, bez czasu rzeczywistego)

- **`tests/dismember_test.tscn` (rozszerzony, nie nowy suite):**
  - Slicer: sześcian i kapsuła pocięte płaszczyzną → 2 zamknięte siatki (każda krawędź w dwóch trójkątach), suma objętości ≈ oryginał (±5 %), przekrój ma powierzchnię `cap` z materiałem żywiołu, `n·m ≈ 0`, `n·a ≈ 0`.
  - Gating: bez węzła tier 5 → zwykłe trafienie; węzeł + imbue + mocne cięcie (≥ 8 m/s) → ≥ 2 kawałki; słabe cięcie (3 m/s) → nic; plain steel → nic.
  - Limit: 20 cięć po kolei → kawałków ≤ 8, najstarsze zwolnione.
  - Chwyt: po cięciu `katana.is_held()` i `grip_error ≤ break_distance + 0.05`.
- **`tests/skill_tree_data_test.tscn`:** każdy tier 5 ma efekt `kirisute` z właściwą nazwą; efekt czyta się przez `effect_value`.
- **`tests/quest_perf_test.tscn` (rozszerzony):** fala 8 cięć w jednej klatce budżetu: draw calls ≤ 345 i headroom ≥ 30, czas klatki w limicie, bez świateł.
- **Screenshoty:** `tests/element_abilities_screenshots.tscn` (rozszerzony): rozcięty wróg w każdym żywiole, kawałki na ziemi, moment cięcia w zwolnieniu.

### 11. Krok po kroku (odhaczane w miarę postępu)

- [x] **D4.0 Plan** (ten commit).
- [ ] **D4.1 `MeshSlicer`:** płaszczyzna, sutherland-hodgman, pętle, cap, testy zamkniętości i objętości.
- [ ] **D4.2 Drzewko:** efekt `kirisute` na 4 węzłach tier 5 (nazwy, opisy, `ElementBalance`), testy drzewka. Przy okazji poprawka opisu Kageyoshi: opis mówi „120 dmg", a stała to 100 (`KAGEYOSHI_DAMAGE`). Ujednolicam do stałej.
- [ ] **D4.3 Gating:** `HeldWeapon` oznacza trafienie flagą `kirisute` i wektorem `blade_axis`, gdy ostrze ma imbue z węzłem tier 5 i trafienie spełnia progi.
- [ ] **D4.4 Yōkai:** podział (zabicie, elita, rana), limit kawałków, ukrycie ciała, odroczony zwrot do puli.
- [ ] **D4.5 Oni:** rana (szczelina w kolorze żywiołu, ~2 s).
- [ ] **D4.6 Materiały:** cap per żywioł, żarzenie, ślad iskier.
- [ ] **D4.7 Testy i perf:** `dismember_test`, `skill_tree_data_test`, `quest_perf_test` rozszerzone; pełny zestaw headless przechodzi.
- [ ] **D4.8 Screenshoty i ocena:** rozcięty wróg ×4 żywioły, kawałki, moment cięcia; surowa ocena i poprawki.
- [ ] **D4.9 Docs:** GDD §5 (jedno zdanie o tachi), QUEST_TEST checklist, README.

### 12. Decyzje podjęte bez pytania (do przeglądu)

- Nazwy: Hanadachi / Raidachi / Sumidachi / Kagedachi (rodzina „tachi", nasza nazwa, bez cudzej IP).
- Pasywny efekt w czasie imbue zamiast aktywacji, bo A/B są zajęte, a cięcie jest już aktem fizycznym.
- Kirisute dodane do tier 5, a nie zamieniające istniejące efekty (koszt testów i balansu).
- Elita: rozcięcie tylko przy zabiciu, bo „zabija każdy kawałek" z elitą (ok. 2.35× HP) byłoby zbyt tanie.
- Własny slicer, nie addon: prymitywy są wypukłe, a addon dodałby licencję i zależność.
