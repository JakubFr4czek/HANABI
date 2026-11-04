class_name RunDemoGrade
extends Node
## N14: demo-only start exposure (docs/n14/README.md). The first seconds of a demo
## run (`-- --demo`) are filmed for the trailer and read too dark on video, so the
## tonemap exposure starts a little higher and eases back to the profile's value.
## Exposure only: palette, fog, sky colour, ambient and lights stay untouched, and
## nothing else in the run writes tonemap_exposure (lightning writes fog/ambient).
## The default run never enables it.

## Full lift for the first HOLD seconds of the run (the intro counts as t = 0).
const HOLD_SECONDS := 10.0
## Smooth return to the profile exposure (≥ 5 s, GDD comfort: no visible pumping).
const FADE_SECONDS := 8.0
## Exposure multiplier at full lift (0.92 → ~1.19 with the default world profile).
const EXPOSURE_LIFT := 0.30

var enabled := false
var _env: Environment
var _base_exposure := 1.0
var _weight := 0.0


static func demo_launch() -> bool:
	return OS.get_cmdline_user_args().has(WaveProfile.DEMO_FLAG)


## Call after WorldGenLook.apply_light so the base is the profile's exposure.
func bind_environment(env: Environment) -> void:
	_env = env
	if _env:
		_base_exposure = _env.tonemap_exposure
	# Rebinding (profile re-applied) restarts from the base; the next step re-lifts.
	_weight = 0.0


func base_exposure() -> float:
	return _base_exposure


## 1 during the hold, smoothstep down to 0 over the fade, 0 afterwards.
static func lift_weight(run_time: float) -> float:
	if run_time <= HOLD_SECONDS:
		return 1.0
	var u := clampf((run_time - HOLD_SECONDS) / FADE_SECONDS, 0.0, 1.0)
	return 1.0 - u * u * (3.0 - 2.0 * u)


func current_weight() -> float:
	return _weight


func step(run_time: float) -> void:
	if _env == null:
		return
	var w := lift_weight(run_time) if enabled else 0.0
	if w == _weight:
		return
	_weight = w
	_env.tonemap_exposure = _base_exposure * (1.0 + EXPOSURE_LIFT * w)
