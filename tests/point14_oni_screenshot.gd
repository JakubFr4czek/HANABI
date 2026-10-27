extends Node

const RUN_SCENE := preload("res://scenes/run.tscn")
var out_dir := "/tmp/hanabi_point14_oni"


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
	var oni := run.wave_director.spawn_oni_boss(player.global_position)
	oni.global_position = Vector3(0.0, 1.0, -4.5)
	oni.home_position = oni.global_position
	oni.set_attacks_enabled(false)
	oni.set_pose("guard")
	var face := player.global_position
	face.y = oni.global_position.y
	oni.look_at(face, Vector3.UP)
	player.teleport(Vector3(0.0, 0.0, 2.8), 0.0)
	player.camera.rotation.x = deg_to_rad(-2.0)
	await _frames(32)
	await _shot("oni_mask_close_fog")
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
