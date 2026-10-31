extends Node
## Plays the game as a VR player would, through the real XRPlayer driven by
## XrSim (fake head and controller tracking, grip and stick input): watch the
## gate, reach for the katana and close the hand, turn to the yōkai, walk with
## the stick, cut with arm swings, glance
## at the wrist, die, restart by cutting the restart ema, and do it all
## again. Everything is done physically; whatever cannot be done that way is a
## bug. The RuntimeGuard watches the whole session. Run with:
##   godot --headless --path . --fixed-fps 90 res://tests/xr_play_test.tscn -- --xr-sim
## Exit code 0 when everything passed.

const RUN_SCENE := preload("res://scenes/run.tscn")

var failures := 0
var run: RunGame
var xr: XRPlayer
var sim: XrSim
var origin: XROrigin3D
var yaw := 0.0  # head/body facing in origin space
var _swing_t := -1.0
var _swing_from := Vector3.ZERO
var _swing_to := Vector3.ZERO
var _swing_len := 0.22
var _swing_target := Vector3.ZERO


func _ready() -> void:
	await _run_all()
	RuntimeGuard.print_summary()
	_check("the runtime guard stayed clean (%d violations)" % RuntimeGuard.violation_count(), RuntimeGuard.violation_count() == 0)
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	RuntimeGuard.reset()
	run = RUN_SCENE.instantiate()
	add_child(run)
	await _frames(5)
	xr = run.player as XRPlayer
	sim = get_tree().get_first_node_in_group("xr_sim") as XrSim
	_check("the XR player runs on simulated tracking", xr != null and sim != null)
	if xr == null or sim == null:
		return
	origin = xr.get_node("XROrigin3D") as XROrigin3D
	for cycle in 2:
		var tag := "run %d" % (cycle + 1)
		await _intro_and_grab(tag)
		await _fight(tag, 40.0 if cycle == 0 else 20.0)
		await _die_and_restart(tag)


# --- Phases --------------------------------------------------------------------

func _intro_and_grab(tag: String) -> void:
	_rest_hands()
	for i in 1500:
		await get_tree().physics_frame
		_look_at_world(run.katana.global_position)
		if run.run_intro._waiting_grab:
			break
	_check("%s: the katana is offered after the gate" % tag, run.run_intro._waiting_grab)
	# Reach: put the right fist around the handle, then close it.
	var grip_world := run.katana.global_transform * Vector3(0.0, 0.0, 0.06)
	await _move_hand_to_world("right", grip_world, run.katana.global_basis, 0.5)
	sim.set_grip("right", 1.0)
	await _frames(6)
	_check("%s: closing the hand on the handle takes the katana" % tag, xr.right_holder.held == run.katana)
	await _frames(10)
	_check("%s: taking it starts the run" % tag, run.state == RunGame.RunState.PLAYING)
	var local := run.katana.get_local_grip(xr.right_holder).origin
	_check("%s: the fist sits on the handle, not the blade (grip z %.3f)" % [tag, local.z],
		local.z >= run.katana.grip_min_z() - 0.001 and local.z <= run.katana.grip_max_z() + 0.001)


func _fight(tag: String, seconds: float) -> void:
	var kills0 := run.kills
	var wrist_seen := false
	var t := 0.0
	var hp_low := false
	while t < seconds:
		await get_tree().physics_frame
		var dt := 1.0 / 90.0
		t += dt
		var health := xr.health
		if health.hp < 35.0:
			health.heal(health.max_hp)  # stay alive to see the whole fight
			hp_low = true
		if run.state == RunGame.RunState.PLAYING:
			var target := _nearest_enemy()
			if target:
				var tp := target.root_part().global_position
				_look_at_world(tp)
				var dist := Vector2(tp.x - _feet().x, tp.z - _feet().z).length()
				sim.set_stick("left", Vector2(0.0, 1.0) if dist > 2.0 else Vector2.ZERO)
				if dist < 2.3 and _swing_t < 0.0:
					_start_swing_through(tp + Vector3.UP * 0.25)
			else:
				sim.set_stick("left", Vector2.ZERO)
			# Every few seconds bring the left wrist up to read the plate.
			if fmod(t, 6.0) < 0.8:
				_raise_wrist()
				if run.diegetic_hud.wrist_label.visible:
					wrist_seen = true
			else:
				_rest_left()
		_step_swing(dt)
	sim.set_stick("left", Vector2.ZERO)
	_check("%s: arm swings kill yōkai (%d kills)" % [tag, run.kills - kills0], run.kills - kills0 > 0)
	_check("%s: raising the wrist shows the HUD readout" % tag, wrist_seen)
	_check("%s: the katana stays in the hand through the fight" % tag, xr.right_holder.held == run.katana)
	if hp_low:
		print("    (%s: the player was topped up to stay alive)" % tag)


func _die_and_restart(tag: String) -> void:
	xr.health._invulnerable = 0.0
	xr.health.take_hit(10000.0, _feet() + Vector3.FORWARD)
	for i in 600:
		await get_tree().physics_frame
		if is_instance_valid(run.restart_ema) and run.restart_ema.is_ready_to_cut():
			break
	_check("%s: death raises the restart ema" % tag, is_instance_valid(run.restart_ema))
	var cut := false
	for i in 600:
		await get_tree().physics_frame
		if run.state == RunGame.RunState.INTRO:
			cut = true
			break
		if is_instance_valid(run.restart_ema):
			_look_at_world(run.restart_ema.global_position)
			_step_toward(run.restart_ema.global_position, 1.3)
			if _swing_t < 0.0 and run.restart_ema.is_ready_to_cut() and _flat_dist(run.restart_ema.global_position) <= 1.4:
				_start_swing_through(run.restart_ema.global_position)
			if OS.get_cmdline_user_args().has("--verbose-cards") and i % 15 == 0:
				var ro := run.restart_ema
				var inv := ro._card_root.global_transform.affine_inverse()
				print("    restart i%d dist %.2f ready %s armed %s clear %s swing %.2f tip %s stick %s feet %s ro %s" % [i, _flat_dist(ro.global_position),
					ro.is_ready_to_cut(), ro.is_armed(), ro._blade_clear, _swing_t, (inv * run.katana.get_tip_global()).snapped(Vector3.ONE * 0.01),
					sim._hands["left"].get_input("primary"), _feet().snapped(Vector3.ONE * 0.01), ro.global_position.snapped(Vector3.ONE * 0.01)])
		_step_swing(1.0 / 90.0)
	_check("%s: cutting the restart ema starts a new run" % tag, cut)
	if not cut and is_instance_valid(run.restart_ema):
		var rp := run.restart_ema.global_position
		print("    restart miss: trunk push at the ema %.2f, ground %.2f, ro y %.2f" % [
			run.forest_world.trunk_push(rp, Vector3.FORWARD, 0.9).length(), run.forest_world.height_at(rp.x, rp.z), rp.y])
	if not cut and is_instance_valid(run.restart_ema):
		run.restart_ema.slice(run.restart_ema.global_position, Vector3.RIGHT)
	sim.set_grip("right", 0.0)
	await _frames(10)


# --- Body language -------------------------------------------------------------

func _feet() -> Vector3:
	return xr.feet_position()


## Turn head (and so the body) toward a world point.
func _look_at_world(p: Vector3) -> void:
	var cam := xr.get_node("XROrigin3D/XRCamera3D") as Node3D
	var to := origin.global_transform.affine_inverse() * p - origin.global_transform.affine_inverse() * cam.global_position
	if Vector2(to.x, to.z).length() < 0.05:
		return
	var want := atan2(-to.x, -to.z)
	yaw = lerp_angle(yaw, want, 0.15)
	var pitch := clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.6, 0.6)
	var h := sim.head_xf
	sim.set_head(Transform3D(Basis.from_euler(Vector3(pitch * 0.6, yaw, 0.0)), h.origin))


func _flat_dist(p: Vector3) -> float:
	var cam := xr.get_node("XROrigin3D/XRCamera3D") as Node3D
	return Vector2(p.x - cam.global_position.x, p.z - cam.global_position.z).length()


## Walk with the left stick until [param p] is within [param reach].
func _step_toward(p: Vector3, reach: float) -> void:
	sim.set_stick("left", Vector2(0.0, 0.6) if _flat_dist(p) > reach else Vector2.ZERO)


func _body_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func _rest_hands() -> void:
	var b := _body_basis()
	sim.set_hand("right", Transform3D(b, sim.head_xf.origin + b * Vector3(0.22, -0.6, -0.3)))
	_rest_left()


func _rest_left() -> void:
	var b := _body_basis()
	sim.set_hand("left", Transform3D(b, sim.head_xf.origin + b * Vector3(-0.22, -0.6, -0.3)))


## Left forearm level in front of the face, back of the wrist toward the eyes: the check-the-watch
## pose (P9; an upright hand does not show the readout). The readout (the ring on the back of the
## wrist) lands about 0.27 m from the eyes: inside the gesture's 0.35 m (wrist_hud_test pins the limits).
func _raise_wrist() -> void:
	var b := _body_basis()
	var ring_at := sim.head_xf.origin + b * Vector3(-0.06, -0.20, -0.26)
	var to_eye := (sim.head_xf.origin - ring_at).normalized()
	# The forearm runs level from the wrist back toward the elbow, which is by the body.
	var z := Vector3.UP.cross(to_eye).normalized()
	if z.dot(b * Vector3.BACK) < 0.0:
		z = -z
	var x := to_eye.cross(z).normalized()
	var target_basis := Basis(x, to_eye, z)
	var mount := Basis.from_euler(Vector3(deg_to_rad(6.0), 0.0, deg_to_rad(-14.0)))
	var wrist := target_basis * mount.inverse()
	sim.set_hand("left", Transform3D(wrist, ring_at - wrist * DiegeticHud.RING_OFFSET))


## Move a hand so its weapon holder lands on [param world] over [param seconds].
func _move_hand_to_world(side: String, world: Vector3, world_basis: Basis, seconds: float) -> void:
	var holder := xr.right_holder if side == "right" else xr.left_holder
	var o_inv := origin.global_transform.affine_inverse()
	var want_holder := Transform3D(o_inv.basis * world_basis, o_inv * world)
	var want_ctrl := want_holder * holder.transform.affine_inverse()
	var start: Transform3D = sim.hand_xf[side]
	var n := int(seconds * 90.0)
	for i in n:
		sim.set_hand(side, start.interpolate_with(want_ctrl, float(i + 1) / float(n)))
		await get_tree().physics_frame


## A committed cut: the hand sweeps from up-right to down-left in ~0.22 s
## while the blade points at the target and its edge leads the motion, so
## the steel crosses the target like a real diagonal cut (kesa-giri).
func _start_swing_through(world_target: Vector3) -> void:
	var o_inv := origin.global_transform.affine_inverse()
	_swing_target = o_inv * world_target
	var b := _body_basis()
	var shoulder := sim.head_xf.origin + b * Vector3(0.2, -0.25, 0.0)
	var reach := _swing_target - shoulder
	var hand_mid := shoulder + reach.normalized() * clampf(reach.length() - 0.6, 0.3, 0.65)
	_swing_from = hand_mid + b * Vector3(0.3, 0.3, 0.05)
	_swing_to = hand_mid + b * Vector3(-0.3, -0.3, -0.05)
	_swing_t = 0.0


func _step_swing(dt: float) -> void:
	if _swing_t < 0.0:
		return
	_swing_t += dt
	var b := _body_basis()
	var u := clampf(_swing_t / _swing_len, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var pos := _swing_from.lerp(_swing_to, e)
	var motion := (_swing_to - _swing_from).normalized()
	# Aim through the target, the aim point sweeping across it with the hand.
	var aim := _swing_target + b * Vector3(0.45, 0.45, 0.0) * (1.0 - 2.0 * e)
	var blade_dir := (aim - pos).normalized()
	var up := -motion.slide(blade_dir)
	if up.length_squared() < 1e-4:
		up = Vector3.UP
	sim.set_hand("right", Transform3D(Basis.looking_at(blade_dir, up.normalized()), pos))
	if _swing_t > _swing_len + 0.25:
		_swing_t = -1.0
		_rest_right_after_swing()


func _rest_right_after_swing() -> void:
	var b := _body_basis()
	sim.set_hand("right", Transform3D(b, sim.head_xf.origin + b * Vector3(0.25, -0.45, -0.35)))


func _nearest_enemy() -> Yokai:
	var best := 30.0
	var out: Yokai = null
	for y in run.wave_director.alive_enemies():
		var d := y.root_part().global_position.distance_to(_feet())
		if d < best:
			best = d
			out = y
	return out


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
