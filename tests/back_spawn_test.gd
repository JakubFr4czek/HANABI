extends Node
## Nothing spawns behind the player (P6, uwaga 6). The back sector is 120° wide, centred
## on the opposite of the view direction, so a spawn is refused within 60° of "behind".
##   - 10 min of simulated waves with the view turning round: no yōkai, no Oni, in that sector.
##   - Straggler recall: a yōkai pulled back into the ring also lands outside it.
##   godot --headless --path . --fixed-fps 90 res://tests/back_spawn_test.tscn

const RUN_SCENE := preload("res://scenes/run.tscn")
const SIM_SECONDS := 600.0
const STEP := 0.1
const BACK_LIMIT_DEG := 60.0

var failures := 0


func _ready() -> void:
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(10)
	var player := run.player as DesktopPlayer
	var director := run.wave_director
	director.stop_director()
	director.clear_enemies()
	director.start_director()

	# Spawns are recorded with the view yaw they were made under (a dict: lambdas copy ints).
	var sim := {"yaw": 0.0}
	var spawned: Array[Dictionary] = []
	director.enemy_spawned.connect(func(y: Yokai) -> void:
		spawned.append({"pos": y.global_position, "yaw": sim.yaw}))
	var center := player.global_position
	for step in int(SIM_SECONDS / STEP):
		# The view turns a full circle every ~14 s, so every sector passes over the spawner.
		sim.yaw = step * STEP * 0.45
		director.step_director(STEP, center, Vector3(sin(sim.yaw), 0.0, cos(sim.yaw)))
		if step % 30 == 29:
			# Kill-and-clear every 3 s so the planner keeps spawning for the whole 10 min.
			director.clear_enemies()
	var closest := INF
	for s in spawned:
		closest = minf(closest, _from_behind_deg(s.pos, center, s.yaw))
	_check("10 min of waves: %d yōkai spawned" % spawned.size(), spawned.size() >= 40)
	_check("No yōkai in the back sector over 10 min (closest to dead behind %.1f°, limit %.0f°)" % [closest, BACK_LIMIT_DEG],
		spawned.size() >= 40 and closest >= BACK_LIMIT_DEG)

	# The Oni has its own ring placement: same rule, with the view turned to several sides.
	var oni_count := 0
	var oni_closest := INF
	for i in 36:
		var yaw := i * TAU / 36.0
		director.clear_enemies()
		var oni := director.spawn_oni_boss(center, Vector3(sin(yaw), 0.0, cos(yaw)))
		if oni == null:
			continue
		oni_count += 1
		oni_closest = minf(oni_closest, _from_behind_deg(oni.global_position, center, yaw))
	_check("Oni placed in every view direction (%d of 36)" % oni_count, oni_count >= 30)
	_check("Oni never in the back sector (closest to dead behind %.1f°)" % oni_closest,
		oni_count >= 30 and oni_closest >= BACK_LIMIT_DEG)
	director.clear_enemies()

	# Straggler recall: a yōkai left 60 m behind the player is pulled into the ring, not behind.
	var view := Vector3(0.0, 0.0, 1.0)
	var far := center + Vector3(0.0, 0.0, -60.0)
	far.y = run.forest_world.height_at(far.x, far.z)
	var left := director.spawn_enemy_at(far, center)
	left.brain.attacks_enabled = false
	director.recall_stragglers(center)
	await _frames(2)
	var recalled := left.root_part().global_position
	var recall_closest := _from_behind_deg(recalled, center, atan2(view.x, view.z))
	_check("Recalled yōkai came back into the ring (%.1f m)" % Vector2(recalled.x - center.x, recalled.z - center.z).length(),
		recalled.distance_to(far) > 10.0)
	_check("Recalled yōkai is not in the back sector (closest to dead behind %.1f°)" % recall_closest,
		recall_closest >= BACK_LIMIT_DEG)
	director.stop_director()
	director.clear_enemies()
	run.queue_free()


## Degrees between the direction from [param center] to [param pos] and straight behind a
## view turned to [param yaw_view]. 0 = dead behind; the back sector is everything under 60.
func _from_behind_deg(pos: Vector3, center: Vector3, yaw_view: float) -> float:
	var dir_yaw := atan2(pos.x - center.x, pos.z - center.z)
	return rad_to_deg(absf(angle_difference(yaw_view + PI, dir_yaw)))


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
