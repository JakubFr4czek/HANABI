extends Node
## Windowed screenshots of the wrist readout (D14): the readout raised (desktop: H held)
## at 100 %, 50 % and 15 % HP with the kcal figure and a storm imbue, then the hand lowered
## (nothing drawn). Needs a window, so run it without --headless:
##   godot --path . --fixed-fps 90 res://tests/point15_wrist_screenshot.tscn -- --desktop --shots /tmp/dir

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

	player.health.hp = player.health.max_hp
	run._refresh_hud()
	await _frames(24)
	await _shot("wrist_lowered_hidden")
	run.queue_free()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for _k in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	else:
		await _frames(2)
	var tex := get_viewport().get_texture()
	if tex == null:
		return
	var img := tex.get_image()
	if img and not img.is_empty():
		img.save_png(out_dir.path_join(name + ".png"))
		print("saved ", name)
