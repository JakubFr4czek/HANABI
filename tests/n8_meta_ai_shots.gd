extends Node
## N8 visual test on the real run scene (windowed; headless reports SKIP): the run boss
## driven by a local mock of the Meta chat-completions API, seen from 4 m.
##   timeout 600 xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 960x540 res://tests/n8_meta_ai_shots.tscn -- --shots docs/n8
## Shots (one camera): 00 before (no reply yet), 01 AI bubble, 02 + demo overlay, 03 fallback (HTTP 500).
## Pixel checks: the bubble text reads (bright glyphs on a dark plate) inside the frame,
## the plate sits wholly above the head (never covers the boss), the overlay slip reads.

const RUN_SCENE := preload("res://scenes/run.tscn")
const DISTANCE := 4.0
var out_dir := "/tmp/hanabi_n8"
var run: RunGame
var player: DesktopPlayer
var failures := 0


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP  n8_meta_ai_shots needs a window (pixels)")
		print("\nALL PASSED (0 failed)")
		get_tree().quit(0)
		return
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(150.0).timeout.connect(func():
		print("WATCHDOG TIMEOUT in n8_meta_ai_shots")
		get_tree().quit(1))

	var server := MetaApiMockServer.new()
	add_child(server)
	server.start()
	server.decision = {"tactic": "flank_left", "attack": "sweep", "speech": "You always cut from the right."}
	VrComfortSettings.ai_endpoint = server.endpoint()
	VrComfortSettings.meta_api_key = "test-key-not-a-secret"
	VrComfortSettings.ai_boss_enabled = true
	VrComfortSettings.ai_demo_overlay = false
	VrComfortSettings.ai_language = "en"

	run = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	run.high_score_path = "user://n8_shots_save.cfg"
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

	var cam := player.camera
	var eye := cam.global_position
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	player._pitch = deg_to_rad(-2.0)
	cam.rotation.x = player._pitch
	var spot := eye + fwd * DISTANCE
	spot.y = run.forest_world.height_at(spot.x, spot.z)
	var boss := director.spawn_oni_boss(player.global_position)
	boss.set_attacks_enabled(false)
	var brain := boss.brain as OniBossBrain
	brain._ai_timer = 999.0
	var place := func() -> void:
		boss.global_position = spot
		boss.home_position = spot
		boss.rotation.y = atan2(-fwd.x, -fwd.z)
		boss.reset_body()
	place.call()
	await _frames(90)
	var before := await _grab("n8_00_before.png")

	# 01: a real HTTP round-trip to the mock; the reply is the AI decision.
	var d := await _ask(brain)
	_check("mock API reply is used (source %s, tactic %s)" % [d.get("source"), brain.current_tactic],
		d.get("source") == "ai" and brain.current_tactic == "flank_left")
	place.call()
	await _frames(20)
	var img_ai := await _grab("n8_01_ai_bubble.png")
	_bubble_checks(boss, before, img_ai, "ai")

	# 02: demo overlay on.
	VrComfortSettings.ai_demo_overlay = true
	await _frames(6)
	var img_ov := await _grab("n8_02_overlay.png")
	var ov_px := cam.unproject_position(boss.speech_bubble._thought_label.global_position)
	_check("overlay slip reads under the bubble ('%s', Δ %.2f)" % [boss.speech_bubble.get_thought(), _delta(img_ov, img_ai, ov_px, 8)],
		boss.speech_bubble.is_overlay_showing() and boss.speech_bubble.get_thought().contains("ai")
		and _delta(img_ov, img_ai, ov_px, 8) > 0.05)

	# 03: the API fails (500): the boss answers locally, the slip says so.
	server.mode = "500"
	var f := await _ask(brain)
	_check("HTTP 500 -> fallback (%s)" % f.get("fallback_reason", ""), f.get("source") == "fallback")
	place.call()
	await _frames(20)
	var img_fb := await _grab("n8_03_fallback.png")
	_check("overlay names the fallback ('%s')" % boss.speech_bubble.get_thought(),
		boss.speech_bubble.get_thought().contains("fallback"))
	_bubble_checks(boss, before, img_fb, "fallback")

	VrComfortSettings.ai_demo_overlay = false
	VrComfortSettings.meta_api_key = ""
	VrComfortSettings.ai_endpoint = VrComfortSettings.DEFAULT_META_ENDPOINT
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "FAILURES", failures])
	get_tree().quit(1 if failures > 0 else 0)


func _ask(brain: OniBossBrain) -> Dictionary:
	var box := {"d": {}}
	var cb := func(dd: Dictionary) -> void: box.d = dd
	brain.ai_client.decision_received.connect(cb)
	brain._ai_timer = 0.0
	for _k in 120:
		await get_tree().physics_frame
		if not (box.d as Dictionary).is_empty():
			break
	brain._ai_timer = 999.0
	brain.ai_client.decision_received.disconnect(cb)
	return box.d


func _grab(name: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	return img


## Text pixels: bright glyphs and the dark plate inside the bubble rect; plate above the head.
func _bubble_checks(boss: RunOniBoss, before: Image, img: Image, tag: String) -> void:
	var cam := player.camera
	var bubble := boss.speech_bubble
	var size := Vector2(img.get_width(), img.get_height())
	var plate := (bubble._bg_plate.mesh as QuadMesh).size
	var c := bubble.global_position
	var up := cam.global_basis.y
	var rt := cam.global_basis.x
	var tl := cam.unproject_position(c - rt * plate.x * 0.5 + up * plate.y * 0.5)
	var br := cam.unproject_position(c + rt * plate.x * 0.5 - up * plate.y * 0.5)
	var rect := Rect2(tl, br - tl).abs()
	var head := boss.parts["head"] as RagdollPart
	var head_top := cam.unproject_position(head.global_position + Vector3(0, 0.14, 0))
	_check("[%s] bubble wholly in frame (%s)" % [tag, rect], Rect2(Vector2.ZERO, size).encloses(rect))
	_check("[%s] bubble sits above the head, never over the boss (plate bottom %.0f < head top %.0f px)" % [tag, rect.end.y, head_top.y],
		bubble.is_showing() and rect.end.y < head_top.y)
	var bright := 0
	var dark := 0
	var n := 0
	for y in range(int(rect.position.y) + 2, int(rect.end.y) - 2, 2):
		for x in range(int(rect.position.x) + 2, int(rect.end.x) - 2, 2):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			n += 1
			var l := img.get_pixel(x, y).get_luminance()
			if l > 0.6:
				bright += 1
			elif l < 0.08:
				dark += 1
	var fb := float(bright) / maxf(n, 1)
	var fd := float(dark) / maxf(n, 1)
	_check("[%s] text reads from 4 m: glyph pixels %.0f%%, dark plate %.0f%% (%d px tall)" % [tag, fb * 100.0, fd * 100.0, int(rect.size.y)],
		fb > 0.04 and fd > 0.35 and rect.size.y >= 18.0)
	_check("[%s] the bubble changes the frame vs. before (Δ %.2f)" % [tag, _delta(img, before, rect.get_center(), 10)],
		_delta(img, before, rect.get_center(), 10) > 0.08)


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


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame
