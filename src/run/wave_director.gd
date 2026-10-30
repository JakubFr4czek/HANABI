class_name WaveDirector
extends Node3D
## Endless wave spawner for survival runs (docs/GDD.md §3, docs/SPAWN_PLAN.md).
##
## WavePlanner decides when a wave opens, what it may spend and what spawns next;
## every number comes from the WaveProfile (data/waves). This node places the
## yōkai in the fog ring, outside the camera's view and clear of the geometry,
## pools the bodies, and summons the Oni on the planner's cue.

signal wave_started(wave: int, total_in_wave: int)
signal enemy_spawned(enemy: Yokai)
signal enemy_died(enemy: Yokai, hit: Dictionary)
signal oni_spawned(oni: RunOniBoss)
signal oni_defeated(oni: RunOniBoss, hit: Dictionary)

## (x, z) -> ground y; RunGame binds ForestWorld.height_at.
var ground_height: Callable
## The pacing numbers. Empty = the default preset (WaveProfile.load_default).
@export var profile: WaveProfile

var active := false
## Set by start_director, cleared by RunGame.start_run: lets the runtime
## guard tell a deliberate hold from a run whose waves never started.
var started_this_run := false
var wave := 0
var run_seconds := 0.0
var oni_kills := 0

var _planner := WavePlanner.new()
var _rng := RandomNumberGenerator.new()
var _enemies: Array[Yokai] = []
var _active_oni: RunOniBoss
var _yokai_pool: Array[Yokai] = []
var _view_forward := Vector3.ZERO
## Set by AnchorGuards while a guard group waits for free slots under the cap (see step_director).
var reserved_slots := 0
const YOKAI_POOL_CAP := 14
## Nothing spawns behind the player: the back sector is 120° wide, centred on the
## opposite of the view direction, so anything within 60° of "behind" is refused.
const BEHIND_SECTOR_HALF := deg_to_rad(60.0)


func _ready() -> void:
	_rng.randomize()


## Pooled bodies sit off the tree, so nothing frees them with the scene:
## free them with the director (they leaked on every scene change / exit).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for y in _yokai_pool:
			if is_instance_valid(y) and not y.is_inside_tree():
				y.free()
		_yokai_pool.clear()


func get_profile() -> WaveProfile:
	if profile == null:
		profile = WaveProfile.load_default()
	return profile


func start_director() -> void:
	clear_enemies()
	wave = 0
	run_seconds = 0.0
	_planner.profile = get_profile()
	_planner.reset()
	_planner.rng.randomize()
	active = true
	started_this_run = true


func stop_director() -> void:
	active = false


func clear_enemies() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()
	if is_instance_valid(_active_oni):
		_active_oni.queue_free()
	_active_oni = null


func alive_enemies() -> Array[Yokai]:
	var out: Array[Yokai] = []
	for e in _enemies:
		if is_instance_valid(e) and not e.is_dead:
			out.append(e)
	_enemies = out
	return out


func alive_count() -> int:
	return alive_enemies().size()


func has_active_oni() -> bool:
	return is_instance_valid(_active_oni) and not _active_oni.is_dead


func get_active_oni() -> RunOniBoss:
	return _active_oni


## One frame of the director. [param view_forward] is the horizontal direction the
## player looks in; yōkai never appear within the profile's view cone of it.
func step_director(delta: float, player_pos: Vector3, view_forward: Vector3 = Vector3.ZERO) -> void:
	if not active:
		return
	_view_forward = view_forward
	# Slots held back for a guard group that is waiting for room (AnchorGuards): the planner
	# counts them as taken, so the group finds its places under the cap.
	var result := _planner.step(delta, alive_count() + reserved_slots, has_active_oni())
	run_seconds = _planner.t
	if result.wave_started > 0:
		wave = _planner.wave
		GameEvents.log_event("wave_started", {
			"wave": wave,
			"count": int(_planner.credits),
			"state": WavePlanner.STATE_NAMES[_planner.state],
			"run_time": snappedf(run_seconds, 0.1),
		})
		wave_started.emit(wave, int(_planner.credits))
	if result.kind != "":
		spawn_in_fog_ring(player_pos, view_forward, result.kind == "elite")
	if result.oni:
		spawn_oni_boss(player_pos, view_forward)


## The live cap at the current run time (what the planner enforces).
func concurrent_cap() -> int:
	return get_profile().cap_at(run_seconds)


func scaled_hp(wave_num: int, elapsed: float) -> float:
	return get_profile().hp_for(wave_num, elapsed)


func scaled_speed(wave_num: int, elapsed: float) -> float:
	return get_profile().speed_for(wave_num, elapsed)


func scaled_damage(wave_num: int) -> float:
	return get_profile().damage_for(wave_num)


## Null when no legal spot was found this tick: the spawn is skipped, never moved behind.
func spawn_in_fog_ring(target_pos: Vector3 = Vector3.ZERO, view_forward: Vector3 = Vector3.ZERO, elite: bool = false) -> Yokai:
	var pos := find_spawn_point(target_pos, view_forward)
	if pos == Vector3.INF:
		return null
	if elite:
		return spawn_elite_at(pos, target_pos, EnemyCatalog.elite_element_for_roll(_rng))
	return spawn_enemy_at(pos, target_pos, get_profile().roll_swarm_element(run_seconds, _rng))


## A spawn point on the ring round [param center]: outside the view cone of
## [param view_forward] (zero = no cone), clear of the world geometry, and not on top
## of a living yōkai, and never in the back sector (see BEHIND_SECTOR_HALF). Tries a few
## candidates and keeps the most separated. Returns Vector3.INF when none is legal.
func find_spawn_point(center: Vector3, view_forward: Vector3 = Vector3.ZERO) -> Vector3:
	var p := get_profile()
	var cone_half := deg_to_rad(p.view_half_angle)
	var has_view := view_forward.length_squared() > 0.0001
	var yaw_view := atan2(view_forward.x, view_forward.z)
	var best := Vector3.INF
	var best_clear := -1.0
	for i in 16:
		var angle := _rng.randf() * TAU
		if has_view and not _is_legal_angle(angle, yaw_view, cone_half):
			continue
		var pos := _ring_point(center, angle, _rng.randf_range(p.ring_min, p.ring_max))
		if not is_clear_of_world(pos):
			continue
		var clear := _separation(pos)
		if clear > best_clear:
			best_clear = clear
			best = pos
		if clear >= 1.3:
			break
	return best


## Outside the view cone (half-width [param cone_half]) and outside the back sector.
func _is_legal_angle(angle: float, yaw_view: float, cone_half: float) -> bool:
	if absf(angle_difference(yaw_view, angle)) < cone_half:
		return false
	return absf(angle_difference(yaw_view + PI, angle)) >= BEHIND_SECTOR_HALF


## Distance from [param pos] to the nearest living yōkai, on the ground plane.
func _separation(pos: Vector3) -> float:
	var clear := INF
	for yokai in alive_enemies():
		var rp := yokai.root_part().global_position
		clear = minf(clear, Vector2(pos.x - rp.x, pos.z - rp.z).length())
	return clear


## True when a clearance sphere at [param pos] touches no solid geometry (trunks,
## rocks, undergrowth, terrain) on the layers the yōkai themselves collide with.
func is_clear_of_world(pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var radius := get_profile().clearance_radius
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0.0, radius + 0.4, 0.0))
	query.collision_mask = 4 | 8
	return space.intersect_shape(query, 1).is_empty()


## Ring around the player (not the world origin: the player roams the forest),
## dropped onto the terrain so nobody spawns inside a hill.
func _ring_point(center: Vector3, angle: float, radius: float) -> Vector3:
	var x := center.x + sin(angle) * radius
	var z := center.z + cos(angle) * radius
	var y := float(ground_height.call(x, z)) if ground_height.is_valid() else 0.0
	return Vector3(x, y, z)


## Yōkai the player has walked away from are pulled back into the fog ring
## ahead of them instead of trudging after them for a minute out of sight.
func recall_stragglers(player_pos: Vector3) -> void:
	var p := get_profile()
	for yokai in alive_enemies():
		# A guard keeps its post at the gate or shrine, however far the player has walked.
		if yokai.guard_post != 0:
			continue
		var rp := yokai.root_part().global_position
		if Vector2(rp.x - player_pos.x, rp.z - player_pos.z).length() < p.straggler_distance:
			continue
		var pos := find_spawn_point(player_pos, _view_forward)
		if pos == Vector3.INF:
			continue
		var dir := player_pos - pos
		yokai.place_at(pos, atan2(dir.x, dir.z))


## One swarm yōkai at [param pos]; [param element] is its school (plain by default).
## [param guard_post] is the instance id of the gate or shrine it guards (0 = a wave yōkai).
func spawn_enemy_at(pos: Vector3, facing_target: Vector3 = Vector3.ZERO, element: String = Elements.NONE, guard_post: int = 0) -> Yokai:
	var yokai := _acquire_yokai()
	yokai.guard_post = guard_post
	var p := get_profile()
	var hp_val := p.hp_for(maxi(wave, 1), run_seconds)
	yokai.configure_kind(Yokai.Kind.SWARM, element, hp_val)
	yokai.enable_pathfinding()
	yokai.ground_probe = ground_height

	var dir := facing_target - pos
	dir.y = 0.0
	var yaw := atan2(dir.x, dir.z) if dir.length_squared() > 0.001 else 0.0
	yokai.position = pos
	yokai.rotation = Vector3(0.0, yaw, 0.0)
	add_child(yokai)
	# Pooled yōkai still carry the anchor of the spot they died on; without a
	# reset in place the anchor spring drags them back there.
	yokai.place_at(pos, yaw)

	if yokai.brain:
		yokai.brain.move_speed = p.speed_for(maxi(wave, 1), run_seconds)
		yokai.brain.base_damage = p.damage_for(maxi(wave, 1))

	if not yokai.died.is_connected(_on_enemy_died):
		yokai.died.connect(_on_enemy_died)
	if not yokai.dissolve_finished.is_connected(_recycle_yokai):
		yokai.dissolve_finished.connect(_recycle_yokai)
	_enemies.append(yokai)
	enemy_spawned.emit(yokai)
	return yokai


func spawn_elite_at(pos: Vector3, facing_target: Vector3, element: String) -> Yokai:
	var yokai := spawn_enemy_at(pos, facing_target)
	yokai.configure_kind(Yokai.Kind.ELITE, element, get_profile().hp_for(maxi(wave, 1), run_seconds, true))
	yokai.add_to_group("elite_yokai")
	GameEvents.log_event("elite_spawned", {"element": element, "name": yokai.profile.display_name})
	return yokai


## The Oni stands on the ring round the player, never in the back sector. Null when no
## legal spot came up this tick (the planner cues it again).
func spawn_oni_boss(facing_target: Vector3, view_forward: Vector3 = Vector3.ZERO) -> RunOniBoss:
	if has_active_oni():
		return _active_oni
	var p := get_profile()
	var has_view := view_forward.length_squared() > 0.0001
	var yaw_view := atan2(view_forward.x, view_forward.z)
	var angle := _rng.randf() * TAU
	for i in 16:
		if not has_view or _is_legal_angle(angle, yaw_view, 0.0):
			break
		angle = _rng.randf() * TAU
	if has_view and not _is_legal_angle(angle, yaw_view, 0.0):
		return null
	var pos := _ring_point(facing_target, angle, 9.2)
	var oni := RunOniBoss.new()
	oni.profile = EnemyCatalog.make_oni_profile(p.hp_for(maxi(wave, 1), run_seconds) * p.oni_hp_mult)
	oni.hold_sword = true
	var dir := facing_target - pos
	dir.y = 0.0
	oni.position = pos
	oni.rotation.y = atan2(dir.x, dir.z) if dir.length_squared() > 0.001 else 0.0
	oni.home_position = pos
	oni.ground_probe = ground_height
	add_child(oni)
	oni.set_difficulty(EnemyCatalog.oni_difficulty())
	oni.set_attacks_enabled(true)
	oni.boss_defeated.connect(_on_oni_defeated)
	_active_oni = oni
	oni_spawned.emit(oni)
	GameEvents.log_event("oni_boss_spawn", {"wave": wave, "run_time": snappedf(run_seconds, 0.1)})
	return oni


func _on_enemy_died(yokai: Yokai, hit: Dictionary) -> void:
	enemy_died.emit(yokai, hit)


func _acquire_yokai() -> Yokai:
	while not _yokai_pool.is_empty():
		var cached: Yokai = _yokai_pool.pop_back()
		if is_instance_valid(cached):
			cached.prepare_for_spawn()
			cached.set_physics_process(true)
			return cached
	return Yokai.new()


func _recycle_yokai(yokai: Yokai) -> void:
	if not is_instance_valid(yokai):
		return
	if yokai.get_parent() == self:
		remove_child(yokai)
	_enemies.erase(yokai)
	if _yokai_pool.size() >= YOKAI_POOL_CAP:
		yokai.queue_free()
		return
	yokai.visible = false
	yokai.set_physics_process(false)
	_yokai_pool.append(yokai)


func _on_oni_defeated(oni: RunOniBoss, hit: Dictionary) -> void:
	oni_kills += 1
	_active_oni = null
	oni_defeated.emit(oni, hit)
