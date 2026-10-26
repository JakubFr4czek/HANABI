# Licenses

Every third-party file in this repository, where it came from and under which license.
Update this file whenever an asset or plugin is added (see `docs/GDD.md`, section 10).

## Layout rules
- `assets/` holds only the files the game actually uses. They are committed.
- `assets_raw/` holds the original downloaded packs (about 436 MB). It is **git-ignored** and has a `.gdignore`, so Godot does not import it. Copy a file from there into `assets/` when you need it and add a row below.
- **Vacuous BGM** (`assets_raw/.../vacuous_horror_bgm_vol06/`) may be used in the shipped game but its license forbids redistributing the raw audio files. It must never be committed. `.gitignore` blocks it.

## Plugins (`addons/`)

| Path | Source | Author | License |
|---|---|---|---|
| `addons/godot-xr-tools/` (v4.5.2) | https://github.com/GodotVR/godot-xr-tools | Bastiaan Olij and contributors | MIT (`addons/godot-xr-tools/LICENSE`) |
| `addons/godot-xr-tools/hands/` | bundled with godot-xr-tools | DigitalN8m4r3 (Miodrag Sejic) | CC0 1.0 (`hands/License.md`) |
| `addons/godotopenxrvendors/` (v5.1.0-stable) | https://github.com/GodotVR/godot_openxr_vendors | Godot XR contributors / W4 Games | MIT (plugin code) |
| `addons/godotopenxrvendors/khronos/`, `androidxr/`, `pico/`, `magicleap/` | bundled OpenXR loaders | Khronos Group and vendors | Apache 2.0 (`LICENSE` in each folder) |
| `addons/godotopenxrvendors/meta/` | bundled Meta OpenXR loader | Meta Platforms | Oculus SDK License (`meta/LICENSE-SDK`, `meta/LICENSE-LOADER`) |

## Assets in use (`assets/`)

| Path | Source | Author | License |
|---|---|---|---|
| `assets/audio/sfx/sword_swing/sword.*.ogg` | https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes | StarNinjas | CC0 |
| `assets/audio/sfx/sword_clash/sword_clash.*.ogg` | same pack | StarNinjas | CC0 |
| `assets/audio/sfx/impact/impactPlank_medium_*.ogg`, `impactPunch_heavy_*.ogg` | https://kenney.nl/assets/impact-sounds | Kenney | CC0 |
| `assets/models/weapons/katana_grab3d/katana.glb` | https://grab3d.com/models/weapons/katana/ | Grab3D | CC0 1.0 |
| `assets/models/environment/Torii_Gate_Quaternius.glb` | https://poly.pizza/m/7SyXZ62xR5 | Quaternius | CC0 |
| `assets/models/environment/Lantern_KayLousberg.glb` | https://poly.pizza/m/CtHBJ1ufeW | Kay Lousberg | CC0 |

## Generated in-project (no third-party license)
- Training dummy, the dummy's bokken, the kanabō, and the **Dojo of the Storm** training arena (`scenes/training_arena.tscn`): built from Godot primitives (`CylinderMesh`, `TorusMesh`, `PlaneMesh`, `SphereMesh`, `BoxMesh`), custom shaders (`src/shaders/*.gdshader`), and the procedural `ImmediateMesh` generator `StormLightning` for branching storm bolts.
- Blade trails and spark bursts: generated at runtime (`ImmediateMesh`, `CPUParticles3D`).

## Raw packs available locally (`assets_raw/`, not committed)

| Folder | Source | Author | License |
|---|---|---|---|
| `katana/Katana_ColoradoStark/` | https://opengameart.org/content/katana-2 | Colorado Stark | CC0 |
| `katana/grab3d_katana/` | https://grab3d.com/models/weapons/katana/ | Grab3D | CC0 1.0 |
| `environment/polypizza/Torii_Gate_Quaternius.glb` | https://poly.pizza/m/7SyXZ62xR5 | Quaternius | CC0 |
| `environment/polypizza/Shrine_KayLousberg.glb` | https://poly.pizza/m/tFxdxO5clk | Kay Lousberg | CC0 |
| `environment/polypizza/Lantern_KayLousberg.glb` | https://poly.pizza/m/CtHBJ1ufeW | Kay Lousberg | CC0 |
| `environment/pixor_cherry_tree/` | https://pixor.art/library/nature/cherry-tree/ | Pixor | CC0 |
| `environment/grab3d_cherry_tree/` | https://grab3d.com/models/nature/cherry-blossom-tree/ | Grab3D | CC0 1.0 |
| `environment/kenney_nature-kit/` | https://kenney.nl/assets/nature-kit | Kenney | CC0 |
| `enemies/quaternius_ultimate_monsters/*.glb` (45 animated models) | https://quaternius.com/packs/ultimatemonsters.html | Quaternius | CC0 |
| `enemies/quaternius_universal_base_characters/` (+ hairstyles) | https://quaternius.com/packs/universalbasecharacters.html | Quaternius | CC0 (Standard/free edition) |
| `enemies/quaternius_universal_animation_library/` | https://quaternius.com/packs/universalanimationlibrary.html | Quaternius | CC0 |
| `textures/rough_wood`, `rock_pitted_mossy`, `cobblestone_01`, `sakura_bark` | https://polyhaven.com | Poly Haven | CC0 |
| `hdri/moonless_golf_2k.hdr` | https://polyhaven.com/a/moonless_golf | Poly Haven | CC0 |
| `vfx_shaders/kenney_particle-pack/` | https://kenney.nl/assets/particle-pack | Kenney | CC0 |
| `vfx_shaders/procedural_slash.gdshader` | https://thegodotbarn.com/contributions/shader/86/procedural-slash | Casual Garage Coder (alkaliii) | CC0 |
| `vfx_shaders/lightning_fencerdevlog.gdshader` | https://godotshaders.com/shader/lightning/ | FencerDevLog | MIT (keep the notice in the file) |
| `vfx_shaders/GPUTrail-main/` | https://github.com/celyk/GPUTrail | celyk | MIT |
| `sfx/starninjas_swords/` | https://opengameart.org/content/20-sword-sound-effects-attacks-and-clashes | StarNinjas | CC0 |
| `sfx/kenney_impact-sounds/` | https://kenney.nl/assets/impact-sounds | Kenney | CC0 |
| `music/vacuous_horror_bgm_vol06/` | https://vacuous2409.itch.io/horror-exploration-bgm-pack-vol06 | Vacuous BGM | Free for games incl. commercial, no attribution; **do not redistribute the audio files**; never commit |
| `music/orientalsomber.ogg`, `.mid` | https://opengameart.org/content/oriental-somber | Tozan | CC0 |
| `music/ruskerdax_-_kamogawa_nightbreak.mp3` | https://opengameart.org/content/kamogawa-nightbreak | Ruskerdax | CC0 |
| `fonts/yujisyuku`, `yujiboku`, `yujimai`, `zenantique` | https://github.com/google/fonts/tree/main/ofl | Kinuta Font Factory / Yoshimichi Ohira | SIL OFL 1.1 |

Not downloaded (need a login, see `assets_raw/*/MANUAL_DOWNLOADS.md`): Sketchfab CC-BY models, Mixamo, Freesound sounds. If any of them is added, it needs a row here and a CC-BY credit in `CREDITS.md`.
