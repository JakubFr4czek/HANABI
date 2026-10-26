extends Node
## Central gameplay event bus and log (autoload "GameEvents").
##
## Every gameplay system reports what happened here, in one place. The debug UI
## listens to the signals now; the later telemetry / Meta AI phase will read the
## same log (see docs/GDD.md, section 8). Keep payloads plain Dictionaries of
## primitive values (no node references) so they can be serialized as-is.

## Emitted for every logged event.
signal event_logged(event: Dictionary)
## A weapon hit a damageable body part. See [method report_hit] for keys.
signal hit_landed(hit: Dictionary)
## Two weapons collided. See [method report_clash] for keys.
signal weapon_clash(clash: Dictionary)

const MAX_LOG_SIZE := 4000

var _log: Array[Dictionary] = []
var _run_start_msec := Time.get_ticks_msec()


## Seconds since the current run started.
func run_time() -> float:
	return (Time.get_ticks_msec() - _run_start_msec) / 1000.0


## Append an event to the log. [param type] is a short snake_case name.
func log_event(type: String, data: Dictionary = {}) -> Dictionary:
	var event := data.duplicate()
	event["type"] = type
	event["t"] = snappedf(run_time(), 0.001)
	_log.append(event)
	if _log.size() > MAX_LOG_SIZE:
		_log.pop_front()
	event_logged.emit(event)
	return event


## Report a weapon hit. Expected keys: attacker, target, part, zone,
## speed (m/s, relative at the contact point), damage, point (Vector3),
## direction (Vector3, normalized swing direction).
func report_hit(hit: Dictionary) -> void:
	hit_landed.emit(log_event("hit", hit))


## Report a weapon-vs-weapon collision. Expected keys: attacker, defender,
## speed (relative m/s), angle_deg (between blade axes), point (Vector3).
func report_clash(clash: Dictionary) -> void:
	weapon_clash.emit(log_event("clash", clash))


## Most recent events, newest last. Optionally filtered by type.
func recent(count: int, type: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(_log.size() - 1, -1, -1):
		if type == "" or _log[i].get("type") == type:
			out.push_front(_log[i])
			if out.size() >= count:
				break
	return out


func clear() -> void:
	_log.clear()
	_run_start_msec = Time.get_ticks_msec()
