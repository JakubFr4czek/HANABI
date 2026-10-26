# HANABI (花火)

VR melee survivor-like for Meta Quest: Blade & Sorcery–style physics swordplay in a foggy, procedurally generated dark Japan. Built with **Godot 4.7 (GDScript) + OpenXR**, for the Meta Global AI Developer Hackathon 2026.

The design reference is [`docs/GDD.md`](docs/GDD.md). The development brief is [`docs/HANABI_agent_prompt.md`](docs/HANABI_agent_prompt.md).

## Current state: milestone 1, step 1 (physics test room)

| Works | Stubbed / temporary |
|---|---|
| OpenXR rig (godot-xr-tools): smooth move, snap turn, hands | Sword follows the hand by **velocity** (stiff, no weight lag). The PD-controlled katana is the next task |
| Grab the practice bokken with **grip**; recall it with grip + B/Y | Bokken is a primitive mesh (the katana model comes with the PD katana) |
| Physics blade: collides with walls and bodies (no clipping), continuous collision detection | No hit-stop, trail or parry slow-mo yet (parry *detection data* is logged) |
| **Active ragdoll training dummy**: 11 rigid bodies + joints, muscles hold a guard pose, balance help, staggers, falls, gets up | Dummy is built from primitives, not the Quaternius mesh |
| Dummy holds its own physics bokken (blade vs blade clashes are detected and logged with speed and angle) | Dummy does not attack |
| Damage from the relative speed at the contact point, zone multipliers (head ×1.5, limbs ×0.7) | |
| Debug panel on the wall (hit speed, damage, body part, dummy HP/balance/state), floating damage numbers, haptics, sword SFX | |
| Desktop test rig for machines without a headset (e.g. macOS) | |
| Central event log (`GameEvents`), data-driven enemy profile, swappable enemy brain | No AI/LLM features yet (later phase, see GDD §8) |

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
   | Hold **right mouse button** + move the mouse | move the sword hand (swing it yourself) |
   | **F / G / T** | scripted horizontal slash / overhead cut / thrust |
   | Mouse wheel | scripted swing duration (faster swings hit harder) |
   | E | drop / take the sword |
   | R | reset the dummy (and the sword, if dropped) |

## Automated checks
```sh
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --headless --path . --import                  # first time / after adding assets
$GODOT --headless --path . --fixed-fps 90 res://tests/physics_test.tscn -- --desktop
```
`physics_test` checks that:
- the dummy stands and holds its sword;
- faster slashes hit harder;
- hits stagger the dummy, a quick combo knocks it down, and it gets up again;
- a thrust into a wall stops at the wall;
- blade clashes are detected.

The exit code is 0 when all checks pass. `res://tests/screenshots.tscn -- --desktop --shots /tmp/shots` renders screenshots. `tests/diag/` holds small diagnostic scenes, e.g. the Jolt joint-limit sign check.

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
| **Grip** near the bokken (on the table) | take it; release grip to drop |
| Grip + **B/Y** | recall the bokken into the hand |
| **A/X** | reset the dummy |

## Project layout
```
addons/            godot-xr-tools, godotopenxrvendors (third-party, see LICENSES.md)
assets/            only assets the game uses (tracked)
assets_raw/        original downloaded packs (git-ignored, Godot-ignored)
data/enemies/      EnemyProfile resources (stats, resistances, tactics as data)
docs/              GDD and brief
scenes/            test_room, player rigs, weapons
src/core/          GameEvents (central event log), Sfx, test room
src/player/        XR rig, desktop rig, WeaponHolder (grab/recall/haptics)
src/weapons/       BladeBody (blade geometry, pre-impact velocity), HeldWeapon (follow, hits, clashes)
src/enemies/       ActiveRagdoll, TrainingDummy, EnemyBrain / DummyBrain, EnemyProfile
src/debug/         hit debug panel, damage numbers
tests/             headless physics test, screenshots, diagnostics
```

## How the physics works (short)
- **Weapon hit speed:** each weapon stores its velocity before every physics step. On a new contact, the hit speed is the relative velocity of the two contact points *before* the solver slowed them down. Damage = `(speed − 1.5 m/s) × 9`, capped at 120, times the zone multiplier.
- **Active ragdoll:** each joint's muscle is a velocity-level PD drive that rotates the joint's whole subtree (e.g. upper arm + forearm + sword) toward the pose, so joints don't fight and the solver stays stable. "Puppet string" balance keeps the pelvis and chest upright, at standing height and near an anchor. Hits drain `balance` and `muscle`: low balance means a stagger, zero means a knockdown, then a timed get-up.
- **Jolt note:** Generic6DOF angular limits are measured in the opposite sense to the pose convention, so the ragdoll negates them. `tests/diag/diag_joint.tscn` verifies this.

## Licensing
All third-party files and their licenses are listed in [LICENSES.md](LICENSES.md); credits are in [CREDITS.md](CREDITS.md). The Vacuous BGM music must never be committed.
