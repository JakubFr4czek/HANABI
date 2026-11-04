extends Node
## F5 visual test on the real run scene (windowed; headless reports SKIP): the run boss is
## the masked katana duelist, seen from 4 m in the forest, plus the AI speech bubble.
## Same camera for the old Oni (--tag before) and the new boss (--tag after):
##   timeout 600 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 960x540 res://tests/f5_katana_boss_shots.tscn -- --shots docs/f5 --tag after
## Pixel checks (after): the boss covers its projected box against the empty frame, the
## whole body (head to feet) and the katana are inside the frame, the mask reads against
## the body, and the bubble text is on screen above the head.

const RUN_SCENE := preload("res://scenes/run.tscn")
const DISTANCE := 4.0
var out_dir := "/tmp/hanabi_f5"
var tag := "after"
var run: RunGame
var player: DesktopPlayer
var failures := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  f5_katana_boss_shots needs a window (pixels)")
		print("\nALL PASSED (0 failed)")
		get_tree().quit(0)
		return
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	i = args.find("--tag")
	if i >= 0 and i + 1 < args.size():
		tag = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(120.0).timeout.connect(func():
		print("WATCHDOG TIMEOUT in f5_katana_boss_shots")
		get_tree().quit(1))

	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	# The run-start controls hint lives 6 s; the boss enters at ≥ 60 s, so hide it here too.
	run.controls_hint_shown = true
	run.high_score_path = "user://f5_shots_save.cfg"
	add_child(run)
	player = run.player as DesktopPlayer
	var health := get_tree().get_first_node_in_group("player_health") as PlayerHealth
	if health:
		health.max_hp = 100000.0
		health.hp = 100000.0
	var director := run.wave_director
	director.stop_director()
	director.clear_enemies()
	await _frames(40)

	# The player stands where the run starts and looks straight ahead (camera at eye height).
	var cam := player.camera
	var eye := cam.global_position
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	player._pitch = deg_to_rad(-6.0)
	cam.rotation.x = player._pitch
	await _frames(10)
	var empty := get_viewport().get_texture().get_image()

	director.boss_katana_duelist = tag != "before"
	var dist := DISTANCE
	var di := OS.get_cmdline_user_args().find("--distance")
	if di >= 0 and di + 1 < OS.get_cmdline_user_args().size():
		dist = float(OS.get_cmdline_user_args()[di + 1])
	var spot := eye + fwd * dist
	spot.y = run.forest_world.height_at(spot.x, spot.z)
	var boss := director.spawn_oni_boss(player.global_position)
	boss.set_attacks_enabled(false)
	boss.global_position = spot
	boss.home_position = spot
	boss.rotation.y = atan2(-fwd.x, -fwd.z)
	boss.reset_body()
	var brain := boss.brain as OniBossBrain
	brain._ai_timer = 999.0
	await _frames(90)
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join("%s_01_boss_4m.png" % tag))

	# The AI bubble: a mock reply goes through the brain as a real decision does.
	brain.ai_client.set_mock_provider(func(_s: Dictionary) -> Dictionary:
		return {"tactic": "feint", "attack": "sweep", "speech": "Twoja stal drży, wędrowcze."})
	brain._ai_timer = 0.0
	await _frames(4)
	brain._ai_timer = 999.0
	await _frames(40)
	var img_b := get_viewport().get_texture().get_image()
	img_b.save_png(out_dir.path_join("%s_02_ai_bubble.png" % tag))

	if tag != "before":
		_pixel_checks(boss, empty, img, img_b)
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _pixel_checks(boss: RunOniBoss, empty: Image, img: Image, img_b: Image) -> void:
	var cam := player.camera
	var size := Vector2(img.get_width(), img.get_height())
	var d := _flat(boss.root_part().global_position).distance_to(_flat(cam.global_position))
	_check("boss stands ~4 m from the camera (%.2f m)" % d, d > 3.4 and d < 4.6)
	var head := boss.parts["head"] as RagdollPart
	var feet := boss.get_feet_lowest_y()
	var head_px := cam.unproject_position(head.global_position + Vector3(0, 0.13, 0))
	var feet_px := cam.unproject_position(Vector3(head.global_position.x, feet, head.global_position.z))
	var rect := Rect2(Vector2.ZERO, size)
	_check("head and feet in frame (head %s, feet %s)" % [head_px, feet_px],
		rect.has_point(head_px) and rect.has_point(feet_px) and feet_px.y - head_px.y > size.y * 0.22)
	# Body coverage: pixels in the boss column that differ from the empty frame.
	var x0 := int(head_px.x - size.x * 0.06)
	var x1 := int(head_px.x + size.x * 0.06)
	var changed := 0
	var total := 0
	for y in range(int(head_px.y), int(feet_px.y), 3):
		for x in range(x0, x1, 3):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			total += 1
			var a := img.get_pixel(x, y)
			var b := empty.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.06:
				changed += 1
	var cover := float(changed) / maxf(float(total), 1.0)
	_check("the boss body reads against the forest (%.0f%% of its column changed)" % (cover * 100.0), cover > 0.25)
	# Katana: blade mid and tip project inside the frame and change pixels around them.
	var sword := boss.sword
	var mid := sword.global_transform * ((sword.blade_start + sword.blade_tip) * 0.5)
	var mid_px := cam.unproject_position(mid)
	var tip_px := cam.unproject_position(sword.get_tip_global())
	var blade_seen := 0
	for k in 9:
		var p := mid_px.lerp(tip_px, float(k) / 8.0)
		if rect.has_point(p) and _delta(img, empty, p, 2) > 0.05:
			blade_seen += 1
	_check("the katana is in frame and visible (%d/9 samples along the blade)" % blade_seen,
		rect.has_point(mid_px) and rect.has_point(tip_px) and blade_seen >= 4)
	# The mask: the face differs from the empty frame (the mask reads in the fog).
	var face_px := cam.unproject_position(head.global_position + head.global_basis.z * 0.12)
	_check("the demon mask reads on the face (Δ %.2f)" % _delta(img, empty, face_px, 3), _delta(img, empty, face_px, 3) > 0.08)
	# Bubble: above the head, inside the frame, and it changes the picture there.
	var bubble_px := cam.unproject_position(boss.speech_bubble.global_position)
	_check("AI bubble shows in frame above the head (%s, '%s')" % [bubble_px, boss.speech_bubble.get_text()],
		boss.speech_bubble.is_showing() and rect.has_point(bubble_px) and bubble_px.y < head_px.y
		and _delta(img_b, img, bubble_px, 6) > 0.05)


func _delta(a: Image, b: Image, p: Vector2, r: int) -> float:
	var sum := 0.0
	var n := 0
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			var x := int(p.x) + dx
			var y := int(p.y) + dy
			if x < 0 or y < 0 or x >= a.get_width() or y >= a.get_height():
				continue
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			n += 1
	return sum / maxf(float(n), 1.0)


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame
