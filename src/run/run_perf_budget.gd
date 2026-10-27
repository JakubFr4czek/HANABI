class_name RunPerfBudget
extends RefCounted
## Quest 3 targets for the stressed run scene (NIGHT_PLAN.md §6, §16).
## Desktop headless CI uses the same caps; re-checked 2026-10-27 after §9–§15
## (forest MultiMesh, combat fog, VfxPool firework light cap, CC0 audio/Music).

# Stressed run (8 yōkai + elements): draw ~330–340, prims ~385k, process ~5.2 ms
const BASELINE_DRAW_CALLS := 338
const BASELINE_PRIMITIVES := 388_000
const BASELINE_PROCESS_MS := 5.2

const MAX_DRAW_CALLS := 345
const MAX_PRIMITIVES := 420_000
const MAX_PROCESS_MS := 6.0
const MAX_YOKAI_PHYSICS_BODIES := 72
const MAX_PARTICLES := 4000
const MAX_DYNAMIC_LIGHTS := 12
const MAX_AUDIO_VOICES := 28
