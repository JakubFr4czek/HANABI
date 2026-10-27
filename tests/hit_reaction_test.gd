extends Node
## Headless checks for satisfying combat physics: hits throw the enemy toward
## where the blade travelled (a cut to the arm flings that arm, an overhead cut
## folds the torso forward, a rising cut arches it back), and the blade itself
## loses speed in flesh so the katana reads as having weight. Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/hit_reaction_test.tscn -- --desktop
## Exit code 0 when everything passed.

const ROOM := preload("res://scenes/test_room.tscn")

var room: Node3D
var dummy: TrainingDummy
var katana: HeldWeapon
var failures := 0
var events: Array[Dictionary] = []


func _ready() -> void:
	room = ROOM.instantiate()
	add_child(room)
	dummy = room.dummy
	katana = room.katana
	GameEvents.event_logged.connect(func(e): events.append(e))
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	await _wait(1.0)
	# The room auto-grabs the katana for the desktop rig; scripted holders need it free.
	var dp := room.player as DesktopPlayer
	if dp != null:
		dp.holder.release()
		dp.left_holder.release()
	await _test_horizontal_blow_throws_torso_along()
	await _test_downward_cut_folds_forward()
	await _test_rising_cut_arches_back()
	await _test_hit_arm_flings_that_arm()
	_test_cut_resistance()
	await _test_swing_reacts_and_bites()


## Face the dummy a known way (it faces +Z) with full muscle, settled.
func _face_dummy() -> void:
	room.reset_room()
	dummy.global_rotation = Vector3.ZERO
	dummy.reset_body()
	dummy.snap_pose("guard")
	await _wait(0.8)


func _chest_up() -> Vector3:
	return (dummy.parts["chest"] as RagdollPart).global_basis.y


## A horizontal cut travelling +X must lean the torso toward +X.
func _test_horizontal_blow_throws_torso_along() -> void:
	await _face_dummy()
	var arm: RagdollPart = dummy.parts["upper_arm_l"]
	var before := _chest_up()
	dummy.apply_hit_reaction(arm, arm.global_position, Vector3.RIGHT, 12.0)
	_check("reaction arms on a solid blow (part=%s, time=%.2f s)" % [dummy._react_part, dummy._react_time],
		dummy._react_part == "upper_arm_l" and dummy._react_time > 0.2)
	await _wait(0.18)
	var after := _chest_up()
	_check("horizontal cut throws the torso along the blade (up.x %.3f -> %.3f)" % [before.x, after.x],
		after.x > before.x + 0.02)


## An overhead cut (blade travelling down) folds the torso forward (+Z).
func _test_downward_cut_folds_forward() -> void:
	await _face_dummy()
	var chest: RagdollPart = dummy.parts["chest"]
	var before := _chest_up()
	dummy.apply_hit_reaction(chest, chest.global_position, Vector3.DOWN, 12.0)
	await _wait(0.18)
	var after := _chest_up()
	_check("overhead cut folds the torso forward (up.z %.3f -> %.3f)" % [before.z, after.z],
		after.z > before.z + 0.02)


## A rising cut (blade travelling up) arches the torso back.
func _test_rising_cut_arches_back() -> void:
	await _face_dummy()
	var chest: RagdollPart = dummy.parts["chest"]
	var before := _chest_up()
	dummy.apply_hit_reaction(chest, chest.global_position, Vector3.UP, 12.0)
	await _wait(0.18)
	var after := _chest_up()
	_check("rising cut arches the torso back (up.z %.3f -> %.3f)" % [before.z, after.z],
		after.z < before.z - 0.02)


## A cut to the left arm must throw THAT arm along the blade, harder than the torso.
func _test_hit_arm_flings_that_arm() -> void:
	await _face_dummy()
	var arm: RagdollPart = dummy.parts["upper_arm_l"]
	var other: RagdollPart = dummy.parts["upper_arm_r"]
	# Muscles off: the stiff guard would yank the limb back within a tick, so
	# the raw impulse is measured as displacement over a few ticks instead.
	dummy.muscle = 0.0
	var start := arm.global_position.x
	var start_other := other.global_position.x
	# Off-center contact (toward the hand), like a real cut to the forearm.
	dummy.apply_hit_reaction(arm, arm.global_position + Vector3(0, -0.2, 0), Vector3.RIGHT, 12.0)
	for i in 3:
		await get_tree().physics_frame
	var dx := arm.global_position.x - start
	var dx_other := other.global_position.x - start_other
	var spin := arm.angular_velocity.length()
	dummy.reset_body()
	_check("hit arm flies with the blade, far arm barely moves (%.3f vs %.3f m, spin %.2f rad/s)" % [dx, dx_other, spin],
		dx > 0.04 and dx > dx_other * 2.0 and spin > 0.5)


## Flesh resists the cut: the blade loses speed along it, blunts more than the edge.
func _test_cut_resistance() -> void:
	await get_tree().physics_frame
	var point := katana.global_position
	katana.linear_velocity = Vector3(10, 0, 0)
	katana._apply_cut_resistance({"point": point, "direction": Vector3.RIGHT}, {"impulse": 12.0}, "edge")
	var edge_v := katana.linear_velocity.x
	katana.linear_velocity = Vector3(10, 0, 0)
	katana._apply_cut_resistance({"point": point, "direction": Vector3.RIGHT}, {"impulse": 12.0}, "blunt")
	var blunt_v := katana.linear_velocity.x
	# edge: 12 * 0.22 / 1.1 kg = 2.4 m/s lost; blunt: capped at 3.5 m/s.
	_check("sharp cut passes through with a small bite (10 -> %.2f m/s)" % edge_v,
		absf(edge_v - 7.6) < 0.2)
	_check("blunt impact stops the blade harder, capped (10 -> %.2f m/s)" % blunt_v,
		absf(blunt_v - 6.5) < 0.2)
	katana.linear_velocity = Vector3.ZERO


## A real scripted sweep: the hit carries impulse, the dummy reacts, the blade bites.
func _test_swing_reacts_and_bites() -> void:
	room.reset_room()
	dummy.global_rotation = Vector3.ZERO
	dummy.reset_body()
	await _wait(1.2)
	var before := _chest_up()
	var basis := Basis(Vector3.BACK, deg_to_rad(-90.0))
	var start := Transform3D(basis, Vector3(0.8, 1.25, 0.8))
	var holder := WeaponHolder.new()
	room.add_child(holder)
	holder.global_transform = start
	katana.global_transform = start
	katana.linear_velocity = Vector3.ZERO
	katana.angular_velocity = Vector3.ZERO
	holder.grab(katana, Transform3D.IDENTITY)
	await _wait(0.5)
	events.clear()
	var max_speed := 0.0
	var reacted := false
	var min_upx := before.x
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(holder, "global_position", Vector3(-0.8, 1.25, 0.8), 0.25)
	for i in 60:
		await get_tree().physics_frame
		max_speed = maxf(max_speed, katana.get_point_velocity(katana.get_tip_global()).length())
		if dummy._react_time > 0.0:
			reacted = true
		min_upx = minf(min_upx, _chest_up().x)
	holder.release()
	holder.queue_free()
	var hits := events.filter(func(ev): return ev.type == "hit")
	var impulse := float(hits[0].get("impulse", 0.0)) if not hits.is_empty() else 0.0
	_check("scripted sweep lands a committed hit (impulse %.1f N·s)" % impulse,
		not hits.is_empty() and impulse > 4.0)
	_check("the hit triggers a directional reaction on the dummy", reacted)
	_check("the torso follows the blade (-X) during the sweep (up.x %.3f -> min %.3f)" % [before.x, min_upx],
		min_upx < before.x - 0.01)
	print("    sweep peak tip speed %.1f m/s" % max_speed)


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1
