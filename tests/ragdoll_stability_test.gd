extends Node
## Ragdolls must not explode: a heavy hit on a limb must not launch body parts
## at absurd speeds, and two bodies spawned overlapping must separate instead
## of detonating. Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/ragdoll_stability_test.tscn -- --desktop
## Exit code 0 when everything passed.

const ROOM := preload("res://scenes/test_room.tscn")
const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0


func _ready() -> void:
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	await _test_heavy_hit_stays_bounded()
	await _test_overlapping_spawns_separate()


## A kanabo-grade blow to the forearm: the arm may fly, the body must not.
func _test_heavy_hit_stays_bounded() -> void:
	var room: Node3D = ROOM.instantiate()
	add_child(room)
	await _frames(30)
	var dummy: TrainingDummy = room.dummy
	dummy.global_rotation = Vector3.ZERO
	dummy.reset_body()
	await _frames(60)
	var arm: RagdollPart = dummy.parts["upper_arm_l"]
	var pelvis: RagdollPart = dummy.root_part()
	var home := pelvis.global_position
	dummy.apply_hit_reaction(arm, arm.global_position + Vector3(0, -0.2, 0), Vector3.RIGHT, 28.0)
	var max_speed := 0.0
	var max_spin := 0.0
	for i in 180:
		await get_tree().physics_frame
		for p in dummy.parts.values():
			var part := p as RagdollPart
			max_speed = maxf(max_speed, part.linear_velocity.length())
			max_spin = maxf(max_spin, part.angular_velocity.length())
	var drift := pelvis.global_position.distance_to(home)
	print("    heavy hit: peak part speed %.1f m/s, peak spin %.1f rad/s, pelvis drift %.2f m" % [max_speed, max_spin, drift])
	_check("heavy hit throws no part across the map (peak %.1f m/s)" % max_speed, max_speed < 14.0)
	_check("heavy hit spins no part like a propeller (peak %.1f rad/s)" % max_spin, max_spin < 25.0)
	_check("heavy hit does not relocate the body (drift %.2f m)" % drift, drift < 2.0)
	room.queue_free()


## Two yokai spawned inside each other must push apart, not detonate.
func _test_overlapping_spawns_separate() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(12)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(4)
	var at := Vector3(0.0, 0.0, 6.0)
	var a: Yokai = run.wave_director.spawn_enemy_at(at, Vector3.ZERO)
	var b: Yokai = run.wave_director.spawn_enemy_at(at, Vector3.ZERO)
	await _frames(5)
	var max_speed := 0.0
	for i in 120:
		await get_tree().physics_frame
		for e in [a, b]:
			if not is_instance_valid(e):
				continue
			for p in (e as Yokai).parts.values():
				max_speed = maxf(max_speed, (p as RagdollPart).linear_velocity.length())
	print("    overlap: peak part speed %.1f m/s" % max_speed)
	_check("overlapping spawns separate without detonating (peak %.1f m/s)" % max_speed, max_speed < 14.0)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
