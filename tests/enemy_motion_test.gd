extends Node
## Headless checks that the dummy moves with weight instead of snapping: poses
## blend in with easing (no jolt when a pose changes), the body does not jitter
## while it circles, a wind-up visibly settles before the strike, the strike
## stays fast, and the recovery follows through and returns to guard slowly. Run:
##   godot --headless --path . --fixed-fps 90 res://tests/enemy_motion_test.tscn -- --desktop
## Exit code 0 when everything passed.

const ROOM := preload("res://scenes/test_room.tscn")
const FIGHT_SPOT := Vector3(0.0, 0.0, 1.45)
const LIMBS := ["chest", "head", "upper_arm_r", "lower_arm_r", "upper_arm_l", "lower_arm_l", "upper_leg_l", "upper_leg_r"]

var room: Node3D
var dummy: TrainingDummy
var brain: DuelistBrain
var player: DesktopPlayer
var failures := 0


func _ready() -> void:
	room = ROOM.instantiate()
	add_child(room)
	dummy = room.dummy
	brain = dummy.brain as DuelistBrain
	player = room.player
	await _run()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run() -> void:
	await _wait(0.5)
	await _test_attack_rhythm()
	await _test_no_jitter_while_circling()


## Wind-up -> strike -> recovery of a vertical cut, sampled every tick.
func _test_attack_rhythm() -> void:
	await _start_fight(FIGHT_SPOT)
	brain.force_attack("vertical")
	var dt := 1.0 / Engine.physics_ticks_per_second
	var arm := dummy.parts["lower_arm_r"] as RagdollPart
	var prev_w := arm.angular_velocity
	var prev_tip := dummy.sword.get_tip_global()
	var prev_local_tip := _local(prev_tip)
	var phase := ""
	var phase_time := 0.0
	var onset_accel := 0.0  # first 0.15 s of the wind-up
	var windup_end_speed := 0.0  # tip speed over the last 0.1 s of the wind-up
	var windup_speeds: Array[float] = []
	var strike_peak := 0.0
	var recover_accel := 0.0
	var recover_start_tip := Vector3.ZERO
	var recover_samples: Array[Vector3] = []
	var guard_tip := _local(dummy.sword.get_tip_global())
	for i in 5 * 90:
		await get_tree().physics_frame
		var now := _phase()
		if now != phase:
			phase = now
			phase_time = 0.0
		phase_time += dt
		var w := arm.angular_velocity
		var accel := (w - prev_w).length() / dt
		prev_w = w
		var tip := dummy.sword.get_tip_global()
		var tip_speed := tip.distance_to(prev_tip) / dt
		prev_tip = tip
		# Relative to the body: the dummy may still be stepping in while it winds up.
		var local_tip := _local(tip)
		var local_speed := local_tip.distance_to(prev_local_tip) / dt
		prev_local_tip = local_tip
		match phase:
			"windup":
				if phase_time <= 0.15:
					onset_accel = maxf(onset_accel, accel)
				windup_speeds.append(local_speed)
			"strike":
				strike_peak = maxf(strike_peak, tip_speed)
			"recover":
				if recover_samples.is_empty():
					recover_start_tip = _local(tip)
				# Skip the first ticks: the blade is still finishing the strike.
				if phase_time > 0.1:
					recover_accel = maxf(recover_accel, accel)
				recover_samples.append(_local(tip))
			"stalk":
				if not recover_samples.is_empty():
					break
	if windup_speeds.size() > 9:
		windup_end_speed = windup_speeds.slice(-9).max()
	var settle := _time_to_settle(recover_samples, guard_tip)
	print("    wind-up onset arm accel %.0f rad/s², tip speed at the end of the wind-up %.2f m/s, strike peak %.1f m/s" % [onset_accel, windup_end_speed, strike_peak])
	print("    recovery: arm accel after the follow-through %.0f rad/s², back in guard after %.2f s" % [recover_accel, settle])
	_check("wind-up eases in: no jolt when the pose changes (arm %.0f rad/s² < 260)" % onset_accel, onset_accel < 260.0)
	_check("wind-up settles before the strike: the blade hangs still over the body (%.2f m/s < 0.6)" % windup_end_speed, windup_end_speed < 0.6)
	_check("the strike is still fast (peak tip %.1f m/s > 5)" % strike_peak, strike_peak > 5.0)
	_check("recovery has no snap (arm %.0f rad/s² < 150)" % recover_accel, recover_accel < 150.0)
	_check("recovery takes its time back to guard (%.2f s >= 0.35)" % settle, settle >= 0.35)


## While circling the player the body must glide, not shiver: average angular
## jerk of the limbs (second difference of angular velocity) stays low.
func _test_no_jitter_while_circling() -> void:
	var d := DuelistDifficulty.preset("normal")
	d.attack_cooldown = Vector2(60.0, 60.0)
	await _start_fight(Vector3(0.0, 0.0, 1.55), d)
	var dt := 1.0 / Engine.physics_ticks_per_second
	var hist := {}
	for name in LIMBS:
		hist[name] = [Vector3.ZERO, Vector3.ZERO]
	var total := 0.0
	var worst := 0.0
	var per_limb := {}
	var samples := 0
	await _wait(0.5)
	for i in 4 * 90:
		await get_tree().physics_frame
		for name in LIMBS:
			var w := (dummy.parts[name] as RagdollPart).angular_velocity
			var h: Array = hist[name]
			if i >= 2:
				var jerk: float = (w - 2.0 * (h[0] as Vector3) + (h[1] as Vector3)).length() / (dt * dt)
				total += jerk
				per_limb[name] = float(per_limb.get(name, 0.0)) + jerk
				worst = maxf(worst, jerk)
				samples += 1
			h[1] = h[0]
			h[0] = w
	var mean := total / maxf(samples, 1)
	var legs := (float(per_limb.upper_leg_l) + float(per_limb.upper_leg_r)) / 2.0 / maxf(samples / LIMBS.size(), 1)
	print("    circling: mean limb jerk %.0f rad/s³ (legs %.0f), worst %.0f rad/s³" % [mean, legs, worst])
	_check("circling without shivering (mean limb jerk %.0f rad/s³ < 1500)" % mean, mean < 1500.0)
	dummy.set_attacks_enabled(false)


# --- Helpers -------------------------------------------------------------------------

func _phase() -> String:
	if brain.state == DuelistBrain.State.ATTACK:
		return "windup" if brain.attack_phase == DuelistBrain.AttackPhase.WINDUP else "strike"
	return brain.state_name()


## Seconds until the tip stays within 12 cm of where it rests in guard.
func _time_to_settle(samples: Array[Vector3], guard_tip: Vector3) -> float:
	for i in samples.size():
		var rest := true
		for j in range(i, samples.size()):
			if samples[j].distance_to(guard_tip) > 0.12:
				rest = false
				break
		if rest:
			return i / float(Engine.physics_ticks_per_second)
	return samples.size() / float(Engine.physics_ticks_per_second)


func _start_fight(at: Vector3, difficulty: DuelistDifficulty = null) -> void:
	dummy.set_attacks_enabled(false)
	room.reset_room()
	player.health.heal_full()
	player.left_holder.release()
	player.holder.release()
	room.katana.global_position = Vector3(-3.5, 0.3, 3.5)
	room.kanabo.global_position = Vector3(3.5, 0.3, -3.5)
	player.teleport(at)
	var d := difficulty
	if d == null:
		d = DuelistDifficulty.preset("normal")
		d.feint_chance = 0.0
		d.combo_chance = 0.0
		d.block_chance = 0.0
		d.evade_chance = 0.0
		d.riposte_chance = 0.0
		d.hesitate_chance = 0.0
	dummy.set_difficulty(d)
	brain.set_seed(7)
	dummy.set_motion_seed(7)
	await _wait(1.0)
	dummy.set_attacks_enabled(true)


## World point in the dummy's frame: x = its left, y = up, z = toward its front.
func _local(p: Vector3) -> Vector3:
	var pelvis := dummy.root_part().global_position
	return Basis(Vector3.UP, dummy._facing_yaw).inverse() * (p - pelvis)


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _wait(seconds: float) -> void:
	for i in int(seconds * Engine.physics_ticks_per_second):
		await get_tree().physics_frame
