class_name WaveDirector
extends Node3D
## Endless wave spawner for survival runs (docs/GDD.md §3, NIGHT_PLAN.md §1).
##
## Spawns yōkai in rings in the fog over the water outside the stone platform.
## Pressure scales with run time and wave number (count, health, speed, damage),
## while capping simultaneous active ragdolls to keep Quest 3 at 72-90 fps.

signal wave_started(wave: int, total_in_wave: int)
signal enemy_spawned(enemy: Yokai)
signal enemy_died(enemy: Yokai, hit: Dictionary)

@export var spawn_radius_min := 7.6
@export var spawn_radius_max := 10.8
@export var max_concurrent_enemies := 10
@export var initial_wave_delay := 0.6
@export var between_wave_delay := 1.8
@export var max_wave_duration := 18.0
@export var base_enemy_hp := 42.0
@export var base_enemy_speed := 2.05
@export var base_enemy_damage := 12.0

var active := false
var wave := 0
var run_seconds := 0.0
var pending_spawns := 0

var _wave_timer := 0.0
var _spawn_stagger_timer := 0.0
var _next_wave_cooldown := 0.0
var _rng := RandomNumberGenerator.new()
var _enemies: Array[Yokai] = []


func _ready() -> void:
	_rng.randomize()


func start_director() -> void:
	clear_enemies()
	wave = 0
	run_seconds = 0.0
	pending_spawns = 0
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


func alive_enemies() -> Array[Yokai]:
	var out: Array[Yokai] = []
	for e in _enemies:
		if is_instance_valid(e) and not e.is_dead:
			out.append(e)
	_enemies = out
	return out


func alive_count() -> int:
	return alive_enemies().size()


func step_director(delta: float, player_pos: Vector3) -> void:
	if not active:
		return
	run_seconds += delta
	_wave_timer += delta
	var alive := alive_count()

	# Spawn queued enemies from the current wave up to the concurrent cap.
	if pending_spawns > 0 and alive < max_concurrent_enemies:
		_spawn_stagger_timer -= delta
		if _spawn_stagger_timer <= 0.0:
			_spawn_stagger_timer = 0.22
			pending_spawns -= 1
			spawn_in_fog_ring(player_pos)
			alive += 1

	# Advance to the next wave when the wave is cleared or its timer expires.
	if pending_spawns == 0 and (alive == 0 or _wave_timer >= max_wave_duration):
		_next_wave_cooldown -= delta
		if _next_wave_cooldown <= 0.0:
			start_next_wave(player_pos)


func start_next_wave(player_pos: Vector3 = Vector3.ZERO) -> void:
	wave += 1
	_wave_timer = 0.0
	_next_wave_cooldown = between_wave_delay
	var count := wave_enemy_count(wave, run_seconds)
	pending_spawns = count
	GameEvents.log_event("wave_started", {
		"wave": wave,
		"count": count,
		"run_time": snappedf(run_seconds, 0.1),
	})
	wave_started.emit(wave, count)
	# Immediately spawn the first batch up to the concurrent limit.
	var batch := mini(pending_spawns, maxi(1, max_concurrent_enemies - alive_count()))
	for i in batch:
		pending_spawns -= 1
		spawn_in_fog_ring(player_pos, float(i) / float(maxi(batch, 1)))


func wave_enemy_count(wave_num: int, elapsed: float) -> int:
	return 3 + int(floor(float(wave_num - 1) * 1.35 + elapsed / 28.0))


func scaled_hp(wave_num: int, elapsed: float) -> float:
	var w := maxi(wave_num, 1)
	return base_enemy_hp * (1.0 + 0.14 * float(w - 1) + elapsed * 0.004)


func scaled_speed(wave_num: int, elapsed: float) -> float:
	var w := maxi(wave_num, 1)
	return clampf(base_enemy_speed + 0.06 * float(w - 1) + elapsed * 0.0015, base_enemy_speed, 3.15)


func scaled_damage(wave_num: int) -> float:
	var w := maxi(wave_num, 1)
	return base_enemy_damage * (1.0 + 0.08 * float(w - 1))


func spawn_in_fog_ring(target_pos: Vector3 = Vector3.ZERO, sector_bias: float = -1.0) -> Yokai:
	var angle := _rng.randf() * TAU
	if sector_bias >= 0.0:
		angle = wrapf(sector_bias * TAU + _rng.randf_range(-0.42, 0.42), 0.0, TAU)
	var r := _rng.randf_range(spawn_radius_min, spawn_radius_max)
	var pos := Vector3(sin(angle) * r, 0.0, cos(angle) * r)
	return spawn_enemy_at(pos, target_pos)


func spawn_enemy_at(pos: Vector3, facing_target: Vector3 = Vector3.ZERO) -> Yokai:
	var yokai := Yokai.new()
	var prof := EnemyProfile.new()
	prof.display_name = "Yokai"
	prof.max_hp = scaled_hp(maxi(wave, 1), run_seconds)
	prof.poise_per_impulse = 0.045
	prof.poise_damage_scale = 0.018
	prof.muscle_damage_scale = 0.01
	prof.knockdown_time = 0.9
	prof.getup_time = 1.1
	yokai.profile = prof

	var dir := facing_target - pos
	dir.y = 0.0
	var yaw := atan2(dir.x, dir.z) if dir.length_squared() > 0.001 else 0.0
	yokai.position = pos
	yokai.rotation = Vector3(0.0, yaw, 0.0)
	add_child(yokai)

	if yokai.brain:
		yokai.brain.move_speed = scaled_speed(maxi(wave, 1), run_seconds)
		yokai.brain.base_damage = scaled_damage(maxi(wave, 1))

	yokai.died.connect(_on_enemy_died)
	_enemies.append(yokai)
	enemy_spawned.emit(yokai)
	return yokai


func _on_enemy_died(yokai: Yokai, hit: Dictionary) -> void:
	enemy_died.emit(yokai, hit)
