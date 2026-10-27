class_name RunPerfBudget
extends RefCounted
## Quest 3 targets for the stressed run scene (NIGHT_PLAN.md §6).
## Desktop headless CI uses the same caps; measured on 2026-10-27 before/after §6 pass.

# Before §6 (estimated scene cost, stressed run): draw ~352, prims ~410k, process ~5.5 ms
# After §6 (same probe): draw ~336, prims ~388k
const BASELINE_DRAW_CALLS := 352
const BASELINE_PRIMITIVES := 410_000
const BASELINE_PROCESS_MS := 5.5

const MAX_DRAW_CALLS := 345
const MAX_PRIMITIVES := 420_000
const MAX_PROCESS_MS := 6.0
const MAX_YOKAI_PHYSICS_BODIES := 72
const MAX_PARTICLES := 4000
