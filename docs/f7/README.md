# F7 – soul vessels (naczynia dusz): the goal of a run

Lore (Jakub, 02.11): the souls of the villagers are sealed in objects scattered through the
forest. The player looks for them; they are rare.

## Decisions
- **Vessel = small komainu statuette** (scan "Lion-dog (Komainu, from Hanazono Shrine)" by Yu,
  CC BY 4.0, `assets/models/props/komainu/`, 3.9k tris, fitted to 0.62 m). It reads as a
  realistic weathered stone object, not a toy prop, and differs from the tōrō lanterns
  already along the paths. Over it hangs a pale hitodama-blue wisp with an additive halo
  (depth tested: trunks hide it, like the torii lamps) and one short-range omni light that burns
  only within 24 m (vessels are ≥45 m apart, so at most one light; within the ≤12 lights budget).
- **5 per run** (`SoulVesselManager.COUNT`), planned at run start from `world_seed` and the
  analytic footpath network only (no loaded chunks needed), so a seed always gives the same spots:
  50–150 m from the spawn, one per sector round the spawn, 1.4–2.6 m beside a path (≤8 m),
  ≥45 m apart, clear of torii gates. Rarer than the hokora shrines.
- **Release**: within 2.4 m, A/X (VR) or E (desktop), through `RunGame.reach_for_offering`
  (the vessel takes the press before the shrine). The wisp rises 3 m and fades (1.8 s), the
  light flares and dies, a soft chime and the suzu sound; the statue stays dark.
- **HUD**: wrist row `DUSZE n/5` (F1 `set_row`, bar in soul-blue).
- **Win**: 5/5 → `RunGame._end_run(true)`: the existing end of run (stele + RUN AGAIN ema),
  with 救 / "THE VILLAGE IS SAVED" in place of 散 / chiru, no death slow-fall. The stele's last
  line counts souls freed on every run. Death works as before.
- **Lore text**: on the vessel's own sign when in reach: "A villager's soul is sealed in this
  stone. / A / X  RELEASE IT". Not added to the controls hint (its 4-line layout is pinned by the
  F4 tests) or the menu header (no free row) – a 1–2 line lore plate in the intro is left for later.

## Tests
`tests/hokora_test.gd` (`-- --desktop --only-f7`, `--f7-shots` writes the screenshots here):
exactly 5, spacing, path reach, determinism, one press = one soul, `DUSZE 1/5`, 5/5 = saved;
windowed: the glow lifts the vessel above the forest from 8 m (before/after same camera).
