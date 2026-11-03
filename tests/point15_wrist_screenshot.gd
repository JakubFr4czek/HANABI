extends Node
## Windowed screenshots of the wrist readout (D14): the readout raised (desktop: H held)
## at 100 %, 50 % and 15 % HP with the kcal figure and a storm imbue, then the hand lowered
## (nothing drawn). Needs a window, so run it without --headless:
##   godot --path . --fixed-fps 90 res://tests/point15_wrist_screenshot.tscn -- --desktop --shots /tmp/dir
## F6: also the STAMINA row full and empty, with a pixel check that the row is in frame and
## its bar is drawn (bright when full, dark track when empty). Exit 1 when that fails.

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_point15_wrist"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--shots")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)

	var run: RunGame = RUN_SCENE.instantiate()
	run.skip_run_intro = true
	add_child(run)
	var player := run.player as DesktopPlayer
	run.wave_director.stop_director()
	run.wave_director.clear_enemies()
	run.kills = 5
	run.score = 42
	run.xp = 14
	run.calorie_meter.kcal = 42.6
	player.teleport(Vector3(0.0, 0.0, 2.0), 0.0)
	player.camera.rotation.x = deg_to_rad(-34.0)
	player.hand_offset = Vector3(0.18, -0.14, 0.0)
	run.element_system.imbue(Elements.STORM, 12.0)
	await _frames(48)

	for shot in [["wrist_hp100_gesture", 1.0], ["wrist_hp50_gesture", 0.5], ["wrist_hp15_gesture", 0.15]]:
		player.health.hp = player.health.max_hp * float(shot[1])
		run._refresh_hud()
		player.wrist_check = true
		await _frames(24)
		await _shot(String(shot[0]))
		player.wrist_check = false

	# F6: STAMINA full, then empty (winded). Stamina is pinned each tick so it does not refill.
	var failures := 0
	var lum := {}
	for st in [["wrist_stamina_full", 100.0, false], ["wrist_stamina_empty", 0.0, true]]:
		player.health.hp = player.health.max_hp
		player.wrist_check = true
		for _k in 24:
			run.stamina.value = float(st[1])
			run.stamina.is_exhausted = bool(st[2])
			run.stamina._rest = -100.0  # no refill while the shot is taken
			run._refresh_hud()
			await get_tree().physics_frame
		var img := await _shot(String(st[0]))
		if img == null:
			continue
		var hud := run.diegetic_hud
		var label := hud.row_labels("stamina")[1] as Label3D
		var track := hud.wrist_face.find_child("StaminaTrack", true, false) as Node3D
		var cam := player.camera
		var size := Vector2(img.get_width(), img.get_height())
		var at_value := cam.unproject_position(label.global_position)
		var at_bar := cam.unproject_position(hud.wrist_face.to_global(Vector3(-DiegeticHud.PANEL_HALF_WIDTH * 0.6, DiegeticHud.LABEL_Y, track.position.z)))
		var in_frame := Rect2(Vector2.ZERO, size).grow(-8.0).has_point(at_value) and Rect2(Vector2.ZERO, size).grow(-8.0).has_point(at_bar)
		print("%s  value px %s  bar px %s  in frame %s" % [st[0], at_value, at_bar, in_frame])
		if not in_frame:
			failures += 1
			print("FAIL  %s: the STAMINA row is out of frame" % st[0])
			continue
		var sum := 0.0
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				sum += img.get_pixel(int(at_bar.x) + dx, int(at_bar.y) + dy).get_luminance()
		lum[st[0]] = sum / 9.0
		print("%s  bar luminance %.3f" % [st[0], lum[st[0]]])
	run.stamina.reset()
	if lum.size() == 2:
		var full: float = lum["wrist_stamina_full"]
		var empty: float = lum["wrist_stamina_empty"]
		var ok: bool = full > 0.4 and full - empty > 0.2
		print(("PASS  " if ok else "FAIL  ") + "STAMINA bar renders: full %.3f vs empty %.3f" % [full, empty])
		if not ok:
			failures += 1
	elif DisplayServer.get_name() != "headless":
		failures += 1
		print("FAIL  STAMINA shots missing")
	player.wrist_check = false

	player.health.hp = player.health.max_hp
	run._refresh_hud()
	await _frames(24)
	await _shot("wrist_lowered_hidden")
	run.queue_free()
	get_tree().quit(1 if failures > 0 else 0)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(name: String) -> Image:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	else:
		await _frames(2)
	var tex := get_viewport().get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img and not img.is_empty():
		img.save_png(out_dir.path_join(name + ".png"))
		print("saved ", name)
		return img
	return null
