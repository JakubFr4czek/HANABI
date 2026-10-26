extends Node
## Headless checks for the PD katana, weight lag, hit-stop, trail, parry,
## free grip (handle / tsuba / blunt blade spine) and two-handed grip. Run with:
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
	_check("heavier kanabō lags behind more than the katana", lag_kanabo[0] > lag_katana[0] * 1.3 and lag_kanabo[1] > lag_kanana_tip(lag_katana[1]))

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
	dummy.set_difficulty(calm_difficulty())
	dummy.set_attacks_enabled(true)
	(dummy.brain as DuelistBrain).force_attack("vertical")
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
		_check("dummy is stunned with a counter window (%.2f s)" % dummy.counter_time_left(), dummy.counter_time_left() > 0.5 and (dummy.brain as DuelistBrain).state == DuelistBrain.State.STAGGER)

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

	# 7. Free grip anywhere (handle, tsuba, blunt side of the blade) and two-handed grip.
	await _test_free_and_two_handed_grip(lag_kanabo[0])

	# 8. Dojo of the Storm arena elements: storm lightning, water and fog.
	await _test_dojo_of_the_storm()


func lag_kanana_tip(v: float) -> float:
	return v


func _test_free_and_two_handed_grip(kanabo_1h_settle: float) -> void:
	player.holder.release()
	player.left_holder.release()
	player.teleport(Vector3(3.5, 0, 3.5))
	var h1 := WeaponHolder.new()
	var h2 := WeaponHolder.new()
	h1.side = "right"
	h2.side = "left"
	room.add_child(h1)
	room.add_child(h2)

	var base_pose := Transform3D(Basis.IDENTITY, Vector3(-3.0, 1.4, 3.0))

	# 7a. Grabbing near the rear handle (tsuka, z = +0.16).
	katana.release_all()
	katana.global_transform = base_pose
	katana.linear_velocity = Vector3.ZERO
	katana.angular_velocity = Vector3.ZERO
	h1.global_transform = base_pose * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.16))
	h1.grab(katana)
	await _wait(0.35)
	h1.global_position += Vector3(0.25, 0.1, 0.0)
	await _wait(0.35)
	var handle_err := katana.get_grip_point_global(h1).distance_to(h1.global_position)
	_check("free grip on the handle (tsuka, z=%.2f, zone=%s, err=%.3f m)" % [
		katana.get_local_grip(h1).origin.z, katana.get_grip_zone(h1), handle_err],
		katana.get_grip_zone(h1) == HeldWeapon.ZONE_HANDLE and absf(katana.get_local_grip(h1).origin.z - 0.16) < 0.01 and handle_err < 0.03)

	# 7b. Grabbing the guard (tsuba, z = -0.085).
	katana.release_all()
	katana.global_transform = base_pose
	katana.linear_velocity = Vector3.ZERO
	katana.angular_velocity = Vector3.ZERO
	h1.global_transform = base_pose * Transform3D(Basis.IDENTITY, Vector3(0.02, 0.01, -0.085))
	h1.grab(katana)
	await _wait(0.35)
	h1.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(35.0)), base_pose.origin + Vector3(-0.2, 0.05, 0.1))
	await _wait(0.35)
	var tsuba_err := katana.get_grip_point_global(h1).distance_to(h1.global_position)
	_check("free grip on the guard (tsuba, z=%.3f, zone=%s, err=%.3f m)" % [
		katana.get_local_grip(h1).origin.z, katana.get_grip_zone(h1), tsuba_err],
		katana.get_grip_zone(h1) == HeldWeapon.ZONE_TSUBA and tsuba_err < 0.03)

	# 7c. Grabbing the blade clamps onto the blunt spine (mune), never the sharp edge (ha).
	katana.release_all()
	katana.global_transform = base_pose
	katana.linear_velocity = Vector3.ZERO
	katana.angular_velocity = Vector3.ZERO
	# Approach even from the sharp edge side (-Y): the grip must snap to the blunt spine (+Y).
	h1.global_transform = base_pose * Transform3D(Basis.IDENTITY, Vector3(-0.025, -0.02, -0.45))
	h1.grab(katana)
	var mune_local := katana.get_local_grip(h1).origin
	await _wait(0.4)
	h1.global_position += Vector3(0.2, 0.15, -0.1)
	await _wait(0.35)
	var mune_err := katana.get_grip_point_global(h1).distance_to(h1.global_position)
	_check("free grip on the blade snaps to blunt spine (mune, zone=%s, blunt=%s, err=%.3f m)" % [
		katana.get_grip_zone(h1), katana.is_on_blunt_side(mune_local), mune_err],
		katana.get_grip_zone(h1) == HeldWeapon.ZONE_MUNE and katana.is_on_blunt_side(mune_local) and mune_err < 0.03)

	# 7d. Two-handed grip (handle + blunt blade spine / half-swording):
	# grabbing with the second hand keeps the first hand attached, steers the blade
	# between both hands, and releasing the first hand transfers control to the second.
	katana.release_all()
	katana.global_transform = base_pose
	katana.linear_velocity = Vector3.ZERO
	katana.angular_velocity = Vector3.ZERO
	h1.global_transform = base_pose * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.05))
	h2.global_transform = base_pose * Transform3D(Basis.IDENTITY, Vector3(-0.025, 0.02, -0.45))
	h1.grab(katana)
	h2.grab(katana)
	_check("second hand grabs without releasing the first (two_handed=%s, holders=%d)" % [
		katana.is_two_handed(), katana.holders.size()],
		katana.is_two_handed() and katana.holders.size() == 2 and h1.held == katana and h2.held == katana)
	await _wait(0.35)
	# Move the second hand sideways and up to aim the blade.
	var span := katana.get_local_grip(h2).origin.distance_to(katana.get_local_grip(h1).origin)
	var aim_dir := Vector3(0.45, 0.25, -0.85).normalized()
	h2.global_position = h1.global_position + aim_dir * span
	await _wait(0.4)
	var actual_vec := (katana.get_grip_point_global(h2) - katana.get_grip_point_global(h1)).normalized()
	var aim_angle_err := rad_to_deg(acos(clampf(actual_vec.dot(aim_dir), -1.0, 1.0)))
	var h1_err := katana.get_grip_point_global(h1).distance_to(h1.global_position)
	var h2_err := katana.get_grip_point_global(h2).distance_to(h2.global_position)
	_check("two-handed grip aligns weapon between both hands (angle err %.1f°, h1 %.3f m, h2 %.3f m)" % [
		aim_angle_err, h1_err, h2_err],
		aim_angle_err < 5.0 and h1_err < 0.03 and h2_err < 0.03)

	# Release primary hand -> secondary hand seamlessly becomes primary at its grip point.
	h1.release()
	await _wait(0.3)
	h2.global_position += Vector3(-0.15, 0.1, 0.0)
	await _wait(0.35)
	var handoff_err := katana.get_grip_point_global(h2).distance_to(h2.global_position)
	_check("releasing first hand keeps weapon in second hand at its grip point (holder=%s, err=%.3f m)" % [
		katana.holder.side if katana.holder else "none", handoff_err],
		katana.is_held() and not katana.is_two_handed() and katana.holder == h2 and handoff_err < 0.03)

	# 7e. Two-handed strength: two hands move the heavy kanabō faster than one hand.
	h1.release()
	h2.release()
	kanabo.release_all()
	kanabo.global_transform = base_pose
	kanabo.linear_velocity = Vector3.ZERO
	kanabo.angular_velocity = Vector3.ZERO
	h1.global_transform = base_pose
	h2.global_transform = base_pose * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.35))
	h1.grab(kanabo)
	h2.grab(kanabo)
	await _wait(1.0)
	var jump_pose := Transform3D(Basis(Vector3.UP, deg_to_rad(60.0)), Vector3(-2.6, 1.4, 3.0))
	h1.global_transform = jump_pose
	h2.global_transform = jump_pose * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, -0.35))
	var settle_2h := -1.0
	for i in 90:
		await get_tree().physics_frame
		var ang := rad_to_deg(kanabo.global_basis.get_rotation_quaternion().angle_to(jump_pose.basis.get_rotation_quaternion()))
		if settle_2h < 0.0 and kanabo.grip_error < 0.03 and ang < 5.0:
			settle_2h = (i + 1) / 90.0
	_check("two-handed grip drives heavy kanabō faster than one hand (2H %.3f s < 1H %.3f s)" % [settle_2h, kanabo_1h_settle],
		settle_2h > 0.0 and settle_2h < kanabo_1h_settle * 0.9)

	h1.release()
	h2.release()
	h1.queue_free()
	h2.queue_free()

	# 7f. Desktop two-handed slash hits the dummy cleanly without breaking physics.
	room.reset_room()
	player.take_weapon(katana)
	player.set_two_handed(true)
	player.teleport(Vector3(0.0, 0.0, 1.15))
	await _wait(1.0)
	events.clear()
	player.swing_duration = 0.14
	player.swing(DesktopPlayer.SLASH_HORIZONTAL)
	await _wait(0.6)
	var hit_2h := events.filter(func(e): return e.type == "hit")
	_check("two-handed slash registers a clean hit on the dummy (%d hits)" % hit_2h.size(),
		katana.is_two_handed() and not hit_2h.is_empty())
	player.set_two_handed(false)

	# 7g. VR rig hand anchors: both XR hands pin to their exact grip spots on the katana.
	var xr_player: XRPlayer = load("res://scenes/player/xr_player.tscn").instantiate()
	var start_xr := xr_player.get_node_or_null("StartXR")
	if start_xr:
		xr_player.remove_child(start_xr)
		start_xr.free()
	room.add_child(xr_player)
	await get_tree().physics_frame
	katana.release_all()
	katana.global_transform = base_pose
	xr_player.right_controller.global_transform = base_pose * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.04))
	xr_player.left_controller.global_transform = base_pose * Transform3D(Basis.IDENTITY, Vector3(-0.025, 0.018, -0.40))
	xr_player.right_holder.grab(katana)
	xr_player.left_holder.grab(katana)
	var anchor_r := katana.get_node_or_null("HandAnchor_right") as Node3D
	var anchor_l := katana.get_node_or_null("HandAnchor_left") as Node3D
	_check("VR hand models pin to both grip locations on the katana",
		anchor_r != null and anchor_l != null and anchor_r.position.distance_to(Vector3(0.0, 0.0, 0.04)) < 0.01 and anchor_l.position.z < -0.35)
	xr_player.right_holder.release()
	xr_player.left_holder.release()
	xr_player.queue_free()
	player.take_weapon(katana)


func _test_dojo_of_the_storm() -> void:
	var disc := room.get_node_or_null("Arena/PlatformDisc") as MeshInstance3D
	var water := room.get_node_or_null("Arena/WaterMirror") as MeshInstance3D
	var mist_low := room.get_node_or_null("Arena/WaterMistLow") as MeshInstance3D
	var mist_high := room.get_node_or_null("Arena/WaterMistHigh") as MeshInstance3D
	var seal := room.get_node_or_null("Arena/SpawnSeal") as MeshInstance3D
	var giant_torii := room.get_node_or_null("Arena/ToriiGates/GiantTorii") as Node3D
	var lightmap := room.get_node_or_null("Arena/LightmapGI") as LightmapGI
	var we := room.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_check("Dojo of the Storm core nodes present (disc, water mirror, mist layers, seal, giant torii, LightmapGI)",
		disc != null and water != null and mist_low != null and mist_high != null and seal != null and giant_torii != null and lightmap != null)
	var water_mat := water.material_override as ShaderMaterial if water else null
	var water_plane := water.mesh as PlaneMesh if water else null
	_check("Water shader has a light mesh (normal-mapped swell, no vertex waves), dual normal maps, and baked sky panorama",
		water_mat != null and water_plane != null and water_plane.subdivide_width <= 16
		and water_mat.get_shader_parameter("normal_map_a") != null
		and water_mat.get_shader_parameter("normal_map_b") != null
		and water_mat.get_shader_parameter("sky_panorama") != null)
	_check("WorldEnvironment uses depth+height fog ending past the giant torii (begin=%.1f m, end=%.1f m)" % [
		we.environment.fog_depth_begin if we and we.environment else -1.0,
		we.environment.fog_depth_end if we and we.environment else -1.0],
		we != null and we.environment != null and we.environment.fog_enabled
		and we.environment.fog_mode == Environment.FOG_MODE_DEPTH
		and we.environment.fog_depth_end <= 30.0 and we.environment.fog_height_density > 0.1)
	var rain: StormRain = room.rain
	await get_tree().process_frame
	var cam := room.get_viewport().get_camera_3d()
	_check("Rain: streaks follow the camera, splashes on the platform, drips on the katana blade",
		rain != null and rain.rain.amount >= 1000 and rain.rain.emitting and rain.splashes.emitting
		and cam != null and absf(rain.rain.global_position.x - cam.global_position.x) < 0.01
		and absf(rain.rain.global_position.z - cam.global_position.z) < 0.01
		and katana.get_node_or_null("BladeDrips") is GPUParticles3D)
	if room.lightning:
		room.lightning.trigger_strike(-0.22)
		await get_tree().process_frame
		var flash_val: float = room.lightning.current_intensity
		var base_fog: Color = room.lightning.base_fog_light_color
		_check("StormLightning drives the global storm_flash (water, clouds, mist) and brightens fog + ambient (flash=%.2f)" % flash_val,
			room.lightning.visible and flash_val > 0.1
			and we.environment.fog_light_color.get_luminance() > base_fog.get_luminance() + 0.01
			and we.environment.ambient_light_energy > room.lightning.base_ambient_energy * 1.2)
		await _wait(0.45)
		_check("Lightning flash fades out and its light pass is switched off (flash=%.3f)" % room.lightning.current_intensity,
			room.lightning.current_intensity < 0.01
			and (room.lightning.flash_light == null or not room.lightning.flash_light.visible))
		var thunders_before: int = room.ambience.thunders_played if room.ambience else 0
		await _wait(2.4)
		_check("Distant thunder rolls in after the strike (%d played)" % (room.ambience.thunders_played if room.ambience else -1),
			room.ambience != null and room.ambience.thunders_played > thunders_before)

	var world_bus := AudioServer.get_bus_index(Sfx.WORLD_BUS)
	var amb: StormAmbience = room.ambience
	var rain_stream := amb.rain_player.stream as AudioStreamWAV if amb else null
	_check("Audio: World bus with reverb, steel ring + thunder sounds, looping rain bed on Ambience bus",
		world_bus >= 0 and AudioServer.get_bus_effect_count(world_bus) > 0
		and AudioServer.get_bus_effect(world_bus, 0) is AudioEffectReverb
		and Sfx._streams.has("blade_ring") and Sfx._streams.has("thunder")
		and amb != null and amb.rain_player.playing and amb.rain_player.bus == Sfx.AMBIENCE_BUS
		and rain_stream != null and rain_stream.loop_mode != AudioStreamWAV.LOOP_DISABLED)

	TimeController.clear()
	TimeController.micro_stop(0.03)
	var micro_scale := Engine.time_scale
	await _wait(0.1)
	_check("Micro hit-stop is a brief partial slow-down (scale %.2f, then %.2f)" % [micro_scale, Engine.time_scale],
		micro_scale > 0.1 and micro_scale < 0.6 and is_equal_approx(Engine.time_scale, 1.0))


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


## Normal difficulty without feints, combos or blocks: one predictable attack.
static func calm_difficulty() -> DuelistDifficulty:
	var d := DuelistDifficulty.preset("normal")
	d.feint_chance = 0.0
	d.combo_chance = 0.0
	d.block_chance = 0.0
	d.riposte_chance = 0.0
	return d


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1
