extends Node
## Single-frame forest vista for visual review (run scene, no full run_screenshots loop).

const RUN_SCENE := preload("res://scenes/run.tscn")

var out_dir := "/tmp/hanabi_forest_shots"


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
	player.teleport(Vector3(0.0, 0.0, 2.2), 0.0)
	player.camera.rotation.x = deg_to_rad(-10.0)
	await _frames(45)
	await _shot("forest_horizon")
	run.queue_free()
	get_tree().quit(0)


func _frames(n: int) -> void:
	for k in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
