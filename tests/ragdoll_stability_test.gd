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
	await _test_yokai_body_invariants()
	await _test_recycled_body_stays_whole()


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


## A standing yōkai's parts must not collide with their own layer (the body
## tore itself apart on self-overlaps), elites must not scale the physics
## node, and a knocked-down yōkai must land on the terrain and get back up
## instead of sinking through the world.
func _test_yokai_body_invariants() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(12)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(4)
	var gy := float(run.wave_director.ground_height.call(0.0, 6.0))
	var yokai: Yokai = run.wave_director.spawn_enemy_at(Vector3(0.0, gy, 6.0), Vector3.ZERO)
	await _frames(10)
	var self_collision := false
	for p in yokai.parts.values():
		self_collision = self_collision or ((p as RagdollPart).collision_mask & 2) != 0
	_check("standing yokai parts ignore their own layer (no self-collision)", not self_collision)
	yokai.configure_kind(Yokai.Kind.ELITE, Elements.NONE, 200.0)
	_check("elite yokai does not scale its physics node (scale %s)" % yokai.scale, yokai.scale == Vector3.ONE)
	yokai.configure_kind(Yokai.Kind.SWARM, Elements.NONE, 95.0)
	# Knock it flat and watch: it must land near the ground, then stand again.
	yokai.weaken(1.0, 1.0)
	_check("full weaken knocks the yokai down", yokai.state == Yokai.State.KNOCKED_DOWN)
	var min_pelvis := INF
	for i in 120:
		await get_tree().physics_frame
		min_pelvis = minf(min_pelvis, yokai.root_part().global_position.y)
	_check("knocked-down yokai lands on the terrain instead of falling through (min pelvis %.2f, ground %.2f)" % [min_pelvis, gy],
		min_pelvis > gy - 0.85)
	var rose := false
	for i in 600:
		await get_tree().physics_frame
		if yokai.state == Yokai.State.STANDING:
			rose = true
			break
	if rose:
		await _frames(240)
	var pelvis_h := yokai.root_part().global_position.y - float(run.wave_director.ground_height.call(
		yokai.root_part().global_position.x, yokai.root_part().global_position.z))
	_check("yokai gets back up after a knockdown (pelvis %.2f m over ground)" % pelvis_h, rose and pelvis_h > 0.55)
	run.queue_free()


## How far the body is from its rest shape: the largest gap (m) between a
## part's distance to the pelvis now and in the rest pose. A torn body (limbs
## held off by mis-anchored joints) reads in metres; a whole one in cm.
func _body_tear(e: ActiveRagdoll) -> float:
	var pelvis := e.root_part()
	var rest_root: Transform3D = e._rest[pelvis.name]
	var worst := 0.0
	for part_name in e.parts:
		var part := e.parts[part_name] as RagdollPart
		var rest_d := ((e._rest[part_name] as Transform3D).origin - rest_root.origin).length()
		worst = maxf(worst, absf(part.global_position.distance_to(pelvis.global_position) - rest_d))
	return worst


## A pooled yōkai dies wherever its body walked to (the parts roam away from
## the Yokai node), then comes back somewhere else. Its joints re-anchor when
## it re-enters the tree: that must happen with the body in its rest shape,
## or every limb is pinned metres off and flies around the map.
func _test_recycled_body_stays_whole() -> void:
	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	await _frames(12)
	var director := run.wave_director
	director.stop_director()
	director.clear_enemies()
	await _frames(4)
	var gy := float(director.ground_height.call(0.0, 6.0))
	var yokai: Yokai = director.spawn_enemy_at(Vector3(0.0, gy, 6.0), Vector3.ZERO)
	await _frames(30)
	# The body walked 3 m off its node, then dies there and crumples.
	for p in yokai.parts.values():
		(p as RagdollPart).global_position += Vector3(3.0, 0.0, 1.5)
	await _frames(5)
	yokai.die({})
	await _frames(140)
	var again: Yokai = director.spawn_enemy_at(Vector3(-3.0, float(director.ground_height.call(-3.0, 7.0)), 7.0), Vector3.ZERO)
	_check("the pool hands back the same body", again == yokai)
	var worst := 0.0
	for i in 180:
		await get_tree().physics_frame
		worst = maxf(worst, _body_tear(again))
	print("    recycled body: worst tear %.2f m" % worst)
	_check("a recycled yokai comes back whole (worst tear %.2f m)" % worst, worst < 0.35)
	run.queue_free()


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
