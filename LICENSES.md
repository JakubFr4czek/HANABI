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
| `assets/audio/sfx/cc0_combat/*.ogg` | https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 (`assets/audio/sfx/cc0_combat/LICENSE.txt`) |
| `assets/audio/sfx/kenney_run/*.ogg` | https://kenney.nl/assets/interface-sounds & https://kenney.nl/assets/impact-sounds | Kenney | CC0 1.0 (`assets/audio/sfx/kenney_run/LICENSE.txt`) |
| `assets/audio/sfx/cc0_storm/*` | https://opengameart.org/content/amb-rain-loop-1 , https://opengameart.org/content/rain-long-thunder , thunderclap WAV on OGA | Kresiek The Furry / WuxiaScrub / OGA submitters | CC0 (`assets/audio/sfx/cc0_storm/LICENSE.txt`) |
| `assets/audio/sfx/bonsho/bonsho_*.wav` | https://commons.wikimedia.org/wiki/File:Bonsyou5599.ogg | Jnn | **CC BY 2.1 JP** / FAL / CC BY-SA (`assets/audio/sfx/bonsho/LICENSE.txt`) |
| `assets/audio/music/cc0_run/orientalsomber.ogg` | https://opengameart.org/content/oriental-somber | Tozan | CC0 |
| `assets/audio/music/cc0_run/shakuhachi_taiko_layer.wav` | in-project arrangement of CC0 taiko (Scott Harding / Singapore Wind Symphony) & public domain shakuhachi (Araki Kodō III) recordings | Singapore Wind Symphony / Araki Kodō III / HANABI | CC0 1.0 (`assets/audio/music/cc0_run/LICENSE.txt`) |
| `assets/models/environment/torii_bazylonator/` ("Japanese Torii gate Game Asset", hero torii) | https://sketchfab.com/3d-models/japanese-torii-gate-game-asset-e12d2fa1b2b94928b8b87cb7787e2462 | Bazylonator | **CC BY 4.0**, modified (rescaled, rain/wet shading); credited in `CREDITS.md` and in game |
| `assets/models/environment/torii_old_primagenevieve/` ("Old Torii", sunken torii) | https://sketchfab.com/3d-models/old-torii-34f21f85784a4dcf9e0f9c6b9d772e37 | Sarah Nguyen (Nguyen Phuong Hoa) (primagenevieve) | **CC BY 4.0**, modified (rescaled, darkened, wet shading); credited in `CREDITS.md` and in game |
| `assets/models/environment/lanterns/stone_lantern_sahir.glb` (hero stone lantern, D5) | https://sketchfab.com/3d-models/japanese-stone-lantern-e0417d1e05984727a50f9ab1451d162d | Sahir Virmani | **CC BY 4.0**, modified (scaled to metres, four textures packed into one 2K atlas, `tools/prep_forest_assets.py`); credited in `CREDITS.md` and in game |
| `assets/models/environment/forest_trees/scots_pine.glb` (forest pine, D5) | https://sketchfab.com/3d-models/scots-pine-trees-set-422b961ff3d14e7baa7e9077572b2247 | Maksim Batyrev | **CC BY 4.0**, modified (one tree of the set cut out, scaled to metres, atlas, `tools/prep_forest_assets.py`); credited in `CREDITS.md` and in game |
| `assets/models/environment/forest_trees/giant_redwood.glb` (forest sugi, D5) | https://sketchfab.com/3d-models/giant-redwood-1a2052c58869479eb7b204d5cdc7c63a | rhcreations | **CC BY 4.0**, modified (decimated 14k to 6k triangles, textures packed into one 2K atlas, `tools/prep_forest_assets.py`); credited in `CREDITS.md` and in game |
| `assets/textures/forest_ground/moss002/moss002_diff_1k.jpg`, `moss002_nor_gl_1k.jpg` (ground moss, D5) | https://ambientcg.com/view?id=Moss002 | ambientCG (Lennart Demes) | CC0 1.0 |
| `assets/models/enemies/oni_mask_run.glb`, `oni_mask_run_normal.png` | `tools/gen_oni_mask_glb.py`, `ONI_MASK_LICENSE.txt` | Jakub Frączek (HANABI) | CC0 1.0 — §17: no suitable external CC0 GLB without login |
| `assets/models/enemies/oni_body_run.glb`, `oni_kanabo_run.glb` | `tools/gen_oni_body_glb.py` | Jakub Frączek (HANABI) | CC0 1.0 (§21 procedural boss shell) |
| `assets/fonts/YujiBoku-Regular.ttf` | https://github.com/google/fonts/tree/main/ofl/yujiboku | Kinuta Font Factory | SIL OFL 1.1 (`assets/fonts/LICENSE.txt`) |
| `assets/fonts/Cinzel-Variable.ttf`, `OFL-Cinzel.txt` | https://github.com/google/fonts/tree/main/ofl/cinzel | The Cinzel Project Authors (Natanael Gama) | SIL OFL 1.1 (`assets/fonts/OFL-Cinzel.txt`); free, no attribution required in game, 125 KB |
| `assets/models/weapons/antique_katana_01/` (glTF, 2K) | https://polyhaven.com/a/antique_katana_01 | Tal Swicegood (Poly Haven) | CC0 1.0 |
| `assets/models/props/katana_stand_01/` (glTF, textures downscaled to 1K) | https://polyhaven.com/a/katana_stand_01 | Rico Cilliers (Poly Haven) | CC0 1.0 |
| `assets/models/environment/rocks/rock_face_01/` (glTF, textures 1K) | https://polyhaven.com/a/rock_face_01 | Dario Barresi (Poly Haven) | CC0 1.0 |
| `assets/textures/forest_ground/leafy_grass/` (1K) | https://polyhaven.com/a/leafy_grass | Charlotte Baglioni (Poly Haven) | CC0 1.0 |
| `assets/textures/forest_ground/forrest_ground_01/` (1K) | https://polyhaven.com/a/forrest_ground_01 | Rob Tuytel (Poly Haven) | CC0 1.0 |
| `assets/textures/forest_path/ground067_*_1k.jpg` (colour and GL normal, 1K) | https://ambientcg.com/view?id=Ground067 | Lennart Demes (ambientCG) | CC0 1.0 |
| `assets/textures/forest_ground/rocky_trail/` (1K) | https://polyhaven.com/a/rocky_trail | Amal Kumar (Poly Haven) | CC0 1.0 |
| `assets/models/environment/rocks/rock_face_02/` (glTF, textures 1K) | https://polyhaven.com/a/rock_face_02 | Dario Barresi, Rico Cilliers (Poly Haven) | CC0 1.0 |
| `assets/textures/japanese_stone_wall/` (diff, nor_gl, arm; 1K) | https://polyhaven.com/a/japanese_stone_wall | Rico Cilliers, Charlotte Baglioni, Dario Barresi (Poly Haven) | CC0 1.0 |

## Generated in-project (no third-party license)
- Training dummy, the dummy's bokken, the kanabō, and the **Dojo of the Storm** training arena (`scenes/training_arena.tscn`): built from Godot primitives (`CylinderMesh`, `TorusMesh`, `PlaneMesh`, `SphereMesh`, `BoxMesh`), custom shaders (`src/shaders/*.gdshader`), and the procedural `ImmediateMesh` generator `StormLightning` for branching storm bolts.
- Blade trails and spark bursts: generated at runtime (`ImmediateMesh`, `CPUParticles3D`).
- Rain, splashes and blade drips: runtime `GPUParticles3D` with `src/shaders/rain_streak.gdshader`.
- `assets/audio/generated/*.wav` (rain loop, distant thunder, blade ring, enemy wind-up whoosh, player hurt thump, edge cut, flat slap): synthesized from noise and sine partials by `tools/gen_storm_audio.py`; no recordings involved.

## Raw packs available locally (`assets_raw/`, not committed)

| Folder | Source | Author | License |
|---|---|---|---|
| `HANABI_assets_midpoly/` (Sketchfab CC BY 4.0 sakura trees, torii, stone lanterns, platform, dummy; Poly Haven CC0 rocks, katana, stand, textures, sky) | per-asset links in `assets_raw/HANABI_assets_midpoly/CREDITS.md` | see that file | CC BY 4.0 / CC0 1.0 (each CC BY model needs an in-game credit if used) |
| `katana/Katana_ColoradoStark/` | https://opengameart.org/content/katana-2 | Colorado Stark | CC0 |
| `katana/grab3d_katana/` | https://grab3d.com/models/weapons/katana/ | Grab3D | CC0 1.0 |
| `assets/audio/sfx/hanabi_proc/*.wav` (run stingers, forest wind, element imbue cues `imbue_*`, `element_fade`) | `scripts/generate_hanabi_proc_audio.py` in repo | Jakub Frączek / HANABI | CC0 (procedural) |
| `assets/models/environment/forest_trees/` (run forest MultiMesh; Grab3D cherry, canopy simplified, albedo recolored for night fog) | https://grab3d.com/models/nature/cherry-blossom-tree/ | Grab3D | CC0 1.0 |
| `assets/models/environment/forest_quaternius/tree_simple_quaternius.glb` (unused fallback mesh) | https://quaternius.com/packs/simplenature.html | Quaternius | CC0 |
| `assets/models/environment/forest_quaternius/torii_gate_polyfork.glb` (run forest MultiMesh) | https://polyfork.dev/asset/torii-gate-402f30 | polyfork.dev (Little Tokyo kit) | CC0 / commercial use per site |
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
| `splash/hanabi.ogv`, `splash/nanjo.ogv`, `splash/hanabi_boot.png` (frame of `hanabi.ogv`) | Nanjo (original) | Nanjo (studio's own work) | Own asset, not CC; boot splash and studio film. Re-encoded to 1280x720 Theora |

Not downloaded (need a login, see `assets_raw/*/MANUAL_DOWNLOADS.md`): Mixamo, Freesound sounds. Any CC BY asset added to `assets/` needs a row here, a credit in `CREDITS.md`, and a line in the in-game `CreditsLabel` (`scenes/training_arena.tscn`).
