class_name WaveDirector
extends Node3D
## Endless wave spawner for survival runs (docs/GDD.md §3, NIGHT_PLAN.md §1–4).
##
## Spawns swarm and elite yōkai in the fog ring, scales pressure with run time,
## and summons an Oni boss on a timer with duelist AI.

signal wave_started(wave: int, total_in_wave: int)
signal enemy_spawned(enemy: Yokai)
signal enemy_died(enemy: Yokai, hit: Dictionary)
signal oni_spawned(oni: RunOniBoss)
signal oni_defeated(oni: RunOniBoss, hit: Dictionary)

@export var spawn_radius_min := 7.6
@export var spawn_radius_max := 10.8
## Beyond this flat distance from the player a yōkai is recalled into the ring.
@export var straggler_distance := 17.0
## (x, z) -> ground y; RunGame binds ForestWorld.height_at.
var ground_height: Callable
## Hard cap; the live cap ramps up to it over the run (concurrent_cap()).
@export var max_concurrent_enemies := 12
## Live yōkai allowed at the very start, and seconds per extra one.
@export var start_concurrent_enemies := 2
@export var seconds_per_extra_enemy := 20.0
## Seconds of run time over which spawn trickle and wave breaks tighten.
@export var ramp_seconds := 180.0
@export var initial_wave_delay := 0.6
@export var between_wave_delay := 4.5
@export var max_wave_duration := 18.0
## Two committed cuts kill a wave yōkai (a solid edge hit lands ~85);
## a wrist flick only chips.
@export var base_enemy_hp := 95.0
@export var base_enemy_speed := 2.05
@export var base_enemy_damage := 12.0
@export var oni_spawn_interval := 100.0
@export var oni_spawn_min_run_time := 120.0

var active := false
var wave := 0
var run_seconds := 0.0
var pending_spawns := 0
var oni_kills := 0

var _wave_timer := 0.0
var _spawn_stagger_timer := 0.0
var _next_wave_cooldown := 0.0
var _oni_cooldown := 0.0
var _rng := RandomNumberGenerator.new()
var _enemies: Array[Yokai] = []
var _active_oni: RunOniBoss
var _yokai_pool: Array[Yokai] = []
const YOKAI_POOL_CAP := 14


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


func start_director() -> void:
	clear_enemies()
	wave = 0
	run_seconds = 0.0
	pending_spawns = 0
	_oni_cooldown = oni_spawn_interval * 0.55
	_wave_timer = 0.0
	_spawn_stagger_timer = 0.0
	_next_wave_cooldown = initial_wave_delay
	active = true


func stop_director() -> void:
	active = false
	pending_spawns = 0


func clear_enemies() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()
	pending_spawns = 0
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


func step_director(delta: float, player_pos: Vector3) -> void:
	if not active:
		return
	run_seconds += delta
	_wave_timer += delta
	var alive := alive_count()

	if pending_spawns > 0 and alive < concurrent_cap():
		_spawn_stagger_timer -= delta
		if _spawn_stagger_timer <= 0.0:
			# Early on yōkai drift out of the fog one at a time; later in quick
			# succession.
			_spawn_stagger_timer = lerpf(1.3, 0.35, _ramp())
			pending_spawns -= 1
			spawn_in_fog_ring(player_pos)
			alive += 1

	if pending_spawns == 0 and (alive == 0 or _wave_timer >= max_wave_duration):
		_next_wave_cooldown -= delta
		if _next_wave_cooldown <= 0.0:
			start_next_wave(player_pos)

	_oni_cooldown -= delta
	if _oni_cooldown <= 0.0 and run_seconds >= oni_spawn_min_run_time and not has_active_oni():
		spawn_oni_boss(player_pos)
		_oni_cooldown = oni_spawn_interval


func start_next_wave(player_pos: Vector3 = Vector3.ZERO) -> void:
	wave += 1
	_wave_timer = 0.0
	_next_wave_cooldown = lerpf(between_wave_delay, 2.0, _ramp())
	var count := wave_enemy_count(wave, run_seconds)
	pending_spawns = count
	GameEvents.log_event("wave_started", {
		"wave": wave,
		"count": count,
		"run_time": snappedf(run_seconds, 0.1),
	})
	wave_started.emit(wave, count)
	# Only the first of a wave appears at once; the rest trickle in (step).
	var batch := mini(pending_spawns, 1 if _ramp() < 0.35 else maxi(1, concurrent_cap() - alive_count()) / 2)
	for i in batch:
		pending_spawns -= 1
		spawn_in_fog_ring(player_pos, float(i) / float(maxi(batch, 1)))


func wave_enemy_count(wave_num: int, elapsed: float) -> int:
	return 2 + int(floor(float(wave_num - 1) * 0.9 + elapsed / 40.0))


## How many yōkai may be alive at once right now: a couple at the start,
## one more about every [member seconds_per_extra_enemy] s, up to the hard cap.
func concurrent_cap() -> int:
	return clampi(start_concurrent_enemies + int(run_seconds / seconds_per_extra_enemy),
		start_concurrent_enemies, max_concurrent_enemies)


func _ramp() -> float:
	return clampf(run_seconds / ramp_seconds, 0.0, 1.0)


func scaled_hp(wave_num: int, elapsed: float) -> float:
	var w := maxi(wave_num, 1)
	return base_enemy_hp * (1.0 + 0.14 * float(w - 1) + elapsed * 0.004)


func scaled_speed(wave_num: int, elapsed: float) -> float:
	var w := maxi(wave_num, 1)
	return clampf(base_enemy_speed + 0.06 * float(w - 1) + elapsed * 0.0015, base_enemy_speed, 3.15)


func scaled_damage(wave_num: int) -> float:
	var w := maxi(wave_num, 1)
	return base_enemy_damage * (1.0 + 0.08 * float(w - 1))


func elite_spawn_chance(wave_num: int) -> float:
	if wave_num < 3:
		return 0.0
	return clampf(0.10 + float(wave_num - 3) * 0.05, 0.10, 0.42)


func spawn_in_fog_ring(target_pos: Vector3 = Vector3.ZERO, sector_bias: float = -1.0) -> Yokai:
	var angle := _rng.randf() * TAU
	if sector_bias >= 0.0:
		angle = wrapf(sector_bias * TAU + _rng.randf_range(-0.42, 0.42), 0.0, TAU)
	var r := _rng.randf_range(spawn_radius_min, spawn_radius_max)
	var pos := _separated_ring_point(target_pos, angle, r)
	if _rng.randf() < elite_spawn_chance(maxi(wave, 1)):
		return spawn_elite_at(pos, target_pos, EnemyCatalog.elite_element_for_roll(_rng))
	return spawn_enemy_at(pos, target_pos)


## A ring point that does not stack a new body on top of a living one:
## batch spawns share a sector, and two ragdolls born interpenetrated used
## to pop apart at solver speed. Tries a few angles, keeps the best.
func _separated_ring_point(center: Vector3, angle: float, radius: float) -> Vector3:
	var best := _ring_point(center, angle, radius)
	var best_clear := -1.0
	for i in 6:
		var candidate := _ring_point(center, angle + float(i) * 0.85, radius)
		var clear := INF
		for yokai in alive_enemies():
			var rp := yokai.root_part().global_position
			clear = minf(clear, Vector2(candidate.x - rp.x, candidate.z - rp.z).length())
		if clear > best_clear:
			best_clear = clear
			best = candidate
		if clear >= 1.3:
			break
	return best


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
	for yokai in alive_enemies():
		var rp := yokai.root_part().global_position
		if Vector2(rp.x - player_pos.x, rp.z - player_pos.z).length() < straggler_distance:
			continue
		var pos := _separated_ring_point(player_pos, _rng.randf() * TAU, spawn_radius_max)
		var dir := player_pos - pos
		yokai.place_at(pos, atan2(dir.x, dir.z))


func spawn_enemy_at(pos: Vector3, facing_target: Vector3 = Vector3.ZERO) -> Yokai:
	var yokai := _acquire_yokai()
	var hp_val := scaled_hp(maxi(wave, 1), run_seconds)
	yokai.configure_kind(Yokai.Kind.SWARM, Elements.NONE, hp_val)
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
		yokai.brain.move_speed = scaled_speed(maxi(wave, 1), run_seconds)
		yokai.brain.base_damage = scaled_damage(maxi(wave, 1))

	if not yokai.died.is_connected(_on_enemy_died):
		yokai.died.connect(_on_enemy_died)
	if not yokai.dissolve_finished.is_connected(_recycle_yokai):
		yokai.dissolve_finished.connect(_recycle_yokai)
	_enemies.append(yokai)
	enemy_spawned.emit(yokai)
	return yokai


func spawn_elite_at(pos: Vector3, facing_target: Vector3, element: String) -> Yokai:
	var yokai := spawn_enemy_at(pos, facing_target)
	yokai.configure_kind(Yokai.Kind.ELITE, element, scaled_hp(maxi(wave, 1), run_seconds) * 2.35)
	yokai.add_to_group("elite_yokai")
	GameEvents.log_event("elite_spawned", {"element": element, "name": yokai.profile.display_name})
	return yokai


func spawn_oni_boss(facing_target: Vector3) -> RunOniBoss:
	if has_active_oni():
		return _active_oni
	var pos := _ring_point(facing_target, _rng.randf() * TAU, 9.2)
	var oni := RunOniBoss.new()
	oni.profile = EnemyCatalog.make_oni_profile(scaled_hp(maxi(wave, 1), run_seconds) * 6.5)
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
