# Credits

HANABI (花火) by Jakub Frączek, made for the Meta Global AI Developer Hackathon 2026.

## Code and plugins
- **Godot Engine**: Juan Linietsky, Ariel Manzur and contributors (MIT)
- **Godot XR Tools**: Bastiaan Olij and contributors (MIT); hand models by DigitalN8m4r3 (CC0)
- **Godot OpenXR Vendors**: Godot XR contributors / W4 Games (MIT), with the Khronos OpenXR loader (Apache 2.0) and the Meta OpenXR loader (Oculus SDK License)

## Assets in the game
- Katana: "Antique Katana 01" by **Tal Swicegood** (Poly Haven, CC0)
- Katana stand: "Katana Stand 01" by **Rico Cilliers** (Poly Haven, CC0)
- Rocks in the water: "Rock Face 01" by **Dario Barresi**, "Rock Face 02" by **Dario Barresi and Rico Cilliers** (Poly Haven, CC0)
- Platform stone texture: "Japanese Stone Wall" by **Rico Cilliers, Charlotte Baglioni and Dario Barresi** (Poly Haven, CC0)
- Run forest floor: "Leafy Grass" by **Charlotte Baglioni**, "Forest Ground 01" by **Rob Tuytel**, "Rocky Trail" by **Amal Kumar** (Poly Haven, CC0)
- Forest footpath: "Ground067" by **Lennart Demes** (ambientCG, CC0)
- Sword swing and clash sounds: **StarNinjas** (OpenGameArt, CC0)
- Impact sounds + combat cuts/slaps/hurt/tells: **Kenney** Impact Sounds (kenney.nl, CC0), `assets/audio/sfx/impact/` & `cc0_combat/`
- Run sting SFX (soul collect, firework, ofuda slice, level-up, yōkai slice): **Kenney** Interface Sounds & Impact Sounds (kenney.nl, CC0), in `assets/audio/sfx/kenney_run/`
- Bonshō temple bell (run start toll, Oni boss arrival, Torii gate imbue): authentic field recording at Chōmei-ji (長命寺), Shiga Prefecture, Japan by **Jnn** (Wikimedia Commons, CC BY 2.1 JP / FAL / CC BY-SA / GFDL), modified (DC offset removed, attack trimmed, resampled to 44.1 kHz, volume normalized to -1 dBFS, tuned per cue), `assets/audio/sfx/bonsho/`
- Forest wind bed, Torii gate fūrin (wind chime) & element imbue cues: procedural WAV in `assets/audio/sfx/hanabi_proc/` (project author, CC0)
- Storm rain + thunder: Kresiek The Furry, WuxiaScrub, OpenGameArt CC0 in `assets/audio/sfx/cc0_storm/` (see `LICENSE.txt`)
- Distant matsuri fireworks (D18): the far boom reuses Kenney Impact `thunder_impact_heavy_*` from `cc0_storm/`, and the near pop reuses `firework_pop_soft_000` from `kenney_run/` (both CC0, no new files)
- Run ambient music: Tozan "Oriental Somber" (OpenGameArt CC0), `assets/audio/music/cc0_run/orientalsomber.ogg`
- Run music shakuhachi & taiko ensemble layer: balanced arrangement combining CC0 taiko drum rhythm (Scott Harding / **Singapore Wind Symphony Percussion Ensemble**) and shakuhachi flute meditation (**Araki Kodō III**, Public Domain) into a seamless 24s loop on the Music bus, `assets/audio/music/cc0_run/shakuhachi_taiko_layer.wav`
- Forest ground moss (D5): "Moss002" by **Lennart Demes** (ambientCG, CC0), `assets/textures/forest_ground/moss002/`
- Run forest trees (`cherry_forest.gltf`, `cherry_forest_albedo.jpg`, `cherry_forest_normal.jpg`): "Cherry Blossom Tree" by **Grab3D** (CC0), crown simplified and the daylight blossoms recolored to night foliage, `assets/models/environment/forest_trees/`
- Run forest torii (distant MultiMesh): procedural torii gate from **polyfork.dev** (commercial/CC0 kit, no attribution required; credited here by choice)
- Interactive Torii gate & andon lantern: hexagonal paper andon with eaves and ribs, procedural mesh by project author (CC0)
- Custom shaders (blade rim fresnel, katana steel edge light, wrist element plate, torii halo): project author (CC0)
- Oni boss: mask `oni_mask_run.glb` + normal map; body `oni_body_run.glb` + kanabō `oni_kanabo_run.glb` (project CC0, `tools/gen_oni_mask_glb.py`, `tools/gen_oni_body_glb.py`; §17/§21 no account-free external boss mesh)
- Memorial stele engraving font: **Yuji Boku** (Kinuta, SIL OFL), `assets/fonts/YujiBoku-Regular.ttf`
- Skill-tree menu Latin lettering: **Cinzel** (The Cinzel Project Authors, SIL OFL 1.1), `assets/fonts/Cinzel-Variable.ttf`
- Boot splash films: "HANABI" firework film (`assets/splash/hanabi.ogv`, its frame is the boot still `assets/splash/hanabi_boot.png`) and "NANJO" studio film (`assets/splash/nanjo.ogv`): **Nanjo (original)**, the studio's own work; re-encoded to 1280x720 Theora for the game (`assets/splash/`)

## Required attributions (CC BY 4.0 / CC BY 2.1 JP)
These are also shown in game on the `CreditsLabel` under the controls board at the arena's edge.
- "Japanese Torii gate Game Asset" by Bazylonator (https://sketchfab.com/3d-models/japanese-torii-gate-game-asset-e12d2fa1b2b94928b8b87cb7787e2462), licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) — modified (rescaled, rain/wet shading over the original PBR textures).
- "Old Torii" by Sarah Nguyen (Nguyen Phuong Hoa) (primagenevieve) (https://sketchfab.com/3d-models/old-torii-34f21f85784a4dcf9e0f9c6b9d772e37), licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) — modified (rescaled, darkened, rain/wet shading over the original PBR textures).
- "Bonsyou5599" by Jnn (https://commons.wikimedia.org/wiki/File:Bonsyou5599.ogg), licensed under CC BY 2.1 JP / FAL / CC BY-SA — modified (DC offset removed, attack trimmed, resampled to 44.1 kHz, pitch and decay tuned for run start, Oni arrival, and gate imbue).

- "Japanese Stone Lantern" by Sahir Virmani (https://sketchfab.com/3d-models/japanese-stone-lantern-e0417d1e05984727a50f9ab1451d162d), licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) — modified (scaled to metres, textures packed into one atlas).
- "Giant Redwood" by rhcreations (https://sketchfab.com/3d-models/giant-redwood-1a2052c58869479eb7b204d5cdc7c63a), licensed under CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) — modified (decimated to about 6k triangles, textures packed into one atlas).

## Thanks (optional credits for CC0 packs available to the project)
Quaternius, Kay Lousberg, Poly Haven (Greg Zaal and team), Grab3D, Pixor, Tozan, Ruskerdax, Vacuous BGM, Casual Garage Coder, FencerDevLog, celyk (GPUTrail), Jnn, Scott Harding, Singapore Wind Symphony Percussion Ensemble, Araki Kodō III;
fonts by Kinuta Font Factory (Yuji), Yoshimichi Ohira (Zen Antique) and the Cinzel Project Authors, SIL OFL 1.1.
