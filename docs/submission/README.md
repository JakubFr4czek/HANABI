# Submission screenshots (N11)

Copies of existing in-game captures (real `run.tscn` renders from the windowed tests, 960×540,
Compatibility renderer). No new renders were made for N11.

| File | Source | Why this one |
|---|---|---|
| `01_first_person_combat.png` | `docs/n10/n10_04_fp_combat.png` | The core fantasy in one frame: katana in hand, three yōkai with glowing eyes closing in on the forest path, from the smoothed recording camera. |
| `02_oni_meta_ai_bubble.png` | `docs/n8/n8_01_ai_bubble.png` | The only frame that shows the Meta AI feature working: the Oni on the path with its Muse Spark line "You always cut from the right." over its head. |
| `03_four_schools_torii.png` | `docs/n3/POST_2_four_schools_8m.png` | Four yōkai of the four schools under a red torii, readable by eye colour at 8 m: explains the counter ring visually. |
| `04_shrine_ofuda.png` | `docs/f3/after_03_cards_rising.png` | The hokora shrine lit warm in the dark forest with the ofuda rising: the one warm accent in a cold palette and the buff loop. |
| `05_skill_tree_menu.png` | `docs/n9/n9_after_01_tree.png` | The in-world lacquer skill-tree panel (costs, kanji, unlock button) floating in the forest: shows progression and the diegetic UI style. |
| `06_forest_path_sakura_torii.png` | `docs/n4/final_torii30.png` | World overview: winding path, neon sakura crown and a distant lit torii in the fog. |

## Honest verdict
None of these frames is premium yet. Shared weaknesses:
- **Yōkai bodies** are blocky low-poly figures in flat blue/red; next to the scanned katana they
  read as placeholders (01, 02, 03).
- **Lighting is flat**: a uniform violet sky, nearly black tree silhouettes, a grey path that is the
  brightest thing in most frames; no rim light on the enemies (01, 03, 06).
- **Sakura crowns** are faceted blobs with a hard magenta edge (06), which tips toward kitsch.
- **Text** in the speech bubble and the debug-style overlay is small at 960×540 (02).
- The camera holds the katana low in the corner; the blade barely reads (01, 04).

No later N-task in the backlog targets these frames yet. The ones that would lift them most:
a yōkai body mesh pass (biggest gain, 01–03), a lighting / rim-light pass on enemies and trunks
(01, 03, 06), and a softer sakura crown material (06). For the video, the in-headset view and
motion (cuts, splits, fireworks) carry the game much better than these stills.
