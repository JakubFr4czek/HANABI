extends Node
## N14: demo-only start exposure, checked on the real run scene (windowed, not headless):
##   godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --resolution 960x540 res://tests/n14_demo_start_visual_test.tscn -- --shots=docs/n14
## Same camera for PRE (lift off = default run) and POST (demo lift at t = 0): the
## spawn looking down the trail with a torii 16 m ahead. Checks what renders:
## the frame is brighter, the torii and the trail stay distinct from the fog, the
## hue of the frame does not move, and after the fade the frame is the default one.

const RUN_SCENE := preload("res://scenes/run.tscn")

var shots_dir := ""
var run: RunGame = null
var player: DesktopPlayer = null
var forest: ForestWorld = null
var failures: Array[String] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots_dir = a.trim_prefix("--shots=")
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	if DisplayServer.get_name() == "headless":
		print("SKIP  N14 pixel checks need a window (run windowed, see docs/n14)")
		get_tree().quit(0)
		return
	_logic_checks()
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	for _k in 30:
		await get_tree().process_frame
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	var lightning := run.get_node_or_null("Arena/StormLightning")
	if lightning:
		lightning.process_mode = Node.PROCESS_MODE_DISABLED
		lightning.set("_strike_age", -1.0)
		lightning.call("_set_flash", 0.0)
	player = run.player as DesktopPlayer
	forest = run.forest_world
	var grade := run.demo_grade
	_check(grade != null, "run has a RunDemoGrade")
	if grade == null:
		_finish()
		return
	var env: Environment = (run.get_node("WorldEnvironment") as WorldEnvironment).environment
	# The default run (no --demo) never lifts.
	_check(not grade.enabled, "grade is off without --demo")
	_check(is_equal_approx(env.tonemap_exposure, grade.base_exposure()), "default run keeps the profile exposure")

	var spawn := run.find_child("PlayerSpawn", true, false) as Node3D
	var at := Vector2(spawn.global_position.x, spawn.global_position.z)
	var along: Vector2 = AtmosphereMetrics.trail_direction(forest, at)
	var gate_pos := Vector3.INF
	var ahead: Vector2 = AtmosphereMetrics.trail_point(forest, at, along, 16.0)
	if ahead != Vector2.INF:
		forest.torii_manager.clear_gates()
		var gate: Node3D = forest.torii_manager.spawn_gate_at(ahead.x, ahead.y, Elements.STORM)
		gate_pos = gate.global_position
	var target: Vector2 = Vector2(gate_pos.x, gate_pos.z) if gate_pos != Vector3.INF else at + along
	var to := target - at
	player.teleport(Vector3(at.x, forest.height_at(at.x, at.y) + 0.2, at.y), atan2(-to.x, -to.y))
	player.camera.rotation.x = deg_to_rad(-6.0)

	run.run_time = 0.0
	var before := await _settle_capture("before_start")
	grade.enabled = true
	run.run_time = 0.0
	var after := await _settle_capture("after_start")
	_check(grade.current_weight() > 0.99, "demo lift is full at t=0 (w=%.2f)" % grade.current_weight())
	run.run_time = RunDemoGrade.HOLD_SECONDS + RunDemoGrade.FADE_SECONDS + 1.0
	var faded := await _settle_capture("after_fade")
	_check(is_equal_approx(env.tonemap_exposure, grade.base_exposure()), "exposure back to the profile after the fade")

	var m0 := AtmosphereMetrics.mean_lum(before)
	var m1 := AtmosphereMetrics.mean_lum(after)
	var m2 := AtmosphereMetrics.mean_lum(faded)
	print("MEASURE mean before=%.3f after=%.3f faded=%.3f" % [m0, m1, m2])
	_check(m1 > m0 * 1.10, "start frame is visibly brighter (%.3f → %.3f)" % [m0, m1])
	_check(m1 < m0 * 1.60, "lift stays subtle (≤ +60%% mean luminance)")
	_check(absf(m2 - m0) < maxf(0.01, m0 * 0.04), "after the fade the frame is the default one (%.3f vs %.3f)" % [m2, m0])
	# Lower third = trail ahead of the feet.
	var t0 := AtmosphereMetrics.mean_lum(before, 0.66, 1.0)
	var t1 := AtmosphereMetrics.mean_lum(after, 0.66, 1.0)
	print("MEASURE trail before=%.3f after=%.3f" % [t0, t1])
	_check(t1 > t0 * 1.10, "trail at the feet is brighter")
	var c0 := AtmosphereMetrics.rms_contrast(before)
	var c1 := AtmosphereMetrics.rms_contrast(after)
	print("MEASURE rms before=%.3f after=%.3f std before=%.3f after=%.3f" % [c0, c1, c0 * m0, c1 * m1])
	# Lifting the shadows lowers std/mean a little by design (dark-heavy frame), but the
	# absolute spread must grow (more detail visible) and the frame must not go flat.
	_check(c1 * m1 > c0 * m0, "absolute contrast grows with the lift")
	_check(c1 >= c0 * 0.85, "lift does not wash out the frame (rms %.3f → %.3f)" % [c0, c1])
	var h0 := _mean_color(before)
	var h1 := _mean_color(after)
	var hue_shift := AtmosphereMetrics.hue_gap(h0, h1)
	print("MEASURE hue before=%.0f after=%.0f gap=%.1f" % [AtmosphereMetrics.hue_deg(h0), AtmosphereMetrics.hue_deg(h1), hue_shift])
	_check(hue_shift < 10.0, "palette unchanged (mean hue shift %.1f°)" % hue_shift)
	if gate_pos != Vector3.INF:
		var cam := player.camera
		var top := gate_pos + Vector3.UP * 3.0
		_check(not cam.is_position_behind(top), "torii is in front of the camera")
		var side := cam.global_transform.basis.x * 3.5
		var g0 := AtmosphereMetrics.patch_lum(before, cam, top, 3)
		var f0 := AtmosphereMetrics.patch_lum(before, cam, top + side, 3)
		var g1 := AtmosphereMetrics.patch_lum(after, cam, top, 3)
		var f1 := AtmosphereMetrics.patch_lum(after, cam, top + side, 3)
		print("MEASURE torii before=%.3f fog=%.3f | after=%.3f fog=%.3f" % [g0, f0, g1, f1])
		if g0 >= 0.0 and f0 >= 0.0 and g1 >= 0.0 and f1 >= 0.0:
			_check(absf(f1 - g1) >= absf(f0 - g0) * 0.9, "torii stays separated from the fog")
	_finish()


## Pure data: the weight curve holds, then eases to 0 without a step (no pumping at 72 Hz).
func _logic_checks() -> void:
	_check(RunDemoGrade.FADE_SECONDS >= 5.0, "fade back is ≥ 5 s")
	_check(RunDemoGrade.lift_weight(0.0) == 1.0 and RunDemoGrade.lift_weight(RunDemoGrade.HOLD_SECONDS) == 1.0, "full lift during the hold")
	_check(RunDemoGrade.lift_weight(RunDemoGrade.HOLD_SECONDS + RunDemoGrade.FADE_SECONDS) == 0.0, "lift ends after the fade")
	var prev := 1.0
	var max_step := 0.0
	var t := 0.0
	while t < 30.0:
		t += 1.0 / 72.0
		var w := RunDemoGrade.lift_weight(t)
		_check(w <= prev + 1e-6, "weight never rises")
		max_step = maxf(max_step, prev - w)
		prev = w
	_check(max_step * RunDemoGrade.EXPOSURE_LIFT < 0.004, "exposure moves < 0.4 %% per frame (%.4f)" % (max_step * RunDemoGrade.EXPOSURE_LIFT))


func _settle_capture(name: String) -> Image:
	for _k in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img.is_compressed():
		img.decompress()
	if shots_dir != "":
		img.save_png(shots_dir.path_join("%s.png" % name))
	return img


func _mean_color(img: Image) -> Color:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in range(0, img.get_height(), 6):
		for x in range(0, img.get_width(), 6):
			var c := img.get_pixel(x, y)
			r += c.r
			g += c.g
			b += c.b
			n += 1
	return Color(r / n, g / n, b / n)


func _check(ok: bool, label: String) -> void:
	if ok:
		return
	failures.append(label)
	print("FAIL: ", label)


func _finish() -> void:
	if failures.is_empty():
		print("PASS n14_demo_start_visual_test")
		get_tree().quit(0)
	else:
		print("FAIL n14_demo_start_visual_test: %d" % failures.size())
		get_tree().quit(1)
