extends Node
## F4 visual test on the real run.tscn: the start-of-run controls hint as it RENDERS
## (before = the same frame with the hint hidden, after = shown, same camera), checked
## in pixels (in frame, lower-centre, readable text on a dark plate), then the controls
## map page of the menu. Windowed only (SKIP headless):
##   timeout 600 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 960x540 res://tests/f4_controls_shots.tscn -- --shots docs/f4

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_f4"
var run: RunGame
var failures := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  F4 hint pixel checks need a window (see docs/f4)")
		get_tree().quit(0)
		return
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _run_all()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _run_all() -> void:
	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://f4_shots_save.cfg"
	add_child(run)
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	await _frames(20)
	var hint := run.controls_hint
	_check("the run showed the controls hint at the start", run.controls_hint_shown and is_instance_valid(hint))
	if not is_instance_valid(hint):
		return
	# Hold it fully shown for the shots (its own clock would fade it on a slow xvfb).
	hint.set_process(false)
	hint._alpha = 1.0
	hint._apply_alpha()
	var cam := get_viewport().get_camera_3d()
	hint.visible = false
	await _frames(6)
	var before := await _shot("before_01_run_start")
	hint.visible = true
	await _frames(6)
	var after := await _shot("after_01_run_start_hint")

	var size := after.get_size()
	var centre := cam.unproject_position(hint.global_position)
	_check("the hint sits in frame, centred, below the middle (%s of %s)" % [centre, size],
		not cam.is_position_behind(hint.global_position) and absf(centre.x - size.x * 0.5) < size.x * 0.1
		and centre.y > size.y * 0.5 and centre.y < size.y * 0.92)
	# The plate's box on screen from its corners.
	var half := ControlsHint.PLATE_SIZE * 0.5
	var r := Rect2(cam.unproject_position(hint.to_global(Vector3(-half.x, half.y, 0.0))), Vector2.ZERO)
	r = r.expand(cam.unproject_position(hint.to_global(Vector3(half.x, -half.y, 0.0))))
	r = r.grow(-4.0).intersection(Rect2(Vector2.ZERO, size))
	# 0.56 m at 1.5 m: about 21° wide in the headset, ~13 % of this 75° desktop frame.
	_check("the plate is a fair size on screen (%s)" % r.size, r.size.x > size.x * 0.11 and r.size.y > size.y * 0.06)
	var b := _stats(before, r)
	var a := _stats(after, r)
	print("hint box %s  before mean %.3f bright %.3f  after mean %.3f bright %.3f dark %.3f" % [r, b.mean, b.bright, a.mean, a.bright, a.dark])
	_check("the hint text renders bright on the plate (%.1f%% bright px)" % (a.bright * 100.0), a.bright > 0.03 and a.bright > b.bright + 0.02)
	_check("the plate behind it is dark (%.0f%% dark px)" % (a.dark * 100.0), a.dark > 0.5)

	# The controls map page in the menu (the same map, from the action map).
	run.pause_controller.open()
	var menu := run.pause_controller.menu
	await _frames(40)
	menu.select_settings()
	menu.canvas.settings_page = SkillTreeCanvas.PAGE_CONTROLS
	await _frames(14)
	await _shot("after_02_controls_map")


func _stats(img: Image, r: Rect2) -> Dictionary:
	var n := 0
	var sum := 0.0
	var bright := 0
	var dark := 0
	for y in range(int(r.position.y), int(r.end.y), 2):
		for x in range(int(r.position.x), int(r.end.x), 2):
			var l := img.get_pixel(x, y).get_luminance()
			sum += l
			n += 1
			if l > 0.6:
				bright += 1
			elif l < 0.12:
				dark += 1
	n = maxi(n, 1)
	return {"mean": sum / n, "bright": float(bright) / n, "dark": float(dark) / n}


func _shot(name: String) -> Image:
	# Wait for frames that were really drawn: on a slow xvfb several physics frames
	# fall inside one render, and the capture would be the stale frame.
	for _k in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(out_dir.path_join(name + ".png"))
		print("saved ", name)
	return img


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame
