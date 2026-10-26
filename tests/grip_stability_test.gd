extends Node
## Headless checks that a held weapon stays calm in the hand and never flies
## away after a strong impact. Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/grip_stability_test.tscn -- --desktop
## Exit code 0 when everything passed.

const ROOM := preload("res://scenes/test_room.tscn")
const BASE_POSE := Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.4, 3.0))
const MUNE_GRIP := Vector3(-0.025, 0.02, -0.40)

var room: Node3D
var player: DesktopPlayer
var katana: HeldWeapon
var kanabo: HeldWeapon
var failures := 0


func _ready() -> void:
	room = ROOM.instantiate()
	add_child(room)
	player = room.player
	katana = room.katana
	kanabo = room.kanabo
	player.teleport(Vector3(3.5, 0, 3.5))
	player.holder.release()
	player.left_holder.release()
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	await _wait(0.5)
	# 1. Holding still: Quest runs physics at the display rate (72 or 90 Hz) and
	# the controller pose carries sub-millimeter tracking noise.
	for hz in [72, 90]:
		for weapon: HeldWeapon in [katana, kanabo]:
			for two_handed in [false, true]:
				var r := await _hold_still(weapon, two_handed, hz)
				_check("%s %s at %d Hz holds still (tip wobble %.1f mm, spin %.2f rad/s, tip jitter %.2f× the hand's own noise)" % [
					weapon.weapon_name, "2H" if two_handed else "1H", hz, r.wobble * 1000.0, r.spin, r.jitter_ratio],
					r.wobble < 0.005 and r.spin < 0.5 and r.jitter_ratio < 1.0)
	Engine.physics_ticks_per_second = 90

	# 2. A heavy, fast body slams into the held blade (contact impulse).
	var slam := await _slam(katana)
	_check("katana stays near the hand after a heavy slam (max grip error %.2f m, final %.3f m)" % [slam.max_err, slam.final_err],
		slam.max_err <= katana.break_distance + 0.05 and slam.final_err < 0.03)
	_check("katana does not spin out after the slam (peak spin %.1f rad/s)" % slam.max_spin, slam.max_spin < 40.0)

	# 3. A raw impulse at the tip (worst case, bypasses contacts) is clamped too.
	var kick := await _tip_kick(katana)
	_check("katana kicked at the tip stays within the break distance (max grip error %.2f m, final %.3f m)" % [kick.max_err, kick.final_err],
		kick.max_err <= katana.break_distance + 0.05 and kick.final_err < 0.03)

	# 4. Already flying away past the break distance: put back in the hand.
	var h := _new_holder("right")
	_place(katana, BASE_POSE)
	h.global_transform = BASE_POSE
	h.grab(katana)
	await _wait(0.3)
	katana.global_position += Vector3(0.5, 0, 0)
	katana.linear_velocity = Vector3(3.0, 0, 0)
	await _wait(0.05)
	var reset_err := katana.get_grip_point_global(h).distance_to(h.global_position)
	_check("katana flying off past %.2f m is put back in the hand (grip error %.3f m)" % [katana.break_distance, reset_err], reset_err < 0.03)
	h.release()
	h.queue_free()

	# 5. VR rig: the weapon ignores the player's own bodies and the hand model
	# never flies away from the controller.
	await _xr_hand_stays_with_controller()


## Grab [param weapon] at the base pose (optionally with a second hand on the
## blunt spine), let it settle, then hold still with tracking noise for 3 s.
func _hold_still(weapon: HeldWeapon, two_handed: bool, hz: int) -> Dictionary:
	Engine.physics_ticks_per_second = hz
	var h1 := _new_holder("right")
	var h2 := _new_holder("left")
	_place(weapon, BASE_POSE)
	h1.global_transform = BASE_POSE
	h1.grab(weapon)
	var h2_pose := BASE_POSE * Transform3D(Basis.IDENTITY, weapon.clamp_grip_point(MUNE_GRIP))
	if two_handed:
		h2.global_transform = h2_pose
		h2.grab(weapon)
	await _wait(1.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var rest_tip := BASE_POSE * weapon.blade_tip
	var wobble := 0.0
	var spin := 0.0
	# Sum of tick-to-tick tip motion: blade vs. the noisy hand target. An
	# under-damped controller rings and moves the tip more than the hand does.
	var tip_path := 0.0
	var hand_path := 0.0
	var prev_tip := weapon.get_tip_global()
	var prev_hand_tip := rest_tip
	for i in 3 * hz:
		var noise := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.0004
		var twist := Basis.from_euler(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * deg_to_rad(0.05))
		h1.global_transform = Transform3D(twist, BASE_POSE.origin + noise)
		if two_handed:
			h2.global_transform = Transform3D(twist, h2_pose.origin + noise)
		var hand_tip := h1.global_transform * weapon.blade_tip
		hand_path += hand_tip.distance_to(prev_hand_tip)
		prev_hand_tip = hand_tip
		await get_tree().physics_frame
		var tip := weapon.get_tip_global()
		tip_path += tip.distance_to(prev_tip)
		prev_tip = tip
		wobble = maxf(wobble, tip.distance_to(rest_tip))
		spin = maxf(spin, weapon.angular_velocity.length())
	h1.release()
	h2.release()
	h1.queue_free()
	h2.queue_free()
	return {"wobble": wobble, "spin": spin, "jitter_ratio": tip_path / maxf(hand_path, 1e-6)}


func _slam(weapon: HeldWeapon) -> Dictionary:
	var h1 := _new_holder("right")
	_place(weapon, BASE_POSE)
	h1.global_transform = BASE_POSE
	h1.grab(weapon)
	await _wait(0.5)
	var ram := RigidBody3D.new()
	ram.mass = 40.0
	ram.collision_layer = 8  # enemy_body: the weapon collides with it
	ram.collision_mask = 4
	ram.gravity_scale = 0.0
	ram.continuous_cd = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	shape.shape = box
	ram.add_child(shape)
	room.add_child(ram)
	ram.global_position = BASE_POSE * Vector3(-0.8, 0.0, -0.75)
	ram.linear_velocity = Vector3(16.0, 0, 0)
	var r := await _track(weapon, h1, 1.5)
	ram.queue_free()
	h1.release()
	h1.queue_free()
	return r


func _tip_kick(weapon: HeldWeapon) -> Dictionary:
	var h1 := _new_holder("right")
	_place(weapon, BASE_POSE)
	h1.global_transform = BASE_POSE
	h1.grab(weapon)
	await _wait(0.5)
	weapon.apply_impulse(Vector3(0, 14.0, 6.0), weapon.get_tip_global() - weapon.global_position)
	var r := await _track(weapon, h1, 1.5)
	h1.release()
	h1.queue_free()
	return r


func _track(weapon: HeldWeapon, h: WeaponHolder, seconds: float) -> Dictionary:
	var max_err := 0.0
	var max_spin := 0.0
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
		max_err = maxf(max_err, weapon.get_grip_point_global(h).distance_to(h.global_position))
		max_spin = maxf(max_spin, weapon.angular_velocity.length())
	return {"max_err": max_err, "max_spin": max_spin, "final_err": weapon.get_grip_point_global(h).distance_to(h.global_position)}


func _xr_hand_stays_with_controller() -> void:
	var xr_player: XRPlayer = load("res://scenes/player/xr_player.tscn").instantiate()
	var start_xr := xr_player.get_node_or_null("StartXR")
	if start_xr:
		xr_player.remove_child(start_xr)
		start_xr.free()
	room.add_child(xr_player)
	await get_tree().physics_frame
	katana.register_player_collision_exceptions(xr_player)
	var exceptions := katana.get_collision_exceptions()
	var player_bodies := xr_player.find_children("*", "PhysicsBody3D", true, false)
	var all_excepted := not player_bodies.is_empty()
	for b in player_bodies:
		all_excepted = all_excepted and exceptions.has(b)
	_check("held weapons ignore the player's own bodies (%d bodies, %d exceptions)" % [player_bodies.size(), exceptions.size()],
		all_excepted and (katana.collision_mask & HeldWeapon.PLAYER_BODY_LAYER) == 0)

	var controller := xr_player.right_controller
	var hand := controller.get_node("RightHandModel") as Node3D
	_place(katana, BASE_POSE)
	controller.global_transform = BASE_POSE
	xr_player.right_holder.grab(katana)
	await _wait(0.3)
	var pinned_gap := hand.global_position.distance_to(controller.global_position)
	# Hold the blade back with a wall-like stop, then yank the hand far away.
	katana.freeze = true
	var max_gap := 0.0
	for i in 30:
		controller.global_position += Vector3(0.03, 0, 0)
		await get_tree().physics_frame
		max_gap = maxf(max_gap, hand.global_position.distance_to(controller.global_position))
	katana.freeze = false
	var limit := xr_player.right_holder.hand_pin_max_distance
	_check("VR hand model stays on the grip in normal use (gap %.3f m)" % pinned_gap, pinned_gap < 0.03)
	_check("VR hand model never drifts more than %.2f m from the controller (max gap %.2f m)" % [limit, max_gap], max_gap <= limit + 0.04)
	await _wait(0.6)
	var back_gap := hand.global_position.distance_to(controller.global_position)
	_check("VR hand model re-pins to the weapon once it is back in the hand (gap %.3f m, error %.3f m)" % [back_gap, katana.grip_error],
		back_gap < 0.03 and katana.grip_error < 0.03)
	xr_player.right_holder.release()
	xr_player.queue_free()
	await get_tree().physics_frame


func _new_holder(side: String) -> WeaponHolder:
	var h := WeaponHolder.new()
	h.side = side
	room.add_child(h)
	return h


func _place(weapon: HeldWeapon, pose: Transform3D) -> void:
	weapon.release_all()
	weapon.global_transform = pose
	weapon.linear_velocity = Vector3.ZERO
	weapon.angular_velocity = Vector3.ZERO


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1
