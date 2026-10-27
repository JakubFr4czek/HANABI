extends Node
## Yōkai spawned in the fog ring must keep closing in on the player, never turn
## back toward their spawn point (pathfinding regression).
##   godot --headless --path . --fixed-fps 90 res://tests/yokai_approach_test.tscn -- --desktop

const RUN_SCENE := preload("res://scenes/run.tscn")

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
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	var pack: Array[Yokai] = []
	for i in 4:
		var y := run.wave_director.spawn_in_fog_ring(player.global_position, float(i) / 4.0)
		y.brain.attacks_enabled = false
		pack.append(y)
	# "Walks in, then turns back": distance rising well above the closest it got
	# while still out of reach. Brief shoves inside a converging pack are fine.
	var start_d: Array[float] = []
	var min_d: Array[float] = []
	var last_d: Array[float] = []
	var worst_back := 0.0
	var player_start := player.global_position
	for y in pack:
		var d := _flat_dist(y, player)
		start_d.append(d)
		min_d.append(d)
		last_d.append(d)
	for step in 110:
		await _frames(6)
		for i in pack.size():
			var d := _flat_dist(pack[i], player)
			if min_d[i] > 3.0:
				worst_back = maxf(worst_back, d - min_d[i])
			min_d[i] = minf(min_d[i], d)
			last_d[i] = d
	_check("The pack did not shove the player (moved %.2f m)" % player.global_position.distance_to(player_start),
		player.global_position.distance_to(player_start) < 0.3)
	for i in pack.size():
		print("  yokai %d: %.2f m -> %.2f m" % [i, start_d[i], last_d[i]])
		_check("Yōkai %d closed in from %.1f m to <= 2.2 m (now %.2f m)" % [i, start_d[i], last_d[i]], last_d[i] <= 2.2)
	_check("No yōkai turned back toward its spawn while approaching (worst retreat %.2f m)" % worst_back,
		worst_back < 0.35)

	# Pooled yōkai: kill the pack, let it dissolve back into the pool, respawn.
	for y in pack:
		y.die({"element": Elements.NONE})
	# Their souls would level the player up and slow time; not under test here.
	run._clear_souls()
	await _frames(200)
	TimeController.clear()
	var reused := run.wave_director.spawn_in_fog_ring(player.global_position, 0.5)
	reused.brain.attacks_enabled = false
	var reused_start := _flat_dist(reused, player)
	await _frames(240)
	var reused_end := _flat_dist(reused, player)
	_check("Pooled yōkai is reused (%s)" % str(pack.has(reused)), pack.has(reused))
	# A trunk sidestep bends the path, so the bar is "clearly closed in",
	# not a straight 2 m/s line.
	_check("Pooled yōkai approaches from its new spawn (%.1f m -> %.1f m)" % [reused_start, reused_end],
		reused_start > 6.0 and reused_end < reused_start - 1.5)

	# Out in the forest: the ring follows the player and bodies follow the hills.
	player.teleport(Vector3(30.0, run.forest_world.height_at(30.0, 22.0), 22.0), 0.0)
	await _frames(30)
	var far := run.wave_director.spawn_in_fog_ring(player.global_position, 0.0)
	far.brain.attacks_enabled = false
	var far_start := _flat_dist(far, player)
	await _frames(20)
	var rp := far.root_part().global_position
	var ground := run.forest_world.height_at(rp.x, rp.z)
	_check("Fog ring spawns around the roaming player (%.1f m away)" % far_start,
		far_start > 6.0 and far_start < 12.0)
	_check("Yōkai pelvis stands on the hill (pelvis %.2f m above ground)" % (rp.y - ground),
		rp.y - ground > 0.5 and rp.y - ground < 1.4)
	player.teleport(Vector3(30.0, run.forest_world.height_at(30.0, 50.0), 50.0), 0.0)
	await _frames(4)
	run.wave_director.recall_stragglers(player.global_position)
	await _frames(4)
	_check("Yōkai left far behind is recalled into the ring (%.1f m)" % _flat_dist(far, player),
		_flat_dist(far, player) < 13.0)
	run.queue_free()


func _flat_dist(y: Yokai, player: Node3D) -> float:
	var a := y.root_part().global_position
	var b := player.global_position
	return Vector2(a.x - b.x, a.z - b.z).length()


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _i in n:
		await get_tree().physics_frame
