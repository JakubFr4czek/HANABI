extends Node
## CI fuzz test: plays the real run scene through the real XRPlayer driven by
## XrSim (fake head and controller tracking, as tests/xr_play_test.gd does) and
## feeds it random sequences of LEGAL player actions from a seeded RNG: walk,
## look around, snap turn, katana swings, open/close the menu (also mid-swing),
## walk to a shrine, use a skill, glance at the wrist, idle. After every action
## it checks invariants: no new RuntimeGuard violation (script/engine errors,
## NaN bodies, ...), HP within [0, max], the player above the terrain and inside
## the world, finite transforms, the tree paused only while the menu is open, no
## sliding while paused, and the game unpausing when the menu closes.
## Every failure prints the seed, the step and the last actions; rerun it with
##   godot --headless --path . --fixed-fps 90 res://tests/ci/fuzz_runner.tscn -- --xr-sim --seed=<seed> --steps=<n>
## Exit code 0 when no invariant broke. Game RNG is reseeded too, but physics
## and timing are not bit-exact, so a repro is very likely, not guaranteed.

const RUN_SCENE_PATH := "res://scenes/run.tscn"
const ACTIONS := ["walk", "look", "snap_turn", "swing", "menu", "menu_mid_swing", "shrine", "skill", "wrist", "idle"]
const WEIGHTS := [6, 3, 2, 7, 2, 1, 1, 2, 1, 1]
const MAX_FAILURES := 5
const WORLD_LIMIT := 20000.0
const BELOW_GROUND_TOLERANCE := 0.75
const HISTORY_LEN := 15
const SWING_LEN := 0.22

var seed_value := 0
var steps := 300
var rng := RandomNumberGenerator.new()
var run: Node = null  # RunGame (untyped so this runner never breaks a parse when the game API moves)
var xr: Node = null  # XRPlayer
var sim: Node = null  # XrSim
var origin: Node3D = null
var yaw := 0.0
var failures: Array[String] = []
var guard_seen := 0
var step_i := -1
var action := "setup"
var history: Array[String] = []
var _swing_t := -1.0
var _swing_from := Vector3.ZERO
var _swing_to := Vector3.ZERO
var _swing_target := Vector3.ZERO


func _ready() -> void:
	# Keep stepping while the menu pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_args()
	rng.seed = seed_value
	print("FUZZ seed=%d steps=%d" % [seed_value, steps])
	print(
		(
			"FUZZ repro: godot --headless --path . --fixed-fps 90 res://tests/ci/fuzz_runner.tscn -- --xr-sim --seed=%d --steps=%d"
			% [seed_value, steps]
		)
	)
	await _run_all()
	_release_inputs()
	if get_tree().paused:
		get_tree().paused = false
	if _guard():
		RuntimeGuard.print_summary()
	print("FUZZ RESULT seed=%d steps_done=%d failures=%d" % [seed_value, step_i + 1, failures.size()])
	print("\n%s (%d failed)" % ["ALL PASSED" if failures.is_empty() else "FAILURES", failures.size()])
	get_tree().quit(1 if not failures.is_empty() else 0)


func _parse_args() -> void:
	seed_value = int(Time.get_unix_time_from_system()) % 1000000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_value = int(a.get_slice("=", 1))
		elif a.begins_with("--steps="):
			steps = maxi(1, int(a.get_slice("=", 1)))


func _guard() -> bool:
	return has_node("/root/RuntimeGuard")


func _run_all() -> void:
	if _guard():
		RuntimeGuard.reset()
	var scene: PackedScene = load(RUN_SCENE_PATH)
	if scene == null:
		_fail("cannot load %s" % RUN_SCENE_PATH)
		return
	run = scene.instantiate()
	# This runner is PROCESS_MODE_ALWAYS; the game under it must pause like it does in play.
	run.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(run)
	await _frames(5)
	if "_rng" in run and run.get("_rng") is RandomNumberGenerator:
		(run.get("_rng") as RandomNumberGenerator).seed = seed_value
	xr = run.get("player")
	sim = get_tree().get_first_node_in_group("xr_sim")
	if xr == null or sim == null or not xr.has_node("XROrigin3D"):
		_fail("the XR player does not run on simulated tracking (start with -- --xr-sim)")
		return
	origin = xr.get_node("XROrigin3D") as Node3D
	guard_seen = _guard_count()
	await _intro_and_grab()
	if not failures.is_empty():
		return
	for i in steps:
		step_i = i
		if _state_name() == "GAME_OVER":
			print("FUZZ note: the run ended at step %d (player died); stopping early" % i)
			break
		_keep_alive()
		action = _pick_action()
		history.append("%d:%s" % [i, action])
		if history.size() > HISTORY_LEN:
			history.pop_front()
		await _do(action)
		_check_invariants()
		if failures.size() >= MAX_FAILURES:
			break
		if i % 50 == 0:
			print("FUZZ step %d/%d ok (%s) feet=%s" % [i, steps, action, str(_feet().snapped(Vector3.ONE * 0.1))])


# --- Actions -------------------------------------------------------------------


func _do(name: String) -> void:
	match name:
		"walk":
			await _act_walk()
		"look":
			await _act_look()
		"snap_turn":
			await _act_snap_turn()
		"swing":
			await _act_swing()
		"menu":
			await _act_menu()
		"menu_mid_swing":
			await _act_menu_mid_swing()
		"shrine":
			await _act_shrine()
		"skill":
			await _act_skill()
		"wrist":
			await _act_wrist()
		_:
			await _act_idle()


func _pick_action() -> String:
	var total := 0
	for w in WEIGHTS:
		total += w
	var r := rng.randi_range(1, total)
	for k in ACTIONS.size():
		r -= WEIGHTS[k]
		if r <= 0:
			return ACTIONS[k]
	return "idle"


func _act_walk() -> void:
	var dir := Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 1.0))
	if dir.length() < 0.2:
		dir = Vector2(0.0, 1.0)
	dir = dir.normalized() * rng.randf_range(0.35, 1.0)
	_set_head_yaw(yaw + rng.randf_range(-0.8, 0.8), rng.randf_range(-0.3, 0.2))
	sim.set_stick("left", dir)
	await _frames(rng.randi_range(30, 180))
	sim.set_stick("left", Vector2.ZERO)
	await _frames(5)


func _act_look() -> void:
	var target_yaw := yaw + rng.randf_range(-PI, PI)
	var pitch := rng.randf_range(-0.6, 0.5)
	var n := rng.randi_range(20, 60)
	var y0 := yaw
	for k in n:
		_set_head_yaw(lerp_angle(y0, target_yaw, float(k + 1) / n), pitch)
		await get_tree().physics_frame


func _act_snap_turn() -> void:
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	sim.set_stick("right", Vector2(side, 0.0))
	await _frames(8)
	sim.set_stick("right", Vector2.ZERO)
	await _frames(15)


func _act_swing() -> void:
	var cam := _camera()
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var target := cam.global_position + fwd * rng.randf_range(0.9, 1.8) + Vector3.UP * rng.randf_range(-0.7, 0.1)
	_start_swing_through(target)
	for k in 45:
		await get_tree().physics_frame
		_step_swing(1.0 / 90.0)


func _act_menu() -> void:
	await _menu_cycle(rng.randi_range(5, 90))


func _act_menu_mid_swing() -> void:
	var cam := _camera()
	_start_swing_through(cam.global_position - cam.global_basis.z * 1.3)
	for k in 8:
		await get_tree().physics_frame
		_step_swing(1.0 / 90.0)
	await _menu_cycle(rng.randi_range(10, 40))
	for k in 30:
		await get_tree().physics_frame
		_step_swing(1.0 / 90.0)


func _act_shrine() -> void:
	var hm: Node = run.get("hokora_manager")
	if hm == null or not hm.has_method("alive_shrines"):
		await _act_idle()
		return
	var shrines: Array = hm.alive_shrines()
	var best: Node3D = null
	var best_d := 40.0
	for s in shrines:
		var d := (s as Node3D).global_position.distance_to(_feet())
		if d < best_d:
			best_d = d
			best = s
	if best == null:
		await _act_walk()
		return
	var goal: Vector3 = best.call("altar_position") if best.has_method("altar_position") else best.global_position
	for k in 540:  # walk there for up to 6 s
		_look_at_world(goal)
		var flat := Vector2(goal.x - _feet().x, goal.z - _feet().z).length()
		sim.set_stick("left", Vector2(0.0, 0.8) if flat > 1.3 else Vector2.ZERO)
		await get_tree().physics_frame
		if flat <= 1.3:
			break
	sim.set_stick("left", Vector2.ZERO)
	await _frames(60)


func _act_skill() -> void:
	var cam := _camera()
	var dir := -cam.global_basis.z
	var sig := "ability_1_requested" if rng.randf() < 0.6 else "ability_2_requested"
	if xr.has_signal(sig):
		xr.emit_signal(sig, dir)
	await _frames(rng.randi_range(20, 90))


func _act_wrist() -> void:
	var b := Basis(Vector3.UP, yaw)
	var pos: Vector3 = sim.head_xf.origin + b * Vector3(-0.08, -0.28, -0.32)
	var wrist := b * Basis.from_euler(Vector3(deg_to_rad(55.0), deg_to_rad(-20.0), deg_to_rad(35.0)))
	sim.set_hand("left", Transform3D(wrist, pos))
	await _frames(rng.randi_range(30, 90))
	_rest_left()
	await _frames(5)


func _act_idle() -> void:
	await _frames(rng.randi_range(10, 60))


## Opens the menu the way the rig does (its menu_requested signal), holds it,
## checks the pause, pushes the stick (nothing may move), then closes it.
func _menu_cycle(hold: int) -> void:
	var pc: Node = run.get("pause_controller")
	if pc == null:
		await _frames(10)
		return
	if pc.has_method("can_open") and not pc.can_open():
		await _frames(10)
		return
	if xr.has_signal("menu_requested"):
		xr.emit_signal("menu_requested")
	await _frames(3)
	if not bool(pc.get("is_open")):
		pc.call("toggle")  # same entry point the button reaches
		await _frames(3)
	if not bool(pc.get("is_open")):
		_fail("the menu does not open while playing")
		return
	if not get_tree().paused:
		_fail("menu open but the game is not paused")
	var before := _feet()
	sim.set_stick("left", Vector2(0.0, 1.0))
	await _frames(hold)
	sim.set_stick("left", Vector2.ZERO)
	var slid := _feet().distance_to(before)
	if slid > 0.05:
		_fail("the player moved %.2f m while the menu was open" % slid)
	if xr.has_signal("menu_requested"):
		xr.emit_signal("menu_requested")
	await _frames(3)
	if bool(pc.get("is_open")):
		pc.call("toggle")
		await _frames(3)
	if bool(pc.get("is_open")):
		_fail("the menu does not close")
	elif get_tree().paused:
		_fail("the game stays paused after the menu closed")
	elif Engine.time_scale <= 0.0:
		_fail("time scale is %.2f after the menu closed" % Engine.time_scale)


# --- Intro (as tests/xr_play_test.gd) ----------------------------------------------


func _intro_and_grab() -> void:
	_rest_hands()
	var intro: Node = run.get("run_intro")
	var katana: Node3D = run.get("katana")
	for i in 1500:
		await get_tree().physics_frame
		if katana:
			_look_at_world(katana.global_position)
		if intro and bool(intro.get("_waiting_grab")):
			break
		if _state_name() == "PLAYING":
			return
	if katana == null or intro == null or not bool(intro.get("_waiting_grab")):
		_fail("the katana is never offered after the intro")
		return
	var grip_world := katana.global_transform * Vector3(0.0, 0.0, 0.06)
	await _move_hand_to_world("right", grip_world, katana.global_basis, 0.5)
	sim.set_grip("right", 1.0)
	await _frames(20)
	if _state_name() != "PLAYING":
		_fail("taking the katana does not start the run (state %s)" % _state_name())


# --- Invariants ----------------------------------------------------------------


func _check_invariants() -> void:
	var g := _guard_count()
	if g > guard_seen:
		_fail("RuntimeGuard: %d new violation(s): %s" % [g - guard_seen, _guard_codes()])
		guard_seen = g
	var health: Node = xr.get("health")
	if health:
		var hp := float(health.get("hp"))
		var max_hp := float(health.get("max_hp"))
		if is_nan(hp) or hp < 0.0 or hp > max_hp + 0.001:
			_fail("HP out of range: %s / %s" % [hp, max_hp])
	var feet := _feet()
	if not _finite(feet):
		_fail("player feet position is not finite: %s" % feet)
	else:
		if absf(feet.x) > WORLD_LIMIT or absf(feet.z) > WORLD_LIMIT or absf(feet.y) > 1000.0:
			_fail("player left the world: %s" % feet)
		var fw: Node = run.get("forest_world")
		if fw and fw.has_method("height_at"):
			var ground := float(fw.height_at(feet.x, feet.z))
			if feet.y < ground - BELOW_GROUND_TOLERANCE:
				_fail("player %.2f m below the terrain at %s" % [ground - feet.y, feet.snapped(Vector3.ONE * 0.01)])
	for n in [
		_camera(),
		xr.get_node_or_null("XROrigin3D/LeftHand"),
		xr.get_node_or_null("XROrigin3D/RightHand"),
		run.get("katana")
	]:
		if n is Node3D and not _finite_xf((n as Node3D).global_transform):
			_fail("non-finite transform on %s" % (n as Node).name)
	var pc: Node = run.get("pause_controller")
	var open := pc != null and bool(pc.get("is_open"))
	if get_tree().paused and not open:
		_fail("the tree is paused with no menu open")
	if not open and Engine.time_scale <= 0.0:
		_fail("Engine.time_scale is %.2f outside the menu" % Engine.time_scale)


func _guard_count() -> int:
	return int(RuntimeGuard.violation_count()) if _guard() else 0


func _guard_codes() -> String:
	if not _guard():
		return ""
	var first: Dictionary = RuntimeGuard.get("_first_seen") if "_first_seen" in RuntimeGuard else {}
	var out: Array[String] = []
	for code in RuntimeGuard.get("violations") as Dictionary:
		out.append("%s (%s)" % [code, str(first.get(code, "")).left(160)])
	return ", ".join(out)


func _fail(msg: String) -> void:
	var line := "FUZZ FAIL seed=%d step=%d action=%s :: %s" % [seed_value, step_i, action, msg]
	print(line)
	print("    last actions: %s" % " ".join(history))
	failures.append(line)


func _keep_alive() -> void:
	var health: Node = xr.get("health")
	if health and float(health.get("hp")) < 35.0 and health.has_method("heal"):
		health.heal(float(health.get("max_hp")))


func _state_name() -> String:
	var s = run.get("state")
	if s == null:
		return ""
	var names := ["INTRO", "PLAYING", "GAME_OVER"]
	return names[int(s)] if int(s) >= 0 and int(s) < names.size() else str(s)


static func _finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


static func _finite_xf(t: Transform3D) -> bool:
	return _finite(t.origin) and _finite(t.basis.x) and _finite(t.basis.y) and _finite(t.basis.z)


# --- Body (from tests/xr_play_test.gd) ------------------------------------------


func _camera() -> Node3D:
	return xr.get_node("XROrigin3D/XRCamera3D") as Node3D


func _feet() -> Vector3:
	return xr.feet_position() if xr.has_method("feet_position") else (xr as Node3D).global_position


func _set_head_yaw(new_yaw: float, pitch: float) -> void:
	yaw = new_yaw
	sim.set_head(Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0.0)), sim.head_xf.origin))


func _look_at_world(p: Vector3) -> void:
	var inv := origin.global_transform.affine_inverse()
	var to := inv * p - inv * _camera().global_position
	if Vector2(to.x, to.z).length() < 0.05:
		return
	yaw = lerp_angle(yaw, atan2(-to.x, -to.z), 0.15)
	var pitch := clampf(atan2(to.y, Vector2(to.x, to.z).length()), -0.6, 0.6)
	sim.set_head(Transform3D(Basis.from_euler(Vector3(pitch * 0.6, yaw, 0.0)), sim.head_xf.origin))


func _rest_hands() -> void:
	var b := Basis(Vector3.UP, yaw)
	sim.set_hand("right", Transform3D(b, sim.head_xf.origin + b * Vector3(0.22, -0.6, -0.3)))
	_rest_left()


func _rest_left() -> void:
	var b := Basis(Vector3.UP, yaw)
	sim.set_hand("left", Transform3D(b, sim.head_xf.origin + b * Vector3(-0.22, -0.6, -0.3)))


func _release_inputs() -> void:
	if sim:
		sim.set_stick("left", Vector2.ZERO)
		sim.set_stick("right", Vector2.ZERO)


func _move_hand_to_world(side: String, world: Vector3, world_basis: Basis, seconds: float) -> void:
	var holder: Node3D = xr.get("right_holder") if side == "right" else xr.get("left_holder")
	var o_inv := origin.global_transform.affine_inverse()
	var want_holder := Transform3D(o_inv.basis * world_basis, o_inv * world)
	var want_ctrl := want_holder * (holder.transform.affine_inverse() if holder else Transform3D.IDENTITY)
	var start: Transform3D = sim.hand_xf[side]
	var n := int(seconds * 90.0)
	for i in n:
		sim.set_hand(side, start.interpolate_with(want_ctrl, float(i + 1) / float(n)))
		await get_tree().physics_frame


func _start_swing_through(world_target: Vector3) -> void:
	_swing_target = origin.global_transform.affine_inverse() * world_target
	var b := Basis(Vector3.UP, yaw)
	var shoulder: Vector3 = sim.head_xf.origin + b * Vector3(0.2, -0.25, 0.0)
	var reach := _swing_target - shoulder
	var hand_mid := shoulder + reach.normalized() * clampf(reach.length() - 0.6, 0.3, 0.65)
	var flip := -1.0 if rng.randf() < 0.3 else 1.0  # some backhand cuts too
	_swing_from = hand_mid + b * Vector3(0.3 * flip, 0.3, 0.05)
	_swing_to = hand_mid + b * Vector3(-0.3 * flip, -0.3, -0.05)
	_swing_t = 0.0


func _step_swing(dt: float) -> void:
	if _swing_t < 0.0:
		return
	_swing_t += dt
	var b := Basis(Vector3.UP, yaw)
	var u := clampf(_swing_t / SWING_LEN, 0.0, 1.0)
	var e := u * u * (3.0 - 2.0 * u)
	var pos := _swing_from.lerp(_swing_to, e)
	var motion := (_swing_to - _swing_from).normalized()
	var aim := _swing_target + b * Vector3(0.45, 0.45, 0.0) * (1.0 - 2.0 * e)
	var blade_dir := (aim - pos).normalized()
	var up := -motion.slide(blade_dir)
	if up.length_squared() < 1e-4:
		up = Vector3.UP
	if blade_dir.cross(up.normalized()).length_squared() > 1e-6:
		sim.set_hand("right", Transform3D(Basis.looking_at(blade_dir, up.normalized()), pos))
	if _swing_t > SWING_LEN + 0.25:
		_swing_t = -1.0
		sim.set_hand("right", Transform3D(b, sim.head_xf.origin + b * Vector3(0.25, -0.45, -0.35)))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame
