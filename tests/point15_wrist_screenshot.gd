extends Node

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
	run._refresh_hud()
	player.teleport(Vector3(0.0, 0.0, 2.0), 0.0)
	player.camera.rotation.x = deg_to_rad(-12.0)
	player.hand_offset = Vector3(0.06, -0.04, 0.0)
	await _frames(4)
	await _frames(40)
	await _shot("wrist_hud_natural_angle")
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
