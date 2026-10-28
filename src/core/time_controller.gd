extends Node
## Global time effects (autoload "TimeController"): hit-stop and slow motion.
##
## Effects are timed in *unscaled* game time (counted in physics ticks), so a 60 ms hit-stop lasts 60 ms
## for the player whatever the current time scale is. The lowest active scale
## wins.
##
## "Player compensation": during a parry slow-mo the world slows down but the
## player's own weapon should keep up with the real hand. Weapons read
## [method compensation] (1 / time_scale while compensated) and scale their
## controller gains with it. Hit-stop does not compensate, so the player's
## blade freezes together with the world for a moment.

signal effect_started(kind: String, scale: float, duration: float)

## Current effective time scale (same as Engine.time_scale).
var time_scale := 1.0
## True while an active effect asks to keep the player at real-time speed.
var player_compensated := false

var _effects: Array[Dictionary] = []
var _clock := 0.0  # unscaled seconds since start
## While a menu pauses the tree the effects are parked: their clock stops (so
## a parry slow-mo resumes with the exact time it had left) and
## Engine.time_scale reads 1.0, so the ALWAYS-processing rig and UI are not
## slowed down by a world that is standing still anyway.
var _suspended := false


## Freeze the world briefly on a strong hit (50–80 ms, GDD section 4).
func hit_stop(duration: float, scale: float = 0.05) -> void:
	_add("hit_stop", scale, duration, false)


## A barely-felt catch on medium hits and blade clashes (25–35 ms), so contact
## has weight without breaking the flow.
func micro_stop(duration: float, scale: float = 0.3) -> void:
	_add("micro_stop", scale, duration, false)


## Slow the world down; the player's weapon stays real-time if [param compensate_player].
func slow_motion(scale: float, duration: float, compensate_player: bool = true) -> void:
	_add("slow_motion", scale, duration, compensate_player)


## 1 / time_scale while the player is compensated, else 1.
func compensation() -> float:
	return 1.0 / time_scale if player_compensated else 1.0


## Compensation for a physics tick that simulated [param sim_delta] seconds.
## Uses the tick's actual delta, which stays correct on the tick where the
## time scale changes (that tick still has the old delta).
func compensation_for(sim_delta: float) -> float:
	if not player_compensated or sim_delta <= 0.0:
		return 1.0
	return real_tick() / sim_delta


## Real seconds per physics tick (the tick rate is real-time, only delta is scaled).
func real_tick() -> float:
	return 1.0 / Engine.physics_ticks_per_second


## Convert a speed measured in simulation units (m per simulated second) of a
## player-driven body into real-world m/s.
func to_real_speed(sim_speed: float) -> float:
	return sim_speed / compensation()


func is_active(kind: String = "") -> bool:
	for e in _effects:
		if kind == "" or e.kind == kind:
			return true
	return false


func clear() -> void:
	_effects.clear()
	_apply()


func is_suspended() -> bool:
	return _suspended


## Parks the active effects for a pause menu (see [member _suspended]).
## Remaining durations and the time scale are kept and come back on [method resume].
func suspend() -> void:
	if _suspended:
		return
	_suspended = true
	_apply()


func resume() -> void:
	if not _suspended:
		return
	_suspended = false
	_apply()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -1000  # expire effects before gameplay runs this tick


func _add(kind: String, scale: float, duration: float, compensate: bool) -> void:
	_effects.append({"kind": kind, "scale": clampf(scale, 0.01, 1.0), "until": _clock + duration, "compensate": compensate})
	effect_started.emit(kind, scale, duration)
	_apply()


func _physics_process(_delta: float) -> void:
	if _suspended:
		return
	# Physics ticks run at a fixed rate of real time whatever the time scale
	# (only their simulated delta shrinks), so counting ticks gives real time.
	_clock += 1.0 / Engine.physics_ticks_per_second
	if _effects.is_empty():
		return
	var kept: Array[Dictionary] = []
	for e in _effects:
		if e.until > _clock:
			kept.append(e)
	_effects = kept
	_apply()


func _apply() -> void:
	var scale := 1.0
	var compensate := false
	var slowest: Dictionary = {}
	for e in _effects:
		if e.scale < scale:
			scale = e.scale
			slowest = e
	if not slowest.is_empty():
		compensate = slowest.compensate
	time_scale = scale
	player_compensated = compensate
	if _suspended:
		Engine.time_scale = 1.0
		AudioServer.playback_speed_scale = 1.0
		return
	Engine.time_scale = scale
	# Audio: a gentle pitch drop in slow-mo; hit-stop keeps normal audio so the impact sound plays.
	AudioServer.playback_speed_scale = lerpf(1.0, scale, 0.5) if compensate else 1.0
