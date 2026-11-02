class_name N7PacingSim
extends RefCounted
## Stand-in run for the N7 pacing measurement (docs/SPAWN_PLAN.md, "N7 – pomiar").
## It drives the real run.tscn forest, the real WaveDirector and AnchorGuards in fixed
## 0.1 s steps of virtual time. The stand-in player walks (or stands), turns the view,
## and kills the yōkai that reach contact one at a time, with the same kill model as
## WavePlanner.simulate (hp / sim_player_dps, then sim_gap). Yōkai walk to the player at
## their move speed; guards only when the player is within AGGRO_M, otherwise they hold
## their post. Nothing here ships in the game: it only observes and advances the clock.

const DT := 0.1
const WALK_SPEED := 1.3
const CONTACT_M := 1.6
const AGGRO_M := 14.0
const SAMPLE_EVERY := 15.0
const BACK_DEG := 60.0
const EMPTY_FROM := 60.0
const EYE := Vector3(0.0, 0.9, 0.0)

var run: RunGame
var director: WaveDirector
var guards: AnchorGuards
var profile: WaveProfile

var samples: Array[Dictionary] = []
var spawns: Array[Dictionary] = []
## Every wave opening: {t, wave, state} (the director's own clock).
var wave_opens: Array[Dictionary] = []
## [t, Callable] pairs, time-ordered: the callable is awaited once the run clock reaches t
## (the visual test takes its pictures there, with frames rendered between steps).
var pauses: Array = []
var first_contact := -1.0
var first_oni := -1.0
var longest_empty := 0.0
var guard_slot_seconds := 0.0
var cap_seconds := 0.0
var max_alive := 0
var kills := 0

var _t := 0.0
var _empty := 0.0
var _queue: Array[Yokai] = []
var _engage_left := 0.0
var _kill_gap := 0.0
var _view := Vector3.FORWARD
var _center := Vector3.ZERO
var _heading := 0.0
var _heading_left := 0.0
var _pos := Vector2.ZERO
var _walk := false
var _walk_rng := RandomNumberGenerator.new()


## Plays [param seconds] of run on [param p_run] (already in the tree, physics of its own
## _physics_process switched off). [param walk] false = the player stands on the platform.
func play(tree: SceneTree, p_run: RunGame, p_director: WaveDirector, seconds: float, seed_value: int, walk: bool) -> void:
	run = p_run
	director = p_director
	guards = p_run.anchor_guards
	profile = director.get_profile()
	_walk = walk
	_walk_rng.seed = seed_value * 7919 + 17
	director.stop_director()
	director.clear_enemies()
	director.seed_spawns(seed_value)
	director.start_director()
	director.enemy_spawned.connect(_on_spawned)
	director.wave_started.connect(func(w: int, _n: int) -> void:
		wave_opens.append({"t": snappedf(director.run_seconds, 0.1), "wave": w,
			"state": WavePlanner.STATE_NAMES[director._planner.state]}))
	director.oni_spawned.connect(func(_o: RunOniBoss) -> void:
		if first_oni < 0.0:
			first_oni = director.run_seconds)
	_pos = Vector2(run.player.global_position.x, run.player.global_position.z)
	_heading = _walk_rng.randf() * TAU
	_heading_left = 6.0
	var steps := int(round(seconds / DT))
	for i in steps:
		# Walking streams forest chunks in physics frames; a standing player needs none.
		if walk:
			await tree.physics_frame
		_advance_player()
		_center = Vector3(_pos.x, run.forest_world.height_at(_pos.x, _pos.y) + 1.2, _pos.y)
		_view = _view_direction()
		director.step_director(DT, _center, _view)
		guards.step(DT, _center, _view)
		director.recall_stragglers(_center)
		_approach_and_fight()
		_measure()
		while not pauses.is_empty() and _t >= float(pauses[0][0]) - 0.0001:
			var pause: Array = pauses.pop_front()
			await (pause[1] as Callable).call(_t)
	director.enemy_spawned.disconnect(_on_spawned)
	director.stop_director()
	director.clear_enemies()


func summary() -> Dictionary:
	var out := {
		"requested": director.spawn_stats.requested,
		"placed": director.spawn_stats.placed,
		"skipped": director.spawn_stats.skipped,
		"reject": {
			"cone": director.spawn_stats.reject_cone,
			"back": director.spawn_stats.reject_back,
			"geometry": director.spawn_stats.reject_geometry,
		},
		"spawned": spawns.size(),
		"guards": 0, "wave_yokai": 0, "elites": 0,
		"in_cone": 0, "in_cone_occluded": 0, "behind": 0, "guard_behind": 0,
		"first_contact": first_contact, "first_oni": first_oni,
		"longest_empty_after_60": longest_empty,
		"max_alive": max_alive, "kills": kills,
		"guard_share": guard_slot_seconds / maxf(cap_seconds, 0.001),
		"samples": samples,
		"waves": wave_opens,
	}
	for s in spawns:
		if s.guard:
			out.guards += 1
		else:
			out.wave_yokai += 1
		if s.elite:
			out.elites += 1
		if s.in_cone:
			out.in_cone += 1
			if s.occluded:
				out.in_cone_occluded += 1
		if s.behind:
			out.behind += 1
			if s.guard:
				out.guard_behind += 1
	return out


func _advance_player() -> void:
	if _walk:
		_heading_left -= DT
		if _heading_left <= 0.0:
			_heading += _walk_rng.randf_range(-1.2, 1.2)
			_heading_left = _walk_rng.randf_range(4.0, 10.0)
		_pos += Vector2(sin(_heading), cos(_heading)) * WALK_SPEED * DT
	run.player.global_position = Vector3(_pos.x, run.forest_world.height_at(_pos.x, _pos.y), _pos.y)


## The stand-in turns its view: the heading, plus a slow look-around of ±40°.
func _view_direction() -> Vector3:
	var yaw := _heading + 0.7 * sin(_t * 0.45) if _walk else 0.7 * sin(_t * 0.45)
	return Vector3(sin(yaw), 0.0, cos(yaw))


func _on_spawned(y: Yokai) -> void:
	y.set_physics_process(false)
	var pos := y.root_part().global_position
	var dir_yaw := atan2(pos.x - _center.x, pos.z - _center.z)
	var view_yaw := atan2(_view.x, _view.z)
	var from_view := rad_to_deg(absf(angle_difference(view_yaw, dir_yaw)))
	var from_back := rad_to_deg(absf(angle_difference(view_yaw + PI, dir_yaw)))
	var in_cone := from_view < profile.view_half_angle
	var ground := Vector3(pos.x, float(director.ground_height.call(pos.x, pos.z)), pos.z)
	var occluded := in_cone and director.is_hidden_from(_center + EYE, ground + EYE)
	spawns.append({"t": _t, "pos": pos, "guard": y.guard_post != 0, "elite": y.is_elite(),
		"in_cone": in_cone, "occluded": occluded, "behind": from_back < BACK_DEG})


## Wanderers and guards in reach walk to the player; contact joins the kill queue.
func _approach_and_fight() -> void:
	for y in director.alive_enemies():
		var rp := y.root_part().global_position
		var d := Vector2(rp.x - _center.x, rp.z - _center.z)
		var dist := d.length()
		if dist <= CONTACT_M:
			if not _queue.has(y):
				_queue.append(y)
				if first_contact < 0.0:
					first_contact = _t
			continue
		if y.guard_post != 0 and dist > AGGRO_M:
			continue
		var speed: float = y.brain.move_speed if y.brain else 2.0
		var step := minf(speed * DT, dist - CONTACT_M * 0.9)
		if step <= 0.0:
			continue
		var next := Vector2(_center.x, _center.z) + d.normalized() * (dist - step)
		var ground: float = float(director.ground_height.call(next.x, next.y)) if director.ground_height.is_valid() else 0.0
		y.place_at(Vector3(next.x, ground, next.y), atan2(-d.x, -d.y))
	_fight()


func _fight() -> void:
	while not _queue.is_empty() and (not is_instance_valid(_queue[0]) or _queue[0].is_dead):
		_queue.pop_front()
	if _kill_gap > 0.0:
		_kill_gap -= DT
		return
	if _queue.is_empty():
		return
	var head := _queue[0]
	if _engage_left <= 0.0:
		_engage_left = head.hp / profile.sim_player_dps
	_engage_left -= DT
	if _engage_left > 0.0:
		return
	head.die({})
	director._recycle_yokai(head)
	_queue.pop_front()
	kills += 1
	_engage_left = 0.0
	_kill_gap = profile.sim_gap


func _measure() -> void:
	_t += DT
	var wave_alive := 0
	var guard_alive := 0
	for y in director.alive_enemies():
		if y.guard_post != 0:
			guard_alive += 1
		else:
			wave_alive += 1
	var oni := 1 if director.has_active_oni() else 0
	var cap := director.concurrent_cap()
	max_alive = maxi(max_alive, wave_alive + guard_alive)
	guard_slot_seconds += guard_alive * DT
	cap_seconds += cap * DT
	if _t >= EMPTY_FROM and wave_alive + guard_alive + oni == 0:
		_empty += DT
		longest_empty = maxf(longest_empty, _empty)
	else:
		_empty = 0.0
	if roundi(_t / DT) % roundi(SAMPLE_EVERY / DT) == 0:
		samples.append({"t": snappedf(_t, 0.1), "yokai": wave_alive, "guards": guard_alive, "oni": oni,
			"cap": cap, "wave": director.wave, "state": WavePlanner.STATE_NAMES[director._planner.state],
			"skipped": director.spawn_stats.skipped})
