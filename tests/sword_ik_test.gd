extends Node
## Headless checks for the dummy's procedural sword arm ([SwordArmIK]): it puts
## the blade on a wanted line within a few cm, follows a moving line smoothly
## (no jumps between ticks), is cheap enough for Quest, and the real ragdoll's
## sword actually gets there under physics. Run:
##   godot --headless --path . --fixed-fps 90 res://tests/sword_ik_test.tscn -- --desktop
## Exit code 0 when everything passed.

const ROOM := preload("res://scenes/test_room.tscn")

var room: Node3D
var dummy: TrainingDummy
var failures := 0


func _ready() -> void:
	room = ROOM.instantiate()
	add_child(room)
	dummy = room.dummy
	await _wait(0.5)
	_test_reaches_lines()
	_test_tracks_smoothly()
	await _test_in_physics()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _fresh_ik() -> SwordArmIK:
	var ik := SwordArmIK.new()
	ik.setup(dummy, TrainingDummy._rest_grip(), dummy.sword, dummy._define_poses()["guard"])
	return ik


## Joint angles around the guard, [param spread] rad per joint at most.
func _near_guard(ik: SwordArmIK, rng: RandomNumberGenerator, spread: float) -> Dictionary:
	var a := {}
	for part in ik.angles:
		var c: Vector3 = ik._comfort[part]
		a[part] = ik._clamp(part, c + Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread), rng.randf_range(-spread, spread)))
	return a


## Reachable blade lines around the guard (made from known joint angles) are
## solved starting from the guard.
func _test_reaches_lines() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var probe := _fresh_ik()
	var errs: Array[float] = []
	var worst_a := 0.0
	var times: Array[int] = []
	for k in 24:
		var fk := probe.forward(_near_guard(probe, rng, 0.6))
		var ik := _fresh_ik()
		var dir: Vector3 = ((fk.tip as Vector3) - (fk.start as Vector3)).normalized()
		for it in 30:
			var t0 := Time.get_ticks_usec()
			ik.solve(fk.start, dir, 2)
			times.append(Time.get_ticks_usec() - t0)
		errs.append(ik.error_position)
		worst_a = maxf(worst_a, rad_to_deg(ik.error_angle))
	errs.sort()
	var p90 := errs[int(errs.size() * 0.9) - 1]
	times.sort()
	var per_tick := times[times.size() / 10]  # 10th percentile: the cost without other processes in the way
	print("    lines around the guard: median %.3f m, 90%% under %.3f m, worst %.3f m / %.1f° after 30 ticks; %d µs per tick" % [errs[errs.size() / 2], p90, errs[-1], worst_a, per_tick])
	_check("reaches blade lines around the guard (90%% within %.3f m, median %.3f m)" % [p90, errs[errs.size() / 2]], p90 < 0.04 and errs[errs.size() / 2] < 0.015)
	_check("cheap enough for a Quest frame (%d µs per tick on desktop < 600)" % per_tick, per_tick < 600)


## A blade line sweeping around the guard is followed without jumps.
func _test_tracks_smoothly() -> void:
	var ik := _fresh_ik()
	var probe := _fresh_ik()
	var max_step := 0.0
	var max_err := 0.0
	var ref_step := 0.0
	var prev := ik.angles.duplicate()
	var prev_ref := {}
	var freqs := [0.9, 1.3, 0.7, 1.1, 0.5, 1.7, 0.8, 1.2, 0.6, 1.4, 1.0, 0.75, 1.6, 0.65, 1.15]
	for i in 4 * 90:
		var t := i / 90.0
		var a := {}
		var k := 0
		for part in probe.angles:
			var c: Vector3 = probe._comfort[part]
			var off := Vector3.ZERO
			for ax in 3:
				off[ax] = 0.35 * sin(t * freqs[k % freqs.size()] * TAU * 0.5 + k)
				k += 1
			a[part] = probe._clamp(part, c + off)
		var fk := probe.forward(a)
		ik.solve(fk.start, ((fk.tip as Vector3) - (fk.start as Vector3)).normalized(), 2)
		if not prev_ref.is_empty():
			for part in a:
				ref_step = maxf(ref_step, rad_to_deg(((a[part] as Vector3) - (prev_ref[part] as Vector3)).length()))
		prev_ref = a
		if t > 0.6:
			max_err = maxf(max_err, ik.error_position)
			for part in ik.angles:
				max_step = maxf(max_step, rad_to_deg(((ik.angles[part] as Vector3) - (prev[part] as Vector3)).length()))
		prev = ik.angles.duplicate()
	print("    moving line: max error %.3f m, biggest joint step %.2f° per tick (the path itself %.2f°)" % [max_err, max_step, ref_step])
	_check("follows a moving guard line (error %.3f m) without jumps (%.2f° per tick, path %.2f°)" % [max_err, max_step, ref_step], max_err < 0.05 and max_step < ref_step * 2.0 + 1.0)


## The physical sword follows the procedural arm.
func _test_in_physics() -> void:
	room.reset_room()
	await _wait(0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var probe := _fresh_ik()
	var errs := []
	for k in 3:
		var fk := probe.forward(_near_guard(probe, rng, 0.5))
		var start: Vector3 = dummy.arm_ik.to_world(fk.start)
		var dir: Vector3 = (dummy.arm_ik.to_world(fk.tip) - start).normalized()
		dummy.forced_blade_line = [start, dir]
		await _wait(1.0)
		var real_start := dummy.sword.global_transform * dummy.sword.blade_start
		var real_dir := dummy.sword.get_blade_axis()
		errs.append([snappedf(real_start.distance_to(start), 0.001), snappedf(rad_to_deg(real_dir.angle_to(dir)), 0.1)])
	print("    physical sword vs. wanted line (m, °): %s" % [errs])
	_check("the ragdoll's sword gets onto the wanted lines (%s)" % [errs], errs.all(func(e): return e[0] < 0.08 and e[1] < 10.0))
	_check("the body stays up while the arm reaches (lean %.1f°)" % dummy.lean_degrees(), dummy.lean_degrees() < 15.0 and dummy.state == ActiveRagdoll.State.STANDING)
	dummy.forced_blade_line = []


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
