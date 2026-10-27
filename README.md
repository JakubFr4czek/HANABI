# HANABI (花火)

VR melee survivor-like for Meta Quest: Blade & Sorcery–style physics swordplay in a foggy, procedurally generated dark Japan. Built with **Godot 4.7 (GDScript) + OpenXR**, for the Meta Global AI Developer Hackathon 2026.

The design reference is [`docs/GDD.md`](docs/GDD.md). The development brief is [`docs/HANABI_agent_prompt.md`](docs/HANABI_agent_prompt.md).

## Current state: sword physics + survival loop + elements + endless forest run

| Works | Stubbed / temporary |
|---|---|
| OpenXR rig (godot-xr-tools): smooth move, snap turn, hands; the hand model stays pinned to the exact grip spot when the blade is stopped (up to 0.3 m from the controller) | |
| **Dojo of the Storm training arena** (`scenes/training_arena.tscn`, GDD §9): rain-soaked dark-stone disc with puddles and raindrop rings on an endless black water mirror (shader-faked sky/moon/torii/lightning reflections, no SSR), drifting surface mist, cloud deck lit by a low moon behind the giant vermilion torii, tilted half-sunken torii, branching lightning that lights clouds, fog and water, rain (streaks, splashes, drips off the blade), four-part `桜 雷 墨 影` floor seal, scanned PBR assets (Bazylonator hero torii, *Old Torii* sunken gates, Poly Haven rock faces, katana stand and cut-stone floor texture), weapon stand with the katana in a real *katana-kake*, and `LightmapGI` setup | The sakura tree was removed until a better asset is available; VR comfort options are deferred to later milestones |
| **Free grip anywhere on the katana** (handle / *tsuka*, guard / *tsuba*, blunt spine of the blade / *mune*) and **two-handed grip** (including half-swording and seamless handoff when releasing either hand). On the handle and guard the sword always seats the same natural way (edge on the fingers' side, leading a cut), however the hand came in | |
| **The weapon stays in the hand**: the grip never trails the hand by more than 3.5 cm / 30° (kanabō 40°, two hands tighter), also during hit-stop. Only walls and other static geometry can hold the blade back (the hand model then stays on the hilt). On an enemy body the blade rests up to 10 cm behind the hand (the arm gives way); if the hand goes deeper, the blade follows it through that body part instead of wedging, and the cut still counts | |
| **Edge alignment**: damage depends on what met the target: cutting edge or point ×1.0, flat ×0.3, blunt spine ×0.2, hilt ×0.3 (the kanabō is blunt all round). Edge cuts sound crisp and throw bright sparks, flat/spine hits are a dull slap with a few dim sparks | |
| **Katana on a PD controller** (force + torque, stable PD): weight and inertia matter, a heavy **kanabō** visibly lags behind one hand and responds faster when held two-handed | Katana is Poly Haven's *Antique Katana 01*; kanabō is built from primitives |
| No clipping (CCD) and **no bulldozing**: when the blade is held back by a wall or an enemy the arm gives way (strength drops to 30%), with a light haptic buzz | |
| **Hit-stop** 50–80 ms on hits ≥ 40 damage, **micro hit-stop** 25–35 ms (partial slow-down) on medium hits and blade clashes; **haptic patterns** per event (hit, clash, parry with a softer echo in the free hand) | |
| **Storm audio**: CC0 rain loop on Ambience, distant thunder after each flash, StarNinjas steel clashes on parries/cuts, open-air reverb; subdued CC0 music on the Music bus | Legacy procedural WAVs remain in `assets/audio/generated/` for offline tools only |
| **Four element trees** with a two-element / six-slot cap: Sakura cutting and orbiting glass petals plus light healing; Storm chain lightning and charged strikes; Ink slowing blade-painted pools and tendrils; Shadow combat blink and confusing darkness. Maxed Storm+Ink evolves into black lightning; Sakura+Shadow into phantom petals. The blade trail, diegetic HUD and unlocked `桜 雷 墨 影` seal quadrants follow the build | |
| **Parry**: meeting the dummy's attacking blade fast enough and across it (≥ 25°) is a parry: sparks, compensated slow-mo ×0.3 for 0.6 s (your blade stays real-time), dummy **staggered**, **counter window** 1.5 s with ×1.5 damage | |
| **Duelist AI** (`DuelistBrain` + `SwordArmIK`): the sword arm moves by real-time IK, so the guard follows you fluidly (point on your throat, leaning toward your blade). It sees your blade with a reaction delay, reads your wind-up (covers high, side or low before the cut), lays its blade across cuts that come, or steps out of reach. A light cut into its guard is deflected and answered with a riposte; a committed full-arm cut breaks the guard and staggers it. It attacks into openings (after your miss, a blade held high/low/wide, you stepping in without a cut ready, or when its patience runs out) with vertical / horizontal cuts and thrusts, combos and feints, on planted feet with one step in, then steps back to ma-ai. **Fair by rule**: every strike shows at least 0.4 s of wind-up (pose + glowing eyes + rising whoosh) inside your view, a wind-up is dropped if you look away, and it never flanks out of view. Difficulty presets easy / normal / hard are data (`DuelistDifficulty`) | Attack poses are hand-tuned on the primitive dummy |
| **Player HP** 100 with feedback: red edge vignette (pulses below 35 %), heavy haptic pattern in both hands, hurt sound; at 0 HP you are down for 3 s, the dummy backs off and you get back up at full health | No death / run-over screen yet (milestone 2) |
| **Active ragdoll training dummy** with its own physics bokken: staggers, falls, gets up | Dummy is built from primitives, not the Quaternius mesh |
| **Swing power**: damage and knock-back come from momentum. The arm only adds its weight to a committed swing (hand travel over the last 0.3 s, and how much of the blade speed comes from the hand moving rather than the wrist turning): a wrist flick does ~25 % damage and barely moves the enemy, a full-arm cut staggers it and can break its guard; the 4 kg kanabō hits much harder than the katana. Zone multipliers; debug panel (hits with arm % and impulse, COUNTER, PARRY!, counter window), damage numbers, SFX | |
| Desktop test rig for machines without a headset (e.g. macOS) | |
| Central event log (`GameEvents`), data-driven enemy profile, swappable enemy brain (`DuelistBrain`) | No AI/LLM features yet (later phase, see GDD §8) |

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
   | **X** | wrist flick (no arm behind it: little damage) |
   | Mouse wheel | scripted swing duration (faster swings hit harder) |
   | Hold **Q** | high block (parry the dummy's overhead cut) |
   | **1 / 2** | katana / kanabō |
   | **C** | cycle grip spot on the weapon (handle / tsuba / blunt blade spine) |
   | **V** | toggle one-handed / two-handed grip |
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
$GODOT --headless --path . --fixed-fps 90 res://tests/grip_stability_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/enemy_ai_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/blade_feel_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/arena_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/enemy_motion_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/sword_ik_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/run_loop_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/gdd_loop_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/point12_readability_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/yokai_spawn_pose_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/firework_flash_cap_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/point14_fog_torii_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/audio_sfx_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/elements_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/forest_world_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/enemy_variants_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/run_intro_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/quest_perf_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/vfx_polish_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/vfx_pool_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/audio_sfx_test.tscn -- --desktop
$GODOT --headless --path . --fixed-fps 90 res://tests/quest_perf_overlay_test.tscn -- --desktop
# Diagnostics: 40 s of sparring stats per difficulty, block traces
$GODOT --headless --path . --fixed-fps 90 res://tests/diag/diag_spar.tscn -- --desktop normal
```
- `physics_test` checks the dummy (stands, staggers, knockdown, gets up), velocity-scaled damage, the wall stopping a thrust, and blade clashes.
- `combat_test` checks:
  - the katana settles in about 0.13 s and the kanabō lags (about 0.47 s);
  - pushing into the dummy does not bulldoze it, and the arm gives way;
  - a dense distance fog with a clear arena (fog amount at 3 m, at the giant torii and at 15 m);
  - hit-stop timing and the trail;
  - parrying the dummy's strike leads to slow-mo, stun, counter window and a counter hit;
  - the katana keeps real-time tracking during slow-mo;
  - free grip on the handle (*tsuka*), guard (*tsuba*) and blunt side of the blade (*mune*, snapping away from the cutting edge);
  - two-handed grip (second hand attaches without releasing the first, steers the weapon between both hands, boosts force/torque on heavy weapons, and seamlessly hands off to the remaining hand when either hand lets go);
  - Dojo of the Storm arena nodes (water, mist, fog), the lightning flash (global `storm_flash`, fog and ambient brighten, flash light switched off afterwards), rain setup, thunder after a strike, audio buses, and the micro hit-stop.
- `grip_stability_test` checks that the katana and kanabō (one- and two-handed, at 72 and 90 Hz, with simulated tracking noise) hold still without oscillating, that a heavy body slamming into the blade or a kick at the tip does not knock it out of the hand, that a weapon flying off past 0.4 m is put back in the hand, that weapons ignore the player's own bodies, and that the VR hand model never drifts more than 0.3 m from the controller.

- `sword_ik_test` checks the dummy's IK arm: accuracy around the guard, smooth tracking of a moving blade line, cost per tick, and the physical sword reaching the wanted lines.
- `enemy_ai_test` checks that each attack (vertical, horizontal, thrust) has its own blade path, a visible tell of at least 0.4 s and hurts an unguarded player exactly once; that a parry interrupts the attack into a stagger with no damage and the dummy then recovers; the fairness rules (no wind-up out of view, wind-up dropped when the player turns away); that a heavy hit interrupts a wind-up; combos, feints, chance-based blocks, light cuts parried and full-arm cuts breaking the guard, evading, the guard meeting the cuts that reach it, a riposte after a parry, punishing a missed swing and a raised blade; approaching, backing off and circling within view; calm footwork that follows a retreating player; the guard leaning toward the player's blade; a planted wind-up with a strike step and zanshin, varied tempo; difficulty presets; and the player's hurt vignette, defeat and revive.

- `blade_feel_test` checks the strike kind and multiplier from the angle between motion and edge (edge, flat, spine, thrust, hilt; kanabō blunt), that a handle or guard grip seats the sword the same way from any hand angle (spine grips keep it), that the same sweep through the dummy deals far more damage with the edge than the flat or spine, that the desktop slash lands with the edge, that a light press rests on the body while a deep shove slides through without wedging and leaves nothing stuck, that a fast slash through the dummy keeps the blade in the hand without launching the dummy, that a 25 kg body cannot tear the blade from the hand, and that a wrist flick at the same blade speed as an arm swing has no power (a fraction of the damage and impulse) while the kanabō hits harder than the katana.

All exit with code 0 when all checks pass. `res://tests/screenshots.tscn -- --desktop --shots /tmp/shots` renders screenshots. `tests/diag/` holds small diagnostic scenes, e.g. the Jolt joint-limit sign check and slow-mo tracking.

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

On Quest the renderer switches to **Compatibility** automatically (`rendering_method.mobile` override; the Godot XR docs recommend it for Android XR). `StartXR` asks the headset for 90 Hz (Quest 3 defaults to 72 Hz) and runs physics at the refresh rate it gets.

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
| **Grip** near any part of a weapon (handle, tsuba, or blunt blade spine) | grab it there; squeeze grip with the other hand too for a **two-handed grip**; release grip to let go with that hand |
| Grip + **B/Y** | recall the nearest free weapon into the hand |
| **B/Y** (without grip) | dummy attacks on / off |
| Thumbstick **click** | cycle the element of the weapon in that hand |
| **A/X** | reset the dummy |

To practice parries: turn the dummy's attacks on, stand about 1.3–1.5 m in front of it, watch for the glowing eyes and meet the cut with your blade held across it (vertical cut: blade horizontal above your head; horizontal cut: blade upright on that side; thrust: knock the point aside).

## Project layout
```
addons/            godot-xr-tools, godotopenxrvendors (third-party, see LICENSES.md)
assets/            only assets the game uses (tracked)
assets_raw/        original downloaded packs (git-ignored, Godot-ignored)
data/enemies/      EnemyProfile resources (stats, resistances, tactics as data)
docs/              GDD and brief
scenes/            training_arena, test_room, player rigs, weapons
src/core/          GameEvents (event log), TimeController (hit-stop, micro-stop, slow-mo), Elements, Sfx (+ audio buses), test room, StormLightning, StormAmbience
src/shaders/       Dojo of the Storm shaders (sky, sky dome, water mirror, water mist, stone platform, spawn seal, lightning bolt, rain) and shared materials (wet_surface, katana_steel)
src/vfx/           StormRain (rain streaks, splashes, blade drips)
tools/             offline generators (gen_storm_audio.py → assets/audio/generated/)
src/player/        XR rig, desktop rig, WeaponHolder (grab/recall/haptics), PlayerHealth, HurtFeedback
src/weapons/       BladeBody (blade, element, pre-impact velocity), HeldWeapon (PD follow, hits, clashes, parry), BladeTrail
src/enemies/       ActiveRagdoll, TrainingDummy, EnemyBrain / DuelistBrain (+ DuelistDifficulty), EnemyProfile
src/debug/         hit debug panel, damage numbers, spark bursts
tests/             headless physics test, screenshots, diagnostics
```

## Look & feel (Quest 3, Compatibility renderer)
The target is a realistic, cinematic night storm ("premium, never cheap", GDD §9), within 72+ fps on Quest 3. Everything below runs without post-processing that Compatibility lacks.
- **Tonemapping and grade:** ACES, exposure 1.1. Compatibility has no LUT pass, so the grade lives in the palette: violet/navy fog and sky, cold moonlight, and only a few strong accents (vermilion torii, the active element's neon on the seal, sparks, lightning).
- **Light:** one directional moon, low behind the giant torii, so silhouettes read against brighter fog. Ambient comes from a flat color, reflections from a static sky shader (`storm_sky.gdshader`, radiance only). The lightning light exists only while a strike is visible.
- **Glow:** only HDR emission blooms (threshold 1.15), on desktop. Glow is an extra full-screen pass, so it is switched off on Android/Quest.
- **Materials:** everything is PBR and wet. `wet_surface.gdshader` soaks surfaces (darker, slightly smoother) but keeps them matte; a glossy water film forms only in patches on up-facing surfaces and in rain streaks down walls, so moonlight diffuses instead of sheening off like plastic. It also adds grime at the waterline, wood grain and a diffuse sky fill that keeps backlit props readable without another light pass. Scanned assets keep their own PBR maps (albedo, normal, metal/rough, AO) under that rain treatment (`normal_texture`, `orm_texture`, `orm_mode`). The katana (Poly Haven, ARM texture) is polished steel with rain beads and a rain-darkened handle. The platform is tiled with Poly Haven's *Japanese Stone Wall* under procedural wear; the stone between puddles is rough with scanned AO and relief, while the puddles are near-mirrors with raindrop rings. The moon's specular is not boosted (`arena_test` guards this and the matte materials). New textures are imported VRAM-compressed; static models import with *Static Lightmaps* (UV2) and auto LODs.
- **Storm:** the global shader uniforms `storm_flash`, `storm_flash_dir`, `moon_direction` and `storm_fog_color` (in `project.godot`) let sky, water, mist, seal, katana and rain all react to one lightning strike. The fog and ambient brighten with it.
- **No camera motion of any kind** (no head-bob or shake): VR comfort.
- **LightmapGI must be baked by hand:** Godot has no scripting API for baking. Open `scenes/training_arena.tscn`, select `Arena/LightmapGI`, click **Bake Lightmaps**, then commit the generated `.lmbake`. Until then the arena uses the moon light and ambient only.
- **Performance still has to be measured on the device** (OVR Metrics Tool, GPU level, frame timing). Main suspects if it drops below 72 fps: fog plus the water shader's fill rate, the 1400 rain streaks, and the moon shadow (orthogonal, 14 m).

### Needed assets (to go from good to premium)
The torii, katana, weapon stand, rocks and platform stone are now scanned/PBR assets (see `CREDITS.md`). Still missing:
1. **Training dummy model:** a rigged wooden makiwara or wara-ningyō dummy with PBR textures, to replace the primitive capsules.
2. **Audio recordings:** heavy rain on stone and water (stereo loop), distant thunder rolls (3–5), katana draw and cut whooshes, steel-on-steel clashes and rings, wood bokken hits.
3. **Night-sky HDRI** with clouds (for example from Poly Haven), to bake a richer reflection cubemap.
4. **Sakura tree** (stylized-realistic, with alpha-tested petals that fit the Quest budget), to bring back the tree that was removed.

## How the physics works (short)
- **Katana:** a `RigidBody3D` driven by a stable PD controller.
  - Force goes on the center of mass toward the hand pose, torque toward the hand orientation, and the weapon's own weight is held.
  - Force and torque are capped by the player's arm strength (260 N, 40 N·m). A heavier weapon therefore accelerates less and lags.
  - **Free & two-handed grip:** grabbing records a local grip transform clamped to the handle (*tsuka*), guard (*tsuba*), or blunt spine of the blade (*mune*, `+Y`, never the cutting edge `-Y`). With two hands attached, the target weapon pose aligns the line between both grip points with the line between both hands, blends wrist roll, and scales arm force/torque (`×1.6` / `×1.8`). Releasing either hand transfers control to the remaining hand at its grip point.
  - **Hand priority** (`HeldWeapon._keep_in_hand`): beyond 3.5 cm / 30° (`max_grip_offset`, `max_grip_angle`; with two hands the twist limit shrinks with the hands' spread) the weapon is put back within the limit and loses velocity away from the hand (it gets at most 8 m/s toward it, never spin, so a heavy weapon's weight still shows in how fast it turns). Exceptions: if the corrected pose would overlap static geometry the blade stays where physics put it (ghost hand); if it would overlap an enemy body the blade may rest on it up to 10 cm / 50° behind the hand, and past that it follows the hand into that body part (collision exception until it is out again, `blade_wedge_release` event) and the cut is registered at the hand's speed there.
  - While the blade is held back like that, strength drops to 30%, so it rests on obstacles instead of shoving them.
  - **Strike classification** (`HeldWeapon.classify_strike`): the motion relative to the target, minus its component along the blade, is compared with the edge's outward normal (`-spine_direction`): cos ≥ 0.5 edge, ≤ −0.5 spine, else flat; motion along the blade near the tip is a thrust, contacts on the handle/guard are the hilt.
  - The damping term is implicit (divided by `1 + kd·dt`), so the controller is critically damped at any tick rate. With explicit damping it rang every tick at 90 Hz and was unstable at 72 Hz, which showed up as a buzzing blade on Quest.
  - **Never flies away:** the weapon's speed and spin are capped at the hand's own plus 4 m/s / 18 rad/s; a new impact with a moving body may change its velocity by at most 2 m/s / 12 rad/s beyond what the arm does; a weapon more than 0.4 m from the hand and still moving away is put back in the hand (unless the hand is behind something solid); with hand priority this only matters behind walls. The hand model follows the grip only within 0.3 m of the controller. Weapons never collide with the player's own bodies (`HeldWeapon.register_player_collision_exceptions`).
- **Weapon hit speed:** each weapon stores its velocity before every physics step. On a new contact, the hit speed is the relative velocity of the two contact points *before* the solver slowed them down. Damage = `(speed − 1.5 m/s) × 9` (×13 for the kanabō), capped at 120, times the strike multiplier (edge 1.0 / flat 0.3 / spine 0.2 / hilt 0.3), the zone multiplier and ×1.5 for counters.
- **Time effects (`TimeController`):**
  - Hit-stop and slow-mo set `Engine.time_scale` and are timed in real time (counted in physics ticks, which stay at 90/s). The hand's velocity fed to the weapon controller is measured over real time; hand priority keeps the blade in the hand during a hit-stop (the world freezes, the hand doesn't).
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
