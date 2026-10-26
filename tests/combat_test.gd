extends Node
## Headless checks for the PD katana, weight lag, hit-stop, trail and parry. Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/combat_test.tscn -- --desktop
## Exit code 0 when everything passed.

const ROOM := preload("res://scenes/test_room.tscn")

var room: Node3D
var dummy: TrainingDummy
var player: DesktopPlayer
var katana: HeldWeapon
var kanabo: HeldWeapon
var failures := 0
var events: Array[Dictionary] = []
var time_effects: Array = []


func _ready() -> void:
	room = ROOM.instantiate()
	add_child(room)
	dummy = room.dummy
	player = room.player
	katana = room.katana
	kanabo = room.kanabo
	GameEvents.event_logged.connect(func(e): events.append(e))
	TimeController.effect_started.connect(func(kind, scale, duration): time_effects.append([kind, scale, duration]))
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	await _wait(1.0)

	# 1. Weight: the same "arm" moves a heavy weapon slower than a katana.
	player.teleport(Vector3(3.5, 0, 3.5))  # away from the dummy
	var lag_katana := await _step_response(katana)
	var lag_kanabo := await _step_response(kanabo)
	print("    step response: katana settles in %.3f s (tip err after 0.1 s %.2f m), kanabō %.3f s (%.2f m)" % [
		lag_katana[0], lag_katana[1], lag_kanabo[0], lag_kanabo[1]])
	_check("katana follows the hand quickly (settles < 0.25 s)", lag_katana[0] < 0.25)
	_check("heavier kanabō lags behind more than the katana", lag_kanabo[0] > lag_katana[0] * 1.3 and lag_kanabo[1] > lag_katana[1])

	# 2. No bulldozing: keep thrusting into the dummy's chest.
	player.take_weapon(katana)
	room.reset_room()
	player.teleport(Vector3(0, 0, 1.15))
	player.hand_offset = Vector3(0, -0.2, 0)
	await _wait(1.5)
	events.clear()
	var start := dummy.root_part().global_position
	# Slowly push the hand ~0.45 m into the dummy (a shove, not a strike).
	create_tween().tween_property(player, "hand_offset", Vector3(0, -0.15, 0.45), 0.6)
	var min_strength := 1.0
	for i in 135:
		await get_tree().physics_frame
		min_strength = minf(min_strength, katana.strength)
		if OS.get_cmdline_user_args().has("--verbose-test") and i % 15 == 0:
			print("    t%.2f tip %s grip_err %.2f str %.2f | dummy state %d lean %.0f h %.2f pelvis %s" % [i / 90.0, katana.get_tip_global().snapped(Vector3.ONE * 0.01), katana.grip_error, katana.strength, dummy.state, dummy.lean_degrees(), dummy.pelvis_height(), dummy.root_part().global_position.snapped(Vector3.ONE * 0.01)])
	var moved := Vector2(dummy.root_part().global_position.x - start.x, dummy.root_part().global_position.z - start.z).length()
	if OS.get_cmdline_user_args().has("--verbose-test"):
		print("    push events: ", events.slice(-12).map(func(e): return "%s %s %s" % [e.type, e.get("part", e.get("state", e.get("defender", ""))), e.get("speed", "")]))
	_check("pushing into the dummy does not bulldoze it (moved %.2f m, state %d)" % [moved, dummy.state], moved < 0.35 and dummy.state == ActiveRagdoll.State.STANDING)
	_check("arm gives way while the blade is held back (strength %.2f)" % min_strength, min_strength < 0.6)
	player.hand_offset = Vector3.ZERO
	await _wait(0.8)
	_check("blade comes back to the hand afterwards (grip error %.3f m)" % katana.grip_error, katana.grip_error < 0.05)

	# 3. Strong hit -> hit-stop of 50-80 ms; trail shows during the swing.
	room.reset_room()
	await _wait(1.5)
	time_effects.clear()
	var max_trail := 0.0
	player.swing_duration = 0.12
	player.swing(DesktopPlayer.SLASH_HORIZONTAL)
	var min_scale := 1.0
	for i in 70:
		await get_tree().physics_frame
		max_trail = maxf(max_trail, katana.trail.intensity())
		min_scale = minf(min_scale, Engine.time_scale)
	var stops := time_effects.filter(func(e): return e[0] == "hit_stop")
	_check("strong hit triggers hit-stop (%s)" % str(stops), not stops.is_empty() and stops[0][2] >= 0.05 and stops[0][2] <= 0.08)
	_check("time actually slowed during hit-stop (min scale %.2f)" % min_scale, min_scale < 0.2)
	await _wait(0.5)
	_check("time back to normal after hit-stop (%.2f)" % Engine.time_scale, is_equal_approx(Engine.time_scale, 1.0))
	_check("blade trail visible during a fast swing (intensity %.2f)" % max_trail, max_trail > 0.5)
	_check("trail fades at rest (intensity %.2f)" % katana.trail.intensity(), katana.trail.intensity() < 0.05)
	katana.set_element(Elements.SAKURA)
	_check("trail takes the element color", katana.trail._material.albedo_color.is_equal_approx(Elements.color(Elements.SAKURA)))
	katana.set_element(Elements.NONE)

	# Baseline for the slow-mo check: how far the blade trails the hand when
	# dropping out of the high block in normal time.
	room.reset_room()
	player.teleport(Vector3(3.0, 0, 3.0))
	player.force_block = true
	await _wait(1.0)
	player.force_block = false
	var base_err := 0.0
	for i in 20:
		await get_tree().physics_frame
		base_err = maxf(base_err, katana.grip_error)

	# 4. Parry: the dummy attacks, the player holds a high block.
	room.reset_room()
	dummy.equip_sword()
	player.teleport(Vector3(0, 0, 1.3))
	player.force_block = true
	await _wait(2.0)
	events.clear()
	time_effects.clear()
	dummy.set_attacks_enabled(true)
	var parry: Dictionary = {}
	var max_enemy_tip := 0.0
	var last_tip := dummy.sword.get_tip_global()
	for i in 6 * 90:
		await get_tree().physics_frame
		var tip := dummy.sword.get_tip_global()
		if dummy.sword.attacking and is_equal_approx(Engine.time_scale, 1.0):
			max_enemy_tip = maxf(max_enemy_tip, tip.distance_to(last_tip) * Engine.physics_ticks_per_second)
		last_tip = tip
		for e in events:
			if e.type == "parry":
				parry = e
		if not parry.is_empty():
			break
	print("    dummy strike tip speed up to %.1f m/s; events: %s" % [max_enemy_tip, ", ".join(events.filter(func(e): return e.type in ["enemy_phase", "clash", "parry"]).map(func(e): return "%s:%s" % [e.type, e.get("phase", e.get("speed", ""))]))])
	_check("blocking the dummy's strike is a parry", not parry.is_empty())
	if not parry.is_empty():
		print("    parry: %.1f m/s at %.0f°" % [parry.speed, parry.angle_deg])
		await get_tree().physics_frame
		_check("parry starts compensated slow motion (scale %.2f, compensated %s)" % [TimeController.time_scale, TimeController.player_compensated],
			TimeController.time_scale < 0.5 and TimeController.player_compensated)
		_check("dummy is stunned with a counter window (%.2f s)" % dummy.counter_time_left(), dummy.counter_time_left() > 0.5 and (dummy.brain as DummyBrain).phase == DummyBrain.Phase.STUNNED)

		player.force_block = false

		# 6. Counter hit inside the window does extra damage.
		events.clear()
		player.swing_duration = 0.2
		player.swing(DesktopPlayer.SLASH_HORIZONTAL)
		var counter: Dictionary = {}
		for i in 90:
			await get_tree().physics_frame
			for e in events:
				if e.type == "hit" and e.get("counter", false):
					counter = e
			if not counter.is_empty():
				break
		if counter.is_empty():
			print("    events after parry: ", events.map(func(e): return "%s %s" % [e.type, e.get("part", e.get("phase", e.get("speed", "")))]))
		_check("hit inside the counter window is a counter (×%.1f)" % dummy.profile.counter_multiplier, not counter.is_empty())
	player.force_block = false
	dummy.set_attacks_enabled(false)

	# 5. In compensated slow-mo the player's blade keeps up with the real hand:
	# the same hand motion as the baseline, away from any obstacle.
	room.reset_room()
	player.teleport(Vector3(3.0, 0, 3.0))
	player.force_block = true
	await _wait(1.0)
	TimeController.slow_motion(0.3, 1.0, true)
	player.force_block = false
	var slow_err := 0.0
	for i in 20:
		await get_tree().physics_frame
		slow_err = maxf(slow_err, katana.grip_error)
	_check("katana keeps up with the real hand in slow-mo (grip error %.3f m, normal time %.3f m)" % [slow_err, base_err], slow_err < base_err * 1.5 + 0.02)
	TimeController.clear()


## Hold the weapon in a scripted holder, then jump the target 0.4 m sideways and
## turn it 60°. Returns [seconds until the grip is within 3 cm and the blade
## within 5°, tip distance from its target 0.1 s after the jump].
func _step_response(weapon: HeldWeapon) -> Array:
	player.holder.release()
	var holder := WeaponHolder.new()
	room.add_child(holder)
	holder.global_transform = Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.4, 3.0))
	weapon.global_transform = holder.global_transform
	weapon.linear_velocity = Vector3.ZERO
	weapon.angular_velocity = Vector3.ZERO
	holder.grab(weapon)
	await _wait(1.0)
	holder.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(60.0)), Vector3(-2.6, 1.4, 3.0))
	var settle := -1.0
	var tip_err_01 := 0.0
	for i in 90:
		await get_tree().physics_frame
		var target_tip := holder.global_transform * weapon.blade_tip
		if i == 8:
			tip_err_01 = weapon.get_tip_global().distance_to(target_tip)
		var ang := rad_to_deg(weapon.global_basis.get_rotation_quaternion().angle_to(holder.global_basis.get_rotation_quaternion()))
		if settle < 0.0 and weapon.grip_error < 0.03 and ang < 5.0:
			settle = (i + 1) / 90.0
	holder.release()
	holder.queue_free()
	return [settle if settle >= 0.0 else 9.9, tip_err_01]


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1
