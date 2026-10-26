# HANABI (花火)

VR melee survivor-like for Meta Quest: Blade & Sorcery–style physics swordplay in a foggy, procedurally generated dark Japan. Built with **Godot 4.7 (GDScript) + OpenXR**, for the Meta Global AI Developer Hackathon 2026.

The design reference is [`docs/GDD.md`](docs/GDD.md). The development brief is [`docs/HANABI_agent_prompt.md`](docs/HANABI_agent_prompt.md).

## Current state: milestone 1 (sword physics) — PD katana, hit-stop, trail, parry

| Works | Stubbed / temporary |
|---|---|
| OpenXR rig (godot-xr-tools): smooth move, snap turn, hands; the hand model stays on the hilt when the blade is stopped | Only one weapon per hand; no two-handed grip yet |
| **Katana on a PD controller** (force + torque, stable PD): weight and inertia matter, a heavy **kanabō** visibly lags behind the hand with the same arm strength | Katana is the Grab3D model; kanabō is built from primitives |
| No clipping (CCD) and **no bulldozing**: when the blade is held back the arm gives way (strength drops to 30%), with a light haptic buzz | |
| **Hit-stop** 50–80 ms on hits ≥ 40 damage, haptics scaled by impact | |
| **Blade trail** (CPU ribbon, works on Quest's Compatibility renderer) colored by element: none / sakura / storm / ink / shadow | Elements only change the trail color so far (abilities come in milestone 3) |
| **Parry**: the dummy can attack (telegraphed overhead cut); meeting its attacking blade fast enough and across it (≥ 25°) is a parry: sparks, compensated slow-mo ×0.3 for 0.6 s (your blade stays real-time), dummy stunned, **counter window** 1.5 s with ×1.5 damage | Only the dummy attacks; it does not damage the player (no player HP yet) |
| **Active ragdoll training dummy** with its own physics bokken: staggers, falls, gets up | Dummy is built from primitives, not the Quaternius mesh |
| Damage from the relative speed at the contact point, zone multipliers; debug panel (hits, COUNTER, PARRY!, counter window), damage numbers, SFX | |
| Desktop test rig for machines without a headset (e.g. macOS) | |
| Central event log (`GameEvents`), data-driven enemy profile, swappable enemy brain (DummyBrain has a small attack FSM) | No AI/LLM features yet (later phase, see GDD §8) |

## Requirements
- **Godot 4.7.2** (standard build, not .NET): https://godotengine.org/download. On macOS, move `Godot.app` to `/Applications`.
- Everything else for desktop testing is in the repo (`addons/` contains godot-xr-tools 4.5.2 and Godot OpenXR Vendors 5.1.0).
- Raw asset packs live in `assets_raw/`, which is **not in git** (see [LICENSES.md](LICENSES.md)). They are not needed to run the current build.

## Run on desktop (any OS, no headset)
1. Open Godot and import `project.godot`, or run from a terminal:
   ```sh
   /Applications/Godot.app/Contents/MacOS/Godot --path /path/to/HANABI
   ```
   With no OpenXR runtime (always the case on macOS) the game starts the **desktop rig**. To force it on a PC with a headset, add `-- --desktop`.
2. Controls:

   | Input | Action |
   |---|---|
   | Click / Esc | capture / release the mouse |
   | Mouse | look |
   | WASD | walk |
   | Hold **right mouse button** + move the mouse | move the weapon hand (swing it yourself) |
   | **F / G / T** | scripted horizontal slash / overhead cut / thrust |
   | Mouse wheel | scripted swing duration (faster swings hit harder) |
   | Hold **Q** | high block (parry the dummy's overhead cut) |
   | **1 / 2** | katana / kanabō |
   | E | drop / take the weapon |
   | Z | cycle the element (trail color) |
   | **P** | dummy attacks on / off |
   | R | reset the dummy (and put dropped weapons back) |

## Automated checks
```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --headless --path . --import                  # first time / after adding assets
$GODOT --headless --path . --fixed-fps 90 res://tests/physics_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/combat_test.tscn -- --desktop
```
- `physics_test` checks the dummy (stands, staggers, knockdown, gets up), velocity-scaled damage, the wall stopping a thrust, and blade clashes.
- `combat_test` checks:
  - the katana settles in about 0.13 s and the kanabō lags (about 0.47 s);
  - pushing into the dummy does not bulldoze it, and the arm gives way;
  - hit-stop timing and the trail;
  - parrying the dummy's strike leads to slow-mo, stun, counter window and a counter hit;
  - the katana keeps real-time tracking during slow-mo.

Both exit with code 0 when all checks pass. `res://tests/screenshots.tscn -- --desktop --shots /tmp/shots` renders screenshots. `tests/diag/` holds small diagnostic scenes, e.g. the Jolt joint-limit sign check and slow-mo tracking.

## Run on Meta Quest (standalone)

### 1. One-time setup on macOS (JDK 17, Android SDK, adb)
These steps use Homebrew (https://brew.sh). Apple Silicon paths are shown.

```sh
# Java 17 (Eclipse Temurin build of OpenJDK)
brew install --cask temurin@17
/usr/libexec/java_home -v 17          # prints the JDK path, needed in step 3
# e.g. /Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home

# Android command-line tools (provides sdkmanager)
brew install --cask android-commandlinetools

# Install the SDK into the standard macOS location
export ANDROID_HOME="$HOME/Library/Android/sdk"
mkdir -p "$ANDROID_HOME"
yes | sdkmanager --sdk_root="$ANDROID_HOME" --licenses
sdkmanager --sdk_root="$ANDROID_HOME" \
  "platform-tools" \
  "build-tools;35.0.1" \
  "platforms;android-35" \
  "cmdline-tools;latest" \
  "cmake;3.10.2.4988404" \
  "ndk;28.1.13356709"

# Make adb and the SDK available in every terminal
cat >> ~/.zshrc <<'EOF'
export JAVA_HOME="$(/usr/libexec/java_home -v 17)"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
EOF
source ~/.zshrc
adb version                            # should print "Android Debug Bridge version ..."
```
These are the versions the Godot 4.7 Android export docs ask for: JDK 17, platform-tools ≥ 35, build-tools 35.0.1, platform 35, CMake 3.10.2, NDK r28b.

**Alternative:** install Android Studio (`brew install --cask android-studio`) and add the same packages in *Settings → Languages & Frameworks → Android SDK* (tabs *SDK Platforms* and *SDK Tools*). The SDK path is the same.

**Debug keystore.** Godot signs debug builds with a debug keystore. If export complains that it is missing, create one:
```sh
keytool -genkeypair -v -keystore ~/.android/debug.keystore -storepass android \
  -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Android Debug,O=Android,C=US"
```
Then point *Editor Settings → Export → Android → Debug Keystore* at it (user `androiddebugkey`, password `android`).

### 2. Prepare the Quest
1. Create or join a developer organization at https://developer.meta.com (free; needed for developer mode).
2. In the **Meta Horizon** phone app: *Devices → your headset → Headset settings → Developer mode → On*. Reboot the headset.
3. Connect the headset with a USB-C data cable. In the headset, accept **Allow USB debugging** (tick *Always allow from this computer*).
4. Check that it is visible: `adb devices` should list the device as `device`, not `unauthorized`.

### 3. Configure Godot (once)
1. *Godot → Editor Settings → Export → Android*: set **Java SDK Path** (output of `/usr/libexec/java_home -v 17`) and **Android SDK Path** (`/Users/<you>/Library/Android/sdk`).
2. *Project → Install Android Build Template…* creates `android/`, which is git-ignored. The Meta OpenXR loader needs a Gradle build.
3. The export preset **"Meta Quest"** is already in `export_presets.cfg`: Gradle build on, XR Mode = OpenXR, Meta plugin on, arm64 only, Quest 2/3/Pro support.

### 4. Build and run
- **One-click deploy:** with the headset connected, press the Android "remote deploy" button at the top right of the editor, and the game starts in the headset. Or
- **Export an APK:** *Project → Export… → Meta Quest → Export Project* to `build/quest/hanabi.apk`, then `adb install -r build/quest/hanabi.apk`. Start it from *Library → Unknown Sources*.
- Logs: `adb logcat -s godot`.

On Quest the renderer switches to **Compatibility** automatically (`rendering_method.mobile` override; the Godot XR docs recommend it for Android XR). Physics runs at the headset refresh rate (72/90/120 Hz).

## Run in PCVR (Windows, for recording)
1. Install Godot 4.7.2 for Windows and the **Meta Quest Link** app. Connect the Quest with Link (cable) or Air Link.
2. In the Meta Quest Link app: *Settings → General → OpenXR Runtime → Set Meta Quest Link as active*. SteamVR as the active OpenXR runtime also works.
3. Open the project and press Play. With an active OpenXR runtime the game starts in VR automatically.
4. Optional: export with the **"PCVR (Windows)"** preset (requires Godot's Windows export templates).

## VR controls (test room)
| Input | Action |
|---|---|
| Left stick | move (smooth locomotion) |
| Right stick | snap turn |
| **Grip** near a weapon (on the table) | take it; release grip to drop |
| Grip + **B/Y** | recall the nearest weapon into the hand |
| **B/Y** (without grip) | dummy attacks on / off |
| Thumbstick **click** | cycle the element of the weapon in that hand |
| **A/X** | reset the dummy |

To practice parries: turn the dummy's attacks on, stand about 1.3 m in front of it, and meet its overhead cut with your blade held across it.

## Project layout
```
addons/            godot-xr-tools, godotopenxrvendors (third-party, see LICENSES.md)
assets/            only assets the game uses (tracked)
assets_raw/        original downloaded packs (git-ignored, Godot-ignored)
data/enemies/      EnemyProfile resources (stats, resistances, tactics as data)
docs/              GDD and brief
scenes/            test_room, player rigs, weapons
src/core/          GameEvents (event log), TimeController (hit-stop, slow-mo), Elements, Sfx, test room
src/player/        XR rig, desktop rig, WeaponHolder (grab/recall/haptics)
src/weapons/       BladeBody (blade, element, pre-impact velocity), HeldWeapon (PD follow, hits, clashes, parry), BladeTrail
src/enemies/       ActiveRagdoll, TrainingDummy, EnemyBrain / DummyBrain, EnemyProfile
src/debug/         hit debug panel, damage numbers, spark bursts
tests/             headless physics test, screenshots, diagnostics
```

## How the physics works (short)
- **Katana:** a `RigidBody3D` driven by a stable PD controller.
  - Force goes on the center of mass toward the hand pose, torque toward the hand orientation, and the weapon's own weight is held.
  - Force and torque are capped by the player's arm strength (260 N, 40 N·m). A heavier weapon therefore accelerates less and lags.
  - When the grip is held more than 10 cm away from the hand, strength drops to 30%, so the blade rests on obstacles instead of shoving them.
- **Weapon hit speed:** each weapon stores its velocity before every physics step. On a new contact, the hit speed is the relative velocity of the two contact points *before* the solver slowed them down. Damage = `(speed − 1.5 m/s) × 9` (×13 for the kanabō), capped at 120, times the zone multiplier and ×1.5 for counters.
- **Time effects (`TimeController`):**
  - Hit-stop and slow-mo set `Engine.time_scale` and are timed in real time (counted in physics ticks, which stay at 90/s).
  - In a parry slow-mo the player's weapon is compensated: its gains are scaled by real_tick / sim_delta. Your blade keeps real-time speed while the world moves at ×0.3.
  - Speeds of player hits are converted back to real m/s.
- **Parry:** a new contact between the player's blade and an enemy blade flagged `attacking` (the enemy brain sets it during a strike), with relative speed ≥ 1.5 m/s and blades crossing at ≥ 25°.
- **Active ragdoll:**
  - Each joint's muscle is a velocity-level PD drive that rotates the joint's whole subtree (e.g. upper arm + forearm + sword) toward the pose, so joints don't fight and the solver stays stable.
  - Poses can set `_stiffness` and `_max_speed` (the strike is fast but capped so it can be read and parried).
  - "Puppet string" balance keeps the pelvis and chest upright, at standing height and near an anchor.
  - Hits drain `balance` and `muscle`: low balance means a stagger, zero means a knockdown, then a timed get-up.
  - All parts use CCD, so a flung shin cannot tunnel into the floor.
- **Jolt notes:**
  - Generic6DOF angular limits are measured in the opposite sense to the pose convention, so the ragdoll negates them (`tests/diag/diag_joint.tscn`).
  - `max_angular_velocity` is raised to 150 rad/s so the compensated katana is not clamped in slow-mo.

## Licensing
All third-party files and their licenses are listed in [LICENSES.md](LICENSES.md); credits are in [CREDITS.md](CREDITS.md). The Vacuous BGM music must never be committed.
