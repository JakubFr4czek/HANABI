class_name Stamina
extends RefCounted
## Sprint stamina (F6). Sprinting drains it; when it runs out the player is winded and
## moves slower until it has refilled to [constant RECOVER_RATIO]. It refills after
## [constant REGEN_DELAY_SEC] without sprinting. RunGame steps it every physics tick and
## multiplies [method speed_multiplier] into the locomotion speed. All tuning lives here.

## Fired once each time the bar hits empty (haptic cue on the hands).
signal exhausted

const MAX := 100.0
const DRAIN_PER_SEC := 20.0
const REGEN_PER_SEC := 15.0
const REGEN_DELAY_SEC := 1.0
## Sprint top speed over the walking pace.
const SPRINT_SCALE := 1.5
## Winded pace (empty bar) over the walking pace, until the bar is back at RECOVER_RATIO.
const EXHAUSTED_SCALE := 0.6
const RECOVER_RATIO := 0.3

var value := MAX
var is_exhausted := false
var is_sprinting := false
var _rest := REGEN_DELAY_SEC


func reset() -> void:
	value = MAX
	is_exhausted = false
	is_sprinting = false
	_rest = REGEN_DELAY_SEC


## One tick: [param wants_sprint] is the sprint input (stick click latch / Shift),
## [param moving] whether the move input is actually pushed.
func step(delta: float, wants_sprint: bool, moving: bool) -> void:
	if delta <= 0.0:
		return
	is_sprinting = wants_sprint and moving and not is_exhausted
	if is_sprinting:
		_rest = 0.0
		value -= DRAIN_PER_SEC * delta
		if value <= 0.001:
			value = 0.0
			is_sprinting = false
			is_exhausted = true
			exhausted.emit()
		return
	_rest += delta
	if _rest >= REGEN_DELAY_SEC:
		value = minf(value + REGEN_PER_SEC * delta, MAX)
	if is_exhausted and value >= MAX * RECOVER_RATIO:
		is_exhausted = false


func ratio() -> float:
	return clampf(value / MAX, 0.0, 1.0)


## Multiplies the walking speed: sprint, winded, or plain walk.
func speed_multiplier() -> float:
	if is_exhausted:
		return EXHAUSTED_SCALE
	return SPRINT_SCALE if is_sprinting else 1.0
